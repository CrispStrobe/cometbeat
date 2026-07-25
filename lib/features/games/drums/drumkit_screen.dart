// lib/features/games/drums/drumkit_screen.dart
//
// "Drumkit / BoomBox" — a studio-style virtual drum kit + a step beat-grid,
// a fifth Workshop mode. Tap the pads to audition a drum; toggle the grid to
// build a loop; hit Play to hear it. The pattern IS a `DrumRowsPattern` — the
// SAME model the Loop Mixer's beat track and the Tracker's percussion channel
// use — so it's the shared beat editor (interconnection to those is a follow-up).

import 'dart:async';
import 'dart:math' show max, min;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/beat_capture.dart'
    show BeatFrame, beatboxToTaps;
import 'package:comet_beat/core/audio/daw_sources.dart' show DrumSource;
import 'package:comet_beat/core/audio/drum_presets.dart';
import 'package:comet_beat/core/audio/loop_engine.dart'
    show DrumRowsPattern, LoopTiming, kPatternSteps;
import 'package:comet_beat/core/audio/microphone_pitch_service.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart' show PitchReading;
import 'package:comet_beat/core/audio/rhythm_convert.dart' show toDrumPattern;
import 'package:comet_beat/core/audio/rhythm_quantize.dart'
    show RhythmOnset, RhythmResolution, quantizeToResolution;
import 'package:comet_beat/core/audio/synth.dart'
    show Drum, kSampleRate, renderDrum, wavBytes;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/beat_bridge.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/core/services/gapless_loop_player.dart';
import 'package:comet_beat/features/games/composition/groove_notation.dart'
    show drumParts;
import 'package:comet_beat/features/games/drums/drum_kit_visual.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart'
    show SavedInstrument;
import 'package:comet_beat/features/sound_lab/my_instruments_sheet.dart'
    show renderInstrumentNote, showMyInstrumentsSheet;
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart'
    show showAudioExportSheet;
import 'package:comet_beat/shared/music_io/music_export.dart'
    show showMusicExportSheet;
import 'package:crisp_notation/crisp_notation.dart'
    show MultiPartScore, multiPartToMusicXml;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

/// Test handle onto the running kit (the state class is private).
@visibleForTesting
abstract interface class DrumkitTester {
  int get steps;
  bool cellAt(Drum drum, int step);
  void toggle(Drum drum, int step);
  int get hitCount;

  /// Undo/redo of every pattern change (grid edits, record takes, clear).
  bool get canUndo;
  bool get canRedo;
  void undo();
  void redo();
  bool get isPlaying;
  void togglePlay();
  void stop();
  void clear();
  void tapPad(Drum drum);
  int get tempo;
  void setTempo(int bpm);

  /// Groove: 0 = straight, up to 0.6 delays every off-eighth (a swing feel).
  double get swing;
  void setSwing(double swing);

  /// Pattern length in bars (2/4/8) — resizes the grid, preserving hits.
  int get bars;
  void setBars(int bars);

  /// Tap-to-record: while on, pad taps are captured and, on stop, quantised
  /// onto the step grid (overdubbed into the pattern).
  bool get isRecording;
  void toggleRecord();

  /// Test seam: quantise a list of `(drum, loop-ms)` taps into the grid exactly
  /// as a live recording would, without real-time tapping.
  void debugRecordTaps(List<({Drum drum, double ms})> taps);

  /// Beatbox-to-grid: capture the mic, classify each hit (kick/snare/hat) and
  /// quantise onto the grid — the same pipeline as tapping, timbre-classified.
  bool get isListening;
  void toggleBeatbox();

  /// Test seam: run captured beatbox [frames] through classify → quantise →
  /// grid, without a live microphone.
  void debugBeatboxFrames(List<BeatFrame> frames);

  /// Save/export: the beat as a rhythm-line score (one part per drum). Test
  /// seams: persist into [songs] and read back the MusicXML (null when empty).
  String? debugSaveToSongBook(UserSongsService songs);
  String? debugMusicXml();

  /// Send the current beat to the Multitrack (DAW) as a clip.
  void sendToDaw();

  /// Shared-groove bridge: publish this beat so the other modes (Loop Mixer /
  /// Trackers / Looper) can load it, and pull the shared beat into this grid.
  void shareBeat();
  bool get canLoadSharedBeat;
  void loadSharedBeat();

  /// Load a built-in starter groove ([kDrumPresets] index) into the grid.
  void debugLoadPreset(int index);

