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
// (sample-accurate sync for free) played on a dedicated LoopPlayerService.
// The screen owns the musical clock (a Stopwatch); user changes swap the
// fresh mix at the clock's phase (`play(position: …)`), so layers and feel
// change without the bar ever restarting. Seam-timed changes (the fill) are
// applied when the ticker sees the phase wrap: the new WAV starts near
// position 0 on the downbeat, where the kick masks the swap. A Ticker
// (created in initState — never a lazy `late final`, see CLAUDE.md) drives
// the step playhead and the wrap detection.

import 'dart:async';

import 'package:crisp_notation/crisp_notation.dart' show Clef, StaffView;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:klang_universum/core/audio/groove_capture.dart';
import 'package:klang_universum/core/audio/loop_engine.dart';
import 'package:klang_universum/core/audio/microphone_pitch_service.dart';
import 'package:klang_universum/core/audio/pitch_analysis.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/loop_player_service.dart';
import 'package:klang_universum/features/games/composition/groove_notation.dart';
import 'package:klang_universum/features/games/widgets/game_app_bar.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/score_theme.dart';
import 'package:provider/provider.dart';

class LoopMixerScreen extends StatefulWidget {
  const LoopMixerScreen({super.key});

  /// The tempo presets (all keep the step grid integral — see LoopTiming).
  static const tempos = [75, 100, 120];

  /// Every 4th loop plays the drum fill.
  static const fillEvery = 4;

  @override
  State<LoopMixerScreen> createState() => _LoopMixerScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class LoopMixerTester {
  Set<String> get enabledTracks;
  bool get isPlaying;
  int get tempoBpm;
  double get swing;
  String? get progressionId;
  int get loopIteration;
  int variantOf(String id);
  double levelOf(String id);
  void toggleTrack(String id);
  void cycleTrackVariant(String id);
  void setTrackLevel(String id, double level);
  void setSwing(double value);
  void setTempo(int bpm);
  void setProgression(String? id);
  void stopAll();
  bool get scoreVisible;
  void toggleScorePanel();
  String get grooveToken;
  bool loadGrooveToken(String token);
  bool get isInfinite;
  void toggleInfinite();
  bool get hasVoiceTrack;

  /// Installs a sung layer without the mic (headless tests can't record).
  void debugCaptureCells(List<PatternCell> cells);

  /// Forces the seam handler (normally driven by the real-time clock, which
  /// widget tests can't advance) — asserts fill scheduling without waiting.
  void debugLoopWrap();
}

class _LoopMixerScreenState extends State<LoopMixerScreen>
    with SingleTickerProviderStateMixin
    implements LoopMixerTester {
  final _engine = LoopEngine();
  final _loop = LoopPlayerService();

  /// The groove's musical clock: playback phase is derived from it, never
  /// from the player, so swaps can re-enter the loop in phase.
  final _clock = Stopwatch();

  late final Ticker _ticker;
  final _step = ValueNotifier<int>(-1);

  int _iteration = 0;
  int _lastPhaseMs = 0;

  /// What the loop player is currently looping (identity-compared against
  /// the engine's cached renders to decide whether a seam swap is needed).
  Uint8List? _currentWav;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (!_clock.isRunning) {
        _step.value = -1;
        return;
      }
      final t = _engine.timing;
      final phase = _clock.elapsedMilliseconds % t.totalMs;
      if (phase < _lastPhaseMs) _onLoopWrap();
      _lastPhaseMs = phase;
      _step.value = phase ~/ t.beatMs;
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _step.dispose();
    _loop.dispose();
    _countInTimer?.cancel();
    _captureStopTimer?.cancel();
    _micSub?.cancel();
    _mic?.dispose();
    super.dispose();
  }

