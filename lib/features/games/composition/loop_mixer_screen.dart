// lib/features/games/composition/loop_mixer_screen.dart
//
// "Loop-Mixer" — a kid loop-mixer toy that grows into a groovebox. Five cards
// (drums · bass · chords · melody · sparkle) each toggle a pre-authored 2-bar
// loop on/off; everything is in C pentatonic so any combination grooves (the
// Colour Melody rule). A creative sandbox: no stars, no wrong answers.
//
// v2 depth (PLAN.md « groovebox ladder », slice 3): a swing slider, per-card
// A/B/C pattern variants, per-card level sliders, and an automatic drum fill
// every 4th loop, applied at the loop seam.
//
// Audio: LoopEngine mixes the enabled tracks offline into ONE looping WAV
// (sample-accurate sync for free) played on a dedicated GaplessLoopPlayer.
// The screen owns the musical clock (a Stopwatch); user changes swap the
// fresh mix at the clock's phase (`play(position: …)`), so layers and feel
// change without the bar ever restarting. Seam-timed changes (the fill) are
// applied when the ticker sees the phase wrap: the new WAV starts near
// position 0 on the downbeat, where the kick masks the swap. A Ticker
// (created in initState — never a lazy `late final`, see CLAUDE.md) drives
// the step playhead and the wrap detection.

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:comet_beat/core/audio/aec_capability.dart';
import 'package:comet_beat/core/audio/aec_engine.dart';
import 'package:comet_beat/core/audio/beat_capture.dart';
import 'package:comet_beat/core/audio/daw_sources.dart' show GrooveSource;
import 'package:comet_beat/core/audio/groove_capture.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/loop_reference.dart';
import 'package:comet_beat/core/audio/loop_stack_render.dart'
    show crossfadePcm16Seam;
import 'package:comet_beat/core/audio/microphone_pitch_service.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/play_along.dart';
import 'package:comet_beat/core/audio/synth.dart'
    show
        Drum,
        Instrument,
        kDrumKits,
        midiToFrequency,
        renderSegments,
        timbreFor,
        wavBytes;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/beat_bridge.dart';
import 'package:comet_beat/core/services/gapless_loop_player.dart';
import 'package:comet_beat/core/services/melody_bridge.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:comet_beat/features/games/composition/custom_progressions.dart';
import 'package:comet_beat/features/games/composition/groove_notation.dart';
import 'package:comet_beat/features/games/composition/groove_play_along.dart';
import 'package:comet_beat/features/games/composition/groove_slots.dart';
import 'package:comet_beat/features/games/composition/loop_challenges.dart';
import 'package:comet_beat/features/games/composition/loop_creatures.dart';
import 'package:comet_beat/features/games/composition/loop_secrets.dart';
import 'package:comet_beat/features/games/composition/multipart_to_tracker.dart';
import 'package:comet_beat/features/games/composition/score_analysis_view.dart'
    show harmonicFunctionColor;
import 'package:comet_beat/features/games/composition/smear_pad.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/sound_lab/my_instruments_sheet.dart';
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/daw/send_to_daw.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:comet_beat/shared/music_io/music_export.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:comet_beat/shared/tutorial/primers.dart' show loopMixerPrimer;
import 'package:comet_beat/shared/widgets/step_grid.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show Clef, HarmonicFunction, Score, StaffView, multiPartToMusicXml;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoopMixerScreen extends StatefulWidget {
  const LoopMixerScreen({
    super.key,
    this.aecFactory,
    this.initialSpec,
    this.showAppBar = true,
    this.simpleLayout = false,
  });

  /// An optional groove to open with — lets another Workshop mode hand a
  /// [GrooveSpec] over (e.g. a tracker pattern → a groove). Null = the default
  /// starter groove.
  final GrooveSpec? initialSpec;

  /// The Loop Studio shell owns the app bar when embedding this editor.
  final bool showAppBar;

  /// Hide arrangement and production controls while retaining the same
  /// editable tracks, transport, BPM, and beat/tune editors.
  final bool simpleLayout;

  /// Builds the native Tier-3b [AecEngine] for graded jam mode, or returns null
  /// when the platform has no full-duplex plugin (web / not built) — then jam
  /// falls back to the platform `echoCancel`. Defaults to [createNativeAecEngine];
  /// tests inject a fake engine to drive the graded path headlessly.
  @visibleForTesting
  final AecEngine? Function()? aecFactory;

  /// The tempo presets (all keep the step grid integral — see LoopTiming).
  static const tempos = [75, 100, 120];

  /// Root-note labels for the key selector (index 0–11 = the transpose).
  static const _keyNames = [
    'C', 'C♯', 'D', 'D♯', 'E', 'F', //
    'F♯', 'G', 'G♯', 'A', 'A♯', 'B',
  ];

  /// Every 4th loop plays the drum fill.
  static const fillEvery = 4;

  @override
  State<LoopMixerScreen> createState() => _LoopMixerScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class LoopMixerTester {
  Set<String> get enabledTracks;
  String? get soloTrack;
  bool get isPlaying;
  int get tempoBpm;
  double get swing;
  String? get progressionId;
  int get loopIteration;
  int variantOf(String id);
  double levelOf(String id);
  void toggleTrack(String id);
  void toggleSolo(String id);
  void cycleTrackVariant(String id);
  void rollTrackVariant(String id);
  void setTrackLevel(String id, double level);
  void pauseOrResume();

  /// Whether track [id] can be voiced by a saved instrument (pitched tracks
  /// only), the id of its current voice (null = built-in timbre), and a setter
  /// that bypasses the picker sheet (headless tests can't drive it).
  bool trackIsPitched(String id);
  String? voiceIdOf(String id);
  void debugSetTrackVoice(String id, TrackerInstrument? voice);
  void setSwing(double value);
  void setTempo(int bpm);
  void setProgression(String? id);

  /// Root key (0–11) + scale of the pitched stems.
  int get key;
  void setKey(int key);
  GrooveScale get scale;
  void setScale(GrooveScale scale);

  /// The drum-kit timbre id.
  String get kitId;
  void setKit(String id);

  /// The band-flavour (style) id.
  String get styleId;
  void setStyle(String id);

  /// The master send effect on the whole mix, and a setter.
  LoopSend get send;
  void setSend(LoopSend value);

  /// One-knob master filter (−1 low-pass … 0 off … +1 high-pass).
  double get masterFilter;
  void setMasterFilter(double value);
  void stopAll();
  bool get scoreVisible;
  void toggleScorePanel();

  /// LM-UX4: the tappable drum step-grid that builds/edits the beat.
  bool get beatEditVisible;
  void toggleBeatEdit();
  void debugEditBeatCell(Drum drum, int step);
  DrumRowsPattern? get debugBeatPattern;

  /// LM-UX4b: the tappable diatonic step-grid that builds/edits the tune (the
  /// user melodic track), via the shared StepGridView + setUserTrack.
  bool get tuneEditVisible;
  void toggleTuneEdit();
  void debugEditTuneCell(int midi, int step);
  List<PatternCell>? get debugTuneCells;
  void debugSetTuneTarget(String id);
  String get grooveToken;
  bool loadGrooveToken(String token);
  bool get isInfinite;
  void toggleInfinite();

  /// Quantized launch: card changes queue to the next seam when on.
  bool get quantizeLaunch;
  void toggleQuantize();
  Set<String> get pendingLaunches;

  /// The current no-score band challenge, whether it's met, and a way to skip.
  String get currentChallengeId;
  bool get currentChallengeMet;
  void nextChallenge();

  /// Section/scene grid: capture the live layers into slot [i], relaunch a
  /// slot, whether a slot is empty, and the auto-advancing chain.
  void captureScene(int i);
  void launchScene(int i);
  bool sceneIsEmpty(int i);
  bool get isChaining;
  void toggleChain();

  /// §G-2: bake the captured section chain into one arranged track (for tests,
  /// the rendered PCM).
  bool get hasScenes;
  Float64List debugRenderArrangement();

  /// Scale-locked smear pad (§F-1): visibility, whether a lead is recorded, and
  /// keeping it as a layer. Tests: the in-key notes played, playing at a
  /// normalized x, and injecting a timed sample.
  bool get smearPadVisible;
  void toggleSmearPad();
  bool get hasSmearRecording;
  void keepSmear();
  List<int> get debugSmearNotes;
  void debugSmearAt(double x);
  void debugSmearSample(double ms, double x);
  bool get hasVoiceTrack;
  bool get hasBeatTrack;

  /// Shared-groove bridge: publish this mixer's beat so other modes can load it,
  /// and pull the shared beat in as the user beat track.
  void shareBeat();
  bool get canLoadSharedBeat;
  void loadSharedBeat();

  /// MelodyBridge: publish this mixer's tune / pull a shared one (pitched twin
  /// of shareBeat/loadSharedBeat).
  void shareTune();
  bool get canLoadSharedTune;
  void loadSharedTune();
  bool get isJamming;
  void toggleJam();

  /// True while jam mode is running on the Tier-3b full-duplex AEC (vs the
  /// platform `echoCancel` fallback).
  bool get usesAecJam;

  /// The latest live jam reading (null when not jamming / silent).
  PitchReading? get jamReading;

  /// True while "follow the melody" grading is on (only meaningful in jam).
  bool get isFollowing;

  /// Live per-pass accuracy of the follow grade (0..1).
  double get followAccuracy;

  /// Toggle "follow the melody" grading during jam.
  void toggleFollow();

  /// Grade one reading against the follow target at an explicit [elapsedMs]
  /// (the live grade reads a real Stopwatch, which widget tests can't advance).
  void debugFeedFollow(PitchReading reading, double elapsedMs);

  /// True when a pitched track is enabled — the Song Book / MusicXML export
  /// is offered (and enabled) only then.
  bool get hasPitchedTrack;

  /// Saves the current groove to the Song Book without the title dialog
  /// (headless tests can't drive it); returns the saved multi-part MusicXML,
  /// or null when nothing pitched is enabled.
  String? debugSaveToSongBook(UserSongsService songs);

  /// Send the whole current groove to the Multitrack (DAW) as a clip.
  void sendToDaw();

  /// Saves the current groove to a local slot (bypasses the name dialog).
  Future<void> debugSaveGroove(String name);

  /// The saved slot names.
  Future<List<String>> debugSlotNames();

  /// Loads a saved groove by name; true if found + applied.
  Future<bool> debugLoadGroove(String name);

  /// Installs a sung layer without the mic (headless tests can't record).
  void debugCaptureCells(List<PatternCell> cells);

  /// Installs a beatboxed layer without the mic.
  void debugCaptureBeat(DrumRowsPattern pattern);

  /// Forces the seam handler (normally driven by the real-time clock, which
  /// widget tests can't advance) — asserts fill scheduling without waiting.
  void debugLoopWrap();

  /// LM-UX7: add a custom harmony without the picker dialog (for tests); the
  /// count reflects the kid's saved harmonies.
  void debugAddCustomHarmony(List<ChordDegree> degrees);
  int get customHarmonyCount;
}

