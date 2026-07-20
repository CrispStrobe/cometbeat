// lib/features/games/composition/perform_screen.dart
//
// Live Looper — "Perform" (the Advanced tile of the loop ladder). A loop-station:
// tap a loop to start it, stack more layers on top (they loop in sync), and
// mute / undo layers as you build a track live. Every layer is one bar-cycle of
// PCM held in a LoopStack; the active layers are summed by `renderLoopStack`
// into one seamless loop and hot-swapped IN PHASE, so a new layer drops in on
// the beat instead of restarting the bar.
//
// S1 seeds layers from a few built-in loops (beat/bass/chords/melody); later
// slices add recording your own (sing / beatbox / play-in keyboard + pads).

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/beat_capture.dart'
    show BeatFrame, quantizeToBeat;
import 'package:comet_beat/core/audio/crisp_dsp/resample.dart'
    show resampleCubic;
import 'package:comet_beat/core/audio/groove_capture.dart'
    show PitchSample, quantizeToGroove;
import 'package:comet_beat/core/audio/loop_engine.dart'
    show DrumRowsPattern, PatternCell;
import 'package:comet_beat/core/audio/loop_record.dart';
import 'package:comet_beat/core/audio/loop_stack_render.dart';
import 'package:comet_beat/core/audio/microphone_pitch_service.dart'
    show MicrophonePitchService, PitchCaptureException;
import 'package:comet_beat/core/audio/sample_pitch.dart'
    show detectSampleBaseMidi;
import 'package:comet_beat/core/audio/synth.dart'
    show Drum, kSampleRate, wavBytes;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/loop_player_service.dart';
import 'package:comet_beat/features/sound_lab/my_samples_sheet.dart'
    show showMySamplesSheet;
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// One overdub layer: a label + one bar-cycle of mono PCM.
class _PerformLayer {
  const _PerformLayer(this.label, this.pcm);
  final String label;
  final Float64List pcm;
}

/// Test seam onto the Perform screen — build/mute/undo layers + read the mix
/// without audio hardware.
abstract class PerformTester {
  void addSeed(String kind);

  /// Play-in a layer: start capturing, tap notes (melody) or pads (beat), then
  /// finish — the played taps render into a new loop layer.
  void startPlayIn();
  void startPlayInBeat();
  void playInNote(int midi);
  void playInPad(String drum);

  /// Sampler voice (P1): make a captured sound the keyboard's instrument, so
  /// playing/recording a melody uses THAT sound (auto-tuned) instead of a synth.
  void setSampleVoice(Float64List pcm, {int? baseMidi, String name});
  void clearSampleVoice();
  bool get hasSampleVoice;
  String? get voiceName;

  /// Pad voices (P2): give a drum pad your own sound instead of the synth drum.
  void setPadVoice(String drum, Float64List pcm, {String name});
  void clearPadVoice(String drum);
  bool hasPadVoice(String drum);
  String? padVoiceName(String drum);

  /// Groove setup (P3): tempo + key, settable only while empty ([canSetup]).
  int get bpm;
  int get keyShift;
  bool get canSetup;
  void setTempo(int bpm);
  void setKey(int semitones);

  /// Sing / beatbox a layer (P4): convert captured mic frames into a layer.
  /// The mic flow calls these; tests drive them with synthetic frames.
  void addSungLayer(List<PitchSample> samples, {required int totalMs});
  void addBeatboxLayer(List<BeatFrame> frames, {required int totalMs});
  bool get isCapturing;

  /// A single note of the current sample voice, pitched — for tests.
  Float64List debugPitched(int midi);

  /// The beat layer rendered from [hits] (uses pad voices) — for tests.
  Float64List debugBeat(List<(String, int)> hits);

  /// A built-in seed loop at the current tempo/key — for tests.
  Float64List debugSeed(String kind);
  void finishPlayIn();
  void cancelPlayIn();
  bool get isPlayingIn;

  int get layerCount;
  String layerLabel(int i);
  bool isMuted(int i);
  void toggleMute(int i);
  void removeLayer(int i);
  void undoLayer();
  void redoLayer();
  bool get canUndo;
  bool get canRedo;
  void clearAll();
  void play();
  void stop();
  bool get isPlaying;

  /// Scenes (S4): snapshot which layers are active, then relaunch that mix.
  /// [launchScene] applies it instantly; [armScene] queues it to swap at the
  /// next bar (the clip-launch feel), fired by [launchArmed].
  void saveScene();
  int get sceneCount;
  int sceneActiveCount(int i);
  void launchScene(int i);
  void armScene(int i);
  int? get armedScene;
  void launchArmed();
  void removeScene(int i);