  /// Per-drum sound override (a library / SoundFont voice; null = the synth
  /// drum): the current voice for [drum], and a setter.
  SavedInstrument? drumVoiceOf(Drum drum);
  void debugSetDrumVoice(Drum drum, SavedInstrument? voice);
}

class DrumkitScreen extends StatefulWidget {
  const DrumkitScreen({super.key, this.initialBeat});

  /// When opened as an editor for another surface's beat (e.g. the Loop
  /// Studio's Drums card), the grid starts from this pattern and a Done action
  /// returns the edited pattern via the Navigator result (round-trip). Null for
  /// the standalone tile.
  final DrumRowsPattern? initialBeat;

  static const tempos = [80, 100, 120, 140];

  /// Width of the grid's fixed drum-label column — the visual kit is inset by
  /// the same amount so it lines up over the step columns it plays.
  static const labelGutter = 64.0;

  @override
  State<DrumkitScreen> createState() => _DrumkitScreenState();
}

class _DrumkitScreenState extends State<DrumkitScreen>
    with SingleTickerProviderStateMixin
    implements DrumkitTester {
  // One boolean row per drum voice; each row is kPatternSteps (16 = 2 bars).
  final Map<Drum, List<bool>> _rows = {
    for (final d in Drum.values) d: List<bool>.filled(kPatternSteps, false),
  };

  // Per-drum sound override: a library instrument (incl. SoundFont-backed
  // voices) replacing the built-in synth voice. Null = the synth drum. The
  // rendered one-shot is cached per voice so playback doesn't re-synthesize.
  final Map<Drum, SavedInstrument> _drumVoice = {};
  final Map<Drum, Float64List> _voiceShot = {};

  final _loop = GaplessLoopPlayer();
  final _clock = Stopwatch();
  late final Ticker _ticker;
  final _step = ValueNotifier<int>(-1);
  // Drives the GarageBand-style visual kit: pieces flash on the step clock, and
  // on a live pad tap via this controller.
  final _visual = DrumKitVisualController();
  // Horizontal scroll for the step grid when the pattern is wider than the
  // screen (4/8 bars) — cells keep a tappable minimum width and scroll.
  final _gridScroll = ScrollController();
  int _tempo = 100;
  double _swing = 0; // 0 = straight; a groove delays every off-eighth
  int _bars = 2; // pattern length — 2/4/8 bars (mehr Takte)

  /// The current grid width in steps (eighths): 8 per bar.
  int get _steps => LoopTiming.stepsPerBar * _bars;

  // Undo/redo history of pattern snapshots (grid edits, record takes, clear).
  static const _maxUndo = 50;
  final List<Map<Drum, List<bool>>> _undoStack = [];
  final List<Map<Drum, List<bool>>> _redoStack = [];

  // Tap-to-record: capture (drum, loop-relative ms) while recording, then
  // quantise onto the step grid on stop.
  bool _recording = false;
  final List<({Drum drum, double ms})> _taps = [];

  // Beatbox capture: collect mic feature frames over one loop, then classify +
  // quantise them onto the grid.
  MicrophonePitchService? _mic;
  StreamSubscription<PitchReading>? _micSub;
  final List<BeatFrame> _frames = [];
  final Stopwatch _captureClock = Stopwatch();
  Timer? _captureStop;
  bool _listening = false;

  LoopTiming get _timing =>
      LoopTiming(tempoBpm: _tempo, swing: _swing, bars: _bars);

  @override
  void initState() {
    super.initState();
    _seedFromInitialBeat();
    _ticker = createTicker((_) {
      if (!_clock.isRunning) {
        _step.value = -1;
        return;
      }
      final t = _timing;
      _step.value = (_clock.elapsedMilliseconds % t.totalMs) ~/ t.stepMs;
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _step.dispose();
    _visual.dispose();
    _gridScroll.dispose();
    _loop.dispose();
    _captureStop?.cancel();
    _micSub?.cancel();
    _mic?.dispose();
    super.dispose();
  }

  // --- Audio -----------------------------------------------------------------

  Int16List _toPcm16(Float64List pcm) {
    final out = Int16List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      out[i] = (pcm[i].clamp(-1.0, 1.0) * 32767).round();
    }
    return out;
  }

  Uint8List _renderWav() => wavBytes(_toPcm16(_renderPattern()));

  /// The pattern rendered to PCM, applying any per-drum voice overrides. With no
  /// overrides this is exactly the shared [DrumRowsPattern] render; otherwise
  /// each overridden drum's hits play its instrument's cached one-shot.
  Float64List _renderPattern() {
    if (_drumVoice.isEmpty) return DrumRowsPattern(_rows).render(_timing);
    final total = _timing.totalSamples;
    final out = Float64List(total);
    for (final drum in Drum.values) {
      final row = _rows[drum]!;
      final shot =
          _drumVoice.containsKey(drum) ? _oneShotFor(drum) : renderDrum(drum);
      if (shot.isEmpty) continue;
      for (var s = 0; s < row.length; s++) {
        if (!row[s]) continue;
        final start = (_timing.boundaryMs(s) * kSampleRate) ~/ 1000;
        final n = min(shot.length, total - start);
        for (var i = 0; i < n; i++) {
          out[start + i] += shot[i];
        }
      }
    }
    return out;
  }

  /// The cached one-shot for [drum]'s override voice (empty if it can't render,
  /// e.g. an unresolved SoundFont reference).
  Float64List _oneShotFor(Drum drum) => _voiceShot.putIfAbsent(drum, () {
        final inst = _drumVoice[drum]?.instrument;
        return inst == null ? Float64List(0) : renderInstrumentNote(inst);
      });

  void _setDrumVoice(Drum drum, SavedInstrument? voice) {
    setState(() {
      _voiceShot.remove(drum);
      if (voice == null) {
        _drumVoice.remove(drum);
      } else {
        _drumVoice[drum] = voice;
      }
    });
    _syncPlayback();
  }

  /// Re-render + re-swap the loop IN PHASE after an edit (so the beat doesn't
  /// restart) — the same trick the Loop Mixer / Tracker use.
  void _syncPlayback() {
    if (!_clock.isRunning) return;
    if (!context.read<AudioService>().soundOn) return;
    final pos =
        Duration(milliseconds: _clock.elapsedMilliseconds % _timing.totalMs);
    _loop.playLoop(_renderWav(), position: pos);
  }

  // --- DrumkitTester ---------------------------------------------------------

  @override
  int get steps => _steps;

  @override
  bool cellAt(Drum drum, int step) => _rows[drum]![step];

  // --- Undo / redo -----------------------------------------------------------

  Map<Drum, List<bool>> _snapshot() => {
        for (final e in _rows.entries) e.key: [...e.value],
      };

  /// The current grid as a [DrumRowsPattern] — the round-trip Done result.
  DrumRowsPattern get currentPattern => DrumRowsPattern(_snapshot());

  /// Seed the grid from [DrumkitScreen.initialBeat] (round-trip open). Sets the
  /// bar count to fit the incoming pattern so a 4/8-bar drums card round-trips
  /// without truncation.
  void _seedFromInitialBeat() {
    final seed = widget.initialBeat;
    if (seed == null) return;
    var maxLen = 0;
    for (final row in seed.rows.values) {
      if (row.length > maxLen) maxLen = row.length;
    }
    _bars = maxLen > 16 ? 8 : (maxLen > 8 ? 4 : 2);
    final steps = LoopTiming.stepsPerBar * _bars;
    for (final d in Drum.values) {
      final src = seed.rows[d] ?? const <bool>[];
      _rows[d] = [
        for (var i = 0; i < steps; i++) i < src.length && src[i],
      ];
    }
  }

  /// Record the current pattern before a mutation, and drop the redo branch.
  void _pushUndo() {
    _undoStack.add(_snapshot());
    if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _restore(Map<Drum, List<bool>> snap) {
    for (final d in Drum.values) {
      _rows[d]!.setAll(0, snap[d]!);
    }
  }

  @override
  bool get canUndo => _undoStack.isNotEmpty;

  @override
  bool get canRedo => _redoStack.isNotEmpty;

  @override
  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_snapshot());
    setState(() => _restore(_undoStack.removeLast()));
    _syncPlayback();
  }

  @override
  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_snapshot());
    setState(() => _restore(_redoStack.removeLast()));
    _syncPlayback();
  }

  @override
  void toggle(Drum drum, int step) {
    _pushUndo();
    setState(() => _rows[drum]![step] = !_rows[drum]![step]);
    _syncPlayback();
  }

  @override
  int get hitCount =>
      _rows.values.fold(0, (n, row) => n + row.where((b) => b).length);

  @override
  bool get isPlaying => _clock.isRunning;

  @override
  void togglePlay() {
    if (_clock.isRunning) {
      stop();
      return;
    }
    if (!context.read<AudioService>().soundOn) return;
    _clock
      ..reset()
      ..start();
    _loop.playLoop(_renderWav());
    setState(() {});
  }

  @override
  void stop() {
    // Stopping while recording commits the take first.
    if (_recording) {
      _quantizeTapsIntoRows(_taps, _timing.beatMs.toDouble());
      _recording = false;
    }
    _clock
      ..stop()
      ..reset();
    _loop.stop();
    _step.value = -1;
    setState(() {});
  }

  @override
  void clear() {
    if (hitCount == 0) return;
    _pushUndo();
    setState(() {
      for (final row in _rows.values) {
        row.fillRange(0, row.length, false);
      }
    });
    _syncPlayback();
  }

  @override
  void tapPad(Drum drum) {
    // While recording, capture the tap at its loop position (so it quantises
    // against the running beat).
    if (_recording && _clock.isRunning) {
      _taps.add(
        (
          drum: drum,
          ms: (_clock.elapsedMilliseconds % _timing.totalMs).toDouble(),
        ),
      );
    }
    _visual.flash(drum); // light the piece on the visual kit
    // Audition the drum's actual voice — its override one-shot, else the synth.
    final shot =
        _drumVoice.containsKey(drum) ? _oneShotFor(drum) : renderDrum(drum);
    if (shot.isNotEmpty) {
      context.read<AudioService>().playWavBytes(wavBytes(_toPcm16(shot)));
    }
  }

  @override
  bool get isRecording => _recording;

  @override
  void toggleRecord() {
    if (_recording) {
      _finishRecording();
      return;
    }
    if (!context.read<AudioService>().soundOn) return;
    // Roll the loop so taps land against a beat (an empty pattern = a metronome-
    // free count, still on the grid via the loop clock).
    if (!_clock.isRunning) {
      _clock
        ..reset()
        ..start();
      _loop.playLoop(_renderWav());
    }
    setState(() {
      _taps.clear();
      _recording = true;
    });
  }

  void _finishRecording() {
    _quantizeTapsIntoRows(_taps, _timing.beatMs.toDouble());
    setState(() => _recording = false);
    _syncPlayback();
  }

  /// Quantise recorded [taps] onto the fixed eighth grid (the DrumKit's grid;
  /// beginners can't out-run it) and OR them into the pattern (overdub). Each
  /// drum snaps independently so a kick and a snare can share a step; the
  /// relevance threshold collapses double-taps and (via [quantizeToResolution])
  /// keeps loose timing on clean eighths.
  void _quantizeTapsIntoRows(
    List<({Drum drum, double ms})> taps,
    double beatMs,
  ) {
    if (taps.isEmpty) return;
    _pushUndo(); // a record take is undoable
    setState(() {
      for (final drum in Drum.values) {
        final onsets = <RhythmOnset>[
          for (final t in taps)
            if (t.drum == drum) (ms: t.ms, strength: 1.0),
        ];
        if (onsets.isEmpty) continue;
        final q = quantizeToResolution(
          onsets,
          beatMs: beatMs,
          resolution: RhythmResolution.eighth,
        );
        final pattern = toDrumPattern(q, drumOf: (_) => drum, steps: _steps);
        for (var s = 0; s < _steps; s++) {
          if (pattern.rows[drum]![s]) _rows[drum]![s] = true;
        }
      }
    });
  }

  @override
  void debugRecordTaps(List<({Drum drum, double ms})> taps) =>
      _quantizeTapsIntoRows(taps, _timing.beatMs.toDouble());

  // --- Beatbox capture -------------------------------------------------------

  @override
  bool get isListening => _listening;

  @override
  void toggleBeatbox() {
    if (_listening) {
      _finishBeatbox();
    } else {
      _beginBeatbox();
    }
  }

  Future<void> _beginBeatbox() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    _frames.clear();
    // Nothing plays during capture, so keep the beat loop silent.
    stop();
    final mic = _mic ??= MicrophonePitchService();
    mic.echoCancel = false; // full accuracy; no output to cancel
    try {
      _micSub = mic.readings.listen((r) {
        _frames.add(
          (
            ms: _captureClock.elapsedMilliseconds.toDouble(),
            rms: r.rms,
            zcr: r.zcr,
            // A hummed "boom" reads as a low pitched note → a kick.
            pitchedLow: r.hasPitch && r.nearestMidi < 60,
          ),
        );
      });
      await mic.start();
    } on PitchCaptureException {
      await _micSub?.cancel();
      if (!mounted) return;
      messenger
          .showSnackBar(SnackBar(content: Text(l10n.drumkitBeatboxNothing)));
      return;
    }
    if (!mounted) return;
    _captureClock
      ..reset()
      ..start();
    setState(() => _listening = true);
    // Capture one loop, then quantise.
    _captureStop = Timer(
      Duration(milliseconds: _timing.totalMs),
      _finishBeatbox,
    );
  }

  Future<void> _finishBeatbox() async {
    _captureStop?.cancel();
    _captureClock.stop();
    await _mic?.stop();
    await _micSub?.cancel();
    if (!mounted) return;
    _quantizeTapsIntoRows(beatboxToTaps(_frames), _timing.beatMs.toDouble());
    setState(() => _listening = false);
  }

  @override
  void debugBeatboxFrames(List<BeatFrame> frames) =>
      _quantizeTapsIntoRows(beatboxToTaps(frames), _timing.beatMs.toDouble());

  // --- Save / export ---------------------------------------------------------

  /// The beat as a rhythm-line multi-part score (one part per drum with a hit),
  /// or null when the grid is empty. [nameOf] resolves the localized labels.
  ({MultiPartScore score, List<String> partNames})? _beatParts(
    AppLocalizations l10n,
  ) =>
      drumParts(DrumRowsPattern(_rows), nameOf: (d) => _drumLabel(l10n, d));

  String? _beatMusicXml(AppLocalizations l10n) {
    final parts = _beatParts(l10n);
    if (parts == null) return null;
    return multiPartToMusicXml(parts.score, partNames: parts.partNames);
  }

  Future<void> _saveToSongBook() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final songs = context.read<UserSongsService>();
    final xml = _beatMusicXml(l10n);
    if (xml == null) return;

    final controller = TextEditingController(text: l10n.drumkitDefaultName);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.drumkitSaveTitle),
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
            child: Text(l10n.drumkitSave),
          ),
        ],
      ),
    );
    if (title == null) return;
    final name = title.trim().isEmpty ? l10n.drumkitDefaultName : title.trim();
    songs.addSong(
      ImportedSong(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: name,
        musicXml: xml,
      ),
    );
    messenger.showSnackBar(SnackBar(content: Text(l10n.drumkitSaved)));
  }

  void _exportBeat() {
    final l10n = AppLocalizations.of(context)!;
    final parts = _beatParts(l10n);
    if (parts == null) return;
    showMusicExportSheet(
      context,
      multiPart: parts.score,
      partNames: parts.partNames,
      baseName: 'beat',
    );
  }

  /// Render the beat and offer it as WAV or MP3 (pure-Dart, web-safe).
  void _exportAudio() {
    showAudioExportSheet(
      context,
      pcm: _renderPattern(), // include per-drum voice overrides
      baseName: 'beat',
    );
  }

  @override
  String? debugSaveToSongBook(UserSongsService songs) {
    final l10n = AppLocalizations.of(context)!;
    final xml = _beatMusicXml(l10n);
    if (xml == null) return null;
    songs.addSong(
      ImportedSong(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: l10n.drumkitDefaultName,
        musicXml: xml,
      ),
    );
    return xml;
  }

  @override
  String? debugMusicXml() => _beatMusicXml(AppLocalizations.of(context)!);

  @override
  void sendToDaw() {
    if (hitCount == 0) return;
    // A SNAPSHOT (deep-copied rows) so later DrumKit edits don't change the
    // sent clip; the timing carries the current tempo + swing.
    context.read<DawService>().addClip(
          DrumSource(DrumRowsPattern(_snapshot()), _timing),
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.dawSent)),
    );
  }

  // --- Shared-groove bridge --------------------------------------------------

  @override
  void shareBeat() {
    if (hitCount == 0) return;
    BeatBridge.instance.publish(
      SharedBeat(
        rows: _snapshot(), // a copy, so later edits don't change what's shared
        tempoBpm: _tempo,
        swing: _swing,
        source: 'drumkit',
        // Carry the per-drum sound overrides so they travel with the beat.
        voices: {
          for (final e in _drumVoice.entries)
            e.key: SharedVoice(e.value.name, e.value.json),
        },
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.beatShared)),
    );
  }

  // --- Presets ---------------------------------------------------------------

  void _loadPreset(DrumPreset preset) {
    _pushUndo();
    setState(() {
      for (final d in Drum.values) {
        final src = preset.pattern.rows[d]!;
        // Tile the 2-bar preset across however many bars are set, so a longer
        // grid gets the groove repeated instead of half-filled.
        for (var i = 0; i < _steps; i++) {
          _rows[d]![i] = src.isNotEmpty && src[i % src.length];
        }
      }
    });
    _syncPlayback();
  }

  @override
  void debugLoadPreset(int index) => _loadPreset(kDrumPresets[index]);

  Future<void> _openPresets() async {
    final l10n = AppLocalizations.of(context)!;
    final chosen = await showModalBottomSheet<DrumPreset>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.drumkitPresetsTitle,
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final preset in kDrumPresets)
                    ListTile(
                      leading: const Icon(Icons.music_note),
                      title: Text(preset.name),
                      onTap: () => Navigator.pop(sheet, preset),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen != null) _loadPreset(chosen);
  }

  // --- Per-drum sounds (instrument library / SoundFont voices) ---------------

  @override
  SavedInstrument? drumVoiceOf(Drum drum) => _drumVoice[drum];

  @override
  void debugSetDrumVoice(Drum drum, SavedInstrument? voice) =>
      _setDrumVoice(drum, voice);

  Future<void> _openDrumSounds() async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.drumkitSounds,
                  style: Theme.of(sheet).textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final drum in Drum.values)
                      ListTile(
                        leading: Icon(_drumIcon(drum)),
                        title: Text(_drumLabel(l10n, drum)),
                        subtitle: Text(
                          _drumVoice[drum]?.name ?? l10n.drumkitDefaultSound,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_drumVoice.containsKey(drum))
                              IconButton(
                                icon: const Icon(Icons.restart_alt),
                                tooltip: l10n.drumkitResetSound,
                                onPressed: () {
                                  _setDrumVoice(drum, null);
                                  setSheet(() {});
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.edit),
                              tooltip: l10n.drumkitChangeSound,
                              onPressed: () async {
                                final saved =
                                    await showMyInstrumentsSheet(sheet);
                                if (saved == null) return;
                                if (saved.instrument == null) {
                                  // A SoundFont reference needs its font loaded.
                                  if (!sheet.mounted) return;
                                  ScaffoldMessenger.of(sheet).showSnackBar(
                                    SnackBar(
                                      content:
                                          Text(l10n.drumkitSoundUnavailable),
                                    ),
                                  );
                                  return;
                                }
                                _setDrumVoice(drum, saved);
                                setSheet(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Shared-groove bridge --------------------------------------------------

  @override
  bool get canLoadSharedBeat => BeatBridge.instance.hasBeat;

  @override
  void loadSharedBeat() {
    final shared = BeatBridge.instance.current;
    if (shared == null || shared.isEmpty) return;
    _pushUndo();
    final fitted = shared.rowsFitted(_steps);
    setState(() {
      for (final d in Drum.values) {
        _rows[d]!.setAll(0, fitted[d]!);
      }
      _tempo = shared.tempoBpm.clamp(40, 240);
      _swing = shared.swing.clamp(0.0, 0.6);
      // Restore any per-drum sound overrides that travelled with the beat.
      _drumVoice.clear();
      _voiceShot.clear();
      for (final e in shared.voices.entries) {
        _drumVoice[e.key] =
            SavedInstrument(name: e.value.name, json: e.value.json);
      }
    });
    _syncPlayback();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.beatLoaded)),
    );
  }

  @override
  int get tempo => _tempo;

  @override
  void setTempo(int bpm) {
    setState(() => _tempo = bpm);
    _syncPlayback();
  }

  @override
  double get swing => _swing;

  @override
  void setSwing(double swing) {
    setState(() => _swing = swing.clamp(0.0, 0.6));
    _syncPlayback();
  }

  @override
  int get bars => _bars;

  @override
  void setBars(int bars) {
    if (bars == _bars || !const [2, 4, 8].contains(bars)) return;
    _pushUndo();
    final newSteps = LoopTiming.stepsPerBar * bars;
    setState(() {
      for (final d in Drum.values) {
        final old = _rows[d]!;
        // Grow → keep existing hits + pad with silence; shrink → truncate.
        _rows[d] = [
          for (var i = 0; i < newSteps; i++) i < old.length && old[i],
        ];
      }
      _bars = bars;
    });
    _syncPlayback();
  }

  // --- UI --------------------------------------------------------------------

  String _drumLabel(AppLocalizations l10n, Drum d) => switch (d) {
        Drum.kick => l10n.drumkitKick,
        Drum.snare => l10n.drumkitSnare,
        Drum.hat => l10n.drumkitHat,
        Drum.openHat => l10n.drumkitOpenHat,
        Drum.clap => l10n.drumkitClap,
        Drum.tom => l10n.drumkitTom,
        Drum.rim => l10n.drumkitRim,
        Drum.cowbell => l10n.drumkitCowbell,
        Drum.crash => l10n.drumkitCrash,
        Drum.ride => l10n.drumkitRide,
        Drum.lowTom => l10n.drumkitLowTom,
        Drum.highTom => l10n.drumkitHighTom,
      };

  IconData _drumIcon(Drum d) => switch (d) {
        Drum.kick => Icons.circle,
        Drum.snare => Icons.blur_circular,
        Drum.hat => Icons.brightness_high,
        _ => Icons.graphic_eq, // extended kit voices (default icon)
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: GameAppBar(
        title: l10n.drumkitTitle,
        actions: [
          // Round-trip: return the edited pattern to the surface that opened us
          // (e.g. the Loop Studio's Drums card).
          if (widget.initialBeat != null)
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: l10n.drumkitDone,
              onPressed: () => Navigator.of(context).pop(currentPattern),
            ),
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: l10n.myMelodyUndo,
            onPressed: canUndo ? undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: l10n.workshopRedo,
            onPressed: canRedo ? redo : null,
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: l10n.drumkitSave,
            onPressed: hitCount == 0 ? null : _saveToSongBook,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: l10n.drumkitExport,
            onPressed: hitCount == 0 ? null : _exportBeat,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: l10n.audioExportTitle,
            onPressed: hitCount == 0 ? null : _exportAudio,
          ),
        ],
      ),
      // Scrolls on a short phone (German control labels wrap the button
      // cluster onto more rows than an SE-height screen fits); the kit + grid
      // get fixed heights so the whole body has an intrinsic height to scroll.
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The visual kit: tap a drawn piece to play it; it lights up as
                // the beat plays (step clock) or is tapped/recorded. Inset by the
                // label gutter so it aligns with the step columns below.
                SizedBox(
                  height: 180,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: DrumkitScreen.labelGutter,
                    ),
                    child: DrumKitVisual(
                      step: _step,
                      hitAt: (drum, step) => _rows[drum]![step],
                      controller: _visual,
                      onHit:
                          tapPad, // tap a drawn piece to play it (+ record it)
                    ),
                  ),
                ),
                // Hand percussion that isn't on the drawn kit — compact pads.
                Row(
                  children: [
                    for (final drum in const [
                      Drum.clap,
                      Drum.rim,
                      Drum.cowbell,
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FilledButton.tonalIcon(
                            onPressed: () => tapPad(drum),
                            icon: Icon(_drumIcon(drum), size: 18),
                            label: Text(_drumLabel(l10n, drum)),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // The step grid: a fixed drum-label column + horizontally
                // scrollable step cells (so 4/8-bar patterns stay tappable).
                SizedBox(
                  height: Drum.values.length * 36.0,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const labelW = DrumkitScreen.labelGutter;
                      const minCell = 24.0;
                      final avail = constraints.maxWidth - labelW;
                      // Fill the width at 2 bars; shrink to minCell then scroll.
                      final cellW = max(minCell, avail / _steps);
                      return Row(
                        children: [
                          // Fixed labels column (aligned with the cell rows).
                          SizedBox(
                            width: labelW,
                            child: Column(
                              children: [
                                for (final drum in Drum.values)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 3,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          _drumLabel(l10n, drum),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              controller: _gridScroll,
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: cellW * _steps,
                                child: Column(
                                  children: [
                                    for (final drum in Drum.values)
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 3,
                                          ),
                                          child: Row(
                                            children: [
                                              for (var s = 0; s < _steps; s++)
                                                SizedBox(
                                                  width: cellW,
                                                  child: _StepCell(
                                                    step: _step,
                                                    on: _rows[drum]![s],
                                                    index: s,
                                                    scheme: scheme,
                                                    onTap: () =>
                                                        toggle(drum, s),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                // Transport + tempo + clear.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: togglePlay,
                      icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                      label:
                          Text(isPlaying ? l10n.songStop : l10n.myMelodyPlay),
                    ),
                    // Starter grooves — the quickest way to see how a beat works.
                    FilledButton.tonalIcon(
                      onPressed: _openPresets,
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(l10n.drumkitPresets),
                    ),
                    // Swap any drum's sound for a library / SoundFont voice.
                    FilledButton.tonalIcon(
                      onPressed: _openDrumSounds,
                      icon: const Icon(Icons.library_music),
                      label: Text(l10n.drumkitSounds),
                    ),
                    FilledButton.icon(
                      onPressed: toggleRecord,
                      style: _recording
                          ? FilledButton.styleFrom(
                              backgroundColor: scheme.error,
                            )
                          : null,
                      icon: Icon(
                        _recording ? Icons.stop : Icons.fiber_manual_record,
                      ),
                      label: Text(
                        _recording
                            ? l10n.drumkitStopRecording
                            : l10n.drumkitRecord,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: toggleBeatbox,
                      style: _listening
                          ? FilledButton.styleFrom(
                              backgroundColor: scheme.error,
                            )
                          : null,
                      icon: Icon(_listening ? Icons.stop : Icons.mic),
                      label: Text(
                        _listening
                            ? l10n.drumkitStopListening
                            : l10n.drumkitBeatbox,
                      ),
                    ),
                    for (final bpm in DrumkitScreen.tempos)
                      ChoiceChip(
                        label: Text('$bpm'),
                        selected: _tempo == bpm,
                        onSelected: (_) => setTempo(bpm),
                      ),
                    // Pattern length — mehr Takte (2/4/8 bars).
                    Text(
                      l10n.drumkitBars,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    for (final b in const [2, 4, 8])
                      ChoiceChip(
                        label: Text('$b'),
                        selected: _bars == b,
                        onSelected: (_) => setBars(b),
                      ),
                    // Groove feel: straight vs a swung off-beat.
                    ChoiceChip(
                      label: Text(l10n.drumkitStraight),
                      selected: _swing == 0,
                      onSelected: (_) => setSwing(0),
                    ),
                    ChoiceChip(
                      label: Text(l10n.drumkitSwing),
                      selected: _swing > 0,
                      onSelected: (_) => setSwing(0.4),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: hitCount == 0 ? null : sendToDaw,
                      icon: const Icon(Icons.library_add),
                      label: Text(l10n.dawSend),
                    ),
                    // Shared groove: publish this beat / pull the one another mode
                    // (Loop Mixer, Tracker, Looper) shared.
                    FilledButton.tonalIcon(
                      onPressed: hitCount == 0 ? null : shareBeat,
                      icon: const Icon(Icons.upload),
                      label: Text(l10n.beatShare),
                    ),
                    ValueListenableBuilder<SharedBeat?>(
                      valueListenable: BeatBridge.instance.beat,
                      builder: (context, _, __) => FilledButton.tonalIcon(
                        onPressed: canLoadSharedBeat ? loadSharedBeat : null,
                        icon: const Icon(Icons.download),
                        label: Text(l10n.beatLoadShared),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: hitCount == 0 ? null : clear,
                      icon: const Icon(Icons.clear),
                      label: Text(l10n.trackerClear),
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

/// One step cell in the beat grid: lit when [on], playhead-outlined when the
/// clock is on this step. Every bar's first step (and its downbeats) is tinted
/// so a longer, scrolled pattern stays readable.
class _StepCell extends StatelessWidget {
  const _StepCell({
    required this.step,
    required this.on,
    required this.index,
    required this.scheme,
    required this.onTap,
  });

  final ValueListenable<int> step;
  final bool on;
  final int index;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final barStart = index % LoopTiming.stepsPerBar == 0;
    final beat = index % 2 == 0;
    return Padding(
      padding: EdgeInsets.only(left: barStart && index > 0 ? 6 : 2, right: 2),
      child: ValueListenableBuilder<int>(
        valueListenable: step,
        builder: (context, playing, _) => GestureDetector(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: on
                  ? scheme.primary
                  : (beat
                      ? scheme.surfaceContainerHighest
                      : scheme.surfaceContainerLow),
              borderRadius: BorderRadius.circular(4),
              border: playing == index
                  ? Border.all(color: scheme.tertiary, width: 2)
                  : null,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}
