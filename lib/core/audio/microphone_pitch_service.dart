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

import 'package:klang_universum/core/audio/pitch_analysis.dart';
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
    this.sampleRate = 44100,
    double a4 = kDefaultA4,
  }) : detector = detector ?? PitchDetector(sampleRate: sampleRate, a4: a4);

  final PitchDetector detector;
  final int sampleRate;

  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<PitchReading> _readings =
      StreamController<PitchReading>.broadcast();
  StreamSubscription<Uint8List>? _chunkSub;

  /// Rolling analysis buffer (mono floats). We run the detector on a sliding
  /// window and advance by [_hop] each time, so the meter updates several
  /// times per window rather than once.
  late final int _windowSize = detector.windowSize;
  late final int _hop = _windowSize ~/ 2;
  final List<double> _buffer = <double>[];

  bool _running = false;

  /// Live stream of readings. Silent frames arrive as [PitchReading.silent] so
  /// the UI can dim/park the needle rather than freezing on the last note.
  Stream<PitchReading> get readings => _readings.stream;
  bool get isRunning => _running;

  /// Does the app have (or can it obtain) mic permission?
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Begin capturing and emitting readings. Throws [PitchCaptureException] on
  /// permission denial or unsupported platform.
  Future<void> start() async {
    if (_running) throw PitchCaptureException(PitchCaptureError.alreadyRunning);

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

    // RecordConfig defaults autoGain/echoCancel/noiseSuppress to false, which is
    // exactly what we want: those DSP stages reshape the waveform and skew
    // pitch/intonation. Keep them off if this config is ever expanded.
    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
    );

    final Stream<Uint8List> pcm;
    try {
      pcm = await _recorder.startStream(config);
    } catch (e) {
      throw PitchCaptureException(PitchCaptureError.unknown, '$e');
    }

    _buffer.clear();
    _running = true;
    _chunkSub = pcm.listen(
      _onChunk,
      onError: _readings.addError,
      cancelOnError: false,
    );
  }

  void _onChunk(Uint8List bytes) {
    final floats = pcm16ToFloat(bytes);
    _buffer.addAll(floats);

    while (_buffer.length >= _windowSize) {
      final window = Float64List(_windowSize);
      for (var i = 0; i < _windowSize; i++) {
        window[i] = _buffer[i];
      }
      if (!_readings.isClosed) _readings.add(detector.analyze(window));
      _buffer.removeRange(0, _hop);
    }
  }

  /// Stop capturing. Safe to call when not running.
  Future<void> stop() async {
    _running = false;
    await _chunkSub?.cancel();
    _chunkSub = null;
    _buffer.clear();
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  /// Release the recorder and close the stream. The service is unusable after.
  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
    await _readings.close();
  }
}
