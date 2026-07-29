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
import 'dart:typed_data';

import 'package:comet_beat/core/audio/aec_capability.dart';
import 'package:comet_beat/core/audio/aec_engine.dart';
import 'package:comet_beat/core/audio/beat_capture.dart';
import 'package:comet_beat/core/audio/crisp_dsp/resample.dart' show resampleHq;
import 'package:comet_beat/core/audio/daw_sources.dart' show GrooveSource;
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/groove_capture.dart';
import 'package:comet_beat/core/audio/loop_audio_fit.dart'
    show audioFitIsSubtle;
import 'package:comet_beat/core/audio/loop_automation.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/loop_reference.dart';
import 'package:comet_beat/core/audio/loop_stack_render.dart'
    show crossfadePcm16Seam;
import 'package:comet_beat/core/audio/loop_track_length.dart';
import 'package:comet_beat/core/audio/microphone_pitch_service.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/play_along.dart';
import 'package:comet_beat/core/audio/synth.dart'
    show
        Drum,
        Instrument,
        kSampleRate,
        kDrumKits,
        midiToFrequency,
        renderSegments,
        timbreFor,
        wavBytes,
        wavBytesStereo;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project_link.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/beat_bridge.dart';
import 'package:comet_beat/core/services/gapless_loop_player.dart';
import 'package:comet_beat/core/services/melody_bridge.dart';
import 'package:comet_beat/core/services/project_service.dart';
import 'package:comet_beat/core/services/transport_service.dart';
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
import 'package:comet_beat/features/games/drums/drumkit_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/sound_lab/my_instruments_sheet.dart';
import 'package:comet_beat/features/workshop/model/score_document.dart'
    show grandStaffFromScore;
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/daw/send_to_daw.dart';
import 'package:comet_beat/shared/keymap/intents.dart';
import 'package:comet_beat/shared/keymap/keymap.dart';
import 'package:comet_beat/shared/keymap/keymap_service.dart';
import 'package:comet_beat/shared/keymap/keymap_sheet.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:comet_beat/shared/music_io/audio_import.dart';
import 'package:comet_beat/shared/music_io/export_sheet.dart';
import 'package:comet_beat/shared/music_io/music_export.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:comet_beat/shared/tutorial/primers.dart' show loopMixerPrimer;
import 'package:comet_beat/shared/tutorial/tutorial_sheet.dart'
    show showTutorial;
import 'package:comet_beat/shared/widgets/fx_rack.dart';
import 'package:comet_beat/shared/widgets/step_grid.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show
        Clef,
        GrandStaffView,
        HarmonicFunction,
        Score,
        StaffView,
        multiPartToMusicXml;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart'
    show
        Clipboard,
        ClipboardData,
        HardwareKeyboard,
        KeyDownEvent,
        LogicalKeyboardKey;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WS-T3 — what Loop Studio actually does, so its keymap sheet lists only
/// shortcuts that work here.
const Set<AppIntent> kLoopIntents = {
  AppIntent.transportToggle,
  AppIntent.transportStop,
  AppIntent.editUndo,
  AppIntent.editRedo,
  // WS-L1 — the lane cursor. Listed here so the keymap sheet shows only what
  // this surface can actually do with a key.
  AppIntent.cursorUp,
  AppIntent.cursorDown,
  AppIntent.cursorLeft,
  AppIntent.cursorRight,
  AppIntent.editDelete,
  AppIntent.duplicate,
};

class LoopMixerScreen extends StatefulWidget {
  const LoopMixerScreen({
    super.key,
    this.aecFactory,
    this.initialSpec,
    this.showAppBar = true,
    this.simpleLayout = false,
    this.onReturnToDaw,
  });

  /// In-place round trip back to the Audio Editor: when set, "Send to Audio
  /// Editor" hands the edited groove to THIS callback and pops, instead of
  /// adding a second copy of the same groove to the timeline. Mirrors
  /// `AdvancedTrackerScreen.onReturnToDaw`.
  final void Function(GrooveSpec edited)? onReturnToDaw;

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
  /// WS-X1 — put this groove in the project, re-open that track LIVE, and have
  /// edits land back in it.
  String? addToProject({String? name});
  bool openProjectTrack(String trackId);
  bool get hasLiveProjectLink;
  bool writeBackToProject();

  Set<String> get enabledTracks;
  String? get soloTrack;
  bool get isPlaying;
  int get tempoBpm;
  double get swing;
  String? get progressionId;
  int get loopIteration;
  int variantOf(String id);
  double levelOf(String id);

  /// Per-track stereo pan (−1 left … 0 centre … +1 right) and its setter.
  double panOf(String id);
  void setTrackPan(String id, double pan);
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

  /// E3 — the master bus insert chain in the shared [FxSpec] model. When
  /// non-empty it takes over from [send] (see LoopEngine.masterFxChain), so
  /// this is the "advanced" face of the same control.
  List<FxSpec> get masterFxChain;
  void setMasterFxChain(List<FxSpec> chain);

  /// One-knob master filter (−1 low-pass … 0 off … +1 high-pass).
  double get masterFilter;
  void setMasterFilter(double value);

  /// Editing history: undo/redo the last content edits (toggles, variants,
  /// levels, voices, grid edits, key/scale/kit/tempo/swing/progression, captures).
  bool get canUndo;
  bool get canRedo;
  void undo();
  void redo();

  /// Remove a captured (sung / beatboxed) track; built-in band cards can't be
  /// removed. No-op for unknown/built-in ids.
  void deleteTrack(String id);

  /// Open track [id]'s in-place event editor (beat grid for drums, tune grid
  /// for a pitched track) targeting that track.
  void editTrack(String id);

  void stopAll();
  bool get scoreVisible;
  void toggleScorePanel();

  /// Test seam: give a pitched track explicit cells, so a test can set up a
  /// specific RANGE (e.g. one that straddles middle C) and assert how the score
  /// panel engraves it. Mirrors `LoopEngine.setTrackCells`.
  /// Stops the transport from wrapping on its own, so a test can drive seams
  /// with [debugLoopWrap] and nothing else. `_clock` is a real Stopwatch, so
  /// without this a slow machine can cross a seam between two pumps.
  void debugFreezeSeams();

  void debugSetTrackCells(String id, List<PatternCell> cells);

  /// This track's loop length in steps, and the whole loop's — so a test can
  /// prove the badge changed what actually plays, not just what is drawn.
  int trackSteps(String id);
  int get loopSteps;

  /// The "Sound & Feel" inspector (holds tempo/style/harmony/key/scale/kit/
  /// swing/filter/sections). Advanced view only.
  bool get inspectorVisible;
  void toggleInspector();

  /// LM-UX4: the tappable drum step-grid that builds/edits the beat.
  bool get beatEditVisible;
  void toggleBeatEdit();
  void debugEditBeatCell(Drum drum, int step);
  DrumRowsPattern? get debugBeatPattern;

  /// Long-press a drum hit — cycle its dynamics ghost ↔ normal.
  void debugCycleBeatVelocity(Drum drum, int step);

  /// Which drum track the beat editor targets ('drums' card or captured 'beat').
  void debugSetBeatTarget(String id);

  /// Applies a Drum Kit round-trip result to the current beat target (the pure
  /// half of "edit drums on the Drum Kit pads", without navigation).
  void debugApplyDrumKitEdit(DrumRowsPattern edited);

  /// LM-UX4b: the tappable diatonic step-grid that builds/edits the tune (the
  /// user melodic track), via the shared StepGridView + setUserTrack.
  bool get tuneEditVisible;
  void toggleTuneEdit();
  void debugEditTuneCell(int midi, int step);
  List<PatternCell>? get debugTuneCells;
  void debugSetTuneTarget(String id);

  /// Whether track [id] carries a hand-edited cell override (vs. still playing
  /// its generated preset). Distinguishes "seeded from the real notes" from
  /// "actually overridden by an edit".
  bool debugHasTuneOverride(String id);

  /// The round-trip fold used when returning from the full Tracker: if a fresh
  /// tune arrived on MelodyBridge since [before], load it into the loop.
  void debugFoldTrackerReturn(SharedMelody? before);

  /// Empty the current tune target (removal is per-note taps in the UI).
  void debugClearTune();

  /// Cycle the dynamics of the note(s) at [step] (soft ↔ normal) — the tune
  /// grid's long-press, for note-level velocity editing.
  void debugCycleTuneVelocity(int midi, int step);

  /// Wide pitch range for the tune editor (Beginner-Tracker parity): one octave
  /// off, two octaves on.
  bool get tuneWideRange;
  void setTuneWideRange(bool wide);

  /// The number of pitch rows the tune editor currently offers.
  int get debugTuneRowCount;
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

  /// Copies the section now playing into the next free slot and launches it.
  /// False when every slot is taken.
  bool duplicateSection();

  /// Whether [id] plays in section [i], and a way to change that — the session
  /// grid's cell state.
  /// The section armed to launch at the next seam, if any.
  int? get pendingScene;

  /// Adds a copy of a track / removes one, and the current roster.
  void duplicateTrack(String id);
  void removeCopy(String id);
  List<String> get trackIds;

  /// D1 — adds a fresh track playing an authored role, or an empty one, and
  /// names a track. [trackLabelOf] is what the player actually reads.
  void addRoleTrack(String roleId);
  void addEmptyTrack();
  bool isEmptyTrack(String id);
  void renameTrack(String id, String? name);
  String trackLabelOf(String id);

  /// A track's level-automation lane: the value at a step, a way to step it,
  /// and whether the track has a lane at all.
  double automationAt(String id, int step);
  bool hasAutomationFor(String id);
  void cycleAutomationStep(String id, int step);
  void clearAutomation(String id);

  /// D2 — which parameter the one lane strip is editing, and the lane of any
  /// parameter rather than just the level.
  AutomationParam get automationParam;
  void setAutomationParam(AutomationParam param);
  double automationAtParam(String id, AutomationParam param, int step);
  bool hasAutomationForParam(String id, AutomationParam param);

  /// D3 — a track's own tone control, and a way to step it.
  double trackFilterOf(String id);
  void cycleTrackFilter(String id);

  /// WS-L10 — a recorded loop as a track: add one, ask whether a track is one,
  /// and how far its audio had to stretch to fit the groove.
  String addAudioTrack(Float64List pcm);
  bool isAudioTrack(String id);
  double audioStretchOf(String id);

  /// How many samples one loop is — what an imported take is fitted to.
  int get debugLoopSamples;

  /// WS-L5 — where a track's pattern could go, and putting it there.
  List<String> copyTargetsFor(String from);
  bool copyPattern(String from, String to);

  /// WS-L1 — where the keyboard cursor is on the lane strip, as
  /// `(trackId, step)`, or null before a key has moved it.
  (String, int)? get laneCursor;

  /// A track's swing, whether it has its OWN, and a way to step it.
  double trackSwingOf(String id);
  bool hasOwnSwing(String id);
  void cycleTrackSwing(String id);

  /// How many loops section [i] plays before the chain advances, and a way to
  /// step it.
  int sceneRepeats(int i);
  void cycleSceneRepeats(int i);

  bool sceneHasTrack(int i, String id);
  void toggleSceneTrack(int i, String id);
  bool get isChaining;
  void toggleChain();

  /// §G-2: bake the captured section chain into one arranged track (for tests,
  /// the rendered PCM).
  bool get hasScenes;
  Float64List debugRenderArrangement();

  /// The current loop rendered to a WAV (mono, or interleaved stereo when a
  /// track is panned) — lets a test assert channel count + pan energy.
  Uint8List debugRenderLoop();

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
  ///
  /// It stays the AUTHORITY under WS-W2 — the shared [TransportService] is fed
  /// FROM it, never the other way round. `syncTo`, not `advance`: this is an
  /// absolute read of a monotonic Stopwatch, and accumulating per-frame deltas
  /// would drift away from a free-running pre-rendered WAV.
  final _clock = Stopwatch();

  /// The app-wide transport, when one is provided. Null when this screen is
  /// mounted without a provider tree, so every use is null-safe and no existing
  /// test has to grow one.
  TransportService? _transport;

  /// Test-only: suppress AUTOMATIC loop wraps so a test owns the seams.
  bool _debugFreezeSeams = false;

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

  /// Edit history for undo/redo. Each entry is a full GrooveSpec snapshot of the
  /// engine; a content change is detected by the spec's canonical `cacheKey`, so
  /// toggles, variants, levels, voices, grid edits, key/scale/kit/tempo/swing/
  /// progression and captured tracks are all covered. The Loop Studio is a
  /// sandbox — a kid needs to take an edit back. Capped so it never grows without
  /// bound. `_historyBase` is the last recorded state (the point undo reverts to).
  final List<GrooveSpec> _undoStack = [];
  final List<GrooveSpec> _redoStack = [];
  GrooveSpec? _historyBase;
  static const int _maxHistory = 60;

