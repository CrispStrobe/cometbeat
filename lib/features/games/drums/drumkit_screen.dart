// lib/features/games/drums/drumkit_screen.dart
//
// "Drumkit / BoomBox" — a studio-style virtual drum kit + a step beat-grid,
// a fifth Workshop mode. Tap the pads to audition a drum; toggle the grid to
// build a loop; hit Play to hear it. The pattern IS a `DrumRowsPattern` — the
// SAME model the Loop Mixer's beat track and the Tracker's percussion channel
// use — so it's the shared beat editor (interconnection to those is a follow-up).

import 'dart:async';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/beat_capture.dart'
    show BeatFrame, beatboxToTaps;
import 'package:comet_beat/core/audio/daw_sources.dart' show DrumSource;
import 'package:comet_beat/core/audio/loop_engine.dart'
    show DrumRowsPattern, LoopTiming, kPatternSteps;
import 'package:comet_beat/core/audio/microphone_pitch_service.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart' show PitchReading;
import 'package:comet_beat/core/audio/rhythm_convert.dart' show toDrumPattern;
import 'package:comet_beat/core/audio/rhythm_quantize.dart'
    show RhythmOnset, RhythmResolution, quantizeToResolution;
import 'package:comet_beat/core/audio/synth.dart'
    show Drum, renderDrum, wavBytes;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/core/services/gapless_loop_player.dart';
import 'package:comet_beat/features/games/composition/groove_notation.dart'
    show drumParts;
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart'
    show showAudioExportSheet;
import 'package:comet_beat/shared/music_io/music_export.dart'
    show showMusicExportSheet;
import 'package:crisp_notation/crisp_notation.dart'
    show MultiPartScore, multiPartToMusicXml;
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
}

class DrumkitScreen extends StatefulWidget {
  const DrumkitScreen({super.key});

  static const tempos = [80, 100, 120, 140];

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

  final _loop = GaplessLoopPlayer();
  final _clock = Stopwatch();
  late final Ticker _ticker;
  final _step = ValueNotifier<int>(-1);
  int _tempo = 100;
  double _swing = 0; // 0 = straight; a groove delays every off-eighth

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
      LoopTiming(tempoBpm: _tempo, swing: _swing); // 2 bars (default)

  @override
  void initState() {
    super.initState();
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

  Uint8List _renderWav() =>
      wavBytes(_toPcm16(DrumRowsPattern(_rows).render(_timing)));

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
  int get steps => kPatternSteps;

  @override
  bool cellAt(Drum drum, int step) => _rows[drum]![step];

  // --- Undo / redo -----------------------------------------------------------

  Map<Drum, List<bool>> _snapshot() => {
        for (final e in _rows.entries) e.key: [...e.value],
      };

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
    context
        .read<AudioService>()
        .playWavBytes(wavBytes(_toPcm16(renderDrum(drum))));
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
        final pattern = toDrumPattern(q, drumOf: (_) => drum);
        for (var s = 0; s < kPatternSteps; s++) {
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
      pcm: DrumRowsPattern(_rows).render(_timing),
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

  // --- UI --------------------------------------------------------------------

  String _drumLabel(AppLocalizations l10n, Drum d) => switch (d) {
        Drum.kick => l10n.drumkitKick,
        Drum.snare => l10n.drumkitSnare,
        Drum.hat => l10n.drumkitHat,
        // Extended kit voices — the enum name until @tracker-ui adds l10n keys.
        Drum.openHat => 'Open hat',
        Drum.clap => 'Clap',
        Drum.tom => 'Tom',
        Drum.rim => 'Rim',
        Drum.cowbell => 'Cowbell',
        Drum.crash => 'Crash',
        Drum.ride => 'Ride',
        Drum.lowTom => 'Low tom',
        Drum.highTom => 'High tom',
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The step grid: one row per drum, kPatternSteps toggles.
              Expanded(
                child: Column(
                  children: [
                    for (final drum in Drum.values)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 64,
                                child: Text(
                                  _drumLabel(l10n, drum),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                              for (var s = 0; s < kPatternSteps; s++)
                                Expanded(
                                  child: ValueListenableBuilder<int>(
                                    valueListenable: _step,
                                    builder: (context, playing, _) {
                                      final on = _rows[drum]![s];
                                      final beat = s % 2 == 0;
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 2,
                                        ),
                                        child: GestureDetector(
                                          onTap: () => toggle(drum, s),
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: on
                                                  ? scheme.primary
                                                  : (beat
                                                      ? scheme
                                                          .surfaceContainerHighest
                                                      : scheme
                                                          .surfaceContainerLow),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: playing == s
                                                  ? Border.all(
                                                      color: scheme.tertiary,
                                                      width: 2,
                                                    )
                                                  : null,
                                            ),
                                            child: const SizedBox.expand(),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // The pads — tap to audition a drum.
              Row(
                children: [
                  for (final drum in Drum.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilledButton.tonalIcon(
                          onPressed: () => tapPad(drum),
                          icon: Icon(_drumIcon(drum)),
                          label: Text(_drumLabel(l10n, drum)),
                        ),
                      ),
                    ),
                ],
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
                    label: Text(isPlaying ? l10n.songStop : l10n.myMelodyPlay),
                  ),
                  FilledButton.icon(
                    onPressed: toggleRecord,
                    style: _recording
                        ? FilledButton.styleFrom(backgroundColor: scheme.error)
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
                        ? FilledButton.styleFrom(backgroundColor: scheme.error)
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
    );
  }
}
