// lib/core/audio/microphone_pitch_service.dart
//
// The capture layer: mic → PCM16 stream (via the `record` plugin) → rolling
// window → PitchDetector → a broadcast stream of PitchReading. This is the one
// place that touches a platform plugin; everything above it (widgets, games,
// tests) works against the plain [PitchReading] stream and never sees `record`.
//
// SPIKE NOTE: this is the piece that must be proven on a *physical* device —
// mic permission, actual delivered sample rate, and latency all vary by
// platform. The detector itself is already proven headlessly by
// test/pitch_analysis_test.dart. Web needs a secure context (https/localhost)
// and a user gesture before the mic will open.

import 'dart:async';
import 'dart:typed_data';

import 'package:klang_universum/core/audio/aec_engine.dart';
import 'package:klang_universum/core/audio/chroma_analysis.dart';
import 'package:klang_universum/core/audio/pitch_analysis.dart';
import 'package:klang_universum/core/audio/streaming_analyzer.dart';
import 'package:record/record.dart';

/// Why a capture session failed to start — surfaced to the UI so it can show
/// the right message (ask for permission vs. "no mic" vs. unsupported).
enum PitchCaptureError {
  permissionDenied,
  unsupported,
  alreadyRunning,
  unknown
}

class PitchCaptureException implements Exception {
  PitchCaptureException(this.reason, [this.detail]);
  final PitchCaptureError reason;
  final String? detail;
  @override
  String toString() =>
      'PitchCaptureException($reason${detail == null ? '' : ': $detail'})';
}

class MicrophonePitchService {
  MicrophonePitchService({
    PitchDetector? detector,
    this.chordDetector,
    this.aec,
    this.sampleRate = 44100,
    double a4 = kDefaultA4,
  }) : detector = detector ?? PitchDetector(sampleRate: sampleRate, a4: a4);

  final PitchDetector detector;

  /// Optional AEC Tier-3b full-duplex engine. When supplied, capture comes from
  /// the engine's echo-cancelled [AecEngine.cleaned] stream instead of the raw
  /// `record` mic, and the caller feeds the backing PCM via [pushReference] so
  /// the speaker is cancelled out of the analysis. When null (the default, and
  /// the case whenever the native plugin isn't available), everything below is
  /// unchanged and capture uses `record` (AEC tiers 0/1). See docs/AEC_TIER3B.md.
  final AecEngine? aec;

  bool get usesAec => aec != null;

  /// Optional phase-2 chord recognizer. When set, each analysed window is also
  /// matched for chords and emitted on [chords]; when null there is no extra
  /// cost and the mono [readings] path is unchanged.
  final ChordDetector? chordDetector;

  final int sampleRate;

  /// Turn on the platform's echo canceller (+ its bundled voice DSP). Off by
  /// default because that DSP reshapes the waveform and hurts pitch/intonation
  /// accuracy. Turn it on only when playing audible backing over the speaker
  /// (so the mic doesn't grade the speaker) — headphones are better. Read at
  /// [start]; toggle before (re)starting. See docs on AEC tiers.
  bool echoCancel = false;

  // Lazy so AEC mode (and its headless tests) never touch the `record` plugin.
  late final AudioRecorder _recorder = AudioRecorder();
  final StreamController<PitchReading> _readings =
      StreamController<PitchReading>.broadcast();
  final StreamController<ChordReading> _chords =
      StreamController<ChordReading>.broadcast();
  StreamSubscription<Uint8List>? _chunkSub;

  /// The pure-Dart windowing/analysis core, shared with the CLI. It slides the
  /// analysis window across the PCM stream and yields a frame per window.
  late final StreamingAudioAnalyzer _analyzer = StreamingAudioAnalyzer(
    detector: detector,
    chordDetector: chordDetector,
  );

  bool _running = false;

  /// Live stream of readings. Silent frames arrive as [PitchReading.silent] so
  /// the UI can dim/park the needle rather than freezing on the last note.
  Stream<PitchReading> get readings => _readings.stream;

  /// Live stream of fuzzy chord guesses — empty unless a [chordDetector] was
  /// supplied.
  Stream<ChordReading> get chords => _chords.stream;

  bool get isRunning => _running;

  /// Does the app have (or can it obtain) mic permission?
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Begin capturing and emitting readings. Throws [PitchCaptureException] on
  /// permission denial or unsupported platform.
  Future<void> start() async {
    if (_running) throw PitchCaptureException(PitchCaptureError.alreadyRunning);

    // AEC Tier 3b: when a full-duplex engine is attached, capture comes from its
    // echo-cancelled stream and the `record` plugin is bypassed entirely.
    final engine = aec;
    if (engine != null) {
      await _startAec(engine);
      return;
    }

    final granted = await _recorder.hasPermission();
    if (!granted) {
      throw PitchCaptureException(PitchCaptureError.permissionDenied);
    }
    if (!await _recorder.isEncoderSupported(AudioEncoder.pcm16bits)) {
      throw PitchCaptureException(
        PitchCaptureError.unsupported,
        'pcm16bits not supported',
      );
    }

    // autoGain/noiseSuppress stay off (they reshape the waveform and skew
    // pitch/intonation). echoCancel is opt-in: only for audible-backing mode,
    // where cancelling the speaker is worth the DSP's accuracy cost.
    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
      echoCancel: echoCancel,
    );

    final Stream<Uint8List> pcm;
    try {
      pcm = await _recorder.startStream(config);
    } catch (e) {
      throw PitchCaptureException(PitchCaptureError.unknown, '$e');
    }

    _analyzer.reset();
    _running = true;
    _chunkSub = pcm.listen(
      _onChunk,
      onError: _readings.addError,
      cancelOnError: false,
    );
  }

  /// Start capture from the AEC engine's cleaned near-end stream. The cleaned
  /// PCM16 has the same shape as the `record` stream, so it flows through the
  /// identical [_onChunk] → analyzer path.
  Future<void> _startAec(AecEngine engine) async {
    try {
      await engine.start(sampleRate: sampleRate);
    } catch (e) {
      throw PitchCaptureException(PitchCaptureError.unknown, '$e');
    }
    _analyzer.reset();
    _running = true;
    _chunkSub = engine.cleaned.listen(
      _onChunk,
      onError: _readings.addError,
      cancelOnError: false,
    );
  }

  /// Feed backing PCM16 that is about to be played so the AEC can cancel it out
  /// of the mic. No-op when no [aec] is attached (the caller can push
  /// unconditionally). Mono, little-endian, at [sampleRate].
  void pushReference(Uint8List pcm16) => aec?.reference(pcm16);

  void _onChunk(Uint8List bytes) {
    for (final frame in _analyzer.addPcm16(bytes)) {
      if (!_readings.isClosed) _readings.add(frame.pitch);
      final chord = frame.chord;
      if (chord != null && !_chords.isClosed) _chords.add(chord);
    }
  }

  /// Stop capturing. Safe to call when not running.
  Future<void> stop() async {
    _running = false;
    await _chunkSub?.cancel();
    _chunkSub = null;
    _analyzer.clearBuffer();
    final engine = aec;
    if (engine != null) {
      await engine.stop();
      return; // AEC mode never touches the (lazy) recorder
    }
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  /// Release the recorder and close the stream. The service is unusable after.
  Future<void> dispose() async {
    await stop();
    if (aec == null) await _recorder.dispose();
    await _readings.close();
    await _chords.close();
  }
}