  @override
  void initState() {
    super.initState();
    if (widget.initialSpec != null) _engine.applySpec(widget.initialSpec!);
    // Anchor undo history at the opening state so the very first edit is
    // reversible (without this, base seeds on the first change and loses it).
    _historyBase = _engine.spec;
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
        _publishTransport(playing: false, phaseMs: 0);
        return;
      }
      final t = _engine.timing;
      final phase = _clock.elapsedMilliseconds % t.totalMs;
      // `_clock` is a real Stopwatch, so on a loaded machine enough wall-clock
      // time can pass between two test pumps to cross a seam — and a
      // spontaneous wrap advances the chain out from under a test that meant to
      // drive seams itself with debugLoopWrap(). Tests freeze this; nothing
      // else touches it.
      if (phase < _lastPhaseMs && !_debugFreezeSeams) _onLoopWrap();
      _lastPhaseMs = phase;
      _step.value = phase ~/ t.beatMs;
      _progress.value = phase / t.totalMs;
      _hlStep.value = (phase / (t.beatMs / 2)).floor(); // eighth-step index
      _publishTransport(
        playing: _clock.isRunning,
        phaseMs: phase.toDouble(),
      );
    })
      ..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _transport = Provider.of<TransportService>(context, listen: false);
    } on ProviderNotFoundException {
      _transport = null;
    }
    try {
      _projects = Provider.of<ProjectService>(context, listen: false);
    } on ProviderNotFoundException {
      _projects = null;
    }
  }

  // --- WS-X1 live project links ---------------------------------------------

  ProjectLink? _projectLink;
  ProjectService? _projects;

  ProjectLinker? get _linker {
    final projects = _projects;
    return projects == null ? null : ProjectLinker(projects);
  }

  @override
  String? addToProject({String? name}) {
    final linker = _linker;
    if (linker == null) return null;
    final spec = _engine.spec;
    final id = linker.add(
      kind: AppMode.loop,
      document: spec,
      name: name ?? 'Loop',
    );
    _projectLink = ProjectLink(document: spec, trackId: id, live: true);
    return id;
  }

  /// Opens a project track here. A LOOP track opens live — no conversion, no
  /// copy; anything else is refused rather than silently converted, because a
  /// conversion belongs behind the "Open in…" menu where its cost is shown.
  @override
  bool openProjectTrack(String trackId) {
    final linker = _linker;
    if (linker == null) return false;
    final link = linker.open(trackId, AppMode.loop);
    final doc = link.document;
    if (doc is! GrooveSpec) return false;
    setState(() {
      _engine.applySpec(doc);
      _projectLink = link;
    });
    // The rendered buffer belongs to the old groove; re-enter in phase rather
    // than letting the seam scheduler keep playing what was replaced.
    _syncPlayback();
    return true;
  }

  @override
  bool get hasLiveProjectLink => _projectLink?.live ?? false;

  @override
  bool writeBackToProject() {
    final linker = _linker;
    final link = _projectLink;
    if (linker == null || link == null) return false;
    return linker.writeBack(link, _engine.spec);
  }

  /// Publishes this surface's phase and play state into the SHARED transport.
  ///
  /// Driven from the ticker rather than from the play/stop call sites: `_clock`
  /// is started and stopped from five separate cascades in this file, and the
  /// ticker sees every state it can be in, so there is no site left to forget.
  void _publishTransport({required bool playing, required double phaseMs}) {
    final transport = _transport;
    if (transport == null) return;
    if (playing && !transport.isPlaying) {
      transport.play();
    } else if (!playing && transport.isPlaying) {
      transport.pause();
    }
    transport.syncTo(phaseMs);
  }

  @override
  void dispose() {
    _keyFocus.dispose();
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
  double panOf(String id) => _engine.panOf(id);
  @override
  void setTrackPan(String id, double pan) => _setPan(id, pan);
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
  List<FxSpec> get masterFxChain => _engine.masterFxChain;
  @override
  void setMasterFxChain(List<FxSpec> chain) {
    setState(() => _engine.masterFxChain = chain);
    _syncPlayback();
  }

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
  bool get canUndo => _canUndo;
  @override
  bool get canRedo => _canRedo;
  @override
  void undo() => _undoEdit();
  @override
  void redo() => _redoEdit();
  @override
  void deleteTrack(String id) => _deleteTrack(id);
  @override
  void editTrack(String id) => _editTrack(id);

  @override
  void stopAll() => _stopAll();
  @override
  void pauseOrResume() => _pauseOrResume();
  @override
  @override
  void debugFreezeSeams() => _debugFreezeSeams = true;

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

  @override
  int trackSteps(String id) => _engine.trackSteps(id);
  @override
  int get loopSteps => _engine.timing.totalSteps;

  @override
  void debugSetTrackCells(String id, List<PatternCell> cells) {
    setState(() => _engine.setTrackCells(id, cells));
  }

  bool _showScore = false;

  /// The "Sound & Feel" inspector panel (Score-Editor pattern): all the
  /// multi-value song settings (style/harmony/key/scale/kit/swing/filter/tempo)
  /// live here instead of a stack of always-visible rows. Advanced view only.
  bool _showInspector = false;
  @override
  void toggleInspector() => setState(() => _showInspector = !_showInspector);
  @override
  bool get inspectorVisible => _showInspector;

  // LM-UX4: the beat step-editor panel.
  bool _showBeatEdit = false;
  @override
  bool get beatEditVisible => _showBeatEdit;
  @override
  void toggleBeatEdit() => setState(() => _showBeatEdit = !_showBeatEdit);
  @override
  DrumRowsPattern? get debugBeatPattern => _engine.drumRowsFor(_beatTarget);
  @override
  void debugEditBeatCell(Drum drum, int step) =>
      _toggleBeatEditCell(drum, step);
  @override
  void debugCycleBeatVelocity(Drum drum, int step) =>
      _cycleBeatCellVelocity(drum, step);
  @override
  void debugSetBeatTarget(String id) => setState(() => _beatTarget = id);
  @override
  void debugApplyDrumKitEdit(DrumRowsPattern edited) =>
      _applyDrumKitEdit(edited);

  /// Which drum track the beat grid edits: the built-in 'drums' card or the
  /// captured beatboxed layer. The 'drums' edits write a per-track drum override
  /// (so the actual card changes); 'beat' writes the captured layer.
  String _beatTarget = 'drums';

  /// The drum tracks the beat editor can target — always the drums card, plus
  /// the captured beat if one exists.
  List<String> get _beatTargets => [
        'drums',
        if (_engine.userBeatPattern != null) LoopEngine.beatTrackId,
      ];

  /// The pattern the beat editor currently shows for [_beatTarget].
  DrumRowsPattern? get _beatTargetPattern => _engine.drumRowsFor(_beatTarget);

  /// The beat grid's step count — the full 2-bar grid (or a longer target
  /// pattern). Must be [kPatternSteps], not one bar: the loop, the render and
  /// the share-token decoder all work in 2-bar (kPatternSteps) units, so a
  /// fresh captured beat authored on a 1-bar grid used to render only in bar 1
  /// and get dropped by the token decoder (length mismatch).
  int get _beatSteps {
    final p = _beatTargetPattern;
    if (p == null) return kPatternSteps;
    return p.rows.values.fold(
      kPatternSteps,
      (m, r) => r.length > m ? r.length : m,
    );
  }

  /// The target pattern's rows + per-hit velocities copied into fresh mutable
  /// maps of [_beatSteps] length (velocity defaults to full where absent).
  ({Map<Drum, List<bool>> rows, Map<Drum, List<double>> vels})
      _beatEditGrids() {
    final steps = _beatSteps;
    final p = _beatTargetPattern;
    final rows = <Drum, List<bool>>{};
    final vels = <Drum, List<double>>{};
    if (p != null) {
      for (final e in p.rows.entries) {
        final row = List<bool>.filled(steps, false);
        final vel = List<double>.filled(steps, 1.0);
        final pv = p.velocities?[e.key];
        for (var i = 0; i < e.value.length && i < steps; i++) {
          row[i] = e.value[i];
          if (pv != null && i < pv.length) vel[i] = pv[i];
        }
        rows[e.key] = row;
        vels[e.key] = vel;
      }
    }
    return (rows: rows, vels: vels);
  }

  /// The per-hit velocity the beat grid shows at (drum, step) — full if none.
  double _beatVelAt(Drum drum, int step) {
    final v = _beatTargetPattern?.velocities?[drum];
    return (v != null && step < v.length) ? v[step] : 1.0;
  }

  /// Writes an edited beat grid back to the target and re-renders. Velocities
  /// ride along only when some hit is a ghost, so plain on/off beats stay clean.
  void _writeBeatPattern(
    Map<Drum, List<bool>> rows,
    Map<Drum, List<double>> vels,
  ) {
    final hasGhost = vels.values.any((r) => r.any((v) => v != 1.0));
    final pattern = DrumRowsPattern(rows, velocities: hasGhost ? vels : null);
    if (_beatTarget == LoopEngine.beatTrackId) {
      _engine.setUserBeatTrack(pattern);
      _engine.enabled.add(LoopEngine.beatTrackId);
    } else {
      _engine.setTrackDrums(_beatTarget, pattern);
      _engine.enabled.add(_beatTarget);
    }
    setState(() {});
    _restartGroove();
  }

  /// Toggle one cell of the beat grid and re-render (LM-UX4). Reads/writes the
  /// TARGET drum track (the drums card via a drum override, or the captured
  /// beat), preserving the other lanes AND their dynamics.
  void _toggleBeatEditCell(Drum drum, int step) {
    final g = _beatEditGrids();
    final lane =
        g.rows.putIfAbsent(drum, () => List<bool>.filled(_beatSteps, false));
    g.vels.putIfAbsent(drum, () => List<double>.filled(_beatSteps, 1.0));
    lane[step] = !lane[step];
    if (!lane[step]) {
      g.vels[drum]![step] = 1.0; // clearing a hit resets its dynamics
    }
    _writeBeatPattern(g.rows, g.vels);
  }

  /// Long-press a drum hit → cycle its dynamics ghost ↔ normal, mirroring the
  /// tune editor's soft/normal. No-op on an empty cell.
  void _cycleBeatCellVelocity(Drum drum, int step) {
    final g = _beatEditGrids();
    final lane = g.rows[drum];
    if (lane == null || step >= lane.length || !lane[step]) return;
    final vel =
        g.vels.putIfAbsent(drum, () => List<double>.filled(_beatSteps, 1.0));
    vel[step] = vel[step] >= 1.0 ? _softVelocity : 1.0;
    _writeBeatPattern(g.rows, g.vels);
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
  @override
  bool debugHasTuneOverride(String id) =>
      _engine.trackCellsOverride(id) != null;
  @override
  void debugFoldTrackerReturn(SharedMelody? before) =>
      _foldTrackerReturn(before);
  @override
  void debugClearTune() => _writeTuneCells(const []);
  @override
  void debugCycleTuneVelocity(int midi, int step) =>
      _cycleTuneCellVelocity(midi, step);

  /// Which pitched part the tune editor edits: the user track ('voice' = "My
  /// tune") or a built-in stem (LM-UX4c, via the engine's cell-override).
  String _tuneTarget = LoopEngine.userTrackId;
  static const _tuneTargets = [
    LoopEngine.userTrackId,
    'melody',
    'chords',
    'bass',
    'sparkle',
  ];

  bool get _tuneTargetIsUser => _tuneTarget == LoopEngine.userTrackId;

  /// The authored-C cells behind the current tune target.
  ///
  /// For the user track: its own cells (null until sung/tapped — an empty grid
  /// is correct there). For a built-in stem: its live override, or — when there
  /// is none yet — the notes it CURRENTLY plays ([cellsFor]), so tapping Edit
  /// opens on the real tune instead of a blank grid ("it mostly shows empty").
  /// Only when those cells fit one 2-bar editor grid; a progression can tile a
  /// stem across more bars than this grid can represent, so that stays blank.
  List<PatternCell>? _targetCells() {
    if (_tuneTargetIsUser) return _engine.userTrackCells;
    final override = _engine.trackCellsOverride(_tuneTarget);
    if (override != null) return override;
    final authored = _engine.cellsFor(_tuneTarget);
    if (authored == null) return null;
    final total = authored.fold<int>(0, (a, c) => a + c.steps);
    return total == kPatternSteps ? authored : null;
  }

  /// The tune editor's pitch rows — one octave of C major pentatonic. Cells are
  /// authored in C (like every built-in stem); the engine's `pitchTranspose`
  /// shifts the whole pattern into the current key AND scale at render (the
  /// same `{0,2,4,7,9} + pitchTranspose` rule), so edits always fit the band and
  /// follow later key/scale changes.
  /// Beginner-Tracker parity: a wide-range toggle. Off = one octave of C major
  /// pentatonic (C4..C5); on = two octaves (C4..C6), so a melody can leap
  /// like it can in the Tracker's wide mode.
  bool _tuneWideRange = false;
  @override
  bool get tuneWideRange => _tuneWideRange;
  @override
  void setTuneWideRange(bool wide) => setState(() => _tuneWideRange = wide);
  @override
  int get debugTuneRowCount => _tuneRows.length;

  static const _tunePentatonic = [0, 2, 4, 7, 9];

  List<int> get _tuneRows => [
        for (final octave in _tuneWideRange ? const [0, 12] : const [0])
          for (final d in _tunePentatonic) 60 + octave + d,
        60 + (_tuneWideRange ? 24 : 12),
      ];

  /// A soft note's velocity (accent parity with the Beginner Tracker's soft).
  static const _softVelocity = 0.45;

  /// The target's cells as grid cells (one StepCell per pitch per onset),
  /// carrying each cell's velocity so soft notes render dimmer.
  List<StepCell> _tuneStepCells() {
    final cells = _targetCells() ?? const <PatternCell>[];
    final out = <StepCell>[];
    var pos = 0;
    for (final c in cells) {
      final midis = c.midis;
      if (midis != null) {
        for (final m in midis) {
          out.add(StepCell(m, pos, len: c.steps, velocity: c.velocity));
        }
      }
      pos += c.steps;
    }
    return out;
  }

  /// Grid cells → a bar of [PatternCell]s. Each note keeps its OWN length
  /// (capped so it never runs past the next onset or the grid end); the space
  /// before/after/between notes becomes rest cells. Velocity is per time-slice:
  /// all notes placed on a step share that step's velocity.
  ///
  /// (Regression: the old version gave every note a duration of "steps until
  /// the next note", so a single note sustained all the way to the right edge —
  /// the "table fills from click position to fully right" bug.)
  List<PatternCell> _stepCellsToPattern(List<StepCell> cells, int steps) {
    final midisAt = <int, List<int>>{};
    final velAt = <int, double>{};
    final lenAt = <int, int>{};
    for (final c in cells) {
      if (c.step < 0 || c.step >= steps) continue;
      (midisAt[c.step] ??= []).add(c.row);
      velAt[c.step] = c.velocity;
      lenAt[c.step] = max(lenAt[c.step] ?? 1, c.len);
    }
    final onsets = midisAt.keys.toList()..sort();
    final out = <PatternCell>[];
    var pos = 0;
    for (var i = 0; i < onsets.length; i++) {
      final onset = onsets[i];
      // A rest bridges the gap since the previous note ended.
      if (onset > pos) out.add(PatternCell(steps: onset - pos));
      // The note's own length, capped so it stops at the next onset / bar end.
      final nextOnset = i + 1 < onsets.length ? onsets[i + 1] : steps;
      final noteLen = (lenAt[onset] ?? 1).clamp(1, nextOnset - onset);
      out.add(
        PatternCell(
          midis: midisAt[onset],
          steps: noteLen,
          velocity: velAt[onset] ?? 1.0,
        ),
      );
      pos = onset + noteLen;
    }
    // Trailing rest so the pattern always sums to [steps].
    if (pos < steps) out.add(PatternCell(steps: steps - pos));
    return out;
  }

  /// Writes the edited grid cells back to the current tune target and re-renders.
  void _writeTuneCells(List<StepCell> next) {
    const steps = kPatternSteps; // pitched patterns fill 2 bars
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

  /// The note lengths tapping cycles through, in eighth-steps: 1/8 · 1/4 · 1/2.
  static const _tuneNoteLens = [2, 4, 8];

  /// How far a note at [step] may grow before it hits the next note or the grid
  /// end (a note never overruns its neighbour), capped at the longest length.
  int _tuneGrowCap(List<StepCell> cells, int step) {
    var nextOnset = kPatternSteps;
    for (final c in cells) {
      if (c.step > step && c.step < nextOnset) nextOnset = c.step;
    }
    return min(_tuneNoteLens.last, nextOnset - step);
  }

  /// Tap a pitch cell: place a note (1/8), or — on a note that's already there —
  /// GROW it to the next length (1/8 → 1/4 → 1/2), or REMOVE it once it can't
  /// grow any further (at 1/2, or blocked by the next note). Long-press still
  /// cycles its dynamics. Length editing with no extra controls.
  void _toggleTuneCell(int midi, int step) {
    final cells = _tuneStepCells();
    final idx = cells.indexWhere((c) => c.row == midi && c.step == step);
    final next = [...cells];
    if (idx < 0) {
      next.add(StepCell(midi, step, len: _tuneNoteLens.first));
    } else {
      final cur = cells[idx];
      final cap = _tuneGrowCap(cells, step);
      final grown = _tuneNoteLens.firstWhere(
        (t) => t > cur.len && t <= cap,
        orElse: () => -1,
      );
      if (grown < 0) {
        next.removeAt(idx); // maxed / capped → tapping again clears it
      } else {
        next[idx] =
            StepCell(cur.row, cur.step, len: grown, velocity: cur.velocity);
      }
    }
    _writeTuneCells(next);
  }

  /// Long-press a placed note: cycle the whole time-slice's dynamics
  /// soft ↔ normal (full note-level editing, Beginner-Tracker parity).
  void _cycleTuneCellVelocity(int midi, int step) {
    final cells = _tuneStepCells();
    final atStep = cells.where((c) => c.step == step);
    if (atStep.isEmpty) return; // no note here to accent
    final nextVel = atStep.first.velocity >= 1.0 ? _softVelocity : 1.0;
    _writeTuneCells([
      for (final c in cells)
        if (c.step == step)
          StepCell(c.row, c.step, len: c.len, velocity: nextVel)
        else
          c,
    ]);
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

  /// A section armed to launch at the next seam, when quantize is on.
  ///
  /// Track toggles have been quantized since quantize shipped; sections fired
  /// instantly, so the same screen behaved two different ways — arm a track and
  /// it waits for the beat, tap a section and it jumps. Now both wait.
  int? _pendingScene;

  /// How many loops each section plays before the chain moves on — A×4, B×2.
  ///
  /// Defaults to 1, i.e. exactly the chain behaviour that shipped: one pass per
  /// section. The export has always used 2, and that difference stays until
  /// someone sets a value here, at which point BOTH follow it — a section that
  /// plays four times on screen and twice in the export would be a bug.
  final List<int> _sceneRepeats = List<int>.filled(4, 1);

  /// Passes completed on the current section.
  int _chainPass = 0;
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
  int? get pendingScene => _pendingScene;
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
  void duplicateTrack(String id) => _duplicateTrack(id);
  @override
  void removeCopy(String id) => _removeCopy(id);
  @override
  List<String> get trackIds => [for (final t in _engine.tracks) t.id];
  @override
  void addRoleTrack(String roleId) => _addRoleTrack(roleId);
  @override
  void addEmptyTrack() => _addEmptyTrack();
  @override
  bool isEmptyTrack(String id) => _engine.isEmptyTrack(id);
  @override
  void renameTrack(String id, String? name) =>
      setState(() => _engine.setTrackName(id, name));
  @override
  String trackLabelOf(String id) =>
      _trackLabel(AppLocalizations.of(context)!, id);
  @override
  double automationAt(String id, int step) =>
      _engine.automationFor(id, AutomationParam.level)?.at(step) ?? 1.0;
  @override
  bool hasAutomationFor(String id) =>
      _engine.automationFor(id, AutomationParam.level) != null;
  @override
  void cycleAutomationStep(String id, int step) =>
      _cycleAutomationStep(id, step);
  @override
  void clearAutomation(String id) => _clearAutomation(id);
  @override
  AutomationParam get automationParam => _autoParam;
  @override
  void setAutomationParam(AutomationParam param) => _setAutomationParam(param);
  @override
  double automationAtParam(String id, AutomationParam param, int step) =>
      _engine.automationFor(id, param)?.at(step) ?? param.neutral;
  @override
  bool hasAutomationForParam(String id, AutomationParam param) =>
      _engine.automationFor(id, param) != null;
  @override
  double trackFilterOf(String id) => _engine.trackFilter(id);
  @override
  void cycleTrackFilter(String id) => _cycleTrackFilter(id);
  @override
  String addAudioTrack(Float64List pcm) {
    final id = _engine.addAudioTrack(pcm);
    setState(() {});
    _syncPlayback();
    return id;
  }

  @override
  bool isAudioTrack(String id) => _engine.isAudioTrack(id);
  @override
  double audioStretchOf(String id) => _engine.audioStretchOf(id);
  @override
  int get debugLoopSamples => _engine.timing.totalSamples;
  @override
  (String, int)? get laneCursor {
    final id = _cursorTrackId;
    final step = _cursorStep;
    return id == null || step == null ? null : (id, step);
  }

  @override
  List<String> copyTargetsFor(String from) => _engine.copyTargetsFor(from);
  @override
  bool copyPattern(String from, String to) {
    final ok = _engine.copyPattern(from, to);
    if (ok) {
      setState(() {});
      _syncPlayback();
    }
    return ok;
  }

  @override
  double trackSwingOf(String id) => _engine.trackSwing(id);
  @override
  bool hasOwnSwing(String id) => _engine.hasOwnSwing(id);
  @override
  void cycleTrackSwing(String id) => _cycleTrackSwing(id);
  @override
  int sceneRepeats(int i) => _sceneRepeats[i];
  @override
  void cycleSceneRepeats(int i) => _cycleSceneRepeats(i);
  @override
  bool sceneHasTrack(int i, String id) => _sceneHasTrack(i, id);
  @override
  void toggleSceneTrack(int i, String id) => _toggleSceneTrack(i, id);
  @override
  bool duplicateSection() => _duplicateSection(AppLocalizations.of(context)!);
  @override
  bool get isChaining => _chaining;
  @override
  void toggleChain() => _toggleChain();
  @override
  bool get hasScenes => _scenes.any((s) => s != null);
  @override
  Float64List debugRenderArrangement() =>
      _engine.renderArrangement(_capturedScenes(), repeats: _capturedRepeats());
  @override
  Uint8List debugRenderLoop() => _engine.renderLoop();
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
    final wavData = readWavPcm16(wav);
    // The AEC reference is mono; fold a panned (stereo) loop down before it feeds
    // the reference scheduler so the echo estimate stays correct while jamming.
    if (wavData.channels == 2) {
      final frames = wavData.samples.length ~/ 2;
      final mono = Int16List(frames);
      for (var i = 0; i < frames; i++) {
        mono[i] = (wavData.samples[i * 2] + wavData.samples[i * 2 + 1]) ~/ 2;
      }
      return mono.buffer.asUint8List(mono.offsetInBytes, mono.lengthInBytes);
    }
    final data = wavData.samples;
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
    setState(() {
      _engine.applySpec(spec);
      _discardSolo();
    });
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
        await _exportDoor();
      case 'tracker':
        unawaited(_openInTracker());
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
    final onReturn = widget.onReturnToDaw;
    if (onReturn != null) {
      onReturn(_engine.spec);
      Navigator.of(context).pop();
      return;
    }
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

  /// WS-X6 — one export door for Loop Studio.
  ///
  /// Everything this screen can hand out was scattered across a flat menu:
  /// notation under "export", audio under "wav", and the **share code** — the
  /// thing people here actually pass to each other — under "copy", where
  /// nothing suggested it was a way of getting the music out at all.
  /// Test seam: open the WS-X6 export door. The menu that hosts it is a
  /// PopupMenu, which a widget test cannot drive without the route.
  @visibleForTesting
  Future<void> debugOpenExportDoor() => _exportDoor();

  Future<void> _exportDoor() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    await showExportSheet(
      context,
      options: [
        ExportOption(
          kind: ExportKind.audio,
          label: 'Sound file',
          detail: 'The loop, rendered',
          run: _saveWav,
        ),
        ExportOption(
          kind: ExportKind.symbolic,
          label: 'Notes (MusicXML, MIDI, PDF…)',
          run: () async => _exportGroove(),
          // Drums are unpitched, so a beat-only groove has no score — the same
          // honest refusal the Audio Editor makes.
          enabled: hasPitchedTrack,
          disabledReason: 'Only drums so far — there are no pitched notes yet',
        ),
        ExportOption(
          kind: ExportKind.share,
          label: 'Copy the share code',
          detail: 'A short code someone else can paste in',
          run: () async {
            await Clipboard.setData(ClipboardData(text: grooveToken));
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.loopMixerCodeCopied)),
            );
          },
        ),
      ],
    );
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

  /// Graduate the groove's pitched tracks into the Advanced Tracker to fine-edit
  /// on the full chromatic grid (via the score bridge — one channel per track),
  /// then ROUND-TRIP: if the pro shares their edited tune back through
  /// MelodyBridge (the tracker's "Share tune" seam), fold it into the loop on
  /// return. One-way today only if they don't share; a fully-automatic
  /// publish-on-exit is a coordinated follow-up on the tracker side.
  Future<void> _openInTracker() async {
    final l10n = AppLocalizations.of(context)!;
    final parts = grooveParts(_engine, nameOf: (id) => _trackLabel(l10n, id));
    if (parts == null) return;
    final before = MelodyBridge.instance.current;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdvancedTrackerScreen(
          initialSong: trackerSongFromMultiPart(parts.score),
          // Auto-publish the edited tune back on exit → no manual "Share tune".
          autoShareOnExit: true,
        ),
      ),
    );
    if (!mounted) return;
    _foldTrackerReturn(before);
  }

  /// If a fresh tune arrived on [MelodyBridge] since [before] (the pro shared
  /// their Tracker edit back), fold it into the loop via the shared-tune loader.
  /// Factored out of [_openInTracker] so the round-trip is unit-testable without
  /// driving real navigation.
  void _foldTrackerReturn(SharedMelody? before) {
    final after = MelodyBridge.instance.current;
    if (after != null && !identical(after, before)) loadSharedTune();
  }

  /// Round-trip the current beat target through the full Drum Kit pad editor:
  /// seed the kit from the drum grid, and on Done apply the edited pattern back
  /// to this track (the 'drums' card via a drum override, or the captured beat).
  Future<void> _openDrumsInDrumKit() async {
    final seed = _engine.drumRowsFor(_beatTarget) ?? const DrumRowsPattern({});
    final edited = await Navigator.of(context).push<DrumRowsPattern>(
      MaterialPageRoute(builder: (_) => DrumkitScreen(initialBeat: seed)),
    );
    if (edited == null || !mounted) return;
    _applyDrumKitEdit(edited);
  }

  /// Applies a Drum Kit round-trip result to the current beat target and makes
  /// it audible. Pure state mutation (no navigation) so it's unit-testable.
  void _applyDrumKitEdit(DrumRowsPattern edited) {
    setState(() {
      if (_beatTarget == LoopEngine.beatTrackId) {
        _engine.setUserBeatTrack(edited);
        _engine.enabled.add(LoopEngine.beatTrackId);
      } else {
        _engine.setTrackDrums(_beatTarget, edited);
        _engine.enabled.add(_beatTarget);
      }
    });
    _syncPlayback();
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
      // A track that genuinely uses both sides of middle C gets a GRAND staff.
      // Forcing it into one clef (what this did before) buried the far end under
      // ledger lines — the "hard-coded clef choices" the retirement map lists.
      var staff = GrooveStaff.treble;
      if (cells != null) {
        staff = grooveStaffForCells(cells);
        score = grooveScore(
          cells,
          clef: staff == GrooveStaff.bass ? Clef.bass : Clef.treble,
        );
      } else {
        // Unpitched (drums / beatbox): a one-staff rhythm reduction.
        final variant = (_engine.variants[track.id] ?? 0)
            .clamp(0, track.variants.length - 1);
        final pattern = track.variants[variant];
        if (pattern is DrumRowsPattern) score = drumGrooveScore(pattern);
      }
      if (score == null) continue;
      rows.add(_scoreStaffRow(l10n, track.id, score, staff: staff));
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
      color: _colorFor(track.id),
      child: _TrackCard(
        color: _colorFor(track.id),
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
        steps: _engine.trackSteps(track.id),
        onCycleSteps: () => _cycleTrackSteps(track.id),
        stepsTooltip: l10n.loopMixerTrackLength,
        onLevel: (v) => _setLevel(track.id, v),
        pan: _engine.panOf(track.id),
        onPan: (v) => _setPan(track.id, v),
        panLabel: l10n.loopMixerPan,
        soloed: _soloTrack == track.id,
        onSolo: () => _toggleSolo(track.id),
        voiced: _engine.trackVoice(track.id) != null,
        onVoice:
            _trackIsPitched(track) ? () => _pickVoice(l10n, track.id) : null,
        // Only captured layers (sung / beatboxed) can be removed; the five
        // built-in band cards are the fixed groove.
        onDelete: (track.id == LoopEngine.userTrackId ||
                track.id == LoopEngine.beatTrackId)
            ? () => _deleteTrack(track.id)
            : null,
        deleteTooltip: l10n.loopMixerDeleteTrack,
        // Per-track Edit → open this track's beat/tune grid (Loop Studio
        // contract: edit the actual events, not a baked preview).
        onEdit: _trackIsEditable(track) ? () => _editTrack(track.id) : null,
        editTooltip: l10n.loopMixerEditTrack,
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

  /// LM-UX4: a tappable kick/snare/hat × step grid that builds/edits the beat.
  Widget _buildBeatEditor(AppLocalizations l10n) {
    final steps = _beatSteps;
    final p = _beatTargetPattern;
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.loopMixerBeatEditHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
                // Round-trip this beat into the full Drum Kit pad editor.
                TextButton.icon(
                  onPressed: _openDrumsInDrumKit,
                  icon: const Icon(Icons.grid_4x4, size: 18),
                  label: Text(l10n.loopMixerEditDrumsInKit),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Which drum track to edit — the drums card, or the captured beat.
            if (_beatTargets.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final id in _beatTargets)
                      ChoiceChip(
                        label: Text(_trackLabel(l10n, id)),
                        selected: _beatTarget == id,
                        onSelected: (_) => setState(() => _beatTarget = id),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
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
                          // Long-press a hit → ghost ↔ normal (dynamics), the
                          // beat twin of the tune editor's soft/normal.
                          onLongPress: () => _cycleBeatCellVelocity(drum, s),
                          child: Container(
                            height: 24,
                            margin: const EdgeInsets.all(1),
                            decoration: BoxDecoration(
                              // A ghost hit draws dimmer so dynamics are visible.
                              color: on(drum, s)
                                  ? scheme.primary.withValues(
                                      alpha: _beatVelAt(drum, s) >= 1.0
                                          ? 1.0
                                          : 0.4 + 0.6 * _beatVelAt(drum, s),
                                    )
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
            // Controls wrap so a long label (e.g. DE) never overflows a phone.
            Wrap(
              spacing: 6,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Beginner-Tracker parity: widen the grid to two octaves.
                FilterChip(
                  label: Text(l10n.loopMixerTuneWide),
                  selected: _tuneWideRange,
                  onSelected: setTuneWideRange,
                  visualDensity: VisualDensity.compact,
                ),
                // Graduate to the full (Advanced) Tracker for fine chromatic /
                // per-cell editing; a tune shared back folds into the loop.
                TextButton.icon(
                  onPressed: () => unawaited(_openInTracker()),
                  icon: const Icon(Icons.tune, size: 18),
                  label: Text(l10n.loopMixerTuneInTracker),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
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
                // Long-press a note to cycle its dynamics soft ↔ normal.
                onLongPress: _cycleTuneCellVelocity,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A consistent labelled control row (LM-UX5) — a fixed-width label so every
  /// option (Key / Scale / Kit / Swing / Filter / …) left-aligns cleanly.
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

  /// Whether track [id] has an in-place editor (score → tap-to-edit).
  bool _trackIsEditableById(String id) =>
      id == 'drums' ||
      id == LoopEngine.beatTrackId ||
      _tuneTargets.contains(id);

  Widget _scoreStaffRow(
    AppLocalizations l10n,
    String id,
    Score score, {
    GrooveStaff staff = GrooveStaff.treble,
  }) {
    final editable = _trackIsEditableById(id);
    return InkWell(
      // The score is an editing surface: tap a part's staff to open that
      // track's grid editor (beat grid for drums, tune grid for a pitched part).
      onTap: editable ? () => _editTrack(id) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      _trackLabel(l10n, id),
                      style: Theme.of(context).textTheme.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (editable)
                    Icon(
                      Icons.edit_note,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ),
            // LM-UX2: render the staff at a legible size and SCROLL a wide bar
            // horizontally instead of shrinking the whole thing to fit.
            // LM-UX3: light up the note currently sounding, driven by the loop
            // clock's eighth-step index (rebuilds only when the note moves).
            // Clip the staff to its own row so a tall staff (high notes / ledger
            // lines) can't paint over the neighbouring track's row — that
            // out-of-box bleed was the "rows totally overlap" bug.
            Expanded(
              child: ClipRect(
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
                          final id =
                              grooveNoteIdAtStep(score, step % totalSteps);
                          if (id != null) ids.add(id);
                        }
                        if (staff == GrooveStaff.grand) {
                          // Two staves in the same row height, so the band
                          // stays scannable — a grand staff is inherently
                          // taller, hence the smaller staffSpace.
                          return GrandStaffView(
                            key: const ValueKey('loop-grand-staff'),
                            grandStaff: grandStaffFromScore(score),
                            staffSpace: 7,
                            theme: kidsScoreTheme,
                            highlightedIds: ids,
                          );
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
            ),
          ],
        ),
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
    // An armed SECTION lands first: it defines the whole mix, so applying it
    // after the armed card toggles would throw those away.
    final armedScene = _pendingScene;
    if (armedScene != null) {
      _pendingScene = null;
      _applySceneNow(armedScene);
    }
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
    // Stereo (a panned mix): repair each channel independently and re-interleave.
    if (pcm.channels == 2) {
      final frames = pcm.samples.length ~/ 2;
      final left = Int16List(frames);
      final right = Int16List(frames);
      for (var i = 0; i < frames; i++) {
        left[i] = pcm.samples[i * 2];
        right[i] = pcm.samples[i * 2 + 1];
      }
      final fl = crossfadePcm16Seam(left);
      final fr = crossfadePcm16Seam(right);
      if (identical(fl, left) && identical(fr, right)) return wav;
      final out = Int16List(frames * 2);
      for (var i = 0; i < frames; i++) {
        out[i * 2] = fl[i];
        out[i * 2 + 1] = fr[i];
      }
      return wavBytesStereo(out);
    }
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

  /// Leaves solo, putting back the mix it was hiding. Safe to call when not
  /// soloing.
  ///
  /// Anything that REPLACES the enabled set (launching a scene, loading a token,
  /// Surprise-me, Stop) has to come through here first, or `_enabledBeforeSolo`
  /// still holds the pre-solo mix and the next un-solo silently clobbers what
  /// just replaced it.
  void _leaveSolo() {
    if (_soloTrack == null) return;
    _engine.enabled
      ..clear()
      ..addAll(_enabledBeforeSolo ?? const <String>{});
    _discardSolo();
  }

  /// Forgets the solo state WITHOUT restoring the mix under it — for callers
  /// that are about to define a new mix themselves (loading a token, launching a
  /// scene, Surprise-me, Stop). Restoring there would put back a mix the user
  /// just replaced.
  ///
  /// The two fields must always move together; every site used to do that by
  /// hand, which is how the scene-launch path came to drop one of them.
  void _discardSolo() {
    _soloTrack = null;
    _enabledBeforeSolo = null;
  }

  /// The mix as the user set it, ignoring any solo — what a scene should
  /// capture. Capturing during solo used to store the one-track solo state as
  /// if it were the mix.
  Set<String> get _mixUnderSolo =>
      _soloTrack == null ? {..._engine.enabled} : {...?_enabledBeforeSolo};

  void _toggleSolo(String id) {
    if (!_engine.tracks.any((track) => track.id == id)) return;
    setState(() {
      if (_soloTrack == id) {
        _leaveSolo();
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

  void _captureScene(int i) => setState(() {
        // Not _engine.captureScene() directly: while soloing, `enabled` is the
        // one-track solo state, so that would save "just the lead" as the scene.
        final scene = _engine.captureScene();
        _scenes[i] = GrooveScene(_mixUnderSolo, scene.variants);
      });

  void _launchScene(int i) {
    if (_scenes[i] == null) return;
    // Quantized: arm it for the next seam, exactly as a card toggle is armed.
    // Tapping the armed section again disarms it.
    if (_quantize && _clock.isRunning && _engine.enabled.isNotEmpty) {
      setState(() => _pendingScene = _pendingScene == i ? null : i);
      return;
    }
    _applySceneNow(i);
  }

  /// Puts section [i] on the mix immediately.
  ///
  /// Separate from [_launchScene] because the seam has to bypass the quantize
  /// check: routing the armed section back through [_launchScene] re-read
  /// `_quantize` — still on, still running — and simply re-armed it, so the
  /// section never landed and the pending flag never cleared.
  void _applySceneNow(int i) {
    final scene = _scenes[i];
    if (scene == null) return;
    setState(() {
      // A scene DEFINES the mix, so forget solo rather than restoring under it.
      // Without this the stale _enabledBeforeSolo survived and the next un-solo
      // threw the launched scene away.
      _discardSolo();
      _engine.applyScene(scene);
      _chainIndex = i;
      _chainPass = 0;
    });
    _syncPlayback();
    _checkCombo();
  }

  /// Copies the section now playing into the next free slot and launches the
  /// copy — the sequencer workflow of "take A, make B from it, change one
  /// thing". Without this every variation has to be rebuilt from nothing.
  ///
  /// It launches the COPY rather than staying on the original, because the
  /// point of duplicating is to edit the new one; leaving the user on A would
  /// mean their next change silently edited the wrong section.
  bool _duplicateSection(AppLocalizations l10n) {
    final source = _scenes[_chainIndex];
    if (source == null) return false;
    final free = _scenes.indexWhere((s) => s == null);
    if (free < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.loopMixerSectionsFull)),
      );
      return false;
    }
    setState(() {
      // A fresh Set/Map: sharing them would make editing the copy silently
      // edit the original too.
      _scenes[free] = GrooveScene({...source.enabled}, {...source.variants});
    });
    _launchScene(free);
    return true;
  }

  void _toggleChain() {
    setState(() => _chaining = !_chaining);
  }

  /// Repeats for [_capturedScenes], in the same order — empty slots are skipped
  /// in both, so the two lists stay aligned.
  List<int> _capturedRepeats() => [
        for (var i = 0; i < _scenes.length; i++)
          if (_scenes[i] != null) _sceneRepeats[i],
      ];

  /// Steps section [i]'s repeat count: 1 → 2 → 4 → 8 → 1.
  void _cycleSceneRepeats(int i) {
    const ladder = [1, 2, 4, 8];
    final next = ladder[(ladder.indexOf(_sceneRepeats[i]) + 1) % ladder.length];
    setState(() {
      _sceneRepeats[i] = next;
      if (_chainIndex == i && _chainPass >= next) _chainPass = 0;
    });
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
    // Hold this section for its repeat count before moving on.
    _chainPass++;
    if (_chainPass < _sceneRepeats[_chainIndex]) return;
    _chainPass = 0;
    for (var step = 1; step <= _scenes.length; step++) {
      final next = (_chainIndex + step) % _scenes.length;
      if (_scenes[next] != null) {
        setState(() {
          _discardSolo();
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
      if (!_quantize) {
        _pendingLaunches.clear(); // drop armed changes
        _pendingScene = null;
      }
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
      _discardSolo();
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

  /// Steps this track's loop length to the next allowed value, wrapping back to
  /// the full 2-bar grid.
  ///
  /// Tap-to-cycle rather than a slider or a menu: the whole point is that you
  /// hear what changed, and the child's next tap is the undo. Always resyncs —
  /// unlike a variant change, a length change can alter the LOOP's length, so
  /// the player needs the new buffer even if this track is muted.
  void _cycleTrackSteps(String id) {
    final current = _engine.trackSteps(id);
    final i = kLoopTrackLengths.indexOf(current);
    final next = kLoopTrackLengths[(i + 1) % kLoopTrackLengths.length];
    setState(() => _engine.setTrackSteps(id, next));
    _syncPlayback();
  }

  void _rollVariant(String id) {
    setState(() => _engine.rollVariant(id, rng: _rng));
    if (_engine.enabled.contains(id)) _syncPlayback();
  }

  void _setLevel(String id, double level) {
    setState(() => _engine.levels[id] = level.clamp(0.0, 1.0));
    if (_engine.enabled.contains(id)) _syncPlayback();
  }

  void _setPan(String id, double pan) {
    setState(() => _engine.setPan(id, pan));
    if (_engine.enabled.contains(id)) _syncPlayback();
  }

  /// Whether track [id] has an in-place event editor: drums/beat → the beat
  /// grid, any pitched track → the tune grid.
  bool _trackIsEditable(LoopTrack t) =>
      t.id == 'drums' ||
      t.id == LoopEngine.beatTrackId ||
      _tuneTargets.contains(t.id) ||
      _trackIsPitched(t);

  /// Per-track Edit (Loop Studio contract): open the editor for THIS track's
  /// actual events — the beat grid for a drum/beat track, or the tune grid
  /// targeting this pitched track — and make sure it's audible while editing.
  void _editTrack(String id) {
    final isDrum = id == 'drums' || id == LoopEngine.beatTrackId;
    setState(() {
      if (isDrum) {
        _beatTarget = id;
        _showBeatEdit = true;
        _showTuneEdit = false;
      } else {
        _tuneTarget = _tuneTargets.contains(id) ? id : LoopEngine.userTrackId;
        _showTuneEdit = true;
        _showBeatEdit = false;
      }
      if (!_engine.enabled.contains(id) &&
          _engine.tracks.any((t) => t.id == id)) {
        _engine.enabled.add(id);
      }
    });
    _syncPlayback();
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

  /// E3 — the master bus's insert chain, in the shared FX rack. The two
  /// presets behind [LoopSend] stay as the quick path; this is everything else.
  void _showMasterFxSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final l10n = AppLocalizations.of(sheetContext)!;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (context, setSheetState) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.loopMixerMasterFx,
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.loopMixerMasterFxHint,
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(sheetContext).size.height * 0.5,
                    ),
                    child: SingleChildScrollView(
                      child: FxRack(
                        key: const ValueKey('loop-master-fx'),
                        chain: _engine.masterFxChain,
                        dense: true,
                        onChanged: (next) {
                          setMasterFxChain(next);
                          setSheetState(() {});
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
        ChordDegree.iii => HarmonicFunction.tonic,
        ChordDegree.vi => HarmonicFunction.tonic,
        ChordDegree.ii => HarmonicFunction.subdominant,
        ChordDegree.iv => HarmonicFunction.subdominant,
        ChordDegree.v => HarmonicFunction.dominant,
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
    setState(() {
      _engine.enabled.clear();
      _discardSolo();
    });
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
  // ---------------------------------------------------------------------------
  // Undo / redo — snapshot the engine's GrooveSpec whenever a content edit lands.
  // ---------------------------------------------------------------------------

  /// Records the pre-edit state onto the undo stack when the groove actually
  /// changed since the last record. Called from [_syncPlayback], which nearly
  /// every content edit funnels through, so a single hook covers them all;
  /// pause/resume/jam-handoff calls don't change the spec, so they don't record.
  void _recordHistory() {
    final current = _engine.spec;
    final base = _historyBase;
    if (base != null && current.cacheKey == base.cacheKey) return;
    if (base != null) {
      _undoStack.add(base);
      if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
      _redoStack.clear();
    }
    _historyBase = current;
  }

  bool get _canUndo => _undoStack.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty;

  void _applyHistory(GrooveSpec target) {
    // Solo is a transient screen mode layered over `enabled`; drop it so the
    // restored enabled-set isn't immediately overwritten by the solo re-assert.
    _discardSolo();
    setState(() => _engine.applySpec(target));
    // Anchor the base to the post-apply state so _syncPlayback's own record call
    // (applySpec may clamp/drop ids) doesn't push a spurious history entry.
    _historyBase = _engine.spec;
    _syncPlayback();
    _checkCombo();
  }

  void _undoEdit() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_engine.spec);
    _applyHistory(_undoStack.removeLast());
  }

  void _redoEdit() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_engine.spec);
    _applyHistory(_redoStack.removeLast());
  }

  /// Removes a captured (sung / beatboxed) track. Built-in cards can't be
  /// removed — they are the band. No-op for unknown/built-in ids.
  void _deleteTrack(String id) {
    if (id == LoopEngine.userTrackId) {
      setState(_engine.clearUserTrack);
    } else if (id == LoopEngine.beatTrackId) {
      setState(_engine.clearUserBeatTrack);
    } else {
      return;
    }
    if (_soloTrack == id) {
      _discardSolo();
    }
    _syncPlayback();
    _checkCombo();
  }

  void _syncPlayback() {
    _recordHistory();
    // WS-X1 follow-up — a live link that nothing ever writes to is an inert
    // link: `writeBackToProject` shipped with the link but had no caller, so
    // edits made here never reached the project track. Hooked HERE rather than
    // to the screen's exit because this surface has no single exit — it is
    // popped, backgrounded, or left running while another surface opens the
    // same track — and "write back on close" loses the edit in two of those
    // three. A no-op unless a live link exists.
    writeBackToProject();
    if (_soloTrack case final id?) {
      // Editors and capture callbacks can add tracks directly to the engine;
      // reassert solo at the shared audio boundary.
      _engine.enabled
        ..clear()
        ..add(id);
    }
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
    // An EMPTY track is not a copy of anything, so it has nothing to inherit a
    // colour from — the `_sourceIdOf` fallback would leave it grey and unnamed.
    // Slate: deliberately not one of the pitch-class colours, because it is not
    // yet any particular part.
    'track': Color(0xFF546E7A),
    // An imported loop: warm amber-brown, deliberately unlike the pitch-class
    // colours — it is audio, not a part the groove's key can move.
    'audio': Color(0xFF6D4C41),
  };

  /// A track's name: the player's own if they gave it one, else the app's.
  ///
  /// A duplicate reads as "Bass 2" rather than falling through to the
  /// unknown-id default, which labelled every copy "Sparkle"; an empty track
  /// reads as "Track 2" until it is renamed, which is exactly why renaming
  /// exists — "Track 2" says nothing about what is on it.
  String _trackLabel(AppLocalizations l10n, String id) {
    final given = _engine.trackName(id);
    if (given != null) return given;
    final source = _sourceIdOf(id);
    if (source != id) {
      final n = id.substring(source.length).replaceAll('-', ' ').trim();
      return '${_baseTrackLabel(l10n, source)} $n';
    }
    return _baseTrackLabel(l10n, id);
  }

  String _baseTrackLabel(AppLocalizations l10n, String id) => switch (id) {
        'drums' => l10n.loopMixerTrackDrums,
        'bass' => l10n.loopMixerTrackBass,
        'chords' => l10n.loopMixerTrackChords,
        'melody' => l10n.loopMixerTrackMelody,
        'voice' => l10n.loopMixerTrackVoice,
        'beat' => l10n.loopMixerTrackBeat,
        'track' => l10n.loopMixerTrackEmpty,
        'audio' => l10n.loopMixerTrackAudio,
        _ => l10n.loopMixerTrackSparkle,
      };

  String _kitLabel(AppLocalizations l10n, String id) => switch (id) {
        'deep' => l10n.loopMixerKitDeep,
        'warm' => l10n.loopMixerKitWarm,
        'lofi' => l10n.loopMixerKitLofi,
        'punchy' => l10n.loopMixerKitPunchy,
        'boom' => l10n.loopMixerKitBoom,
        'tight' => l10n.loopMixerKitTight,
        'tape' => l10n.loopMixerKitTape,
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

  // ===========================================================================
  // Score-Editor-style chrome: a slim action bar + one grouped overflow menu +
  // a docked "Sound & Feel" inspector, replacing the old wall of ~14 toolbar
  // icons and ~8 always-visible setting rows. Transport + undo/redo stay as
  // buttons; everything low-frequency moves into the ⋮ menu; every multi-value
  // song setting moves into the inspector.
  // ===========================================================================

  /// A non-selectable small-caps section label inside the overflow menu (the
  /// Score Workshop's `_menuHeader` pattern).
  PopupMenuItem<String> _menuSectionHeader(String text) =>
      PopupMenuItem<String>(
        enabled: false,
        height: 28,
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
        ),
      );

  String _sendLabel(AppLocalizations l10n, LoopSend s) => switch (s) {
        LoopSend.none => l10n.loopMixerSendNone,
        LoopSend.reverb => l10n.loopMixerSendReverb,
        LoopSend.delay => l10n.loopMixerSendDelay,
      };

  /// The one grouped overflow menu that holds every low-frequency action.
  Widget _overflowMenu(AppLocalizations l10n) {
    final canFollow = _jamming && _engravedTrackId != null;
    return PopupMenuButton<String>(
      tooltip: l10n.loopMixerMore,
      icon: const Icon(Icons.more_vert),
      onSelected: (v) {
        switch (v) {
          case 'score':
            toggleScorePanel();
          case 'infinite':
            toggleInfinite();
          case 'quantize':
            _toggleQuantize();
          case 'smear':
            _toggleSmearPad();
          case 'send':
            setSend(
              LoopSend.values[(send.index + 1) % LoopSend.values.length],
            );
          case 'duplicateSection':
            _duplicateSection(l10n);
          case 'masterFx':
            _showMasterFxSheet();
          case 'jam':
            toggleJam();
          case 'follow':
            toggleFollow();
          case 'tracker':
            unawaited(_openInTracker());
          case 'workshop':
            _openInWorkshop();
          case 'share':
            _openShareSheet();
        }
      },
      itemBuilder: (ctx) => [
        _menuSectionHeader(l10n.loopMixerGroupView),
        CheckedPopupMenuItem<String>(
          value: 'score',
          checked: _showScore,
          child: Text(l10n.loopMixerScore),
        ),
        const PopupMenuDivider(),
        _menuSectionHeader(l10n.loopMixerGroupPerform),
        CheckedPopupMenuItem<String>(
          value: 'infinite',
          checked: _infinite,
          child: Text(l10n.loopMixerInfinite),
        ),
        CheckedPopupMenuItem<String>(
          value: 'quantize',
          checked: _quantize,
          child: Text(l10n.loopMixerQuantize),
        ),
        CheckedPopupMenuItem<String>(
          value: 'smear',
          checked: _showSmear,
          child: Text(l10n.loopMixerSolo),
        ),
        PopupMenuItem<String>(
          value: 'send',
          child: Text('${l10n.loopMixerSend}: ${_sendLabel(l10n, send)}'),
        ),
        if (!sceneIsEmpty(_chainIndex))
          PopupMenuItem<String>(
            value: 'duplicateSection',
            child: Text(l10n.loopMixerDuplicateSection),
          ),
        PopupMenuItem<String>(
          value: 'masterFx',
          child: Text(l10n.loopMixerMasterFx),
        ),
        CheckedPopupMenuItem<String>(
          value: 'jam',
          checked: _jamming,
          child: Text(l10n.loopMixerJam),
        ),
        if (canFollow)
          CheckedPopupMenuItem<String>(
            value: 'follow',
            checked: isFollowing,
            child: Text(l10n.loopMixerFollow),
          ),
        const PopupMenuDivider(),
        _menuSectionHeader(l10n.loopMixerGroupShare),
        PopupMenuItem<String>(
          value: 'tracker',
          enabled: hasPitchedTrack,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.open_in_full, size: 18),
              const SizedBox(width: 10),
              Flexible(child: Text(l10n.loopMixerOpenTracker)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'workshop',
          enabled: hasPitchedTrack,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.edit_note, size: 18),
              const SizedBox(width: 10),
              Flexible(child: Text(l10n.loopMixerOpenWorkshopEditor)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'share',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.ios_share, size: 18),
              const SizedBox(width: 10),
              Flexible(child: Text(l10n.loopMixerShareExport)),
            ],
          ),
        ),
      ],
    );
  }

  /// The slim top action bar: transport + undo/redo pinned left, editing tools
  /// scroll in the middle, and the inspector toggle + overflow + help pin right.
  Widget _actionBar(AppLocalizations l10n) {
    final playing = _clock.isRunning;
    final hasBand = _engine.enabled.isNotEmpty;
    final advanced = !widget.simpleLayout;
    Widget vsep() => const SizedBox(
          height: 24,
          child: VerticalDivider(width: 12, thickness: 1),
        );
    final tools = <Widget>[
      if (advanced)
        IconButton(
          icon: const Icon(Icons.casino),
          tooltip: l10n.loopMixerRoll,
          onPressed: _roll,
          visualDensity: VisualDensity.compact,
        ),
      IconButton(
        icon: Icon(_showBeatEdit ? Icons.grid_on : Icons.grid_view),
        tooltip: l10n.loopMixerBeatEdit,
        isSelected: _showBeatEdit,
        onPressed: toggleBeatEdit,
        visualDensity: VisualDensity.compact,
      ),
      IconButton(
        icon: Icon(_showTuneEdit ? Icons.piano : Icons.piano_outlined),
        tooltip: l10n.loopMixerTuneEdit,
        isSelected: _showTuneEdit,
        onPressed: toggleTuneEdit,
        visualDensity: VisualDensity.compact,
      ),
      if (!advanced)
        IconButton(
          icon: Icon(
            _showScore ? Icons.library_music : Icons.library_music_outlined,
          ),
          tooltip: l10n.loopMixerScore,
          isSelected: _showScore,
          onPressed: toggleScorePanel,
          visualDensity: VisualDensity.compact,
        ),
    ];
    return Row(
      children: [
        IconButton(
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          tooltip: playing ? 'Pause' : 'Play',
          onPressed: hasBand ? _pauseOrResume : null,
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          icon: const Icon(Icons.stop),
          tooltip: l10n.loopMixerStop,
          onPressed: hasBand ? _stopAll : null,
          visualDensity: VisualDensity.compact,
        ),
        // WS-T3 — this screen has keyboard shortcuts for the first time, so it
        // needs somewhere to say so.
        IconButton(
          icon: const Icon(Icons.keyboard),
          tooltip: 'Keyboard',
          onPressed: () => showKeymapSheet(
            context,
            keymap: _keymap.keymap,
            supported: kLoopIntents,
            service: _keymap,
          ),
          visualDensity: VisualDensity.compact,
        ),
        vsep(),
        IconButton(
          icon: const Icon(Icons.undo),
          tooltip: l10n.loopMixerUndo,
          onPressed: _canUndo ? _undoEdit : null,
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          icon: const Icon(Icons.redo),
          tooltip: l10n.loopMixerRedo,
          onPressed: _canRedo ? _redoEdit : null,
          visualDensity: VisualDensity.compact,
        ),
        vsep(),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: tools),
          ),
        ),
        if (advanced) ...[
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: l10n.loopMixerSoundFeel,
            isSelected: _showInspector,
            onPressed: toggleInspector,
            visualDensity: VisualDensity.compact,
          ),
          _overflowMenu(l10n),
        ],
        IconButton(
          icon: const Icon(Icons.help_outline),
          tooltip: l10n.loopMixerHelp,
          onPressed: () => showTutorial(context, loopMixerPrimer(l10n)),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  /// One titled section inside the inspector (caption above its control).
  Widget _inspectorSection(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      );

  /// A compact labelled dropdown for a single-select option group. Replaces a
  /// Wrap of many ChoiceChips (Style / Harmony / Key / Scale / Kit) so the
  /// "Sound & Feel" sheet fits on a phone instead of overflowing with buttons.
  /// [below] renders extra controls under the dropdown (e.g. Harmony's custom
  /// chips + "Make" button, or the function strip).
  Widget _dropdownSection<T>(
    String label,
    T value,
    List<(T, String)> options,
    ValueChanged<T> onChanged, {
    Widget? below,
  }) {
    return _inspectorSection(
      label,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InputDecorator(
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                isDense: true,
                items: [
                  for (final (v, l) in options)
                    DropdownMenuItem<T>(
                      value: v,
                      child: Text(l, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
          if (below != null) ...[const SizedBox(height: 6), below],
        ],
      ),
    );
  }

  /// Harmony as a dropdown (Off + built-in progressions) with the custom
  /// progressions + "Make" + the function strip kept below it. A custom
  /// progression can't be a dropdown value (it isn't in the item list), so the
  /// dropdown falls back to Off while the custom's chip shows selected.
  Widget _harmonySection(AppLocalizations l10n) {
    final builtinIds = {for (final p in kProgressions) p.id};
    final curId = _engine.progression?.id;
    final dropdownValue =
        (curId != null && builtinIds.contains(curId)) ? curId : null;
    return _dropdownSection<String?>(
      l10n.loopMixerHarmony,
      dropdownValue,
      [
        (null, l10n.loopMixerHarmonyOff),
        for (final p in kProgressions) (p.id, p.label),
      ],
      (id) => _setProgression(
        id == null ? null : kProgressions.firstWhere((p) => p.id == id),
      ),
      below: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_customProgressions.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final p in _customProgressions)
                  InputChip(
                    label: Text(p.label),
                    selected: _engine.progression?.id == p.id,
                    onSelected: (_) => _setProgression(p),
                    onDeleted: () => _deleteCustomProgression(p),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _makeCustomProgression(l10n),
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.loopMixerHarmonyMake),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
          if (_engine.progression != null) ...[
            const SizedBox(height: 6),
            _progressionFunctionStrip(_engine.progression!),
          ],
        ],
      ),
    );
  }

  /// The "Sound & Feel" inspector body — every multi-value song setting that
  /// used to be an always-visible row now lives here (Score-Editor pattern).
  Widget _soundInspectorContent(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _inspectorSection(
          l10n.loopMixerTempo,
          Row(
            children: [
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
        _dropdownSection<String>(
          l10n.loopMixerStyle,
          _engine.styleId,
          [
            for (final style in kGrooveStyles)
              (style.id, _styleLabel(l10n, style.id)),
          ],
          _setStyle,
        ),
        _harmonySection(l10n),
        _dropdownSection<int>(
          l10n.loopMixerKey,
          _engine.key,
          [
            for (var k = 0; k < LoopMixerScreen._keyNames.length; k++)
              (k, LoopMixerScreen._keyNames[k]),
          ],
          _setKey,
        ),
        _dropdownSection<GrooveScale>(
          l10n.loopMixerScale,
          _engine.scale,
          [
            (GrooveScale.majorPentatonic, l10n.loopMixerScaleMajor),
            (GrooveScale.minorPentatonic, l10n.loopMixerScaleMinor),
          ],
          _setScale,
        ),
        _dropdownSection<String>(
          l10n.loopMixerKit,
          _engine.kitId,
          [for (final kit in kDrumKits) (kit.id, _kitLabel(l10n, kit.id))],
          _setKit,
        ),
        _inspectorSection(
          l10n.loopMixerSwing,
          _captionedSlider(
            low: l10n.loopMixerSwingStraight,
            high: l10n.loopMixerSwingShuffle,
            slider: Slider(
              value: _engine.swing,
              max: 0.6,
              divisions: 12,
              onChanged: _setSwing,
            ),
          ),
        ),
        _inspectorSection(
          l10n.loopMixerSwingPerTrack,
          _trackSwingRow(l10n),
        ),
        _projectRow(l10n),
        _inspectorSection(
          l10n.loopMixerAddTrack,
          _addTrackRow(l10n),
        ),
        _inspectorSection(
          l10n.loopMixerDuplicateTrack,
          _duplicateRow(l10n),
        ),
        _renameRow(l10n),
        _copyPatternRow(l10n),
        _inspectorSection(
          l10n.loopMixerTrackFilter,
          _trackFilterRow(l10n),
        ),
        _inspectorSection(
          l10n.loopMixerAutomation,
          _automationRows(l10n),
        ),
        _inspectorSection(
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
                if (v.abs() < 0.06) _setMasterFilter(0);
              },
            ),
          ),
        ),
        _inspectorSection(
          l10n.loopMixerArrange,
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sceneRow(l10n),
              _sceneGrid(l10n),
            ],
          ),
        ),
      ],
    );
  }

  /// The inspector as a docked panel (wide) — a bordered, independently
  /// scrolling column on the right of the track lane.
  Widget _soundInspectorPanel(AppLocalizations l10n) => Container(
        width: 300,
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
          child: _soundInspectorContent(l10n),
        ),
      );

  /// L2 — the session grid: which tracks play in which section.
  ///
  /// The data for this has existed since sections shipped (each `GrooveScene`
  /// stores an enabled set AND a variant per track); it was only ever shown as
  /// four lettered pads, so you could launch a section but never see what was
  /// in it, let alone change one thing about it.
  ///
  /// Hidden until at least one section is captured. An empty 7×4 grid of
  /// nothing is noise on a child's screen, and the pads above already teach
  /// how to make the first one.
  Widget _sceneGrid(AppLocalizations l10n) {
    if (!hasScenes) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final track in _engine.tracks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      _trackLabel(l10n, track.id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  for (var i = 0; i < _scenes.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: GestureDetector(
                        key: Key('loop-cell-${track.id}-$i'),
                        onTap: _scenes[i] == null
                            ? null
                            : () => _toggleSceneTrack(i, track.id),
                        child: Container(
                          width: 30,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _sceneHasTrack(i, track.id)
                                ? _colorFor(track.id)
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: _sceneHasTrack(i, track.id)
                              ? Text(
                                  String.fromCharCode(
                                    65 + (_scenes[i]!.variants[track.id] ?? 0),
                                  ),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          // Repeats: how many times each section plays before the chain moves
          // on. Only meaningful once sections are chained, but shown always so
          // it is discoverable before you turn chaining on.
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    l10n.loopMixerRepeats,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                for (var i = 0; i < _scenes.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: GestureDetector(
                      key: Key('loop-repeats-$i'),
                      onTap: _scenes[i] == null
                          ? null
                          : () => _cycleSceneRepeats(i),
                      child: SizedBox(
                        width: 30,
                        height: 16,
                        child: Center(
                          child: Text(
                            _scenes[i] == null ? '' : '×${_sceneRepeats[i]}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The values a tapped automation step cycles through, per parameter.
  ///
  /// A ladder, not a continuous drag: this is the same tap-to-cycle the tune
  /// grid, the beat grid, the loop-length badge and the swing badge all use, and
  /// a child who can already build a beat can build a fade with no new gesture.
  /// A continuous curve would be more expressive and a different product.
  ///
  /// Every ladder STARTS at that parameter's neutral value, because the last
  /// rung has to wrap back to it — cycling all the way round is how a lane is
  /// undone, and a lane that has gone neutral everywhere is dropped rather than
  /// stored. That rule is what keeps "no lane" distinguishable from "a flat
  /// lane", which is what keeps an un-automated groove byte-identical.
  static const Map<AutomationParam, List<double>> _ladders = {
    AutomationParam.level: [1.0, 0.66, 0.33, 0.0],
    // Centre, then across the field left to right.
    AutomationParam.pan: [0.5, 0.0, 0.25, 0.75, 1.0],
    // Off, then darker and darker, then thinner and thinner.
    AutomationParam.filter: [0.5, 0.25, 0.0, 0.75, 1.0],
  };

  /// Which parameter the one strip is currently editing.
  ///
  /// One strip with a switch rather than a strip per parameter (the
  /// maintainer's call): three stacked 16-cell grids per track would fill the
  /// inspector with a matrix, and the point of the grid is that it is the same
  /// gesture everywhere, not that it is everywhere at once.
  AutomationParam _autoParam = AutomationParam.level;

  void _setAutomationParam(AutomationParam p) {
    if (p == _autoParam) return;
    setState(() => _autoParam = p);
  }

  String _autoParamLabel(AppLocalizations l10n, AutomationParam p) =>
      switch (p) {
        AutomationParam.level => l10n.loopMixerAutomationVolume,
        AutomationParam.pan => l10n.loopMixerAutomationPan,
        AutomationParam.filter => l10n.loopMixerAutomationFilter,
      };

  /// Steps one cell of [id]'s lane for the parameter on show. Creates the lane
  /// on first touch, and drops it again when it cycles back to neutral.
  void _cycleAutomationStep(String id, int step, [AutomationParam? param]) {
    final p = param ?? _autoParam;
    final ladder = _ladders[p]!;
    final existing = _engine.automationFor(id, p) ??
        AutomationLane.neutral(p, kPatternSteps);
    final current = existing.at(step);
    var i = ladder.indexWhere((v) => (v - current).abs() < 1e-6);
    if (i < 0) i = 0;
    final next = existing.withStep(step, ladder[(i + 1) % ladder.length]);
    setState(() {
      _engine.setAutomation(id, p, next.isNeutralFor(p) ? null : next);
    });
    _syncPlayback();
  }

  // --- WS-L1: a keyboard cursor over the lane strip -------------------------
  //
  // The strip was tap-only, which is right for the surface it is on but leaves
  // it unreachable to anyone not using a touchscreen or a mouse — and drawing a
  // sixteen-step fade by tapping each cell four times is slow even with one.
  //
  // The cursor is ADDITIVE: tap-to-cycle is untouched, and the cursor only
  // exists once a key has moved it. That is why [_cursorStep] starts null
  // rather than at 0 — an outline drawn around a cell nobody asked for would
  // read as a selection the player did not make.

  /// Which lane cell the keyboard is on: track index and step. Null = the
  /// keyboard has not been used yet, and nothing is outlined.
  int? _cursorTrack;
  int? _cursorStep;

  /// Moves the cursor by [dTrack] rows and [dStep] cells, creating it at the
  /// first cell if it does not exist yet.
  ///
  /// Both axes CLAMP rather than wrap. Wrapping steps would jump the player
  /// from the end of a bar to its start, which reads as a mis-key; wrapping
  /// tracks would jump the drums to the sparkle. A cursor at the edge that
  /// stays put is the honest answer to "there is nothing further this way".
  bool _moveCursor(int dTrack, int dStep) {
    final tracks = _engine.tracks;
    if (tracks.isEmpty) return false;
    final track = (_cursorTrack ?? 0) + (_cursorStep == null ? 0 : dTrack);
    final step = (_cursorStep ?? 0) + (_cursorStep == null ? 0 : dStep);
    setState(() {
      _cursorTrack = track.clamp(0, tracks.length - 1);
      _cursorStep = step.clamp(0, kPatternSteps - 1);
    });
    return true;
  }

  /// The track the cursor is on, or null when there is no cursor.
  String? get _cursorTrackId {
    final i = _cursorTrack;
    final tracks = _engine.tracks;
    if (i == null || _cursorStep == null || i >= tracks.length) return null;
    return tracks[i].id;
  }

  /// Sets the cell under the cursor from a digit: 0 = the bottom of the
  /// parameter's range, 9 = the top.
  ///
  /// Digits rather than the tap ladder because a keyboard has ten of them and
  /// the ladder has four: typing a shape in is the thing the keyboard is better
  /// at, and it is how every tracker has done velocities for thirty years.
  bool _typeAutomationDigit(int digit) {
    final id = _cursorTrackId;
    final step = _cursorStep;
    if (id == null || step == null) return false;
    final value = (digit / 9).clamp(0.0, 1.0);
    final existing = _engine.automationFor(id, _autoParam) ??
        AutomationLane.neutral(_autoParam, kPatternSteps);
    final next = existing.withStep(step, value);
    setState(() {
      // The same drop-when-neutral rule the tap path uses — "no lane" has to
      // stay distinguishable from "a flat lane", or an un-automated groove
      // stops being byte-identical.
      _engine.setAutomation(
        id,
        _autoParam,
        next.isNeutralFor(_autoParam) ? null : next,
      );
    });
    _syncPlayback();
    return true;
  }

  /// Duplicates the track the cursor is on.
  ///
  /// The card asked for Cmd/Ctrl+D here and I first recorded it as undoable,
  /// because I had convinced myself there was no duplicate intent to bind. There
  /// is — `AppIntent.duplicate` has been in the shared vocabulary all along,
  /// already bound to Ctrl+D; @daw-suite pointed it out. Worth the comment
  /// because the wrong conclusion came from a truncated grep, not from the code.
  bool _duplicateCursorTrack() {
    final id = _cursorTrackId;
    if (id == null) return false;
    _duplicateTrack(id);
    return true;
  }

  /// Returns the cell under the cursor to neutral.
  bool _clearCursorCell() {
    final id = _cursorTrackId;
    final step = _cursorStep;
    if (id == null || step == null) return false;
    final lane = _engine.automationFor(id, _autoParam);
    if (lane == null) return true;
    final next = lane.withStep(step, _autoParam.neutral);
    setState(() {
      _engine.setAutomation(
        id,
        _autoParam,
        next.isNeutralFor(_autoParam) ? null : next,
      );
    });
    _syncPlayback();
    return true;
  }

  /// Clears [id]'s lane for the parameter on show.
  void _clearAutomation(String id, [AutomationParam? param]) {
    final p = param ?? _autoParam;
    if (_engine.automationFor(id, p) == null) return;
    setState(() => _engine.setAutomation(id, p, null));
    _syncPlayback();
  }

  /// One 16-step lane per track for the parameter on show: tap a step to cycle
  /// it, hold the track name to clear the lane, switch parameters above.
  Widget _automationRows(AppLocalizations l10n) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final p in AutomationParam.values)
                ChoiceChip(
                  key: Key('loop-auto-param-${p.name}'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: Text(
                    _autoParamLabel(l10n, p),
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: _autoParam == p,
                  onSelected: (_) => _setAutomationParam(p),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final track in _engine.tracks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  GestureDetector(
                    onLongPress: () => _clearAutomation(track.id),
                    child: SizedBox(
                      width: 56,
                      child: Text(
                        _trackLabel(l10n, track.id),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
                  for (var s = 0; s < kPatternSteps; s++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: GestureDetector(
                          key: Key('loop-auto-${track.id}-$s'),
                          onTap: () {
                            // A tap moves the cursor too, so the keyboard
                            // carries on from wherever the finger left off
                            // rather than from some remembered other cell.
                            _cursorTrack = _engine.tracks.indexOf(track);
                            _cursorStep = s;
                            _cycleAutomationStep(track.id, s);
                          },
                          child: SizedBox(
                            height: 18,
                            child: _cursorTrack ==
                                        _engine.tracks.indexOf(track) &&
                                    _cursorStep == s
                                ? DecoratedBox(
                                    // An outline rather than a fill: the cell
                                    // already uses colour to say what its VALUE
                                    // is, and a second colour on top would be
                                    // two meanings in one square.
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: _autoCell(track.id, s),
                                  )
                                : _autoCell(track.id, s),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      );

  /// One lane cell, drawn the way its parameter actually behaves.
  ///
  /// Volume is one-sided, so it is a bar growing from the floor — the shape of
  /// a fader. Pan and tone are two-sided and NOT the same two-sidedness: pan is
  /// a position in space, so its marker slides left and right; tone is an amount
  /// of brightness, so it grows up (thinner) or down (darker) from the middle.
  /// Drawing all three as the same bar would have been less code and would have
  /// made a hard-left pan look like a fade-out.
  Widget _autoCell(String id, int step) {
    final colour = _colorFor(id);
    final lane = _engine.automationFor(id, _autoParam);
    final v = lane == null ? _autoParam.neutral : lane.at(step);
    if (_autoParam == AutomationParam.level) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          // Never zero, or a silenced step would vanish and look untappable.
          heightFactor: v < 0.08 ? 0.08 : v,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(2),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    // A faint full cell under both two-sided drawings, so an untouched step is
    // still visibly a target rather than an empty gap.
    final bed = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(2),
      ),
      child: const SizedBox.expand(),
    );
    if (_autoParam == AutomationParam.pan) {
      return Stack(
        children: [
          Positioned.fill(child: bed),
          Align(
            // −1 = hard left … +1 = hard right, which is where the sound is.
            alignment: Alignment(v * 2 - 1, 0),
            child: FractionallySizedBox(
              widthFactor: 0.34,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      );
    }
    // Tone: a bar growing OUT of the middle — up for thinner, down for darker.
    // A step left alone shows only the bed, which is right: neutral means the
    // filter is doing nothing at all there.
    final amount = ((v - 0.5) * 2).clamp(-1.0, 1.0);
    Widget half(double fill, Alignment from) => Expanded(
          child: fill == 0
              ? const SizedBox.expand()
              : Align(
                  alignment: from,
                  child: FractionallySizedBox(
                    heightFactor: fill < 0.12 ? 0.12 : fill,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colour,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
        );
    return Stack(
      children: [
        Positioned.fill(child: bed),
        Column(
          children: [
            half(amount > 0 ? amount : 0, Alignment.bottomCenter),
            half(amount < 0 ? -amount : 0, Alignment.topCenter),
          ],
        ),
      ],
    );
  }

  /// Swing ladder for one track: follow the groove, then straight, light,
  /// medium, heavy, then back to following.
  ///
  /// The same tap-to-cycle badge as the loop-length control, for the same
  /// reason: you hear the change and the next tap is the undo. `–` means "no
  /// opinion, use the groove's swing", which is where every track starts.
  static const List<double?> _swingLadder = [null, 0.0, 0.2, 0.4, 0.6];

  void _cycleTrackSwing(String id) {
    final own = _engine.hasOwnSwing(id) ? _engine.trackSwing(id) : null;
    var i = _swingLadder.indexWhere((v) => v == own);
    if (i < 0) i = 0;
    setState(() {
      _engine.setTrackSwing(id, _swingLadder[(i + 1) % _swingLadder.length]);
    });
    _syncPlayback();
  }

  /// The id a duplicate was made from: `bass-2` → `bass`, `bass-2-2` → `bass`.
  ///
  /// Copies are not in the colour or label tables, and a `!` on those maps threw
  /// the moment the first copy was drawn. Inheriting from the source is also
  /// what a player expects: a copy of the bass should look like the bass.
  String _sourceIdOf(String id) {
    var base = id;
    while (!_trackColors.containsKey(base)) {
      final cut = base.lastIndexOf('-');
      if (cut <= 0) return id;
      base = base.substring(0, cut);
    }
    return base;
  }

  Color _colorFor(String id) =>
      _trackColors[id] ?? _trackColors[_sourceIdOf(id)] ?? Colors.grey;

  /// Adds a copy of [id] and jumps the user to it.
  /// Removes a duplicate (the base band is refused by the engine).
  void _removeCopy(String id) {
    if (!_engine.removeExtraTrack(id)) return;
    setState(() {});
    _syncPlayback();
  }

  void _duplicateTrack(String id) {
    final copy = _engine.duplicateTrack(id);
    if (copy == null) return;
    setState(() {});
    _syncPlayback();
  }

  /// WS-X1 follow-up — the button that puts this groove in the project.
  ///
  /// `addToProject` shipped with the live link and was reachable only from the
  /// test interface, so no player could ever create the link the rest of the
  /// feature depends on. Hidden entirely when no project is in scope, which is
  /// every test that mounts this screen alone and the games registry: a dead
  /// button that explains itself only by doing nothing is worse than none.
  Widget _projectRow(AppLocalizations l10n) {
    if (_projects == null) return const SizedBox.shrink();
    final linked = hasLiveProjectLink;
    return _inspectorSection(
      l10n.projectBrowser,
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          key: const Key('loop-add-to-project'),
          onPressed: linked ? null : () => _addGrooveToProjectFromUi(l10n),
          icon: Icon(linked ? Icons.link : Icons.playlist_add, size: 18),
          label: Text(
            linked ? l10n.loopMixerInProject : l10n.loopMixerAddToProject,
          ),
        ),
      ),
    );
  }

  void _addGrooveToProjectFromUi(AppLocalizations l10n) {
    if (addToProject() == null) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.loopMixerAddedToProject)),
    );
  }

  /// One chip per track: tap to add a copy of it.
  ///
  /// In the inspector rather than on the track card: that card's row is already
  /// a pixel from overflowing, and adding a delete button for copies tipped it
  /// over by 23px the moment the first copy appeared. Long-press a copy's chip
  /// to remove it, so adding and removing live in the same place.
  Widget _duplicateRow(AppLocalizations l10n) => Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final track in _engine.tracks)
            Tooltip(
              message: l10n.loopMixerDuplicateTrackHint,
              child: GestureDetector(
                onLongPress: _engine.isExtraTrack(track.id)
                    ? () => _removeCopy(track.id)
                    : null,
                child: ActionChip(
                  key: Key('loop-dup-${track.id}'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: CircleAvatar(
                    backgroundColor: _colorFor(track.id),
                    radius: 8,
                  ),
                  label: Text(
                    _trackLabel(l10n, track.id),
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () => _duplicateTrack(track.id),
                ),
              ),
            ),
        ],
      );

  /// Adds a fresh track playing [roleId], and its chip row below.
  void _addRoleTrack(String roleId) {
    if (_engine.addRoleTrack(roleId) == null) return;
    setState(() {});
    _syncPlayback();
  }

  void _addEmptyTrack() {
    _engine.addEmptyTrack();
    setState(() {});
    _syncPlayback();
  }

  /// WS-L10 — brings a recorded loop in from a file as an audio track.
  ///
  /// The audio is fitted to the groove's exact length, which for a take that is
  /// nearly right is inaudible and for one that is not is a speed change. So a
  /// large stretch is REPORTED rather than applied silently: the player can hear
  /// that something happened, and the message tells them it was deliberate and
  /// by how much. Their next move — change the tempo, or the loop's bars — is
  /// then an informed one.
  Future<void> _importAudioTrack() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Audio', extensions: kAudioImportExtensions),
        ],
      );
      if (file == null) return;
      final imported = await importAudioMonoAsync(await file.readAsBytes());
      if (!mounted) return;
      if (imported == null || imported.pcm.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.loopMixerAudioImportFailed)),
        );
        return;
      }
      // Resample to the app's rate FIRST if the file disagrees, so the fit to
      // the loop is a length change only and not a length change tangled up
      // with a rate conversion.
      final atAppRate = imported.sampleRate == kSampleRate
          ? imported.pcm
          : resampleHq(
              imported.pcm,
              fromRate: imported.sampleRate.toDouble(),
              toRate: kSampleRate.toDouble(),
            );
      final id = _engine.addAudioTrack(atAppRate);
      setState(() {});
      _syncPlayback();

      final stretch = _engine.audioStretchOf(id);
      if (!audioFitIsSubtle(stretch)) {
        final percent = ((stretch - 1) * 100).round();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n.loopMixerAudioStretched(
                file.name,
                percent > 0 ? '+$percent' : '$percent',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[LOOP] audio import failed: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.loopMixerAudioImportFailed)),
      );
    }
  }

  /// The five authored roles, then Empty.
  ///
  /// Roles first because the ＋ has to land on something that PLAYS: a blank
  /// page is the one outcome a first tap must not produce. Empty last because
  /// it is the end of the ladder rather than the start of it — but it is there,
  /// which is what stops the band being a fixed roster.
  ///
  /// In the inspector, not on the track card: that card's row is full, and the
  /// one time a control was added to it the row overflowed by 23px and took
  /// fourteen tests with it. Treat that row as full.
  Widget _addTrackRow(AppLocalizations l10n) => Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          // The roles of the style in play, so switching to Chill offers Chill's
          // band rather than the default one's.
          for (final role in grooveStyleById(_engine.styleId).tracks)
            Tooltip(
              message: l10n.loopMixerAddTrackHint,
              child: ActionChip(
                key: Key('loop-add-${role.id}'),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                avatar: CircleAvatar(
                  backgroundColor: _colorFor(role.id),
                  radius: 8,
                ),
                label: Text(
                  _baseTrackLabel(l10n, role.id),
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: () => _addRoleTrack(role.id),
              ),
            ),
          Tooltip(
            message: l10n.loopMixerAddAudioHint,
            child: ActionChip(
              key: const Key('loop-add-audio'),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              avatar: const Icon(Icons.graphic_eq, size: 16),
              label: Text(
                l10n.loopMixerAddAudio,
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: _importAudioTrack,
            ),
          ),
          Tooltip(
            message: l10n.loopMixerAddEmptyHint,
            child: ActionChip(
              key: const Key('loop-add-empty'),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              avatar: const Icon(Icons.add, size: 16),
              label: Text(
                l10n.loopMixerAddEmpty,
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: _addEmptyTrack,
            ),
          ),
        ],
      );

  /// Renames [id], or clears the name back to the app's own with a blank entry.
  Future<void> _renameTrack(String id) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: _engine.trackName(id) ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.loopMixerRenameTrack),
        content: TextField(
          key: const Key('loop-rename-field'),
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(hintText: l10n.loopMixerRenameHint),
          onSubmitted: (v) => Navigator.pop(dialog, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(l10n.loopMixerCancel),
          ),
          TextButton(
            key: const Key('loop-rename-ok'),
            onPressed: () => Navigator.pop(dialog, controller.text),
            child: Text(l10n.loopMixerSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || name == null) return;
    setState(() => _engine.setTrackName(id, name));
  }

  /// One chip per ADDED track: tap to rename it.
  ///
  /// Hidden while there are none, like the session grid: the base band is
  /// already named in the player's own language, and a rename row over five
  /// tracks that do not need it is noise. "Track 2" is what makes this
  /// necessary, so it appears exactly when a track called that exists.
  Widget _renameRow(AppLocalizations l10n) {
    final added = [
      for (final t in _engine.tracks)
        if (_engine.isExtraTrack(t.id)) t,
    ];
    if (added.isEmpty) return const SizedBox.shrink();
    return _inspectorSection(
      l10n.loopMixerRenameTrack,
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final track in added)
            Tooltip(
              message: l10n.loopMixerRenameTrackHint,
              child: ActionChip(
                key: Key('loop-rename-${track.id}'),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                avatar: CircleAvatar(
                  backgroundColor: _colorFor(track.id),
                  radius: 8,
                ),
                label: Text(
                  _trackLabel(l10n, track.id),
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: () => _renameTrack(track.id),
              ),
            ),
        ],
      ),
    );
  }

  /// Tone ladder for one track: off, darker, darkest, thinner, thinnest, off.
  ///
  /// The same tap-to-cycle badge as swing and loop length, for the same reason:
  /// you hear the change and the next tap is the way back. A slider per track
  /// would need a row each and would not fit beside the lane strip.
  static const List<double> _trackFilterLadder = [0, -0.5, -0.9, 0.5, 0.9];

  void _cycleTrackFilter(String id) {
    final current = _engine.trackFilter(id);
    var i = _trackFilterLadder.indexWhere((v) => (v - current).abs() < 1e-6);
    if (i < 0) i = 0;
    setState(() {
      _engine.setTrackFilter(
        id,
        _trackFilterLadder[(i + 1) % _trackFilterLadder.length],
      );
    });
    _syncPlayback();
  }

  /// One badge per track: its tone, `–` when it is left alone, or `~` when the
  /// lane below is driving it — the lane REPLACES this knob, and a badge still
  /// reading `-9` under a lane that ignores it would be a lie.
  Widget _trackFilterRow(AppLocalizations l10n) => Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final track in _engine.tracks)
            Tooltip(
              message: '${_trackLabel(l10n, track.id)} · '
                  '${l10n.loopMixerTrackFilterHint}',
              child: GestureDetector(
                key: Key('loop-filter-${track.id}'),
                onTap: () => _cycleTrackFilter(track.id),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: CircleAvatar(
                    backgroundColor: _colorFor(track.id),
                    radius: 8,
                  ),
                  label: Text(
                    _engine.automationFor(track.id, AutomationParam.filter) !=
                            null
                        ? '~'
                        : _engine.trackFilter(track.id) == 0
                            ? '–'
                            : (_engine.trackFilter(track.id) * 10)
                                .round()
                                .toString(),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      );

  /// WS-L5 — puts one track's pattern onto another.
  ///
  /// Two taps: the track you want to copy FROM, then the track to put it on.
  /// A one-tap version would need a selection concept the Loop Studio does not
  /// have (its cards are toggles, not selections), and a drag would need a drop
  /// target on a row that is already full.
  ///
  /// Only compatible destinations are offered, so the meaningless pairings —
  /// a drum grid onto a melody, a pattern onto a recording — cannot be reached
  /// rather than being reachable and then refused.
  Future<void> _copyPatternFrom(String from) async {
    final l10n = AppLocalizations.of(context)!;
    final targets = _engine.copyTargetsFor(from);
    if (targets.isEmpty) return;
    final to = await showDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: Text(l10n.loopMixerCopyPatternTo(_trackLabel(l10n, from))),
        children: [
          for (final id in targets)
            SimpleDialogOption(
              key: Key('loop-copy-to-$id'),
              onPressed: () => Navigator.pop(dialog, id),
              child: Row(
                children: [
                  CircleAvatar(backgroundColor: _colorFor(id), radius: 8),
                  const SizedBox(width: 8),
                  Text(_trackLabel(l10n, id)),
                ],
              ),
            ),
        ],
      ),
    );
    if (!mounted || to == null) return;
    if (!_engine.copyPattern(from, to)) return;
    setState(() {});
    _syncPlayback();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.loopMixerCopiedPattern(
            _trackLabel(l10n, from),
            _trackLabel(l10n, to),
          ),
        ),
      ),
    );
  }

  /// One chip per track that HAS a pattern to give away.
  ///
  /// Hidden entirely when nothing can be copied anywhere, like the rename row:
  /// a band of one track has no destinations, and a row of dead chips teaches
  /// the wrong thing.
  Widget _copyPatternRow(AppLocalizations l10n) {
    final sources = [
      for (final t in _engine.tracks)
        if (_engine.copyTargetsFor(t.id).isNotEmpty) t,
    ];
    if (sources.isEmpty) return const SizedBox.shrink();
    return _inspectorSection(
      l10n.loopMixerCopyPattern,
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final track in sources)
            Tooltip(
              message: l10n.loopMixerCopyPatternHint,
              child: ActionChip(
                key: Key('loop-copy-${track.id}'),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                avatar: CircleAvatar(
                  backgroundColor: _colorFor(track.id),
                  radius: 8,
                ),
                label: Text(
                  _trackLabel(l10n, track.id),
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: () => _copyPatternFrom(track.id),
              ),
            ),
        ],
      ),
    );
  }

  /// One badge per track: its own swing, or `–` when it follows the groove.
  Widget _trackSwingRow(AppLocalizations l10n) => Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final track in _engine.tracks)
            Tooltip(
              message: '${_trackLabel(l10n, track.id)} · '
                  '${l10n.loopMixerSwingPerTrackHint}',
              child: GestureDetector(
                key: Key('loop-swing-${track.id}'),
                onTap: () => _cycleTrackSwing(track.id),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: CircleAvatar(
                    backgroundColor: _colorFor(track.id),
                    radius: 8,
                  ),
                  label: Text(
                    _engine.hasOwnSwing(track.id)
                        ? (_engine.trackSwing(track.id) * 10).round().toString()
                        : '–',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      );

  bool _sceneHasTrack(int i, String id) =>
      _scenes[i]?.enabled.contains(id) ?? false;

  /// Turns [id] on or off inside section [i] — editing the section itself
  /// rather than the live mix.
  ///
  /// If that section is the one playing, the change is applied immediately so
  /// you hear it; otherwise it waits there until the section is launched.
  void _toggleSceneTrack(int i, String id) {
    final scene = _scenes[i];
    if (scene == null) return;
    final next = {...scene.enabled};
    if (!next.remove(id)) next.add(id);
    setState(() {
      _scenes[i] = GrooveScene(next, {...scene.variants});
      if (_chainIndex == i) {
        _discardSolo();
        _engine.applyScene(_scenes[i]!);
      }
    });
    if (_chainIndex == i) _syncPlayback();
  }

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
                    // Armed for the next seam — the same amber the track cards
                    // use, so "waiting for the beat" reads the same everywhere.
                    border: _pendingScene == i
                        ? Border.all(color: Colors.amber, width: 3)
                        : null,
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
      // WS-T3 — Loop Studio had NO keyboard support at all, not even
      // space-to-play. Hosting the shared table is what gives it one, and a
      // rebinding made in the Tracker applies here without this screen knowing
      // anything about bindings.
      body: Focus(
        // Explicit node: disposable with the screen, and claimable by a test
        // (autofocus loses to the route's focus scope in the test binding).
        focusNode: _keyFocus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
                child: _actionBar(l10n),
              ),
              const Divider(height: 1),
              Expanded(child: _mixerLayout(l10n)),
            ],
          ),
        ),
      ),
    );
  }

  /// WS-T3 — Loop Studio's first keyboard support, resolved through the shared
  /// table rather than its own `if` ladder. It handles the subset in
  /// [kLoopIntents]; everything else falls through.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final intent = _keymap.keymap.intentFor(
      chordOf(event.logicalKey, HardwareKeyboard.instance),
    );
    switch (intent) {
      case AppIntent.transportToggle:
        _pauseOrResume();
        return KeyEventResult.handled;
      case AppIntent.transportStop:
        _stopAll();
        return KeyEventResult.handled;
      case AppIntent.editUndo:
        if (_canUndo) {
          _undoEdit();
          return KeyEventResult.handled;
        }
      case AppIntent.editRedo:
        if (_canRedo) {
          _redoEdit();
          return KeyEventResult.handled;
        }
      // WS-L1 — the lane cursor.
      case AppIntent.cursorUp:
        return _handled(_moveCursor(-1, 0));
      case AppIntent.cursorDown:
        return _handled(_moveCursor(1, 0));
      case AppIntent.cursorLeft:
        return _handled(_moveCursor(0, -1));
      case AppIntent.cursorRight:
        return _handled(_moveCursor(0, 1));
      case AppIntent.editDelete:
        return _handled(_clearCursorCell());
      case AppIntent.duplicate:
        return _handled(_duplicateCursorTrack());
      default:
        break;
    }
    // Digits type a value straight into the cell under the cursor. Not routed
    // through an intent: ten digits would be ten bindings for one idea, and
    // every tracker has spelled velocities this way for thirty years.
    final digit = _digitOf(event.logicalKey);
    if (digit != null && _cursorStep != null) {
      return _handled(_typeAutomationDigit(digit));
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handled(bool ok) =>
      ok ? KeyEventResult.handled : KeyEventResult.ignored;

  /// 0–9 from either the number row or the numeric keypad, else null.
  static int? _digitOf(LogicalKeyboardKey key) {
    const row = [
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    const pad = [
      LogicalKeyboardKey.numpad0,
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad9,
    ];
    final i = row.indexOf(key);
    if (i >= 0) return i;
    final p = pad.indexOf(key);
    return p >= 0 ? p : null;
  }

  /// WS-T3 — the shared bindings, loaded once so a rebinding persists.
  final KeymapService _keymap = KeymapService()..load();
  final FocusNode _keyFocus = FocusNode(debugLabel: 'loopKeys');

  /// The area below the action bar: the track-lane content, with the "Sound &
  /// Feel" inspector docked on the right on wide screens (inline on narrow).
  Widget _mixerLayout(AppLocalizations l10n) {
    return LayoutBuilder(
      builder: (context, c) {
        final docked =
            !widget.simpleLayout && _showInspector && c.maxWidth >= 760;
        final main = SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: _mainChildren(
              l10n,
              inlineInspector:
                  !widget.simpleLayout && _showInspector && !docked,
            ),
          ),
        );
        if (docked) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: main), _soundInspectorPanel(l10n)],
          );
        }
        return main;
      },
    );
  }

  /// The inline "Sound & Feel" card (narrow screens): the same inspector content
  /// as a bordered panel above the track lane.
  Widget _inspectorCard(AppLocalizations l10n) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _soundInspectorContent(l10n),
        ),
      );

  /// The main content column (below the action bar): prompt + playhead, the
  /// optional editors/jam/score panels, the track lane, capture row, smear pad,
  /// and the challenge nudge. The song settings + transport live in the
  /// inspector / action bar, not here.
  List<Widget> _mainChildren(
    AppLocalizations l10n, {
    required bool inlineInspector,
  }) {
    return [
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
                  const Icon(Icons.star, size: 16, color: Colors.amber),
                  Text(
                    '${_foundCombos.length}/${kLoopCombos.length}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
        ],
      ),
      if (inlineInspector) ...[
        const SizedBox(height: 8),
        _inspectorCard(l10n),
      ],
      // Jam feedback: the live note, coloured by how it fits the sounding chord.
      if (_jamming) _jamFeedback(l10n),
      // Live engraving of every enabled track as its own small staff.
      if (_showScore) _buildScorePanel(l10n),
      if (_showBeatEdit) _buildBeatEditor(l10n),
      if (_showTuneEdit) _buildTuneEditor(l10n),
      const SizedBox(height: 8),
      // LM-UX1: stacked on narrow, side-by-side panels on wide.
      _trackLane(l10n),
      const SizedBox(height: 6),
      // Capture row: sing a melody / beatbox a beat — the capture joins as a card.
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
      // §F-1 solo pad: drag to improvise an in-key lead, then Keep it as a layer.
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
                    minor: _engine.scale == GrooveScale.minorPentatonic,
                    onNote: _playSmearNote,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _smearSamples.isEmpty ? null : _keepSmear,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.loopMixerSoloKeep),
                ),
              ],
            ),
          ),
        ),
      // A gentle band challenge (no score) to nudge exploration.
      if (!widget.simpleLayout) _challengeBanner(l10n),
    ];
  }

  /// Jam feedback: the live note coloured by chord fit (green=chord, amber=scale,
  /// red=out), the mic-honesty note, and the follow-the-melody accuracy meter.
  Widget _jamFeedback(AppLocalizations l10n) {
    return ValueListenableBuilder<PitchReading?>(
      valueListenable: _jamReading,
      builder: (context, reading, _) {
        final hasNote = reading?.hasPitch ?? false;
        final fit = hasNote
            ? _engine.jamFit(reading!.nearestMidi, bar: _currentBar)
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
              Text(
                usesAecJam
                    ? l10n.loopMixerJamGraded
                    : l10n.loopMixerJamHeadphones,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              if (isFollowing)
                ValueListenableBuilder<double>(
                  valueListenable: _followAccuracy,
                  builder: (context, acc, _) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l10n.loopMixerFollowScore((acc * 100).round()),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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
    required this.steps,
    required this.onCycleSteps,
    required this.stepsTooltip,
    required this.onRollVariant,
    required this.onLevel,
    required this.onSolo,
    required this.soloed,
    this.onVoice,
    this.voiced = false,
    this.onDelete,
    this.deleteTooltip,
    this.pan = 0.0,
    this.onPan,
    this.panLabel,
    this.onEdit,
    this.editTooltip,
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

  /// This track's loop length in eighth-steps ([kPatternSteps] = the full grid).
  final int steps;
  final VoidCallback onCycleSteps;
  final String stepsTooltip;
  final VoidCallback onRollVariant;
  final ValueChanged<double> onLevel;
  final VoidCallback onSolo;
  final bool soloed;

  /// Long-press a pitched track to voice it with a saved "My Instruments"
  /// sound (null for unpitched tracks — drums have no notes to voice).
  final VoidCallback? onVoice;

  /// Whether this track currently plays through a saved instrument.
  final bool voiced;

  /// Removes this track (captured sung/beatboxed layers only; null for the
  /// built-in band cards, which are the fixed groove).
  final VoidCallback? onDelete;
  final String? deleteTooltip;

  /// Stereo pan −1 (left) … 0 (centre) … +1 (right), and its setter. Null
  /// `onPan` hides the pan control.
  final double pan;
  final ValueChanged<double>? onPan;
  final String? panLabel;

  /// Opens this track's event editor (beat/tune grid). Null for tracks with no
  /// editable events.
  final VoidCallback? onEdit;
  final String? editTooltip;

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
                // 8, not 12. This row's own comment below already noted it was
                // "within a pixel of overflowing on a narrow card", and a later
                // badge pushed it 5.5 px over — which fails `live_flow_test`'s
                // registry smoke, so `main` was red for everyone. Narrowing the
                // two gutters flanking the label buys 8 px, which clears it.
                //
                // It is a stopgap by someone who does not own this screen: the
                // row now has ~2.5 px of headroom, so the NEXT badge breaks it
                // again. The real fix is a reflow (wrap the badge cluster, or
                // drop badges below a width threshold as `compact` already
                // does) and that is a design call for whoever owns the card —
                // please override this.
                const SizedBox(width: 8),
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
                const SizedBox(width: 8),
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
                // Loop length. Shown only when this track is SHORTER than the
                // others: at full length it is the default everybody already
                // has, and a badge reading "16" on every card would be noise.
                // The control stays reachable either way — the tap target is
                // the variant badge's neighbour, and a child who shortens one
                // track can tap it back.
                // Deliberately smaller than the variant badge and with a
                // tighter gutter: this row was already within a pixel of
                // overflowing on a narrow card, and a 1px RenderFlex overflow
                // is a test failure, not a cosmetic one. Full length draws a
                // dimmed ∞ so the control is still discoverable without
                // shouting on every card.
                if (!compact) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: stepsTooltip,
                    child: GestureDetector(
                      key: Key('loop-steps-$label'),
                      onTap: onCycleSteps,
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: foreground.withValues(
                          alpha: steps == kPatternSteps ? 0.10 : 0.22,
                        ),
                        child: Text(
                          steps == kPatternSteps ? '∞' : '$steps',
                          style: TextStyle(
                            color: foreground,
                            fontWeight: FontWeight.bold,
                            fontSize: steps == kPatternSteps ? 12 : 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                // A small keyboard glyph marks a track voiced by a saved
                // instrument (long-press to change / reset).
                if (voiced) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.piano, size: 18, color: foreground),
                ],
                if (!compact && onEdit != null) _editButton(foreground),
                if (!compact) _soloButton(foreground),
                if (!compact && onDelete != null) _deleteButton(foreground),
              ],
            ),
            if (compact)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onEdit != null) _editButton(foreground),
                  _soloButton(foreground),
                  if (onDelete != null) _deleteButton(foreground),
                ],
              ),
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
            // Per-card stereo pan (L … C … R). Double-tap the slider to recentre.
            if (active && onPan != null)
              SizedBox(
                width: 220,
                child: Row(
                  children: [
                    Text(
                      'L',
                      style: TextStyle(color: foreground, fontSize: 11),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onDoubleTap: () => onPan!(0),
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            activeTrackColor: foreground.withValues(alpha: 0.5),
                            inactiveTrackColor:
                                foreground.withValues(alpha: 0.5),
                            thumbColor: foreground,
                            overlayShape: SliderComponentShape.noOverlay,
                          ),
                          child: Slider(
                            value: pan.clamp(-1.0, 1.0),
                            min: -1,
                            label: panLabel,
                            onChanged: onPan,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      'R',
                      style: TextStyle(color: foreground, fontSize: 11),
                    ),
                  ],
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

  Widget _deleteButton(Color foreground) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: IconButton(
          tooltip: deleteTooltip,
          onPressed: onDelete,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(Icons.delete_outline, size: 18, color: foreground),
        ),
      );

  Widget _editButton(Color foreground) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: IconButton(
          tooltip: editTooltip,
          onPressed: onEdit,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(Icons.edit_note, size: 20, color: foreground),
        ),
      );
}