  // --- LoopMixerTester ---
  @override
  Set<String> get enabledTracks => Set.unmodifiable(_engine.enabled);
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
  void cycleTrackVariant(String id) => _cycleVariant(id);
  @override
  void setTrackLevel(String id, double level) => _setLevel(id, level);
  @override
  void setSwing(double value) => _setSwing(value);
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
  void stopAll() => _stopAll();
  @override
  void debugLoopWrap() => _onLoopWrap();
  @override
  bool get scoreVisible => _showScore;
  @override
  void toggleScorePanel() => setState(() => _showScore = !_showScore);

  bool _showScore = false;
  bool _infinite = false;

  @override
  bool get isInfinite => _infinite;
  @override
  void toggleInfinite() => setState(() => _infinite = !_infinite);

  // --- Sing a track: count-in → record 2 bars → quantize → a voice card ---

  MicrophonePitchService? _mic;
  StreamSubscription<PitchReading>? _micSub;
  final _captureClock = Stopwatch();
  final List<PitchSample> _samples = [];
  Timer? _countInTimer;
  Timer? _captureStopTimer;
  _CapturePhase _capturePhase = _CapturePhase.idle;
  int _countdown = 0;

  @override
  bool get hasVoiceTrack =>
      _engine.tracks.any((t) => t.id == LoopEngine.userTrackId);

  @override
  void debugCaptureCells(List<PatternCell> cells) {
    setState(() {
      _engine.setUserTrack(cells);
      _engine.enabled.add(LoopEngine.userTrackId);
    });
    _restartGroove();
  }

  /// The capture always spans 2 straight bars at the current tempo (what a
  /// non-follower track tiles from), regardless of progression or swing.
  int get _captureMs => LoopTiming(tempoBpm: _engine.tempoBpm).totalMs;