  /// Bounce (S5): build clips to hand off to the arranger's "My Samples"
  /// library — the whole loop as one clip, or one clip per active layer.
  List<SampleClip> debugBounce(String base, {bool perLayer});

  /// The current summed mix (active layers) — for tests.
  Float64List debugMix();
}

class PerformScreen extends StatefulWidget {
  const PerformScreen({super.key});

  @override
  State<PerformScreen> createState() => _PerformScreenState();
}

class _PerformScreenState extends State<PerformScreen>
    implements PerformTester {
  final LoopStack<_PerformLayer> _stack = LoopStack<_PerformLayer>();
  final LoopPlayerService _loop = LoopPlayerService();
  final Stopwatch _clock = Stopwatch();
  bool _playing = false;

  // Play-in recording: which panel is up ('melody' keyboard / 'beat' pads), and
  // the captured taps with their loop-phase.
  String? _playInMode;
  final List<(int midi, int phaseMs)> _playInNotes = [];
  final List<(String drum, int phaseMs)> _playInHits = [];

  // Sampler voice (P1): a captured sound played pitched. null = built-in synth.
  Float64List? _voicePcm;
  int _voiceBase = 60;
  String? _voiceName;

  // Pad voices (P2): drum → your own sound (at loop rate). Absent = synth drum.
  final Map<String, Float64List> _padVoices = {};
  final Map<String, String> _padVoiceNames = {};

  // Groove setup (P3): tempo + key, chosen while the stack is empty then locked
  // (baked layers are fixed-length PCM, so they can't be re-timed after the fact).
  int _bpm = 120;
  int _keyShift = 0; // semitones from C

  /// One bar (4 beats) of samples at [_bpm] — the master loop length.
  int get _loopSamples => (kSampleRate * 4 * 60 / _bpm).round();

  /// The seed loops S1 offers (kind → label key builder).
  static const List<String> _kinds = ['beat', 'bass', 'chords', 'melody'];

  /// The selectable tempos — all keep the bar length integral in samples.
  static const List<int> _kTempos = [75, 100, 120];

  /// Selectable keys (root name, semitones from C).
  static const List<(int, String)> _kKeys = [
    (0, 'C'),
    (2, 'D'),
    (5, 'F'),
    (7, 'G'),
    (9, 'A'),
  ];

  // Scenes (S4): each is a per-layer "is-active" snapshot; `_armed` is the scene
  // queued to launch at the next bar boundary.
  final List<List<bool>> _scenes = [];
  int? _armed;
  Timer? _boundaryTimer;
  int _lastPhaseMs = 0;

  // Sing / beatbox capture (P4). Lazy mic (never touched in headless tests).
  MicrophonePitchService? _mic;
  StreamSubscription<Object?>? _micSub;
  final Stopwatch _capClock = Stopwatch();
  final List<({double ms, int? midi, double rms, double zcr})> _frames = [];
  String? _capMode; // 'sing' | 'beat' | null = idle
  String _capPhase = 'idle'; // 'countIn' | 'recording'
  int _countdown = 0;
  Timer? _countInTimer;
  Timer? _capStopTimer;

  int get _barMs => (_loopSamples / kSampleRate * 1000).round();

  @override
  void initState() {
    super.initState();
    // Fire an armed scene when the loop crosses a bar boundary (phase wraps).
    _boundaryTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!_playing || _armed == null) {
        _lastPhaseMs = _phaseNow;
        return;
      }
      final now = _phaseNow;
      if (now < _lastPhaseMs) launchArmed();
      _lastPhaseMs = now;
    });
  }

  @override
  void dispose() {
    _boundaryTimer?.cancel();
    _countInTimer?.cancel();
    _capStopTimer?.cancel();
    _micSub?.cancel();
    _mic?.stop();
    _loop.dispose();
    super.dispose();
  }

  // ── Layer editing ─────────────────────────────────────────────────────────
  @override
  void addSeed(String kind) {
    _stack.add(_PerformLayer(kind, _seedLoop(kind)));
    _refresh();
  }

  // ── Groove setup: tempo + key (P3) ────────────────────────────────────────
  @override
  int get bpm => _bpm;
  @override
  int get keyShift => _keyShift;

  /// Tempo/key change the bar length + seed pitch, so they're locked once any
  /// layer is baked (an existing layer can't be re-timed after the fact).
  @override
  bool get canSetup => _stack.isEmpty;

  @override
  void setTempo(int bpm) {
    if (!canSetup || !_kTempos.contains(bpm)) return;
    _bpm = bpm;
    setState(() {});
  }

  @override
  void setKey(int semitones) {
    if (!canSetup) return;
    _keyShift = semitones;
    setState(() {});
  }

  @override
  Float64List debugSeed(String kind) => _seedLoop(kind);

  // ── Sing / beatbox a layer (P4) ───────────────────────────────────────────
  @override
  bool get isCapturing => _capMode != null;

  static const Map<Drum, String> _drumNames = {
    Drum.kick: 'kick',
    Drum.snare: 'snare',
    Drum.hat: 'hat',
  };

  /// A quantized groove (cells over [steps]) → my `(midi, phaseMs)` notes.
  List<(int, int)> _cellsToNotes(List<PatternCell> cells, int steps) {
    final barMs = _barMs;
    final out = <(int, int)>[];
    var step = 0;
    for (final c in cells) {
      final midis = c.midis;
      if (midis != null && midis.isNotEmpty) {
        out.add((midis.first, (step * barMs / steps).round()));
      }
      step += c.steps;
    }
    return out;
  }

  /// A quantized beat pattern → my `(drum, phaseMs)` hits (unknown drums → hat).
  List<(String, int)> _rowsToHits(DrumRowsPattern pattern) {
    final barMs = _barMs;
    final out = <(String, int)>[];
    pattern.rows.forEach((drum, row) {
      final name = _drumNames[drum] ?? 'hat';
      final steps = row.length;
      for (var s = 0; s < steps; s++) {
        if (row[s]) out.add((name, (s * barMs / steps).round()));
      }
    });
    return out;
  }

  @override
  void addSungLayer(List<PitchSample> samples, {required int totalMs}) {
    const steps = 8;
    final cells = quantizeToGroove(samples, totalMs: totalMs, steps: steps);
    if (cells == null) return;
    final notes = _cellsToNotes(cells, steps);
    if (notes.isEmpty) return;
    _stack.add(_PerformLayer('melody', _renderMelody(notes)));
    _refresh();
  }

  @override
  void addBeatboxLayer(List<BeatFrame> frames, {required int totalMs}) {
    const steps = 8;
    final pattern = quantizeToBeat(frames, totalMs: totalMs, steps: steps);
    if (pattern == null) return;
    final hits = _rowsToHits(pattern);
    if (hits.isEmpty) return;
    _stack.add(_PerformLayer('beat', _renderBeat(hits)));
    _refresh();
  }

  /// Mic flow: count-in (4 ticks) → record one bar → convert to a layer. The
  /// band is silenced first so the monophonic detector hears the performer.
  Future<void> _startCapture(String mode) async {
    if (_capMode != null) return;
    final audio = context.read<AudioService>();
    if (_playing) stop();
    setState(() {
      _capMode = mode;
      _capPhase = 'countIn';
      _countdown = 4;
    });
    unawaited(audio.playTick(accent: true));
    final beatMs = (_barMs / 4).round();
    _countInTimer = Timer.periodic(Duration(milliseconds: beatMs), (t) {
      if (!mounted) return t.cancel();
      if (_countdown <= 1) {
        t.cancel();
        unawaited(_beginRecording());
      } else {
        setState(() => _countdown--);
        unawaited(audio.playTick());
      }
    });
  }

  Future<void> _beginRecording() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    _frames.clear();
    final mic = _mic ??= MicrophonePitchService();
    mic.echoCancel = false; // full accuracy; nothing plays during capture
    try {
      _micSub = mic.readings.listen((r) {
        final frame = (
          ms: _capClock.elapsedMilliseconds.toDouble(),
          midi: r.hasPitch ? r.nearestMidi : null,
          rms: r.rms,
          zcr: r.zcr,
        );
        _frames.add(frame);
      });
      await mic.start();
    } on PitchCaptureException {
      await _micSub?.cancel();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.performSingNothing)),
      );
      setState(() {
        _capMode = null;
        _capPhase = 'idle';
      });
      return;
    }
    if (!mounted) return;
    _capClock
      ..reset()
      ..start();
    setState(() => _capPhase = 'recording');
    _capStopTimer = Timer(Duration(milliseconds: _barMs), _finishRecording);
  }

  Future<void> _finishRecording() async {
    _capClock.stop();
    await _mic?.stop();
    await _micSub?.cancel();
    if (!mounted) return;
    final mode = _capMode;
    final totalMs = _barMs;
    final frames = List.of(_frames);
    setState(() {
      _capMode = null;
      _capPhase = 'idle';
    });
    if (mode == 'sing') {
      addSungLayer(
        [for (final f in frames) (f.ms, f.midi)],
        totalMs: totalMs,
      );
    } else if (mode == 'beat') {
      addBeatboxLayer(
        [
          for (final f in frames)
            (
              ms: f.ms,
              rms: f.rms,
              zcr: f.zcr,
              pitchedLow: f.midi != null && f.midi! < 60,
            ),
        ],
        totalMs: totalMs,
      );
    }
  }

  // ── Play-in a layer: melody (S2) / beat pads (S3) ─────────────────────────
  @override
  bool get isPlayingIn => _playInMode != null;

  void _startPlayIn(String mode) {
    _playInNotes.clear();
    _playInHits.clear();
    _playInMode = mode;
    // Run the clock so taps get a loop-phase; if there are layers, play along.
    if (!_clock.isRunning) {
      _clock
        ..reset()
        ..start();
    }
    if (_stack.activeLayers.isNotEmpty && !_playing) play();
    setState(() {});
  }

  @override
  void startPlayIn() => _startPlayIn('melody');
  @override
  void startPlayInBeat() => _startPlayIn('beat');

  int get _phaseNow {
    final loopMs = _loopSamples / kSampleRate * 1000;
    return (_clock.elapsedMilliseconds % loopMs).round();
  }

  @override
  void playInNote(int midi) {
    if (_playInMode != 'melody') return;
    _playInNotes.add((midi, _phaseNow));
  }

  @override
  void playInPad(String drum) {
    if (_playInMode != 'beat') return;
    _playInHits.add((drum, _phaseNow));
  }

  // ── Sampler voice (P1) ────────────────────────────────────────────────────
  @override
  bool get hasSampleVoice => _voicePcm != null && _voicePcm!.isNotEmpty;
  @override
  String? get voiceName => _voiceName;

  @override
  void setSampleVoice(
    Float64List pcm, {
    int? baseMidi,
    String name = 'sample',
  }) {
    _voicePcm = pcm;
    _voiceBase = baseMidi ?? detectSampleBaseMidi(pcm) ?? 60;
    _voiceName = name;
    setState(() {});
  }

  @override
  void clearSampleVoice() {
    _voicePcm = null;
    _voiceName = null;
    setState(() {});
  }

  // ── Pad voices (P2) ───────────────────────────────────────────────────────
  @override
  bool hasPadVoice(String drum) => _padVoices[drum]?.isNotEmpty ?? false;
  @override
  String? padVoiceName(String drum) => _padVoiceNames[drum];

  @override
  void setPadVoice(String drum, Float64List pcm, {String name = 'sample'}) {
    _padVoices[drum] = pcm;
    _padVoiceNames[drum] = name;
    setState(() {});
  }

  @override
  void clearPadVoice(String drum) {
    _padVoices.remove(drum);
    _padVoiceNames.remove(drum);
    setState(() {});
  }

  @override
  Float64List debugBeat(List<(String, int)> hits) => _renderBeat(hits);

  /// The sample voice resampled so [midi] plays in tune (base pitch → [midi]),
  /// optionally capped to [maxSamples]. Empty when no sample voice is set.
  Float64List _pitched(int midi, {int? maxSamples}) {
    final pcm = _voicePcm;
    if (pcm == null || pcm.isEmpty) return Float64List(0);
    final ratio = _midiToFreq(midi) / _midiToFreq(_voiceBase);
    final r = resampleCubic(pcm, ratio <= 0 ? 1.0 : ratio);
    if (maxSamples != null && r.length > maxSamples) {
      return Float64List.sublistView(r, 0, maxSamples);
    }
    return r;
  }

  @override
  Float64List debugPitched(int midi) => _pitched(midi);

  /// Mix [src] into [buf] at [start], capped to [maxLen] and the buffer end.
  void _place(
    Float64List buf,
    Float64List src,
    int start,
    int maxLen, {
    double gain = 0.7,
  }) {
    final len = min(src.length, maxLen);
    for (var i = 0; i < len && start + i < buf.length; i++) {
      buf[start + i] += gain * src[i];
    }
  }

  @override
  void finishPlayIn() {
    final mode = _playInMode;
    _playInMode = null;
    if (mode == 'melody' && _playInNotes.isNotEmpty) {
      _stack.add(_PerformLayer('melody', _renderMelody(_playInNotes)));
    } else if (mode == 'beat' && _playInHits.isNotEmpty) {
      _stack.add(_PerformLayer('beat', _renderBeat(_playInHits)));
    }
    _playInNotes.clear();
    _playInHits.clear();
    _refresh();
  }

  @override
  void cancelPlayIn() {
    _playInMode = null;
    _playInNotes.clear();
    _playInHits.clear();
    setState(() {});
  }

  /// Render captured `(drum, phaseMs)` hits into a one-bar loop — each hit
  /// snapped to the nearest 16th and synthesised as kick/snare/hat.
  Float64List _renderBeat(List<(String, int)> hits) {
    final n = _loopSamples;
    final buf = Float64List(n);
    final sixteenth = n ~/ 16;
    final beat = n ~/ 4;
    final rng = Random(7);
    for (final (drum, ms) in hits) {
      final start =
          ((ms / 1000 * kSampleRate) / sixteenth).round() * sixteenth % n;
      final voice = _padVoices[drum];
      if (voice != null && voice.isNotEmpty) {
        _place(buf, voice, start, beat); // your own sound (P2)
        continue;
      }
      switch (drum) {
        case 'kick':
          _tone(buf, 55, start, sixteenth * 2, gain: 0.6, decay: 22);
        case 'snare':
          _noise(buf, start, sixteenth * 2, rng, gain: 0.4);
        default: // hat
          _noise(buf, start, sixteenth, rng, gain: 0.12, decay: 90);
      }
    }
    return buf;
  }

  /// The three play-in drum pads: `(kind, label)`.
  static final List<(String, String Function(AppLocalizations))> _kPads = [
    ('kick', (l) => l.performPadKick),
    ('snare', (l) => l.performPadSnare),
    ('hat', (l) => l.performPadHat),
  ];

  /// Audition a single drum hit (a short one-shot) when a pad is tapped — the
  /// pad's own sound if one is assigned (P2), else the built-in synth drum.
  void _playHit(String drum) {
    final voice = _padVoices[drum];
    if (voice != null && voice.isNotEmpty) {
      final cap = (kSampleRate * 0.5).round();
      final clip =
          voice.length > cap ? Float64List.sublistView(voice, 0, cap) : voice;
      context.read<AudioService>().playWavBytes(wavBytes(_toInt16(clip)));
      return;
    }
    final buf = Float64List((kSampleRate * 0.25).round());
    switch (drum) {
      case 'kick':
        _tone(buf, 55, 0, buf.length, gain: 0.6, decay: 22);
      case 'snare':
        _noise(buf, 0, buf.length, Random(7), gain: 0.4);
      default: // hat
        _noise(buf, 0, buf.length ~/ 3, Random(9), gain: 0.12, decay: 90);
    }
    context.read<AudioService>().playWavBytes(wavBytes(_toInt16(buf)));
  }

  /// Render captured `(midi, phaseMs)` notes into a one-bar loop: each note is
  /// snapped to the nearest 16th, held until the next note (capped at a beat),
  /// and synthesised with a soft decay.
  Float64List _renderMelody(List<(int, int)> notes) {
    final n = _loopSamples;
    final buf = Float64List(n);
    final sixteenth = n ~/ 16;
    final beat = n ~/ 4;
    // Snap each note to a 16th-note sample position, sorted in time.
    final placed = [
      for (final (midi, ms) in notes)
        (midi, ((ms / 1000 * kSampleRate) / sixteenth).round() * sixteenth % n),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    for (var i = 0; i < placed.length; i++) {
      final (midi, start) = placed[i];
      final next = i + 1 < placed.length ? placed[i + 1].$2 : n;
      final dur = (next - start).clamp(sixteenth, beat);
      if (hasSampleVoice) {
        _place(buf, _pitched(midi), start, dur);
      } else {
        _tone(buf, _midiToFreq(midi), start, dur, gain: 0.28, decay: 6);
      }
    }
    return buf;
  }

  double _midiToFreq(int midi) => 440.0 * pow(2, (midi - 69) / 12).toDouble();

  @override
  int get layerCount => _stack.layers.length;
  @override
  String layerLabel(int i) => _stack.layers[i].label;
  @override
  bool isMuted(int i) => _stack.isMuted(i);
  @override
  void toggleMute(int i) {
    _stack.toggleMute(i);
    _refresh();
  }

  @override
  void removeLayer(int i) {
    // LoopStack only pops the newest via undo; for an arbitrary layer we mute it
    // (kept for undo/redo integrity — a full delete lands with S4's editing).
    if (!_stack.isMuted(i)) _stack.toggleMute(i);
    _refresh();
  }

  @override
  bool get canUndo => _stack.canUndo;
  @override
  bool get canRedo => _stack.canRedo;
  @override
  void undoLayer() {
    _stack.undo();
    _refresh();
  }

  @override
  void redoLayer() {
    _stack.redo();
    _refresh();
  }

  @override
  void clearAll() {
    _stack.clear();
    _scenes.clear();
    _armed = null;
    _refresh();
  }

  // ── Scenes / clip-launch (S4) ─────────────────────────────────────────────
  @override
  int get sceneCount => _scenes.length;
  @override
  int sceneActiveCount(int i) => _scenes[i].where((on) => on).length;
  @override
  int? get armedScene => _armed;

  @override
  void saveScene() {
    _scenes.add([for (var i = 0; i < _stack.layers.length; i++) !isMuted(i)]);
    setState(() {});
  }

  /// Set each layer's mute to match a scene's active-flags (new layers past the
  /// snapshot stay on).
  void _applyScene(List<bool> active) {
    for (var i = 0; i < _stack.layers.length; i++) {
      final wantMuted = i < active.length ? !active[i] : false;
      if (_stack.isMuted(i) != wantMuted) _stack.toggleMute(i);
    }
  }

  @override
  void launchScene(int i) {
    _armed = null;
    _applyScene(_scenes[i]);
    _refresh();
  }

  @override
  void armScene(int i) {
    _armed = _armed == i ? null : i; // tap again to disarm
    setState(() {});
  }

  @override
  void launchArmed() {
    final i = _armed;
    _armed = null;
    if (i != null && i < _scenes.length) {
      _applyScene(_scenes[i]);
      _refresh();
    } else {
      setState(() {});
    }
  }

  @override
  void removeScene(int i) {
    _scenes.removeAt(i);
    if (_armed == i) {
      _armed = null;
    } else if (_armed != null && _armed! > i) {
      _armed = _armed! - 1;
    }
    setState(() {});
  }

  // ── Bounce → arrange (S5) ─────────────────────────────────────────────────
  /// Build the clips to hand off: the whole loop as one clip, or (perLayer) one
  /// clip per ACTIVE layer. Empty when there's nothing playing.
  List<SampleClip> _bounceClips(String base, {required bool perLayer}) {
    if (_stack.activeLayers.isEmpty) return const [];
    if (!perLayer) {
      return [
        SampleClip(
          name: base,
          sampleRate: kSampleRate,
          pcm: renderLoopStack(_activePcm, loopSamples: _loopSamples),
          source: base,
        ),
      ];
    }
    final active = _stack.activeLayers.toList();
    return [
      for (var i = 0; i < active.length; i++)
        SampleClip(
          name: '$base ${i + 1}',
          sampleRate: kSampleRate,
          pcm: active[i].pcm,
          source: base,
        ),
    ];
  }

  @override
  List<SampleClip> debugBounce(String base, {bool perLayer = false}) =>
      _bounceClips(base, perLayer: perLayer);

  /// Save the bounce to the shared "My Samples" library, from where the
  /// Arranger (and other modules) can drop it onto a track.
  Future<void> _sendToArrange(bool perLayer) async {
    final l10n = AppLocalizations.of(context)!;
    final clips = _bounceClips(l10n.performBounceName, perLayer: perLayer);
    if (clips.isEmpty) return;
    final store = SampleClipStore();
    for (final c in clips) {
      await store.save(c);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.performBounceDone(clips.length))),
    );
  }

  /// Pick a sound from "My Samples" to play as the keyboard voice (resampled to
  /// the loop rate + auto-tuned by [setSampleVoice]).
  Future<void> _pickVoice() async {
    final clip = await showMySamplesSheet(context);
    if (clip == null || clip.pcm.isEmpty || !mounted) return;
    final pcm = clip.sampleRate == kSampleRate
        ? clip.pcm
        : resampleCubic(clip.pcm, clip.sampleRate / kSampleRate);
    setSampleVoice(pcm, name: clip.name);
  }

  /// Pick a sound from "My Samples" to play on drum pad [drum] (resampled to
  /// the loop rate). Tapping the label again with a voice set clears it.
  Future<void> _pickPadVoice(String drum) async {
    if (hasPadVoice(drum)) {
      clearPadVoice(drum);
      return;
    }
    final clip = await showMySamplesSheet(context);
    if (clip == null || clip.pcm.isEmpty || !mounted) return;
    final pcm = clip.sampleRate == kSampleRate
        ? clip.pcm
        : resampleCubic(clip.pcm, clip.sampleRate / kSampleRate);
    setPadVoice(drum, pcm, name: clip.name);
  }

  // ── Playback ──────────────────────────────────────────────────────────────
  @override
  bool get isPlaying => _playing;

  Duration get _phase {
    final loopMs = _loopSamples / kSampleRate * 1000;
    if (loopMs <= 0 || !_clock.isRunning) return Duration.zero;
    return Duration(
      milliseconds: (_clock.elapsedMilliseconds % loopMs).round(),
    );
  }

  @override
  Float64List debugMix() =>
      renderLoopStack(_activePcm, loopSamples: _loopSamples);

  List<Float64List> get _activePcm =>
      [for (final l in _stack.activeLayers) l.pcm];

  @override
  void play() {
    if (_stack.activeLayers.isEmpty) return;
    _playing = true;
    if (!_clock.isRunning) {
      _clock
        ..reset()
        ..start();
    }
    _swap();
    setState(() {});
  }

  @override
  void stop() {
    _playing = false;
    _clock.stop();
    _loop.stop();
    setState(() {});
  }

  /// Re-render the mix and, if playing, hot-swap the looping WAV in phase.
  void _refresh() {
    if (_playing) {
      if (_stack.activeLayers.isEmpty) {
        stop();
        return;
      }
      _swap();
    }
    setState(() {});
  }

  void _swap() {
    final mix = renderLoopStack(_activePcm, loopSamples: _loopSamples);
    _loop.playLoop(wavBytes(_toInt16(mix)), position: _phase);
  }

  Int16List _toInt16(Float64List f) {
    final out = Int16List(f.length);
    for (var i = 0; i < f.length; i++) {
      out[i] = (f[i].clamp(-1.0, 1.0) * 32767).round();
    }
    return out;
  }

  // ── Built-in seed loops (S1) ──────────────────────────────────────────────
  Float64List _seedLoop(String kind) {
    final n = _loopSamples;
    final beat = n ~/ 4;
    final eighth = n ~/ 8;
    final buf = Float64List(n);
    final rng = Random(kind.hashCode & 0x7fffffff);
    final k = pow(2, _keyShift / 12).toDouble(); // key transpose (P3)
    switch (kind) {
      case 'beat':
        for (var b = 0; b < 4; b++) {
          if (b.isEven) _tone(buf, 55, b * beat, eighth, gain: 0.6, decay: 22);
          if (b.isOdd) _noise(buf, b * beat, eighth, rng, gain: 0.4);
        }
        for (var e = 0; e < 8; e++) {
          _noise(buf, e * eighth, eighth ~/ 3, rng, gain: 0.08, decay: 90);
        }
      case 'bass':
        const roots = [65.41, 65.41, 87.31, 98.0]; // C2 C2 F2 G2 (I-I-IV-V)
        for (var b = 0; b < 4; b++) {
          _tone(buf, roots[b] * k, b * beat, beat, gain: 0.4, decay: 4);
        }
      case 'chords':
        const chord = [261.63, 329.63, 392.0]; // C E G
        for (var b = 0; b < 4; b += 2) {
          for (final f in chord) {
            _tone(buf, f * k, b * beat, beat * 2, gain: 0.18, decay: 3);
          }
        }
      case 'melody':
        const riff = [
          523.25,
          587.33,
          659.25,
          783.99,
          659.25,
          587.33,
          523.25,
          783.99,
        ]; // C D E G E D C G (pentatonic-ish)
        for (var e = 0; e < 8; e++) {
          _tone(buf, riff[e] * k, e * eighth, eighth, gain: 0.22, decay: 10);
        }
    }
    return buf;
  }

  void _tone(
    Float64List b,
    double freq,
    int start,
    int dur, {
    double gain = 0.3,
    double decay = 8,
  }) {
    for (var i = 0; i < dur && start + i < b.length; i++) {
      final t = i / kSampleRate;
      b[start + i] += gain * exp(-decay * t) * sin(2 * pi * freq * t);
    }
  }

  void _noise(
    Float64List b,
    int start,
    int dur,
    Random rng, {
    double gain = 0.3,
    double decay = 30,
  }) {
    for (var i = 0; i < dur && start + i < b.length; i++) {
      b[start + i] +=
          gain * exp(-decay * i / kSampleRate) * (rng.nextDouble() * 2 - 1);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  String _seedLabel(AppLocalizations l10n, String kind) => switch (kind) {
        'beat' => l10n.performSeedBeat,
        'bass' => l10n.performSeedBass,
        'chords' => l10n.performSeedChords,
        _ => l10n.performSeedMelody,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.performTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: l10n.performUndo,
            onPressed: canUndo ? undoLayer : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: l10n.performRedo,
            onPressed: canRedo ? redoLayer : null,
          ),
          IconButton(
            icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
            tooltip: _playing ? l10n.performStop : l10n.performPlay,
            onPressed:
                _stack.activeLayers.isEmpty ? null : (_playing ? stop : play),
          ),
          PopupMenuButton<bool>(
            icon: const Icon(Icons.drive_file_move_outline),
            tooltip: l10n.performBounce,
            enabled: _stack.activeLayers.isNotEmpty,
            onSelected: _sendToArrange,
            itemBuilder: (context) => [
              PopupMenuItem(value: false, child: Text(l10n.performBounceMix)),
              PopupMenuItem(value: true, child: Text(l10n.performBounceLayers)),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.performClear,
            onPressed: _stack.layers.isEmpty ? null : clearAll,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.performPrompt,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (canSetup) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l10n.performTempo,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    for (final t in _kTempos)
                      ChoiceChip(
                        label: Text('$t'),
                        selected: _bpm == t,
                        onSelected: (_) => setTempo(t),
                      ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.performKey,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    for (final (semis, name) in _kKeys)
                      ChoiceChip(
                        label: Text(name),
                        selected: _keyShift == semis,
                        onSelected: (_) => setKey(semis),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final kind in _kinds)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.add),
                      label: Text(_seedLabel(l10n, kind)),
                      onPressed: () => addSeed(kind),
                    ),
                  FilledButton.icon(
                    icon: const Icon(Icons.piano),
                    label: Text(l10n.performPlayIn),
                    onPressed: isPlayingIn ? null : startPlayIn,
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.grid_view),
                    label: Text(l10n.performPlayInBeat),
                    onPressed: isPlayingIn ? null : startPlayInBeat,
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.mic),
                    label: Text(l10n.performSing),
                    onPressed: (isPlayingIn || isCapturing)
                        ? null
                        : () => _startCapture('sing'),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.record_voice_over),
                    label: Text(l10n.performBeatbox),
                    onPressed: (isPlayingIn || isCapturing)
                        ? null
                        : () => _startCapture('beat'),
                  ),
                ],
              ),
              if (isCapturing) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _capPhase == 'recording'
                            ? Icons.fiber_manual_record
                            : Icons.timer,
                        color: scheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _capPhase == 'recording'
                            ? l10n.performRecording
                            : l10n.performCountIn(_countdown),
                        style: TextStyle(color: scheme.onPrimaryContainer),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (_stack.layers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    l10n.performEmptyHint,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _stack.layers.length,
                  itemBuilder: (context, i) {
                    final muted = _stack.isMuted(i);
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: muted
                              ? scheme.surfaceContainerHighest
                              : scheme.primaryContainer,
                          child: Text('${i + 1}'),
                        ),
                        title: Text(
                          _seedLabel(l10n, _stack.layers[i].label),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            muted ? Icons.volume_off : Icons.volume_up,
                          ),
                          tooltip:
                              muted ? l10n.performUnmute : l10n.performMute,
                          onPressed: () => toggleMute(i),
                        ),
                      ),
                    );
                  },
                ),
              if (_stack.layers.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.add_a_photo, size: 18),
                        label: Text(l10n.performSceneSave),
                        onPressed: saveScene,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _scenes.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final armed = _armed == i;
                            return InputChip(
                              selected: armed,
                              showCheckmark: false,
                              avatar: Icon(
                                armed
                                    ? Icons.hourglass_top
                                    : Icons.play_circle_outline,
                                size: 18,
                              ),
                              label: Text(
                                l10n.performSceneLabel(
                                  i + 1,
                                  sceneActiveCount(i),
                                ),
                              ),
                              onSelected: (_) =>
                                  _playing ? armScene(i) : launchScene(i),
                              onDeleted: () => removeScene(i),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (isPlayingIn) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _playInMode == 'beat'
                            ? l10n.performPlayInBeatHint
                            : l10n.performPlayInHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: cancelPlayIn,
                      child: Text(l10n.performCancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.check),
                      label: Text(l10n.performDone),
                      onPressed: finishPlayIn,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_playInMode == 'beat')
                  Row(
                    children: [
                      for (final pad in _kPads)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FilledButton.tonal(
                                  onPressed: () {
                                    _playHit(pad.$1);
                                    playInPad(pad.$1);
                                  },
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 20,
                                    ),
                                  ),
                                  child: Text(pad.$2(l10n)),
                                ),
                                TextButton(
                                  onPressed: () => _pickPadVoice(pad.$1),
                                  child: Text(
                                    hasPadVoice(pad.$1)
                                        ? (padVoiceName(pad.$1) ??
                                            l10n.performVoiceSample)
                                        : l10n.performVoiceSynth,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  )
                else ...[
                  SizedBox(
                    height: 36,
                    child: Row(
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.graphic_eq, size: 18),
                          label: Text(l10n.performPickSound),
                          onPressed: _pickVoice,
                        ),
                        const SizedBox(width: 8),
                        if (hasSampleVoice)
                          Expanded(
                            child: InputChip(
                              avatar: const Icon(Icons.music_note, size: 18),
                              label: Text(
                                _voiceName ?? l10n.performVoiceSample,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onDeleted: clearSampleVoice,
                            ),
                          )
                        else
                          Text(
                            l10n.performVoiceSynth,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 140,
                    child: PianoKeyboard(
                      whiteKeyCount: 8,
                      onKeyTap: (midi) {
                        if (hasSampleVoice) {
                          context.read<AudioService>().playWavBytes(
                                wavBytes(
                                  _toInt16(
                                    _pitched(
                                      midi,
                                      maxSamples: (kSampleRate * 0.7).round(),
                                    ),
                                  ),
                                ),
                              );
                        } else {
                          context
                              .read<AudioService>()
                              .playMidiNote(midi, ms: 400);
                        }
                        playInNote(midi);
                      },
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