class _LoopMixerScreenState extends State<LoopMixerScreen>
    with SingleTickerProviderStateMixin
    implements LoopMixerTester {
  final _engine = LoopEngine();
  final _loop = GaplessLoopPlayer();

  /// The groove's musical clock: playback phase is derived from it, never
  /// from the player, so swaps can re-enter the loop in phase.
  final _clock = Stopwatch();

  late final Ticker _ticker;
  // LM-UX7: the kid's own saved harmonies, shown alongside the built-in ones.
  final _progStore = CustomProgressionStore();
  List<Progression> _customProgressions = const [];
  int _customProgId = 0; // session-unique ids for new harmonies

  final _step = ValueNotifier<int>(-1);

  /// Smooth loop phase 0..1 for the sweeping playhead; -1 while stopped.
  final _progress = ValueNotifier<double>(-1);
  final _tempoController = TextEditingController(text: '100');

  /// Current eighth-step index across the loop (LM-UX3) for the sheet-music
  /// note highlight; -1 while stopped. Changes ~8×/bar (not every frame), so
  /// the staff only re-lays out when the sounding note actually moves.
  final _hlStep = ValueNotifier<int>(-1);

  int _iteration = 0;
  int _lastPhaseMs = 0;
  bool _paused = false;

  /// What the loop player is currently looping (identity-compared against
  /// the engine's cached renders to decide whether a seam swap is needed).
  Uint8List? _currentWav;

  @override
  void initState() {
    super.initState();
    if (widget.initialSpec != null) _engine.applySpec(widget.initialSpec!);
    _tempoController.text = _engine.tempoBpm.toString();
    // LM-UX7: load the kid's saved harmonies (best-effort).
    _progStore.load().then((ps) {
      if (mounted) setState(() => _customProgressions = ps);
    });
    _ticker = createTicker((_) {
      if (!_clock.isRunning && !_paused) {
        _step.value = -1;
        _progress.value = -1;
        _hlStep.value = -1;
        return;
      }
      final t = _engine.timing;
      final phase = _clock.elapsedMilliseconds % t.totalMs;
      if (phase < _lastPhaseMs) _onLoopWrap();
      _lastPhaseMs = phase;
      _step.value = phase ~/ t.beatMs;
      _progress.value = phase / t.totalMs;
      _hlStep.value = (phase / (t.beatMs / 2)).floor(); // eighth-step index
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _step.dispose();
    _progress.dispose();
    _tempoController.dispose();
    _hlStep.dispose();
    _loop.dispose();
    _countInTimer?.cancel();
    _captureStopTimer?.cancel();
    _refPump?.cancel();
    _micSub?.cancel();
    _mic?.dispose();
    _jamMic?.dispose();
    _followAccuracy.dispose();
    super.dispose();
  }

  // --- LoopMixerTester ---
  @override
  Set<String> get enabledTracks => Set.unmodifiable(_engine.enabled);
  @override
  String? get soloTrack => _soloTrack;
  @override
  bool get isPlaying => _clock.isRunning;
  @override
  int get tempoBpm => _engine.tempoBpm;
  @override
  double get swing => _engine.swing;
  @override
  String? get progressionId => _engine.progression?.id;
  @override
  int get loopIteration => _iteration;
  @override
  int variantOf(String id) => _engine.variants[id] ?? 0;
  @override
  double levelOf(String id) => _engine.levels[id] ?? 1.0;
  @override
  void toggleTrack(String id) => _toggle(id);
  @override
  void toggleSolo(String id) => _toggleSolo(id);
  @override
  void cycleTrackVariant(String id) => _cycleVariant(id);
  @override
  void rollTrackVariant(String id) => _rollVariant(id);
  @override
  void setTrackLevel(String id, double level) => _setLevel(id, level);
  @override
  bool trackIsPitched(String id) =>
      _trackIsPitched(_engine.tracks.firstWhere((t) => t.id == id));
  @override
  String? voiceIdOf(String id) => _engine.trackVoice(id)?.id;
  @override
  void debugSetTrackVoice(String id, TrackerInstrument? voice) =>
      _setTrackVoice(id, voice);
  @override
  void setSwing(double value) => _setSwing(value);
  @override
  LoopSend get send => _engine.send;
  @override
  void setSend(LoopSend value) => _setSend(value);
  @override
  double get masterFilter => _engine.masterFilter;
  @override
  void setMasterFilter(double value) => _setMasterFilter(value);
  @override
  void setTempo(int bpm) => _setTempo(bpm);
  @override
  void setProgression(String? id) {
    Progression? found;
    for (final p in kProgressions) {
      if (p.id == id) found = p;
    }
    _setProgression(found);
  }

  @override
  int get key => _engine.key;
  @override
  void setKey(int key) => _setKey(key);
  @override
  GrooveScale get scale => _engine.scale;
  @override
  void setScale(GrooveScale scale) => _setScale(scale);
  @override
  String get kitId => _engine.kitId;
  @override
  void setKit(String id) => _setKit(id);
  @override
  String get styleId => _engine.styleId;
  @override
  void setStyle(String id) => _setStyle(id);

  @override
  void stopAll() => _stopAll();
  @override
  void pauseOrResume() => _pauseOrResume();
  @override
  void debugLoopWrap() => _onLoopWrap();

  @override
  int get customHarmonyCount => _customProgressions.length;

  @override
  void debugAddCustomHarmony(List<ChordDegree> degrees) {
    final p = Progression('custom-new-${_customProgId++}', degrees);
    setState(() => _customProgressions = [..._customProgressions, p]);
    _progStore.save(_customProgressions);
    _setProgression(p);
  }

  @override
  bool get scoreVisible => _showScore;
  @override
  void toggleScorePanel() => setState(() => _showScore = !_showScore);

  bool _showScore = false;

  // LM-UX4: the beat step-editor panel.
  bool _showBeatEdit = false;
  @override
  bool get beatEditVisible => _showBeatEdit;
  @override
  void toggleBeatEdit() => setState(() => _showBeatEdit = !_showBeatEdit);
  @override
  DrumRowsPattern? get debugBeatPattern => _engine.userBeatPattern;
  @override
  void debugEditBeatCell(Drum drum, int step) =>
      _toggleBeatEditCell(drum, step);

  /// The beat grid's step count — the user beat's length, or one bar.
  int get _beatSteps {
    final p = _engine.userBeatPattern;
    if (p == null) return LoopTiming.stepsPerBar;
    return p.rows.values.fold(
      LoopTiming.stepsPerBar,
      (m, r) => r.length > m ? r.length : m,
    );
  }

  /// Toggle one cell of the beat grid and re-render (LM-UX4). Reads/writes the
  /// user beat track, preserving the other lanes.
  void _toggleBeatEditCell(Drum drum, int step) {
    final steps = _beatSteps;
    final p = _engine.userBeatPattern;
    final rows = <Drum, List<bool>>{};
    if (p != null) {
      for (final e in p.rows.entries) {
        final row = List<bool>.filled(steps, false);
        for (var i = 0; i < e.value.length && i < steps; i++) {
          row[i] = e.value[i];
        }
        rows[e.key] = row;
      }
    }
    final lane = rows.putIfAbsent(drum, () => List<bool>.filled(steps, false));
    lane[step] = !lane[step];
    _engine.setUserBeatTrack(DrumRowsPattern(rows));
    _engine.enabled.add(LoopEngine.beatTrackId);
    setState(() {});
    _restartGroove();
  }

  // LM-UX4b/c: the tune (pitched) step-editor — reuses the shared StepGridView.
  bool _showTuneEdit = false;
  @override
  bool get tuneEditVisible => _showTuneEdit;
  @override
  void toggleTuneEdit() => setState(() => _showTuneEdit = !_showTuneEdit);
  @override
  List<PatternCell>? get debugTuneCells => _targetCells();
  @override
  void debugEditTuneCell(int midi, int step) => _toggleTuneCell(midi, step);
  @override
  void debugSetTuneTarget(String id) => setState(() => _tuneTarget = id);

  /// Which pitched part the tune editor edits: the user track ('voice' = "My
  /// tune") or a built-in stem (LM-UX4c, via the engine's cell-override).
  String _tuneTarget = LoopEngine.userTrackId;
  static const _tuneTargets = [
    LoopEngine.userTrackId,
    'melody',
    'chords',
    'bass',
  ];

  bool get _tuneTargetIsUser => _tuneTarget == LoopEngine.userTrackId;

  /// The authored-C cells behind the current tune target (null = none yet).
  List<PatternCell>? _targetCells() => _tuneTargetIsUser
      ? _engine.userTrackCells
      : _engine.trackCellsOverride(_tuneTarget);

  /// The tune editor's pitch rows — one octave of C major pentatonic. Cells are
  /// authored in C (like every built-in stem); the engine's `pitchTranspose`
  /// shifts the whole pattern into the current key AND scale at render (the
  /// same `{0,2,4,7,9} + pitchTranspose` rule), so edits always fit the band and
  /// follow later key/scale changes.
  List<int> get _tuneRows =>
      const [0, 2, 4, 7, 9, 12].map((d) => 60 + d).toList();

  /// The target's cells as grid cells (one StepCell per pitch per onset).
  List<StepCell> _tuneStepCells() {
    final cells = _targetCells() ?? const <PatternCell>[];
    final out = <StepCell>[];
    var pos = 0;
    for (final c in cells) {
      final midis = c.midis;
      if (midis != null) {
        for (final m in midis) {
          out.add(StepCell(m, pos, len: c.steps));
        }
      }
      pos += c.steps;
    }
    return out;
  }

  /// Grid cells → a bar of [PatternCell]s (rests fill the gaps).
  List<PatternCell> _stepCellsToPattern(List<StepCell> cells, int steps) {
    final byStep = <int, List<int>>{};
    for (final c in cells) {
      (byStep[c.step] ??= []).add(c.row);
    }
    final out = <PatternCell>[];
    var pos = 0;
    while (pos < steps) {
      final midis = byStep[pos];
      var next = pos + 1;
      while (next < steps && !byStep.containsKey(next)) {
        next++;
      }
      out.add((midis: midis, steps: next - pos));
      pos = next;
    }
    return out;
  }

  void _toggleTuneCell(int midi, int step) {
    const steps = kPatternSteps; // pitched patterns fill 2 bars
    final cells = _tuneStepCells();
    final idx = cells.indexWhere((c) => c.row == midi && c.step == step);
    final next = [...cells];
    if (idx >= 0) {
      next.removeAt(idx);
    } else {
      next.add(StepCell(midi, step, len: 2));
    }
    final pattern =
        next.isEmpty ? <PatternCell>[] : _stepCellsToPattern(next, steps);
    if (_tuneTargetIsUser) {
      if (next.isEmpty) {
        _engine.clearUserTrack();
      } else {
        _engine.setUserTrack(pattern, instrument: Instrument.musicBox);
        _engine.enabled.add(LoopEngine.userTrackId);
      }
    } else {
      // A built-in stem: override its pattern (empty clears back to the preset).
      _engine.setTrackCells(_tuneTarget, pattern);
      if (next.isNotEmpty) _engine.enabled.add(_tuneTarget);
    }
    setState(() {});
    _restartGroove();
  }

  bool _infinite = false;

  // §F-1 smear pad: a scale-locked solo surface. Each played note is recorded
  // with its loop phase so "Keep" can quantize the improvisation into a layer.
  bool _showSmear = false;
  final List<PitchSample> _smearSamples = [];

  // Quantized launch: when on, toggling a playing card queues the change until
  // the next loop seam (it "arms") so layers always drop in on the beat.
  bool _quantize = false;
  final Set<String> _pendingLaunches = {};
  String? _soloTrack;
  Set<String>? _enabledBeforeSolo;

  // Section/scene grid (§G-1): 4 snapshot slots of the live layer set. Tap a
  // filled scene to relaunch it; a chain plays them in sequence at each seam.
  final List<GrooveScene?> _scenes = List<GrooveScene?>.filled(4, null);
  bool _chaining = false;
  int _chainIndex = 0;

  // Band challenges (§E-2): a gentle, no-score prompt at a time.
  int _challengeIndex = 0;
  BandChallenge get _challenge =>
      kBandChallenges[_challengeIndex % kBandChallenges.length];
  bool get _challengeMet => _challenge.check(_engine.enabled);

  @override
  bool get isInfinite => _infinite;
  @override
  bool get quantizeLaunch => _quantize;
  @override
  void toggleQuantize() => _toggleQuantize();
  @override
  Set<String> get pendingLaunches => _pendingLaunches;
  @override
  String get currentChallengeId => _challenge.id;
  @override
  bool get currentChallengeMet => _challengeMet;
  @override
  void nextChallenge() => _nextChallenge();
  @override
  void captureScene(int i) => _captureScene(i);
  @override
  void launchScene(int i) => _launchScene(i);
  @override
  bool sceneIsEmpty(int i) => _scenes[i] == null;
  @override
  bool get isChaining => _chaining;
  @override
  void toggleChain() => _toggleChain();
  @override
  bool get hasScenes => _scenes.any((s) => s != null);
  @override
  Float64List debugRenderArrangement() =>
      _engine.renderArrangement(_capturedScenes());
  @override
  bool get smearPadVisible => _showSmear;
  @override
  void toggleSmearPad() => _toggleSmearPad();
  @override
  bool get hasSmearRecording => _smearSamples.isNotEmpty;
  @override
  void keepSmear() => _keepSmear();
  @override
  List<int> get debugSmearNotes => [
        for (final s in _smearSamples)
          if (s.$2 != null) s.$2!,
      ];
  int _smearMidiAt(double x) => smearMidi(
        x,
        key: _engine.key,
        minor: _engine.scale == GrooveScale.minorPentatonic,
      );
  @override
  void debugSmearAt(double x) => _playSmearNote(_smearMidiAt(x));
  @override
  void debugSmearSample(double ms, double x) =>
      _playSmearNote(_smearMidiAt(x), atMs: ms);
  @override
  void toggleInfinite() => setState(() => _infinite = !_infinite);

  // --- Capture (sing / beatbox): count-in → record 2 bars → a new card ---

  MicrophonePitchService? _mic;
  StreamSubscription<PitchReading>? _micSub;
  final _captureClock = Stopwatch();

  /// Raw capture frames — the voice path reads (ms, midi), the beat path
  /// reads (ms, rms, zcr, pitchedLow); one recording serves both.
  final List<({double ms, int? midi, double rms, double zcr})> _frames = [];
  Timer? _countInTimer;
  Timer? _captureStopTimer;
  _CapturePhase _capturePhase = _CapturePhase.idle;
  _CaptureMode _captureMode = _CaptureMode.voice;
  int _countdown = 0;

  @override
  bool get hasVoiceTrack =>
      _engine.tracks.any((t) => t.id == LoopEngine.userTrackId);
  @override
  bool get hasBeatTrack =>
      _engine.tracks.any((t) => t.id == LoopEngine.beatTrackId);

  @override
  void debugCaptureCells(List<PatternCell> cells) {
    setState(() {
      _engine.setUserTrack(cells);
      _engine.enabled.add(LoopEngine.userTrackId);
    });
    _restartGroove();
  }

  @override
  void debugCaptureBeat(DrumRowsPattern pattern) {
    setState(() {
      _engine.setUserBeatTrack(pattern);
      _engine.enabled.add(LoopEngine.beatTrackId);
    });
    _restartGroove();
  }

  // --- Shared-groove bridge --------------------------------------------------

  @override
  void shareBeat() {
    final pattern = _engine.userBeatPattern;
    if (pattern == null) return;
    BeatBridge.instance.publish(
      SharedBeat(
        rows: pattern.rows,
        tempoBpm: _engine.tempoBpm,
        swing: _engine.swing,
        source: 'loopmixer',
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.beatShared)),
    );
  }

  @override
  bool get canLoadSharedBeat => BeatBridge.instance.hasBeat;

  @override
  void loadSharedBeat() {
    final shared = BeatBridge.instance.current;
    if (shared == null || shared.isEmpty) return;
    setState(() {
      _engine.setUserBeatTrack(shared.toDrumPattern());
      _engine.enabled.add(LoopEngine.beatTrackId);
    });
    _restartGroove();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.beatLoaded)),
    );
  }

  @override
  void shareTune() {
    final cells = _engine.userTrackCells;
    if (cells == null || cells.isEmpty) return;
    MelodyBridge.instance.publish(
      SharedMelody(
        cells: cells,
        tempoBpm: _engine.tempoBpm,
        key: _engine.key,
        source: 'loopmixer',
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.tuneShared)),
    );
  }

  @override
  bool get canLoadSharedTune => MelodyBridge.instance.hasMelody;

  @override
  void loadSharedTune() {
    final shared = MelodyBridge.instance.current;
    if (shared == null || shared.isEmpty) return;
    setState(() {
      _engine.setUserTrack(shared.toCells(), instrument: Instrument.musicBox);
      _engine.enabled.add(LoopEngine.userTrackId);
    });
    _restartGroove();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.tuneLoaded)),
    );
  }

  /// The capture always spans 2 straight bars at the current tempo (what a
  /// non-follower track tiles from), regardless of progression or swing.
  int get _captureMs => LoopTiming(tempoBpm: _engine.tempoBpm).totalMs;

  Future<void> _startCapture(_CaptureMode mode) async {
    if (_capturePhase != _CapturePhase.idle) return;
    final audio = context.read<AudioService>();
    if (_jamming) await _stopJam();
    if (!mounted) return;
    // Silence the band while the mic listens — the detector is monophonic
    // and would transcribe the loop playback instead of the performer.
    unawaited(_loop.stop());
    _clock.stop();
    setState(() {
      _captureMode = mode;
      _capturePhase = _CapturePhase.countIn;
      _countdown = 4;
    });
    unawaited(audio.playTick(accent: true));
    _countInTimer = Timer.periodic(
      Duration(milliseconds: _engine.timing.beatMs),
      (timer) {
        if (!mounted) return timer.cancel();
        if (_countdown <= 1) {
          timer.cancel();
          unawaited(_beginRecording());
        } else {
          setState(() => _countdown--);
          unawaited(audio.playTick());
        }
      },
    );
  }

  Future<void> _beginRecording() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    _frames.clear();
    final mic = _mic ??= MicrophonePitchService();
    mic.echoCancel = false; // full accuracy; nothing plays during capture
    try {
      _micSub = mic.readings.listen((reading) {
        final frame = (
          ms: _captureClock.elapsedMilliseconds.toDouble(),
          midi: reading.hasPitch ? reading.nearestMidi : null,
          rms: reading.rms,
          zcr: reading.zcr,
        );
        _frames.add(frame);
      });
      await mic.start();
    } on PitchCaptureException {
      await _micSub?.cancel();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.loopMixerSingNothing)),
      );
      setState(() => _capturePhase = _CapturePhase.idle);
      _restartGroove();
      return;
    }
    if (!mounted) return;
    _captureClock
      ..reset()
      ..start();
    setState(() => _capturePhase = _CapturePhase.recording);
    _captureStopTimer =
        Timer(Duration(milliseconds: _captureMs), _finishRecording);
  }

  Future<void> _finishRecording() async {
    _captureClock.stop();
    await _mic?.stop();
    await _micSub?.cancel();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    var captured = false;
    setState(() {
      _capturePhase = _CapturePhase.idle;
      switch (_captureMode) {
        case _CaptureMode.voice:
          final cells = quantizeToGroove(
            [for (final f in _frames) (f.ms, f.midi)],
            totalMs: _captureMs,
          );
          if (cells != null) {
            _engine.setUserTrack(
              cells,
              instrument: context.read<AudioService>().instrument,
            );
            _engine.enabled.add(LoopEngine.userTrackId);
            captured = true;
          }
        case _CaptureMode.beat:
          final pattern = quantizeToBeat(
            [
              for (final f in _frames)
                (
                  ms: f.ms,
                  rms: f.rms,
                  zcr: f.zcr,
                  pitchedLow: f.midi != null && f.midi! < 60,
                ),
            ],
            totalMs: _captureMs,
          );
          if (pattern != null) {
            _engine.setUserBeatTrack(pattern);
            _engine.enabled.add(LoopEngine.beatTrackId);
            captured = true;
          }
      }
    });
    if (!captured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.loopMixerSingNothing)),
      );
    }
    _restartGroove();
  }

  // --- Jam mode: play/sing over the groove, see how each note fits ---

  bool _jamming = false;
  final _jamReading = ValueNotifier<PitchReading?>(null);

  // Tier-3b graded jam: the native full-duplex engine plays the loop PCM we
  // feed it AND cancels it from the mic, so the cleaned reading grades the
  // player, not the speaker. Null in the echoCancel fallback path.
  AecEngine? _jamAec;
  MicrophonePitchService? _jamMic;
  LoopReferenceScheduler? _refScheduler;
  Timer? _refPump;

  static const _kJamSampleRate = 44100;
  static const _refPumpInterval = Duration(milliseconds: 50);
  static const _refTickSamples =
      _kJamSampleRate * 50 ~/ 1000; // one interval's worth
  static const _refPrimeSamples = _refTickSamples * 2; // ~100 ms prebuffer

  // "Follow the melody": grade the player against the leading track's line
  // (the tune on the score panel) with the same PlayAlongEngine as Play Along,
  // looping over the groove. Null unless follow mode is on while jamming.
  PlayAlongEngine? _followEngine;
  final _followAccuracy = ValueNotifier<double>(0);

  /// One jam reading: colour it (jamFit) and, when following, grade it against
  /// the target line at the groove's live clock.
  void _onJamReading(PitchReading r) {
    _jamReading.value = r;
    final follow = _followEngine;
    if (follow != null) {
      follow.update(
        elapsedMs: _clock.elapsedMilliseconds.toDouble(),
        reading: r,
      );
      _followAccuracy.value = follow.accuracy;
    }
  }

  /// Builds a looping [PlayAlongEngine] over the leading enabled track's line,
  /// or null when there's nothing pitched to follow. The practice loop spans
  /// the whole chart so it re-arms every groove pass; no count-in — the groove
  /// is already playing.
  PlayAlongEngine? _buildFollowEngine() {
    final id = _engravedTrackId;
    if (id == null) return null;
    // Transposed cells so the sing-along target matches the current key/scale.
    final cells = _engine.engravedCellsFor(id);
    if (cells == null) return null;
    final chart = grooveChart(
      cells,
      bpm: _engine.tempoBpm,
      name: id,
      octaveAgnostic: id == 'voice',
    );
    if (chart.notes.isEmpty) return null;
    return PlayAlongEngine(chart, leadInBeats: 0)..setLoop(0, chart.totalBeats);
  }

  @override
  bool get isFollowing => _followEngine != null;

  @override
  double get followAccuracy => _followAccuracy.value;

  @override
  void toggleFollow() {
    setState(() {
      if (_followEngine != null) {
        _followEngine = null;
        _followAccuracy.value = 0;
      } else {
        _followEngine = _buildFollowEngine();
      }
    });
  }

  @override
  void debugFeedFollow(PitchReading reading, double elapsedMs) {
    final follow = _followEngine;
    if (follow == null) return;
    follow.update(elapsedMs: elapsedMs, reading: reading);
    _followAccuracy.value = follow.accuracy;
  }

  @override
  bool get isJamming => _jamming;

  @override
  bool get usesAecJam => _jamAec != null;

  @override
  PitchReading? get jamReading => _jamReading.value;

  @override
  void toggleJam() {
    if (_jamming) {
      unawaited(_stopJam());
    } else {
      unawaited(_startJam());
    }
  }

  Future<void> _startJam() async {
    if (_capturePhase != _CapturePhase.idle || _jamming) return;
    final aec = (widget.aecFactory ?? createNativeAecEngine)();
    if (aec != null) {
      await _startAecJam(aec);
    } else {
      await _startEchoCancelJam();
    }
  }

  /// Tier-3b graded jam. Hands playback to the full-duplex engine: stop the
  /// loop player and pump the loop PCM into the engine's reference (which it
  /// plays out the speaker AND cancels), then analyse the cleaned near-end.
  Future<void> _startAecJam(AecEngine aec) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final mic = MicrophonePitchService(aec: aec);
    unawaited(_loop.stop());
    final scheduler = LoopReferenceScheduler(_loopPcm());
    try {
      _micSub = mic.readings.listen(_onJamReading);
      await mic.start();
    } catch (e) {
      await _micSub?.cancel();
      await mic.dispose();
      if (kDebugMode) {
        debugPrint('[LOOP] AEC jam unavailable, falling back: $e');
      }
      _syncPlayback(); // resume the audible groove
      await _startEchoCancelJam(); // Tier 0/1 fallback
      return;
    }
    _jamAec = aec;
    _jamMic = mic;
    _refScheduler = scheduler;
    // Prime the reference ring, then keep it fed just ahead of the drain.
    mic.pushReference(scheduler.nextWindow(_refPrimeSamples));
    _refPump = Timer.periodic(_refPumpInterval, (_) {
      final s = _refScheduler;
      if (s != null) _jamMic?.pushReference(s.nextWindow(_refTickSamples));
    });
    if (!mounted) return;
    setState(() => _jamming = true);
    messenger.showSnackBar(SnackBar(content: Text(l10n.loopMixerJamHintAec)));
  }

  /// Fallback jam (tiers 0/1): the groove keeps playing on the loop player and
  /// the platform's echo canceller pulls the speaker out of the mic (headphones
  /// are better — the hint says so). No AEC here → the meter is just noisier.
  Future<void> _startEchoCancelJam() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final mic = _mic ??= MicrophonePitchService();
    mic.echoCancel = true;
    try {
      _micSub = mic.readings.listen(_onJamReading);
      await mic.start();
    } catch (e) {
      await _micSub?.cancel();
      mic.echoCancel = false;
      if (kDebugMode) debugPrint('[LOOP] jam mic unavailable: $e');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.loopMixerSingNothing)),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _jamming = true);
    messenger.showSnackBar(SnackBar(content: Text(l10n.loopMixerJamHint)));
  }

  Future<void> _stopJam() async {
    // Flip the visible state synchronously (instant button response); the
    // engine/mic teardown runs after and its awaits don't gate the UI.
    _refPump?.cancel();
    _refPump = null;
    final aecMic = _jamMic;
    final sub = _micSub;
    _micSub = null;
    _jamMic = null;
    _jamAec = null;
    _refScheduler = null;
    _jamReading.value = null;
    _followEngine = null;
    _followAccuracy.value = 0;
    if (mounted) setState(() => _jamming = false);
    if (aecMic != null) {
      await aecMic.stop();
      await sub?.cancel();
      await aecMic.dispose();
      _syncPlayback(); // hand playback back to the loop player
      return;
    }
    await _mic?.stop();
    await sub?.cancel();
    _mic?.echoCancel = false;
  }

  /// The current loop as raw mono PCM16 (the AEC reference), stripped of the
  /// WAV header — the same bytes the loop player would sound.
  Uint8List _loopPcm() => _pcmOf(
        _infinite
            ? _engine.renderVariedLoop(_iteration, fill: _fillDue)
            : _engine.renderLoop(fill: _fillDue),
      );

  Uint8List _pcmOf(Uint8List wav) {
    final data = readWavPcm16(wav).samples;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// The bar the groove is in right now (for chord-fit feedback).
  int get _currentBar {
    final t = _engine.timing;
    if (!_clock.isRunning) return 0;
    return (_clock.elapsedMilliseconds % t.totalMs) ~/
        (t.beatMs * LoopTiming.beatsPerBar);
  }

  @override
  String get grooveToken => encodeGrooveToken(_engine.spec);

  @override
  bool loadGrooveToken(String token) {
    final spec = decodeGrooveToken(token);
    if (spec == null) return false;
    setState(() => _engine.applySpec(spec));
    _restartGroove();
    return true;
  }

  Future<GrooveSlotsService> _slotsService() async =>
      GrooveSlotsService(await SharedPreferences.getInstance());

  /// Names the current groove and saves it to the local slot list.
  Future<void> _saveGrooveSlot() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.loopMixerSaveSlot),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.loopMixerSlotNameHint),
          onSubmitted: (v) => Navigator.pop(dialog, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, controller.text),
            child: Text(l10n.loopMixerSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || name == null || name.trim().isEmpty) return;
    await (await _slotsService()).save(name, grooveToken);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.loopMixerSlotSaved(name.trim()))),
    );
  }

  /// Lists the saved grooves; tap loads one, the bin deletes it.
  Future<void> _openSlots() async {
    final l10n = AppLocalizations.of(context)!;
    final service = await _slotsService();
    var slots = service.list();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setSheet) => slots.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l10n.loopMixerNoSlots),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final slot in slots)
                      ListTile(
                        leading: const Icon(Icons.queue_music),
                        title: Text(slot.name),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            slots = await service.delete(slot.name);
                            setSheet(() {});
                          },
                        ),
                        onTap: () {
                          Navigator.pop(sheet);
                          loadGrooveToken(slot.token);
                        },
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Future<void> debugSaveGroove(String name) async =>
      (await _slotsService()).save(name, grooveToken);

  @override
  Future<List<String>> debugSlotNames() async =>
      (await _slotsService()).list().map((s) => s.name).toList();

  @override
  Future<bool> debugLoadGroove(String name) async {
    for (final slot in (await _slotsService()).list()) {
      if (slot.name == name) return loadGrooveToken(slot.token);
    }
    return false;
  }

  Future<void> _openShareSheet() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(l10n.loopMixerCopyCode),
              onTap: () => Navigator.pop(sheet, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste_go),
              title: Text(l10n.loopMixerPasteCode),
              onTap: () => Navigator.pop(sheet, 'paste'),
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_add),
              title: Text(l10n.loopMixerSaveSlot),
              enabled: _engine.enabled.isNotEmpty,
              onTap: () => Navigator.pop(sheet, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.bookmarks),
              title: Text(l10n.loopMixerMySlots),
              onTap: () => Navigator.pop(sheet, 'slots'),
            ),
            ListTile(
              leading: const Icon(Icons.library_music),
              title: Text(l10n.loopMixerSaveSongBook),
              enabled: hasPitchedTrack,
              onTap: () => Navigator.pop(sheet, 'songbook'),
            ),
            ListTile(
              leading: const Icon(Icons.music_note),
              title: Text(l10n.loopMixerExportMusicXml),
              enabled: hasPitchedTrack,
              onTap: () => Navigator.pop(sheet, 'musicxml'),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: Text(l10n.musicExportTitle),
              enabled: hasPitchedTrack,
              onTap: () => Navigator.pop(sheet, 'export'),
            ),
            ListTile(
              leading: const Icon(Icons.grid_view),
              title: Text(l10n.loopMixerOpenTracker),
              enabled: hasPitchedTrack,
              onTap: () => Navigator.pop(sheet, 'tracker'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text(l10n.loopMixerOpenWorkshop),
              enabled: hasPitchedTrack,
              onTap: () => Navigator.pop(sheet, 'workshop'),
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: Text(l10n.loopMixerSaveAudio),
              enabled: _engine.enabled.isNotEmpty,
              onTap: () => Navigator.pop(sheet, 'wav'),
            ),
            ListTile(
              leading: const Icon(Icons.library_add),
              title: Text(l10n.dawSend),
              enabled: _engine.enabled.isNotEmpty,
              onTap: () => Navigator.pop(sheet, 'daw'),
            ),
            // Shared-groove bridge: publish this mixer's beat / pull the beat
            // another mode (e.g. the Drum Kit) shared.
            ListTile(
              leading: const Icon(Icons.upload),
              title: Text(l10n.beatShare),
              enabled: _engine.userBeatPattern != null,
              onTap: () => Navigator.pop(sheet, 'shareBeat'),
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: Text(l10n.beatLoadShared),
              enabled: BeatBridge.instance.hasBeat,
              onTap: () => Navigator.pop(sheet, 'loadBeat'),
            ),
            // MelodyBridge: the pitched twin — share/pull the tune.
            ListTile(
              leading: const Icon(Icons.upload),
              title: Text(l10n.tuneShare),
              enabled: _engine.userTrackCells != null,
              onTap: () => Navigator.pop(sheet, 'shareTune'),
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: Text(l10n.tuneLoadShared),
              enabled: MelodyBridge.instance.hasMelody,
              onTap: () => Navigator.pop(sheet, 'loadTune'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'shareBeat':
        shareBeat();
      case 'loadBeat':
        loadSharedBeat();
      case 'shareTune':
        shareTune();
      case 'loadTune':
        loadSharedTune();
      case 'copy':
        await Clipboard.setData(ClipboardData(text: grooveToken));
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.loopMixerCodeCopied)),
        );
      case 'paste':
        await _promptForToken();
      case 'save':
        await _saveGrooveSlot();
      case 'slots':
        await _openSlots();
      case 'songbook':
        await _saveToSongBook();
      case 'musicxml':
        await _exportMusicXml();
      case 'export':
        _exportGroove();
      case 'tracker':
        _openInTracker();
      case 'workshop':
        _openInWorkshop();
      case 'wav':
        await _saveWav();
      case 'daw':
        sendToDaw();
      default:
        break;
    }
  }

  /// True when at least one *pitched* track is enabled — the only case where
  /// there's a real score to save (drums/beat are unpitched, see [grooveParts]).
  @override
  bool get hasPitchedTrack => _engravedTrackId != null;

  @override
  String? debugSaveToSongBook(UserSongsService songs) {
    final xml = _grooveMusicXml();
    if (xml == null) return null;
    _writeGrooveToSongBook(songs, AppLocalizations.of(context)!.gameLoopMixer);
    return xml;
  }

  @override
  void sendToDaw() {
    if (_engine.enabled.isEmpty) return;
    // The spec is a value, so this is a snapshot of the current groove.
    sendToMultitrack(context, GrooveSource(_engine.spec));
  }

  /// The current groove as a multi-part MusicXML string (one part per enabled
  /// pitched track), or null when nothing pitched is enabled. Shared by the
  /// Song Book save and the MusicXML export.
  String? _grooveMusicXml() {
    final l10n = AppLocalizations.of(context)!;
    final parts = grooveParts(_engine, nameOf: (id) => _trackLabel(l10n, id));
    if (parts == null) return null;
    return multiPartToMusicXml(parts.score, partNames: parts.partNames);
  }

  /// Export the groove's notation to any format (the shared music-export sheet).
  void _exportGroove() {
    final l10n = AppLocalizations.of(context)!;
    final parts = grooveParts(_engine, nameOf: (id) => _trackLabel(l10n, id));
    if (parts == null) return;
    showMusicExportSheet(
      context,
      multiPart: parts.score,
      partNames: parts.partNames,
      baseName: 'groove',
    );
  }

  /// Send the groove's pitched tracks into the Advanced Tracker to keep editing
  /// on the grid (via the score bridge — one chromatic channel per track).
  void _openInTracker() {
    final l10n = AppLocalizations.of(context)!;
    final parts = grooveParts(_engine, nameOf: (id) => _trackLabel(l10n, id));
    if (parts == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdvancedTrackerScreen(
          initialSong: trackerSongFromMultiPart(parts.score),
        ),
      ),
    );
  }

  /// Open the groove in the Score Workshop for staff editing.
  void _openInWorkshop() {
    final l10n = AppLocalizations.of(context)!;
    final parts = grooveParts(_engine, nameOf: (id) => _trackLabel(l10n, id));
    if (parts == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CompositionWorkshopScreen(
          initialScore: parts.score,
          initialNames: parts.partNames,
        ),
      ),
    );
  }

  /// Persists the groove into the Song Book as a real multi-part score — the
  /// pedagogical payoff: the thing you built by tapping cards IS notation, and
  /// the on-ramp to editing it in the Workshop.
  Future<void> _saveToSongBook() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final songs = context.read<UserSongsService>();

    final controller = TextEditingController(text: l10n.gameLoopMixer);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.loopMixerSaveTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l10n.myMelodySave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || !mounted) return;

    final name = title.trim().isEmpty ? l10n.gameLoopMixer : title.trim();
    if (!_writeGrooveToSongBook(songs, name)) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.myMelodySaved)));
  }

  /// Core save (no UI) — shared by [_saveToSongBook] and the test seam.
  /// Returns false when there's no pitched track to engrave.
  bool _writeGrooveToSongBook(UserSongsService songs, String name) {
    final xml = _grooveMusicXml();
    if (xml == null) return false;
    songs.addSong(
      ImportedSong(
        id: 'groove-${DateTime.now().millisecondsSinceEpoch}',
        title: name,
        musicXml: xml,
      ),
    );
    return true;
  }

  /// Desktop: a save dialog for the groove's MusicXML. Same reach as the WAV
  /// export — platforms without a save dialog report it isn't available here;
  /// the groove code and Song Book save still travel everywhere.
  Future<void> _exportMusicXml() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final xml = _grooveMusicXml();
    if (xml == null) return;
    try {
      final location = await getSaveLocation(
        suggestedName: 'groove.musicxml',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'MusicXML', extensions: ['musicxml', 'xml']),
        ],
      );
      if (location == null || !mounted) return; // cancelled
      await XFile.fromData(
        Uint8List.fromList(utf8.encode(xml)),
        mimeType: 'application/vnd.recordare.musicxml+xml',
        name: 'groove.musicxml',
      ).saveTo(location.path);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.workshopSavedTo(location.path))),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[LOOP] musicxml save unavailable: $e');
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.loopMixerSaveFailed)),
      );
    }
  }

  Future<void> _promptForToken() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.loopMixerPasteCode),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'KU1.…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, controller.text),
            child: Text(l10n.loopMixerLoad),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || token == null || token.isEmpty) return;
    if (!loadGrooveToken(token)) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.loopMixerCodeInvalid)),
      );
    }
  }

  /// Desktop: a save dialog for the current loop's WAV. Platforms without
  /// one (web/mobile) just report that audio saving isn't available there —
  /// audio is juice, the groove code still travels everywhere.
  Future<void> _saveWav() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Render off the UI isolate so exporting a long/complex groove never
      // freezes the frame. We send only the small serializable GrooveSpec (not
      // the whole engine + its stem cache), rebuild + render in the worker.
      final spec = _engine.spec;
      final wav = await Isolate.run(
        () => (LoopEngine()..applySpec(spec)).renderLoop(),
      );
      if (!mounted) return;
      // Offer WAV or MP3 (both pure-Dart, web-safe) from the shared sheet.
      final pcm = wavToMonoFloat(readWavPcm16(wav));
      await showAudioExportSheet(context, pcm: pcm, baseName: 'groove');
    } catch (e) {
      if (kDebugMode) debugPrint('[LOOP] wav save unavailable: $e');
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.loopMixerSaveFailed)),
      );
    }
  }

  /// The most melodic enabled track — what the score panel engraves.
  String? get _engravedTrackId {
    for (final id in const ['voice', 'melody', 'chords', 'sparkle', 'bass']) {
      if (_engine.enabled.contains(id) && _engine.cellsFor(id) != null) {
        return id;
      }
    }
    return null;
  }

  /// The live-engraving panel: one small labelled staff per enabled track
  /// (pitched tracks as real notes, drums/beat as a rhythm reduction), or a
  /// hint when nothing is enabled yet — so the toggle always shows something.
  Widget _buildScorePanel(AppLocalizations l10n) {
    final rows = <Widget>[];
    for (final track in _engine.tracks) {
      if (!_engine.enabled.contains(track.id)) continue;
      // engravedCellsFor = cellsFor transposed by the current key/scale, so the
      // staff tracks transposition once that UI lands (identity at C major).
      final cells = _engine.engravedCellsFor(track.id);
      Score? score;
      Clef clef = Clef.treble;
      if (cells != null) {
        clef = clefForGrooveCells(cells);
        score = grooveScore(cells, clef: clef);
      } else {
        // Unpitched (drums / beatbox): a one-staff rhythm reduction.
        final variant = (_engine.variants[track.id] ?? 0)
            .clamp(0, track.variants.length - 1);
        final pattern = track.variants[variant];
        if (pattern is DrumRowsPattern) score = drumGrooveScore(pattern);
      }
      if (score == null) continue;
      rows.add(_scoreStaffRow(l10n, track.id, score));
    }
    // Show up to three staves at once; more scroll. Each row is a fixed height
    // so the whole band is visible together, not one tall staff at a time.
    final visible = rows.length < 3 ? rows.length : 3;
    return Card(
      child: SizedBox(
        height: rows.isEmpty ? 52 : (visible * (_scoreRowHeight + 4) + 8),
        child: rows.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    l10n.loopMixerScoreEmpty,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(mainAxisSize: MainAxisSize.min, children: rows),
              ),
      ),
    );
  }

  /// Per-track staff row height (LM-UX2 — was cramped at 42).
  static const double _scoreRowHeight = 68;

  /// One track's pulsing card — shared by the stacked (narrow) and side-by-side
  /// (wide) layouts (LM-UX1).
  Widget _trackTile(AppLocalizations l10n, LoopTrack track) {
    return _BeatPulse(
      step: _step,
      active: _engine.enabled.contains(track.id),
      beatsPerBar: LoopTiming.beatsPerBar,
      color: _trackColors[track.id]!,
      child: _TrackCard(
        color: _trackColors[track.id]!,
        shape: creatureShapeFor(track.id),
        label: _trackLabel(l10n, track.id),
        active: _engine.enabled.contains(track.id),
        armed: _pendingLaunches.contains(track.id),
        variant: _engine.variants[track.id] ?? 0,
        variantCount: track.variants.length,
        level: _engine.levels[track.id] ?? 1.0,
        onTap: () => _toggle(track.id),
        onCycleVariant: () => _cycleVariant(track.id),
        onRollVariant: () => _rollVariant(track.id),
        onLevel: (v) => _setLevel(track.id, v),
        soloed: _soloTrack == track.id,
        onSolo: () => _toggleSolo(track.id),
        voiced: _engine.trackVoice(track.id) != null,
        onVoice:
            _trackIsPitched(track) ? () => _pickVoice(l10n, track.id) : null,
      ),
    );
  }

  /// The track lane: cards stacked on a narrow screen, or laid out as ~5 panels
  /// side by side on a wide one to reclaim vertical space (LM-UX1).
  Widget _trackLane(AppLocalizations l10n) {
    final tracks = _engine.tracks;
    return LayoutBuilder(
      builder: (context, c) {
        // Stack on phones; only genuinely wide screens (tablet/desktop/landscape)
        // spread the cards into side-by-side panels.
        if (c.maxWidth < 560) {
          return Column(
            children: [
              for (final track in tracks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: _trackTile(l10n, track),
                ),
            ],
          );
        }
        final cols = (c.maxWidth / 180).floor().clamp(2, tracks.length);
        const spacing = 6.0;
        final w = (c.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final track in tracks)
              SizedBox(width: w, child: _trackTile(l10n, track)),
          ],
        );
      },
    );
  }

  Widget _simpleTools(AppLocalizations l10n) {
    if (MediaQuery.sizeOf(context).width < 420) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              tooltip: l10n.loopMixerBeatEdit,
              icon: Icon(_showBeatEdit ? Icons.close : Icons.grid_on),
              onPressed: toggleBeatEdit,
            ),
            IconButton.filledTonal(
              tooltip: l10n.loopMixerTuneEdit,
              icon: Icon(_showTuneEdit ? Icons.close : Icons.piano),
              onPressed: toggleTuneEdit,
            ),
            IconButton.filledTonal(
              tooltip: l10n.loopMixerScore,
              icon: Icon(
                _showScore ? Icons.library_music : Icons.library_music_outlined,
              ),
              onPressed: toggleScorePanel,
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          FilledButton.tonalIcon(
            icon: Icon(_showBeatEdit ? Icons.close : Icons.grid_on),
            label: Text(
              _showBeatEdit ? l10n.loopStudioClose : l10n.loopMixerBeatEdit,
            ),
            onPressed: toggleBeatEdit,
          ),
          FilledButton.tonalIcon(
            icon: Icon(_showTuneEdit ? Icons.close : Icons.piano),
            label: Text(
              _showTuneEdit ? l10n.loopStudioClose : l10n.loopMixerTuneEdit,
            ),
            onPressed: toggleTuneEdit,
          ),
          OutlinedButton.icon(
            icon: Icon(
              _showScore ? Icons.library_music : Icons.library_music_outlined,
            ),
            label: Text(l10n.loopMixerScore),
            onPressed: toggleScorePanel,
          ),
        ],
      ),
    );
  }

  /// LM-UX4: a tappable kick/snare/hat × step grid that builds/edits the beat.
  Widget _buildBeatEditor(AppLocalizations l10n) {
    final steps = _beatSteps;
    final p = _engine.userBeatPattern;
    final scheme = Theme.of(context).colorScheme;
    bool on(Drum d, int s) => (p?.rows[d]?.length ?? 0) > s && p!.rows[d]![s];
    final lanes = [
      (Drum.hat, l10n.performPadHat),
      (Drum.snare, l10n.performPadSnare),
      (Drum.kick, l10n.performPadKick),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.loopMixerBeatEditHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            for (final (drum, label) in lanes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 46,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    for (var s = 0; s < steps; s++)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _toggleBeatEditCell(drum, s),
                          child: Container(
                            height: 24,
                            margin: const EdgeInsets.all(1),
                            decoration: BoxDecoration(
                              color: on(drum, s)
                                  ? scheme.primary
                                  : (s % 4 == 0
                                      ? scheme.surfaceContainerHighest
                                      : scheme.surfaceContainerHigh),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// LM-UX4b: a tappable diatonic step-grid that builds/edits the tune, using
  /// the shared StepGridView + the LM-UX3 playhead.
  Widget _buildTuneEditor(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.loopMixerTuneEditHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            // LM-UX4c: which part to edit — your own tune, or a built-in stem.
            Wrap(
              spacing: 6,
              children: [
                for (final id in _tuneTargets)
                  ChoiceChip(
                    label: Text(
                      id == LoopEngine.userTrackId
                          ? l10n.loopMixerTuneMine
                          : _trackLabel(l10n, id),
                    ),
                    selected: _tuneTarget == id,
                    onSelected: (_) => setState(() => _tuneTarget = id),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            ValueListenableBuilder<int>(
              valueListenable: _hlStep,
              builder: (context, hl, _) => StepGridView(
                cells: _tuneStepCells(),
                steps: kPatternSteps,
                melodyRows: _tuneRows,
                playStep: hl >= 0 ? hl % kPatternSteps : null,
                onToggle: _toggleTuneCell,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A consistent labelled control row (LM-UX5) — a fixed-width label so every
  /// option (Key / Scale / Kit / Swing / Filter / …) left-aligns cleanly.
  Widget _optionRow(String label, Widget control) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: control),
          ],
        ),
      );

  /// A slider flanked by what its ends mean (LM-UX5), so Swing / Filter read as
  /// musical gestures instead of bare unlabelled sliders.
  Widget _captionedSlider({
    required String low,
    required String high,
    required Widget slider,
  }) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Row(
      children: [
        Text(low, style: style),
        Expanded(child: slider),
        Text(high, style: style),
      ],
    );
  }

  Widget _scoreStaffRow(AppLocalizations l10n, String id, Score score) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              _trackLabel(l10n, id),
              style: Theme.of(context).textTheme.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // LM-UX2: render the staff at a legible size and SCROLL a wide bar
          // horizontally instead of shrinking the whole thing to fit.
          // LM-UX3: light up the note currently sounding, driven by the loop
          // clock's eighth-step index (rebuilds only when the note moves).
          Expanded(
            child: SizedBox(
              height: _scoreRowHeight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ValueListenableBuilder<int>(
                  valueListenable: _hlStep,
                  builder: (context, step, _) {
                    final totalSteps =
                        score.measures.length * LoopTiming.stepsPerBar;
                    final ids = <String>{};
                    if (step >= 0 && totalSteps > 0) {
                      final id = grooveNoteIdAtStep(score, step % totalSteps);
                      if (id != null) ids.add(id);
                    }
                    return StaffView(
                      score: score,
                      staffSpace: 11,
                      theme: kidsScoreTheme,
                      highlightedIds: ids,
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _fillDue =>
      _engine.enabled.contains('drums') &&
      _iteration % LoopMixerScreen.fillEvery == LoopMixerScreen.fillEvery - 1;

  /// Loop seam: advance the iteration counter and, if the groove for the new
  /// iteration differs (fill in / fill out), swap it in near position 0 —
  /// the downbeat kick masks the restart.
  void _onLoopWrap() {
    _iteration++;
    // A running scene chain advances to its next section on the beat.
    _advanceChain();
    // Armed (quantized) card changes land here, on the beat.
    if (_applyPendingLaunches() && _engine.enabled.isEmpty) {
      _clock
        ..stop()
        ..reset();
      _lastPhaseMs = 0;
      _currentWav = null;
      _loop.stop();
      return;
    }
    if (_engine.enabled.isEmpty || !_clock.isRunning) return;
    // Infinite mode re-renders a seeded variation every loop; otherwise the
    // cached render only changes when the fill schedules in or out.
    final wanted = _infinite
        ? _engine.renderVariedLoop(_iteration, fill: _fillDue)
        : _engine.renderLoop(fill: _fillDue);
    if (identical(wanted, _currentWav)) return;
    _currentWav = wanted;
    // AEC jam owns audio via the reference pump: queue the new loop for the
    // scheduler's next seam instead of restarting the (stopped) loop player.
    if (_jamAec != null) {
      _refScheduler?.swap(_pcmOf(wanted));
      return;
    }
    _loop.playLoop(
      _seamSafeWav(wanted),
      position: Duration(
        milliseconds: _clock.elapsedMilliseconds % _engine.timing.totalMs,
      ),
    );
  }

  /// Audio elements can expose a tiny discontinuity when their native loop
  /// callback fires. Repair the finite WAV at the last possible boundary while
  /// keeping the engine's symbolic/render cache byte-stable for editing/tests.
  Uint8List _seamSafeWav(Uint8List wav) {
    final pcm = readWavPcm16(wav);
    final fixed = crossfadePcm16Seam(pcm.samples);
    return identical(fixed, pcm.samples) ? wav : wavBytes(fixed);
  }

  void _toggle(String id) {
    // Solo is an explicit isolation mode. Do not let a normal card tap mutate
    // the saved mix underneath it; leaving solo restores that exact mix.
    if (_soloTrack != null) return;
    // Quantized launch: while a groove is playing, arm the change and apply it
    // at the next seam instead of firing instantly.
    if (_quantize && _clock.isRunning && _engine.enabled.isNotEmpty) {
      setState(() {
        if (!_pendingLaunches.add(id)) _pendingLaunches.remove(id);
      });
      return;
    }
    setState(() => _engine.toggle(id));
    _syncPlayback();
    _checkCombo();
  }

  void _toggleSolo(String id) {
    setState(() {
      if (_soloTrack == id) {
        _engine.enabled
          ..clear()
          ..addAll(_enabledBeforeSolo ?? const <String>{});
        _soloTrack = null;
        _enabledBeforeSolo = null;
      } else {
        _enabledBeforeSolo ??= Set<String>.from(_engine.enabled);
        _engine.enabled
          ..clear()
          ..add(id);
        _soloTrack = id;
      }
    });
    _syncPlayback();
    _checkCombo();
  }

  /// A track is pitched — and so can be voiced by a saved instrument — if it
  /// re-voices per chord (a follower) or any variant plays notes (melodic).
  /// Drum tracks have no midi cells, so a voice would be a no-op.
  bool _trackIsPitched(LoopTrack t) =>
      t.chordFollower != null || t.variants.any((v) => v is MelodicPattern);

  /// Long-press a pitched track → voice it with a saved "My Instruments" sound
  /// (a formula synth OR a sampled soundbank voice — both render the same way),
  /// or reset it to its built-in timbre. SoundFont-reference saves need their
  /// font bytes and are skipped (`saved.instrument` is null then).
  Future<void> _pickVoice(AppLocalizations l10n, String id) async {
    final voiced = _engine.trackVoice(id) != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.piano),
              title: Text(l10n.loopVoiceWithInstrument),
              onTap: () => Navigator.pop(ctx, 'pick'),
            ),
            if (voiced)
              ListTile(
                leading: const Icon(Icons.undo),
                title: Text(l10n.loopVoiceReset),
                onTap: () => Navigator.pop(ctx, 'reset'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'reset') {
      _setTrackVoice(id, null);
      return;
    }
    final saved = await showMyInstrumentsSheet(context);
    if (!mounted || saved == null) return;
    final inst = saved.instrument;
    if (inst == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.loopVoiceUnavailable)),
      );
      return;
    }
    _setTrackVoice(id, inst);
  }

  void _setTrackVoice(String id, TrackerInstrument? voice) {
    setState(() => _engine.setTrackVoice(id, voice));
    _currentWav = null; // the cached loop is stale — force a re-render
    _syncPlayback();
  }

  // Move to the next challenge that isn't already satisfied (wraps around).
  void _nextChallenge() {
    setState(() {
      for (var i = 1; i <= kBandChallenges.length; i++) {
        final next = (_challengeIndex + i) % kBandChallenges.length;
        if (!kBandChallenges[next].check(_engine.enabled)) {
          _challengeIndex = next;
          return;
        }
      }
      _challengeIndex = (_challengeIndex + 1) % kBandChallenges.length;
    });
  }

  // --- Smear pad (§F-1) -----------------------------------------------------

  void _toggleSmearPad() => setState(() => _showSmear = !_showSmear);

  // The current position within the loop, for timestamping a smeared note.
  double _smearPhaseMs() => _clock.isRunning
      ? (_clock.elapsedMilliseconds % _engine.timing.totalMs).toDouble()
      : 0.0;

  // Play an in-key note as a short blip over the running groove, and record it
  // (with its loop phase) so the improvisation can be kept as a layer.
  void _playSmearNote(int midi, {double? atMs}) {
    _smearSamples.add((atMs ?? _smearPhaseMs(), midi));
    final audio = context.read<AudioService>();
    if (!audio.soundOn) return;
    final pcm = renderSegments(
      [
        (freqs: [midiToFrequency(midi)], ms: 260),
      ],
      timbre: timbreFor(Instrument.musicBox),
      gain: 0.7,
    );
    audio.playWavBytes(wavBytes(pcm));
  }

  // "Keep" the improvised lead: quantize the recorded notes onto the groove
  // grid (pentatonic-snapped) and install them as the sung-voice layer, so the
  // solo becomes a real, toggleable card in the band.
  void _keepSmear() {
    final cells = quantizeToGroove(
      _smearSamples,
      totalMs: _engine.timing.totalMs,
    );
    if (cells == null) return;
    setState(() {
      _engine.setUserTrack(cells, instrument: Instrument.musicBox);
      _engine.enabled.add(LoopEngine.userTrackId);
      _smearSamples.clear();
      _showSmear = false;
    });
    _syncPlayback();
    _checkCombo();
  }

  // --- Section/scene grid (§G-1) -------------------------------------------

  void _captureScene(int i) =>
      setState(() => _scenes[i] = _engine.captureScene());

  void _launchScene(int i) {
    final scene = _scenes[i];
    if (scene == null) return;
    setState(() {
      _engine.applyScene(scene);
      _chainIndex = i;
    });
    _syncPlayback();
    _checkCombo();
  }

  void _toggleChain() {
    setState(() => _chaining = !_chaining);
  }

  // The captured scenes, in A→D order (skipping empty slots).
  List<GrooveScene> _capturedScenes() => [
        for (final s in _scenes)
          if (s != null) s,
      ];

  // Bake the section chain into one arranged track and offer WAV/MP3 export.
  void _exportArrangement() {
    final scenes = _capturedScenes();
    if (scenes.isEmpty) return;
    final pcm = _engine.renderArrangement(scenes);
    showAudioExportSheet(context, pcm: pcm, baseName: 'my-arrangement');
  }

  // At a seam, advance the chain to the next non-empty scene and launch it.
  void _advanceChain() {
    if (!_chaining) return;
    for (var step = 1; step <= _scenes.length; step++) {
      final next = (_chainIndex + step) % _scenes.length;
      if (_scenes[next] != null) {
        setState(() {
          _engine.applyScene(_scenes[next]!);
          _chainIndex = next;
        });
        return;
      }
    }
  }

  void _toggleQuantize() {
    setState(() {
      _quantize = !_quantize;
      if (!_quantize) _pendingLaunches.clear(); // drop armed changes
    });
  }

  // Apply the armed launches at a loop seam; returns true if any fired.
  bool _applyPendingLaunches() {
    if (_pendingLaunches.isEmpty) return false;
    setState(() {
      for (final id in _pendingLaunches) {
        _engine.toggle(id);
      }
      _pendingLaunches.clear();
    });
    _checkCombo();
    return true;
  }

  /// Secret combos discovered this session (see loop_secrets.dart).
  final Set<String> _foundCombos = {};

  String _comboName(AppLocalizations l10n, String id) => switch (id) {
        'rhythmSection' => l10n.loopMixerComboRhythmSection,
        'duo' => l10n.loopMixerComboDuo,
        'dreamy' => l10n.loopMixerComboDreamy,
        'marching' => l10n.loopMixerComboMarching,
        _ => l10n.loopMixerComboFullBand,
      };

  /// If the current layers match a secret combo not yet found, celebrate it.
  void _checkCombo() {
    final combo = matchCombo(_engine.enabled);
    if (combo == null || !_foundCombos.add(combo.id)) return;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {}); // refresh the found N/M counter
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.loopMixerComboFound(_comboName(l10n, combo.id))),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  final _rng = Random();

  /// "Surprise me": roll a fresh, always-good groove. Every combination is
  /// consonant (all content is one pentatonic), so the only job is to pick a
  /// full-sounding mix and random variants. Drums anchor the beat; bass usually
  /// joins; each melodic voice joins by chance with at least one guaranteed, so
  /// it never sounds empty. A gentle swing roll varies the feel.
  void _roll() {
    setState(() {
      final ids = _engine.tracks.map((t) => t.id).toSet();
      _engine.enabled.clear();
      if (ids.contains('drums')) _engine.enabled.add('drums');
      if (ids.contains('bass') && _rng.nextDouble() < 0.8) {
        _engine.enabled.add('bass');
      }
      final melodic =
          ['melody', 'chords', 'sparkle', 'voice'].where(ids.contains).toList();
      for (final id in melodic) {
        if (_rng.nextDouble() < 0.55) _engine.enabled.add(id);
      }
      if (melodic.isNotEmpty && !melodic.any(_engine.enabled.contains)) {
        _engine.enabled.add(melodic[_rng.nextInt(melodic.length)]);
      }
      if (ids.contains('beat') && _rng.nextDouble() < 0.4) {
        _engine.enabled.add('beat');
      }
      // A random variant for every enabled layer, and a light swing nudge.
      for (final track in _engine.tracks) {
        if (_engine.enabled.contains(track.id) && track.variants.length > 1) {
          _engine.variants[track.id] = _rng.nextInt(track.variants.length);
        }
      }
      _engine.swing = _rng.nextBool() ? 0.0 : (_rng.nextInt(4) + 1) * 0.1;
    });
    _syncPlayback();
    _checkCombo();
  }

  void _cycleVariant(String id) {
    setState(() => _engine.cycleVariant(id));
    if (_engine.enabled.contains(id)) _syncPlayback();
  }

  void _rollVariant(String id) {
    setState(() => _engine.rollVariant(id, rng: _rng));
    if (_engine.enabled.contains(id)) _syncPlayback();
  }

  void _setLevel(String id, double level) {
    setState(() => _engine.levels[id] = level.clamp(0.0, 1.0));
    if (_engine.enabled.contains(id)) _syncPlayback();
  }

  void _setSwing(double value) {
    setState(() => _engine.swing = value);
    _syncPlayback();
  }

  // One-knob master filter: same grid, only the mix-bus tone changes.
  void _setMasterFilter(double value) {
    setState(() => _engine.masterFilter = value);
    _syncPlayback();
  }

  void _setSend(LoopSend value) {
    if (value == _engine.send) return;
    setState(() => _engine.send = value);
    _syncPlayback();
  }

  void _setTempo(int bpm) {
    if (bpm == _engine.tempoBpm) return;
    setState(() => _engine.tempoBpm = bpm);
    _tempoController.value = TextEditingValue(
      text: _engine.tempoBpm.toString(),
      selection: TextSelection.collapsed(
        offset: _engine.tempoBpm.toString().length,
      ),
    );
    _restartGroove();
  }

  // The harmonic function of a groove chord degree (all in C major).
  HarmonicFunction _degreeFunction(ChordDegree d) => switch (d) {
        ChordDegree.i => HarmonicFunction.tonic,
        ChordDegree.iv => HarmonicFunction.subdominant,
        ChordDegree.v => HarmonicFunction.dominant,
        ChordDegree.vi => HarmonicFunction.tonic,
      };

  /// A strip of the selected progression's chords, coloured by function.
  Widget _progressionFunctionStrip(Progression p) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            for (final d in p.degrees)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: harmonicFunctionColor(_degreeFunction(d)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    d.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  void _setProgression(Progression? progression) {
    if (progression?.id == _engine.progression?.id) return;
    setState(() => _engine.progression = progression);
    _restartGroove();
  }

  // ── Custom harmonies (LM-UX7) ─────────────────────────────────────────────
  void _deleteCustomProgression(Progression p) {
    setState(() {
      _customProgressions = [
        for (final c in _customProgressions)
          if (c.id != p.id) c,
      ];
    });
    if (_engine.progression?.id == p.id) _setProgression(null);
    _progStore.save(_customProgressions);
  }

  Future<void> _makeCustomProgression(AppLocalizations l10n) async {
    final degrees = await _showHarmonyEditor(l10n);
    if (degrees == null || degrees.length < 2) return;
    final p = Progression('custom-new-${_customProgId++}', degrees);
    setState(() => _customProgressions = [..._customProgressions, p]);
    await _progStore.save(_customProgressions);
    _setProgression(p);
  }

  /// A 4-slot chord picker — each bar is any of the offered degrees (all
  /// consonant with the pentatonic melodies, so no combination can clash).
  Future<List<ChordDegree>?> _showHarmonyEditor(AppLocalizations l10n) {
    final sel = [
      ChordDegree.i,
      ChordDegree.v,
      ChordDegree.vi,
      ChordDegree.iv,
    ];
    return showDialog<List<ChordDegree>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(l10n.loopMixerHarmonyMakeTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.loopMixerHarmonyMakeHint,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(width: 20, child: Text('${i + 1}')),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          children: [
                            for (final d in ChordDegree.values)
                              ChoiceChip(
                                label: Text(d.label),
                                selected: sel[i] == d,
                                onSelected: (_) => setD(() => sel[i] = d),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.loopMixerCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, List<ChordDegree>.of(sel)),
              child: Text(l10n.loopMixerHarmonyMakeCreate),
            ),
          ],
        ),
      ),
    );
  }

  // Key/scale keep the loop length, only the pitches move — re-render + re-sync
  // in place (like a master send change), no grid restart needed.
  void _setKey(int key) {
    if (key == _engine.key) return;
    setState(() => _engine.key = key);
    _syncPlayback();
  }

  void _setScale(GrooveScale scale) {
    if (scale == _engine.scale) return;
    setState(() => _engine.scale = scale);
    _syncPlayback();
  }

  void _setKit(String id) {
    if (id == _engine.kitId) return;
    setState(() => _engine.kitId = id);
    _syncPlayback();
  }

  // A style re-points the whole band + biases tempo/kit/scale, so it may change
  // the grid — restart from the top like a tempo change.
  void _setStyle(String id) {
    if (id == _engine.styleId) return;
    setState(() => _engine.styleId = id);
    _restartGroove();
  }

  /// A new grid (tempo or bar count changed) — restart from the top.
  void _restartGroove() {
    _paused = false;
    _clock
      ..stop()
      ..reset();
    _lastPhaseMs = 0;
    _iteration = 0;
    // The follow target (bpm + line) depends on the grid — rebuild it.
    if (_followEngine != null) _followEngine = _buildFollowEngine();
    _syncPlayback();
  }

  void _stopAll() {
    _paused = false;
    setState(_engine.enabled.clear);
    _syncPlayback();
  }

  /// Pause/resume the audio player and musical clock together. Stopwatch keeps
  /// its elapsed value while stopped, so resume re-enters the same loop phase.
  void _pauseOrResume() {
    if (_engine.enabled.isEmpty) return;
    if (_clock.isRunning) {
      _paused = true;
      _clock.stop();
      unawaited(_loop.pause());
      return;
    }
    if (!_paused) {
      _syncPlayback();
      return;
    }
    _paused = false;
    _clock.start();
    // Edits made while paused may have replaced the buffer, so resume through
    // the normal swap path instead of resuming a stale player source.
    _syncPlayback();
  }

  /// Restarts/stops/swaps the looping mix to match the groove state, keeping
  /// the musical phase: the new mix starts exactly where the clock says the
  /// groove is, so the beat never resets when something changes.
  void _syncPlayback() {
    // AEC jam owns audio: a live edit (variant/level/swing) re-feeds the
    // reference scheduler; the loop player stays silent until jam ends.
    if (_jamAec != null) {
      if (_engine.enabled.isNotEmpty) _refScheduler?.swap(_loopPcm());
      return;
    }
    if (_engine.enabled.isEmpty) {
      _clock
        ..stop()
        ..reset();
      _lastPhaseMs = 0;
      _iteration = 0;
      _currentWav = null;
      _loop.stop();
      return;
    }
    if (!context.read<AudioService>().soundOn) return; // master mute
    final wav = _engine.renderLoop(fill: _fillDue);
    if (!_clock.isRunning && !_paused) {
      _clock
        ..reset()
        ..start();
      _lastPhaseMs = 0;
    }
    _currentWav = wav;
    if (_paused) return;
    _loop.playLoop(
      _seamSafeWav(wav),
      position: Duration(
        milliseconds: _clock.elapsedMilliseconds % _engine.timing.totalMs,
      ),
    );
  }

  // One stable colour per card (the drums are unpitched, so a warm brown
  // instead of a pitch-class colour).
  static const _trackColors = <String, Color>{
    'drums': Color(0xFF795548),
    'bass': Color(0xFFE53935), // C red — the bass grounds the key
    'chords': Color(0xFF00ACC1), // G cyan
    'melody': Color(0xFFF9A825), // E amber
    'sparkle': Color(0xFF3949AB), // A indigo
    'voice': Color(0xFF8E24AA), // B purple — the singer's own layer
    'beat': Color(0xFF00897B), // teal — the beatboxer's own layer
  };

  String _trackLabel(AppLocalizations l10n, String id) => switch (id) {
        'drums' => l10n.loopMixerTrackDrums,
        'bass' => l10n.loopMixerTrackBass,
        'chords' => l10n.loopMixerTrackChords,
        'melody' => l10n.loopMixerTrackMelody,
        'voice' => l10n.loopMixerTrackVoice,
        'beat' => l10n.loopMixerTrackBeat,
        _ => l10n.loopMixerTrackSparkle,
      };

  String _kitLabel(AppLocalizations l10n, String id) => switch (id) {
        'deep' => l10n.loopMixerKitDeep,
        'warm' => l10n.loopMixerKitWarm,
        'lofi' => l10n.loopMixerKitLofi,
        _ => l10n.loopMixerKitClean,
      };

  String _styleLabel(AppLocalizations l10n, String id) => switch (id) {
        'four' => l10n.loopMixerStyleFour,
        'chill' => l10n.loopMixerStyleChill,
        _ => l10n.loopMixerStyleClassic,
      };

  String _challengeLabel(AppLocalizations l10n, String id) => switch (id) {
        'bass' => l10n.loopMixerChallengeBass,
        'melody' => l10n.loopMixerChallengeMelody,
        'layers' => l10n.loopMixerChallengeLayers,
        'fullBand' => l10n.loopMixerChallengeFullBand,
        _ => l10n.loopMixerChallengeSparkle,
      };

  // §G-1 arrangement: 4 scene pads (tap = launch, long-press = capture) + a
  // chain toggle that auto-advances the captured scenes at each seam.
  Widget _sceneRow(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Flexible(
          child: Text(
            l10n.loopMixerScenes,
            style: Theme.of(context).textTheme.labelLarge,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        for (var i = 0; i < _scenes.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Tooltip(
              message: l10n.loopMixerScenesHint,
              child: GestureDetector(
                onTap: () => _launchScene(i),
                onLongPress: () => _captureScene(i),
                // A rounded square (NOT a CircleAvatar) so these scene letters
                // stay distinct from the variant badges in widget finders.
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _scenes[i] == null
                        ? scheme.surfaceContainerHighest
                        : (_chaining && _chainIndex == i
                            ? scheme.primary
                            : scheme.primaryContainer),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    String.fromCharCode(65 + i),
                    style: TextStyle(
                      color: _scenes[i] == null
                          ? scheme.outline
                          : scheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        IconButton(
          icon: Icon(
            Icons.repeat,
            color: _chaining ? scheme.primary : null,
          ),
          isSelected: _chaining,
          tooltip: l10n.loopMixerChain,
          onPressed: _toggleChain,
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          icon: const Icon(Icons.download),
          tooltip: l10n.loopMixerExportArrangement,
          onPressed: hasScenes ? _exportArrangement : null,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  // A gentle, no-score prompt with a check when met; tap to try another.
  Widget _challengeBanner(AppLocalizations l10n) {
    final met = _challengeMet;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: _nextChallenge,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          children: [
            Icon(
              met ? Icons.check_circle : Icons.lightbulb_outline,
              size: 18,
              color: met ? Colors.green : scheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                met
                    ? l10n.loopMixerChallengeDone
                    : _challengeLabel(l10n, _challenge.id),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Icon(Icons.refresh, size: 16, color: scheme.outline),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      // LM-UX6: the "?" opens the concept + what-each-control-does primer.
      appBar: widget.showAppBar
          ? GameAppBar(title: l10n.gameLoopMixer, tutorial: loopMixerPrimer)
          : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              children: [
                Text(
                  l10n.loopMixerPrompt,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // A smooth sweeping playhead over a bar/beat lane.
                    Expanded(
                      child: _ProgressPlayhead(
                        progress: _progress,
                        bars: _engine.timing.bars,
                      ),
                    ),
                    if (_foundCombos.isNotEmpty)
                      Tooltip(
                        message: l10n.loopMixerCombosTip,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star,
                              size: 16,
                              color: Colors.amber,
                            ),
                            Text(
                              '${_foundCombos.length}/${kLoopCombos.length}',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                // The control bar WRAPS: ten compact buttons are ~400px, which
                // doesn't fit one line on a 375px phone (layout_audit_test).
                // Wrapping to a second run keeps every control reachable —
                // a horizontal scroller would hide them behind an invisible
                // affordance.
                if (widget.simpleLayout) _simpleTools(l10n),
                if (!widget.simpleLayout)
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        icon: const Icon(Icons.casino),
                        tooltip: l10n.loopMixerRoll,
                        onPressed: _roll,
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        icon: Icon(
                          _showScore
                              ? Icons.library_music
                              : Icons.library_music_outlined,
                        ),
                        tooltip: l10n.loopMixerScore,
                        onPressed: toggleScorePanel,
                        visualDensity: VisualDensity.compact,
                      ),
                      // LM-UX4: the tappable beat step-editor.
                      IconButton(
                        icon: Icon(
                          _showBeatEdit ? Icons.grid_on : Icons.grid_view,
                        ),
                        tooltip: l10n.loopMixerBeatEdit,
                        onPressed: toggleBeatEdit,
                        visualDensity: VisualDensity.compact,
                      ),
                      // LM-UX4b: the tappable tune (pitched) step-editor.
                      IconButton(
                        icon: Icon(
                          _showTuneEdit ? Icons.piano : Icons.piano_outlined,
                        ),
                        tooltip: l10n.loopMixerTuneEdit,
                        onPressed: toggleTuneEdit,
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.all_inclusive,
                          color: _infinite
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        isSelected: _infinite,
                        tooltip: l10n.loopMixerInfinite,
                        onPressed: toggleInfinite,
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.grid_4x4,
                          color: _quantize
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        isSelected: _quantize,
                        tooltip: l10n.loopMixerQuantize,
                        onPressed: _toggleQuantize,
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.gesture,
                          color: _showSmear
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        isSelected: _showSmear,
                        tooltip: l10n.loopMixerSolo,
                        onPressed: _toggleSmearPad,
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.surround_sound,
                          color: send != LoopSend.none
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        isSelected: send != LoopSend.none,
                        tooltip: l10n.loopMixerSend,
                        onPressed: () => setSend(
                          LoopSend.values[
                              (send.index + 1) % LoopSend.values.length],
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.hearing,
                          color: _jamming
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        isSelected: _jamming,
                        tooltip: l10n.loopMixerJam,
                        onPressed: toggleJam,
                        visualDensity: VisualDensity.compact,
                      ),
                      // Follow the melody: grade the player against the leading
                      // track. Only offered while jamming with a tune on screen.
                      if (_jamming && _engravedTrackId != null)
                        IconButton(
                          icon: Icon(
                            Icons.track_changes,
                            color: isFollowing
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          isSelected: isFollowing,
                          tooltip: l10n.loopMixerFollow,
                          onPressed: toggleFollow,
                          visualDensity: VisualDensity.compact,
                        ),
                      IconButton(
                        icon: const Icon(Icons.ios_share),
                        tooltip: l10n.loopMixerShare,
                        onPressed: _openShareSheet,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                // Jam feedback: the live note, coloured by how it fits the
                // sounding chord (green = chord tone, amber = scale, red = out).
                if (_jamming)
                  ValueListenableBuilder<PitchReading?>(
                    valueListenable: _jamReading,
                    builder: (context, reading, _) {
                      final hasNote = reading?.hasPitch ?? false;
                      final fit = hasNote
                          ? _engine.jamFit(
                              reading!.nearestMidi,
                              bar: _currentBar,
                            )
                          : null;
                      final color = switch (fit) {
                        JamFit.chordTone => Colors.green,
                        JamFit.scaleTone => Colors.amber.shade700,
                        JamFit.outside => Colors.redAccent,
                        null => Theme.of(context).disabledColor,
                      };
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.circle, size: 14, color: color),
                                const SizedBox(width: 8),
                                Text(
                                  hasNote ? reading!.noteName : '—',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(color: color),
                                ),
                              ],
                            ),
                            // Tell the child whether the colour can be trusted:
                            // Tier-3b cancels the speaker (the grade is really
                            // them), otherwise headphones keep the mic honest.
                            Text(
                              usesAecJam
                                  ? l10n.loopMixerJamGraded
                                  : l10n.loopMixerJamHeadphones,
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                            // Follow-the-melody: a live per-pass accuracy meter.
                            if (isFollowing)
                              ValueListenableBuilder<double>(
                                valueListenable: _followAccuracy,
                                builder: (context, acc, _) => Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    l10n.loopMixerFollowScore(
                                      (acc * 100).round(),
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                // Live engraving: EVERY enabled track as its own small staff
                // (drums/beat as a rhythm reduction), or a hint when nothing is
                // on yet — so the toggle always shows something.
                if (_showScore) _buildScorePanel(l10n),
                if (_showBeatEdit) _buildBeatEditor(l10n),
                if (_showTuneEdit) _buildTuneEditor(l10n),
                const SizedBox(height: 8),
                // The track lane is natural-height; the whole body scrolls (this
                // screen has ~10 control rows that don't fit a short phone).
                // LM-UX1: stacked on narrow, side-by-side panels on wide.
                _trackLane(l10n),
                const SizedBox(height: 6),
                // Capture row: sing a melody / beatbox a beat — count-in,
                // record 2 bars, the capture joins the band as a card.
                SizedBox(
                  height: 34,
                  child: Row(
                    children: [
                      Expanded(
                        child: _CaptureButton(
                          icon: Icons.mic,
                          idleLabel: hasVoiceTrack
                              ? l10n.loopMixerSingAgain
                              : l10n.loopMixerSing,
                          busyLabel: l10n.loopMixerSingNow,
                          active: _captureMode == _CaptureMode.voice,
                          phase: _capturePhase,
                          countdown: _countdown,
                          onPressed: () => _startCapture(_CaptureMode.voice),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CaptureButton(
                          icon: Icons.graphic_eq,
                          idleLabel: hasBeatTrack
                              ? l10n.loopMixerBeatboxAgain
                              : l10n.loopMixerBeatbox,
                          busyLabel: l10n.loopMixerBeatNow,
                          active: _captureMode == _CaptureMode.beat,
                          phase: _capturePhase,
                          countdown: _countdown,
                          onPressed: () => _startCapture(_CaptureMode.beat),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // §F-1 solo pad: drag to improvise an in-key lead over the groove,
                // then Keep it to turn the improvisation into a band layer.
                if (_showSmear)
                  SizedBox(
                    height: 72,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: SmearPad(
                              keyRoot: _engine.key,
                              minor:
                                  _engine.scale == GrooveScale.minorPentatonic,
                              onNote: _playSmearNote,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonalIcon(
                            onPressed:
                                _smearSamples.isEmpty ? null : _keepSmear,
                            icon: const Icon(Icons.add),
                            label: Text(l10n.loopMixerSoloKeep),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Section grid: capture/launch/chain scenes into an arrangement.
                if (!widget.simpleLayout) _sceneRow(l10n),
                // A gentle band challenge (no score) to nudge exploration.
                if (!widget.simpleLayout) _challengeBanner(l10n),
                // Style: a whole-band flavour preset (re-points every card).
                if (!widget.simpleLayout)
                  _optionRow(
                    l10n.loopMixerStyle,
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final style in kGrooveStyles)
                          ChoiceChip(
                            label: Text(_styleLabel(l10n, style.id)),
                            selected: _engine.styleId == style.id,
                            onSelected: (_) => _setStyle(style.id),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ),
                // The harmony lane: free vamp, or a 4-chord song progression.
                if (!widget.simpleLayout)
                  _optionRow(
                    l10n.loopMixerHarmony,
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: Text(l10n.loopMixerHarmonyOff),
                          selected: _engine.progression == null,
                          onSelected: (_) => _setProgression(null),
                          visualDensity: VisualDensity.compact,
                        ),
                        for (final p in kProgressions)
                          ChoiceChip(
                            label: Text(p.label),
                            selected: _engine.progression?.id == p.id,
                            onSelected: (_) => _setProgression(p),
                            visualDensity: VisualDensity.compact,
                          ),
                        // LM-UX7: the kid's own saved harmonies (deletable).
                        for (final p in _customProgressions)
                          InputChip(
                            label: Text(p.label),
                            selected: _engine.progression?.id == p.id,
                            onSelected: (_) => _setProgression(p),
                            onDeleted: () => _deleteCustomProgression(p),
                            visualDensity: VisualDensity.compact,
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 16),
                          label: Text(l10n.loopMixerHarmonyMake),
                          onPressed: () => _makeCustomProgression(l10n),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                // AnaVis: the selected progression, coloured by harmonic function.
                if (!widget.simpleLayout && _engine.progression != null)
                  _progressionFunctionStrip(_engine.progression!),
                // Key: rigidly transpose every pitched stem to a new root.
                if (!widget.simpleLayout)
                  _optionRow(
                    l10n.loopMixerKey,
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (var k = 0;
                            k < LoopMixerScreen._keyNames.length;
                            k++)
                          ChoiceChip(
                            label: Text(LoopMixerScreen._keyNames[k]),
                            selected: _engine.key == k,
                            onSelected: (_) => _setKey(k),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ),
                // Scale: major = bright, minor = darker (relative-minor set).
                if (!widget.simpleLayout)
                  _optionRow(
                    l10n.loopMixerScale,
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: Text(l10n.loopMixerScaleMajor),
                          selected:
                              _engine.scale == GrooveScale.majorPentatonic,
                          onSelected: (_) =>
                              _setScale(GrooveScale.majorPentatonic),
                          visualDensity: VisualDensity.compact,
                        ),
                        ChoiceChip(
                          label: Text(l10n.loopMixerScaleMinor),
                          selected:
                              _engine.scale == GrooveScale.minorPentatonic,
                          onSelected: (_) =>
                              _setScale(GrooveScale.minorPentatonic),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                // Drum kit: same beat, different timbre (clean/deep/warm/lo-fi).
                if (!widget.simpleLayout)
                  _optionRow(
                    l10n.loopMixerKit,
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final kit in kDrumKits)
                          ChoiceChip(
                            label: Text(_kitLabel(l10n, kit.id)),
                            selected: _engine.kitId == kit.id,
                            onSelected: (_) => _setKit(kit.id),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ),
                if (!widget.simpleLayout)
                  _optionRow(
                    l10n.loopMixerSwing,
                    _captionedSlider(
                      low: l10n.loopMixerSwingStraight,
                      high: l10n.loopMixerSwingShuffle,
                      slider: Slider(
                        value: _engine.swing,
                        max: 0.6,
                        // Discrete stops: the engine snaps the swing offset to the
                        // 10 ms sample grid anyway (LoopTiming._swingMs), so a
                        // continuous slider only offered identical values.
                        divisions: 12,
                        onChanged: _setSwing,
                      ),
                    ),
                  ),
                // One-knob master filter: left = low-pass (dark), right =
                // high-pass (thin); centred = off. A big breakdown/drop gesture.
                if (!widget.simpleLayout)
                  _optionRow(
                    l10n.loopMixerFilter,
                    _captionedSlider(
                      low: l10n.loopMixerFilterDark,
                      high: l10n.loopMixerFilterThin,
                      slider: Slider(
                        value: _engine.masterFilter,
                        min: -1,
                        divisions: 20,
                        onChanged: _setMasterFilter,
                        onChangeEnd: (v) {
                          // Snap back to "off" near the centre detent.
                          if (v.abs() < 0.06) _setMasterFilter(0);
                        },
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            'BPM',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Expanded(
                            child: Slider(
                              key: const ValueKey('loop-mixer-tempo'),
                              min: kMinTempoBpm.toDouble(),
                              max: kMaxTempoBpm.toDouble(),
                              divisions: kMaxTempoBpm - kMinTempoBpm,
                              value: _engine.tempoBpm.toDouble(),
                              label: '${_engine.tempoBpm} BPM',
                              onChanged: (v) => _setTempo(v.round()),
                            ),
                          ),
                          SizedBox(
                            width: 64,
                            child: TextField(
                              controller: _tempoController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                isDense: true,
                                suffixText: 'BPM',
                              ),
                              onSubmitted: (value) {
                                final bpm = int.tryParse(value);
                                if (bpm != null) _setTempo(bpm);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed:
                          _engine.enabled.isEmpty ? null : _pauseOrResume,
                      icon: Icon(
                        _clock.isRunning ? Icons.pause : Icons.play_arrow,
                      ),
                      tooltip: _clock.isRunning ? 'Pause' : 'Play',
                    ),
                    OutlinedButton.icon(
                      onPressed: _engine.enabled.isEmpty ? null : _stopAll,
                      icon: const Icon(Icons.stop),
                      label: Text(l10n.loopMixerStop),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _CapturePhase { idle, countIn, recording }

enum _CaptureMode { voice, beat }

/// One of the two capture buttons; the non-active one greys out while a
/// capture runs, the active one shows the countdown / recording state.
class _CaptureButton extends StatelessWidget {
  const _CaptureButton({
    required this.icon,
    required this.idleLabel,
    required this.busyLabel,
    required this.active,
    required this.phase,
    required this.countdown,
    required this.onPressed,
  });

  final IconData icon;
  final String idleLabel;
  final String busyLabel;
  final bool active;
  final _CapturePhase phase;
  final int countdown;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final recording = active && phase == _CapturePhase.recording;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(34),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        foregroundColor: recording ? Theme.of(context).colorScheme.error : null,
      ),
      onPressed: phase == _CapturePhase.idle ? onPressed : null,
      icon: Icon(recording ? Icons.fiber_manual_record : icon, size: 18),
      label: Text(
        !active || phase == _CapturePhase.idle
            ? idleLabel
            : phase == _CapturePhase.countIn
                ? '$countdown…'
                : busyLabel,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// A row of beat dots (grouped per bar) with the sounding beat lit. Only
/// this leaf listens to the ticker's beat notifier, so the per-frame update
/// never rebuilds the cards.
/// A smooth playhead that sweeps across a lane marked with bar/beat ticks and
/// fills behind itself, so you can watch the loop breathe. [progress] is the
/// loop phase 0..1 (negative while stopped).
class _ProgressPlayhead extends StatelessWidget {
  const _ProgressPlayhead({required this.progress, required this.bars});

  final ValueListenable<double> progress;
  final int bars;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 16,
      child: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, p, _) => CustomPaint(
          size: const Size(double.infinity, 16),
          painter: _PlayheadPainter(
            progress: p,
            beats: bars * LoopTiming.beatsPerBar,
            beatsPerBar: LoopTiming.beatsPerBar,
            color: base,
          ),
        ),
      ),
    );
  }
}

class _PlayheadPainter extends CustomPainter {
  _PlayheadPainter({
    required this.progress,
    required this.beats,
    required this.beatsPerBar,
    required this.color,
  });

  final double progress;
  final int beats;
  final int beatsPerBar;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, mid = h / 2;
    final radius = Radius.circular(h / 2);
    final lane = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, mid - 3, w, 6),
      radius,
    );
    canvas.drawRRect(lane, Paint()..color = color.withValues(alpha: 0.12));

    // Bar/beat ticks — taller and brighter on the downbeat.
    for (var b = 0; b <= beats; b++) {
      final x = (w * b / beats).clamp(0.0, w);
      final down = b % beatsPerBar == 0;
      canvas.drawLine(
        Offset(x, mid - (down ? 6 : 4)),
        Offset(x, mid + (down ? 6 : 4)),
        Paint()
          ..color = color.withValues(alpha: down ? 0.5 : 0.22)
          ..strokeWidth = down ? 1.6 : 1.0,
      );
    }

    if (progress < 0) return; // stopped
    final px = (w * progress).clamp(0.0, w);
    // Fill behind the head.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, mid - 3, px, 6), radius),
      Paint()..color = color.withValues(alpha: 0.32),
    );
    // The head: a bright line + dot.
    canvas.drawLine(
      Offset(px, 1),
      Offset(px, h - 1),
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(px, mid), 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PlayheadPainter old) =>
      old.progress != progress || old.beats != beats || old.color != color;
}

/// Wraps a track card so it pulses and glows on every beat while enabled — a
/// fuller flash on the bar's downbeat — driven by the shared [step] beat
/// notifier. Purely cosmetic and paint-only (a [Transform] + shadow), so it
/// never affects layout or the tap target.
class _BeatPulse extends StatefulWidget {
  const _BeatPulse({
    required this.step,
    required this.active,
    required this.beatsPerBar,
    required this.color,
    required this.child,
  });

  final ValueListenable<int> step;
  final bool active;
  final int beatsPerBar;
  final Color color;
  final Widget child;

  @override
  State<_BeatPulse> createState() => _BeatPulseState();
}

class _BeatPulseState extends State<_BeatPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1, // settled (no flash) at rest
  );
  int _lastBeat = -1;
  double _strength = 0;

  @override
  void initState() {
    super.initState();
    widget.step.addListener(_onBeat);
  }

  @override
  void dispose() {
    widget.step.removeListener(_onBeat);
    _pulse.dispose();
    super.dispose();
  }

  void _onBeat() {
    final beat = widget.step.value;
    if (beat == _lastBeat) return;
    _lastBeat = beat;
    if (!widget.active || beat < 0) return;
    // A fuller flash on the downbeat, a gentler one off the beat.
    _strength = beat % widget.beatsPerBar == 0 ? 1.0 : 0.5;
    _pulse.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      child: widget.child,
      builder: (context, child) {
        // Envelope peaks the instant a beat lands, then decays over ~300 ms.
        final env = widget.active
            ? (1 - Curves.easeOut.transform(_pulse.value)) * _strength
            : 0.0;
        return Transform.scale(
          scale: 1 + 0.045 * env,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: env > 0.01
                  ? [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.45 * env),
                        blurRadius: 18 * env,
                        spreadRadius: 1.5 * env,
                      ),
                    ]
                  : const [],
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.color,
    required this.shape,
    required this.label,
    required this.active,
    this.armed = false,
    required this.variant,
    required this.variantCount,
    required this.level,
    required this.onTap,
    required this.onCycleVariant,
    required this.onRollVariant,
    required this.onLevel,
    required this.onSolo,
    required this.soloed,
    this.onVoice,
    this.voiced = false,
  });

  final Color color;
  final CreatureShape shape;
  final String label;
  final bool active;
  final bool armed;
  final int variant;
  final int variantCount;
  final double level;
  final VoidCallback onTap;
  final VoidCallback onCycleVariant;
  final VoidCallback onRollVariant;
  final ValueChanged<double> onLevel;
  final VoidCallback onSolo;
  final bool soloed;

  /// Long-press a pitched track to voice it with a saved "My Instruments"
  /// sound (null for unpitched tracks — drums have no notes to voice).
  final VoidCallback? onVoice;

  /// Whether this track currently plays through a saved instrument.
  final bool voiced;

  @override
  Widget build(BuildContext context) {
    final foreground = active ? Colors.white : color;
    final compact = MediaQuery.sizeOf(context).width < 420;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onVoice,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: active ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          // Armed (queued for the next seam): an amber ring so the change reads
          // as "waiting" before it snaps in on the beat.
          border: Border.all(
            color: armed
                ? Colors.amber
                : (active ? color : color.withValues(alpha: 0.4)),
            width: armed || active ? 3 : 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                LoopCreature(
                  shape: shape,
                  active: active,
                  color: foreground,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(width: 12),
                // The pattern-variant badge: tap to cycle A → B → C, long-press
                // to roll a random variant.
                if (variantCount > 1)
                  GestureDetector(
                    onTap: onCycleVariant,
                    onLongPress: onRollVariant,
                    child: CircleAvatar(
                      radius: 13,
                      backgroundColor: foreground.withValues(alpha: 0.22),
                      child: Text(
                        String.fromCharCode(65 + variant),
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                // A small keyboard glyph marks a track voiced by a saved
                // instrument (long-press to change / reset).
                if (voiced) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.piano, size: 18, color: foreground),
                ],
                if (!compact) _soloButton(foreground),
              ],
            ),
            if (compact) _soloButton(foreground),
            // Per-card level, only offered while the layer sounds.
            if (active)
              SizedBox(
                height: 22,
                width: 220,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white38,
                    thumbColor: Colors.white,
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(value: level, onChanged: onLevel),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _soloButton(Color foreground) => IconButton(
        tooltip: soloed ? 'Unsolo' : 'Solo',
        onPressed: onSolo,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(
          Icons.headphones,
          size: 18,
          color: soloed ? Colors.amber : foreground,
        ),
      );
}
