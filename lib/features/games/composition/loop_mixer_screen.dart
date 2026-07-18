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
import 'dart:convert';

import 'package:comet_beat/core/audio/aec_capability.dart';
import 'package:comet_beat/core/audio/aec_engine.dart';
import 'package:comet_beat/core/audio/beat_capture.dart';
import 'package:comet_beat/core/audio/groove_capture.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/loop_reference.dart';
import 'package:comet_beat/core/audio/microphone_pitch_service.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/play_along.dart';
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/loop_player_service.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:comet_beat/features/games/composition/groove_notation.dart';
import 'package:comet_beat/features/games/composition/groove_play_along.dart';
import 'package:comet_beat/features/games/composition/multipart_to_tracker.dart';
import 'package:comet_beat/features/games/composition/score_analysis_view.dart'
    show harmonicFunctionColor;
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/music_export.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show Clef, HarmonicFunction, StaffView, multiPartToMusicXml;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

class LoopMixerScreen extends StatefulWidget {
  const LoopMixerScreen({super.key, this.aecFactory, this.initialSpec});

  /// An optional groove to open with — lets another Workshop mode hand a
  /// [GrooveSpec] over (e.g. a tracker pattern → a groove). Null = the default
  /// starter groove.
  final GrooveSpec? initialSpec;

  /// Builds the native Tier-3b [AecEngine] for graded jam mode, or returns null
  /// when the platform has no full-duplex plugin (web / not built) — then jam
  /// falls back to the platform `echoCancel`. Defaults to [createNativeAecEngine];
  /// tests inject a fake engine to drive the graded path headlessly.
  @visibleForTesting
  final AecEngine? Function()? aecFactory;

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

  /// The master send effect on the whole mix, and a setter.
  LoopSend get send;
  void setSend(LoopSend value);
  void stopAll();
  bool get scoreVisible;
  void toggleScorePanel();
  String get grooveToken;
  bool loadGrooveToken(String token);
  bool get isInfinite;
  void toggleInfinite();
  bool get hasVoiceTrack;
  bool get hasBeatTrack;
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

  /// Installs a sung layer without the mic (headless tests can't record).
  void debugCaptureCells(List<PatternCell> cells);

  /// Installs a beatboxed layer without the mic.
  void debugCaptureBeat(DrumRowsPattern pattern);

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
    if (widget.initialSpec != null) _engine.applySpec(widget.initialSpec!);
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
  LoopSend get send => _engine.send;
  @override
  void setSend(LoopSend value) => _setSend(value);
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
    final cells = _engine.cellsFor(id);
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
    // AEC jam owns audio via the reference pump: queue the new loop for the
    // scheduler's next seam instead of restarting the (stopped) loop player.
    if (_jamAec != null) {
      _refScheduler?.swap(_pcmOf(wanted));
      return;
    }
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

  void _setSend(LoopSend value) {
    if (value == _engine.send) return;
    setState(() => _engine.send = value);
    _syncPlayback();
  }

  void _setTempo(int bpm) {
    if (bpm == _engine.tempoBpm) return;
    setState(() => _engine.tempoBpm = bpm);
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

  /// A new grid (tempo or bar count changed) — restart from the top.
  void _restartGroove() {
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
    setState(_engine.enabled.clear);
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
    'beat': Icons.graphic_eq,
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
                    icon: Icon(
                      Icons.surround_sound,
                      color: send != LoopSend.none
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    isSelected: send != LoopSend.none,
                    tooltip: l10n.loopMixerSend,
                    onPressed: () => setSend(
                      LoopSend
                          .values[(send.index + 1) % LoopSend.values.length],
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
              // AnaVis: the selected progression, coloured by harmonic function.
              if (_engine.progression != null)
                _progressionFunctionStrip(_engine.progression!),
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
                      // Discrete stops: the engine snaps the swing offset to the
                      // 10 ms sample grid anyway (see LoopTiming._swingMs), so a
                      // continuous slider only offered indistinguishable values.
                      divisions: 12,
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