  Future<void> _startSingFlow() async {
    if (_capturePhase != _CapturePhase.idle) return;
    // Silence the band while the mic listens — the detector is monophonic
    // and would transcribe the loop playback instead of the singer.
    unawaited(_loop.stop());
    _clock.stop();
    final audio = context.read<AudioService>();
    setState(() {
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
    _samples.clear();
    final mic = _mic ??= MicrophonePitchService();
    try {
      _micSub = mic.readings.listen((reading) {
        final sample = (
          _captureClock.elapsedMilliseconds.toDouble(),
          reading.hasPitch ? reading.nearestMidi : null,
        );
        _samples.add(sample);
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
    final cells = quantizeToGroove(_samples, totalMs: _captureMs);
    setState(() {
      _capturePhase = _CapturePhase.idle;
      if (cells != null) {
        _engine.setUserTrack(
          cells,
          instrument: context.read<AudioService>().instrument,
        );
        _engine.enabled.add(LoopEngine.userTrackId);
      }
    });
    if (cells == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.loopMixerSingNothing)),
      );
    }
    _restartGroove();
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
              leading: const Icon(Icons.download),
              title: Text(l10n.loopMixerSaveAudio),
              enabled: _engine.enabled.isNotEmpty,
              onTap: () => Navigator.pop(sheet, 'wav'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: grooveToken));
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.loopMixerCodeCopied)),
        );
      case 'paste':
        await _promptForToken();
      case 'wav':
        await _saveWav();
      default:
        break;
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
      final wav = _engine.renderLoop();
      final location = await getSaveLocation(
        suggestedName: 'groove.wav',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'WAV', extensions: ['wav']),
        ],
      );
      if (location == null || !mounted) return; // cancelled
      await XFile.fromData(wav, mimeType: 'audio/wav', name: 'groove.wav')
          .saveTo(location.path);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.workshopSavedTo(location.path))),
      );
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

  bool get _fillDue =>
      _engine.enabled.contains('drums') &&
      _iteration % LoopMixerScreen.fillEvery == LoopMixerScreen.fillEvery - 1;

  /// Loop seam: advance the iteration counter and, if the groove for the new
  /// iteration differs (fill in / fill out), swap it in near position 0 —
  /// the downbeat kick masks the restart.
  void _onLoopWrap() {
    _iteration++;
    if (_engine.enabled.isEmpty || !_clock.isRunning) return;
    // Infinite mode re-renders a seeded variation every loop; otherwise the
    // cached render only changes when the fill schedules in or out.
    final wanted = _infinite
        ? _engine.renderVariedLoop(_iteration, fill: _fillDue)
        : _engine.renderLoop(fill: _fillDue);
    if (identical(wanted, _currentWav)) return;
    _currentWav = wanted;
    _loop.playLoop(
      wanted,
      position: Duration(
        milliseconds: _clock.elapsedMilliseconds % _engine.timing.totalMs,
      ),
    );
  }

  void _toggle(String id) {
    setState(() => _engine.toggle(id));
    _syncPlayback();
  }

  void _cycleVariant(String id) {
    setState(() => _engine.cycleVariant(id));
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

  void _setTempo(int bpm) {
    if (bpm == _engine.tempoBpm) return;
    setState(() => _engine.tempoBpm = bpm);
    _restartGroove();
  }

  void _setProgression(Progression? progression) {
    if (progression?.id == _engine.progression?.id) return;
    setState(() => _engine.progression = progression);
    _restartGroove();
  }

  /// A new grid (tempo or bar count changed) — restart from the top.
  void _restartGroove() {
    _clock
      ..stop()
      ..reset();
    _lastPhaseMs = 0;
    _iteration = 0;
    _syncPlayback();
  }

  void _stopAll() {
    setState(_engine.enabled.clear);
    _syncPlayback();
  }

  /// Restarts/stops/swaps the looping mix to match the groove state, keeping
  /// the musical phase: the new mix starts exactly where the clock says the
  /// groove is, so the beat never resets when something changes.
  void _syncPlayback() {
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
    if (!_clock.isRunning) {
      _clock
        ..reset()
        ..start();
      _lastPhaseMs = 0;
    }
    _currentWav = wav;
    _loop.playLoop(
      wav,
      position: Duration(
        milliseconds: _clock.elapsedMilliseconds % _engine.timing.totalMs,
      ),
    );
  }

  static const _trackIcons = <String, IconData>{
    'drums': Icons.album,
    'bass': Icons.speaker,
    'chords': Icons.piano,
    'melody': Icons.music_note,
    'sparkle': Icons.auto_awesome,
    'voice': Icons.mic,
  };

  // One stable colour per card (the drums are unpitched, so a warm brown
  // instead of a pitch-class colour).
  static const _trackColors = <String, Color>{
    'drums': Color(0xFF795548),
    'bass': Color(0xFFE53935), // C red — the bass grounds the key
    'chords': Color(0xFF00ACC1), // G cyan
    'melody': Color(0xFFF9A825), // E amber
    'sparkle': Color(0xFF3949AB), // A indigo
    'voice': Color(0xFF8E24AA), // B purple — the singer's own layer
  };

  String _trackLabel(AppLocalizations l10n, String id) => switch (id) {
        'drums' => l10n.loopMixerTrackDrums,
        'bass' => l10n.loopMixerTrackBass,
        'chords' => l10n.loopMixerTrackChords,
        'melody' => l10n.loopMixerTrackMelody,
        'voice' => l10n.loopMixerTrackVoice,
        _ => l10n.loopMixerTrackSparkle,
      };

  String _tempoLabel(AppLocalizations l10n, int bpm) => switch (bpm) {
        75 => l10n.loopMixerTempoChill,
        120 => l10n.loopMixerTempoFast,
        _ => l10n.loopMixerTempoGroove,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameLoopMixer),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                  // The playhead scales down before anything can overflow.
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _Playhead(
                        beat: _step,
                        beats: _engine.timing.bars * LoopTiming.beatsPerBar,
                      ),
                    ),
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
                    icon: const Icon(Icons.ios_share),
                    tooltip: l10n.loopMixerShare,
                    onPressed: _openShareSheet,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              // Live engraving: the leading enabled track as a real score.
              if (_showScore && _engravedTrackId != null)
                SizedBox(
                  height: 96,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: StaffView(
                          score: grooveScore(
                            _engine.cellsFor(_engravedTrackId!)!,
                            clef: _engravedTrackId == 'bass'
                                ? Clef.bass
                                : Clef.treble,
                          ),
                          staffSpace: 8,
                          theme: kidsScoreTheme,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: Column(
                  children: [
                    for (final track in _engine.tracks)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: _TrackCard(
                            color: _trackColors[track.id]!,
                            icon: _trackIcons[track.id]!,
                            label: _trackLabel(l10n, track.id),
                            active: _engine.enabled.contains(track.id),
                            variant: _engine.variants[track.id] ?? 0,
                            variantCount: track.variants.length,
                            level: _engine.levels[track.id] ?? 1.0,
                            onTap: () => _toggle(track.id),
                            onCycleVariant: () => _cycleVariant(track.id),
                            onLevel: (v) => _setLevel(track.id, v),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // Sing a track: count-in, record 2 bars, join the band.
              SizedBox(
                height: 34,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(34),
                    foregroundColor: _capturePhase == _CapturePhase.recording
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                  onPressed: _capturePhase == _CapturePhase.idle
                      ? _startSingFlow
                      : null,
                  icon: Icon(
                    _capturePhase == _CapturePhase.recording
                        ? Icons.fiber_manual_record
                        : Icons.mic,
                    size: 18,
                  ),
                  label: Text(
                    switch (_capturePhase) {
                      _CapturePhase.idle => hasVoiceTrack
                          ? l10n.loopMixerSingAgain
                          : l10n.loopMixerSing,
                      _CapturePhase.countIn => '$_countdown…',
                      _CapturePhase.recording => l10n.loopMixerSingNow,
                    },
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // The harmony lane: free vamp, or a 4-chord song progression.
              Row(
                children: [
                  Text(
                    l10n.loopMixerHarmony,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
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
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    l10n.loopMixerSwing,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Expanded(
                    child: Slider(
                      value: _engine.swing,
                      max: 0.6,
                      onChanged: _setSwing,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final bpm in LoopMixerScreen.tempos)
                          ChoiceChip(
                            label: Text(_tempoLabel(l10n, bpm)),
                            selected: _engine.tempoBpm == bpm,
                            onSelected: (_) => _setTempo(bpm),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
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
    );
  }
}

enum _CapturePhase { idle, countIn, recording }

/// A row of beat dots (grouped per bar) with the sounding beat lit. Only
/// this leaf listens to the ticker's beat notifier, so the per-frame update
/// never rebuilds the cards.
class _Playhead extends StatelessWidget {
  const _Playhead({required this.beat, required this.beats});

  final ValueListenable<int> beat;
  final int beats;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.primary;
    return ValueListenableBuilder<int>(
      valueListenable: beat,
      builder: (context, current, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < beats; i++)
            Container(
              width: 12,
              height: 12,
              margin: EdgeInsets.only(
                left: i == 0 ? 0 : (i % LoopTiming.beatsPerBar == 0 ? 12 : 5),
              ),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == current
                    ? base
                    : base.withValues(
                        alpha: i % LoopTiming.beatsPerBar == 0 ? 0.3 : 0.14,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.color,
    required this.icon,
    required this.label,
    required this.active,
    required this.variant,
    required this.variantCount,
    required this.level,
    required this.onTap,
    required this.onCycleVariant,
    required this.onLevel,
  });

  final Color color;
  final IconData icon;
  final String label;
  final bool active;
  final int variant;
  final int variantCount;
  final double level;
  final VoidCallback onTap;
  final VoidCallback onCycleVariant;
  final ValueChanged<double> onLevel;

  @override
  Widget build(BuildContext context) {
    final foreground = active ? Colors.white : color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: active ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? color : color.withValues(alpha: 0.4),
            width: active ? 3 : 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: foreground, size: 26),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 12),
                // The pattern-variant badge: tap to cycle A → B → C.
                if (variantCount > 1)
                  GestureDetector(
                    onTap: onCycleVariant,
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
          ],
        ),
      ),
    );
  }
}
