// lib/features/games/composition/daw_screen.dart
//
// The Multitrack — the DAW Workshop tool (docs/DAW_SCOPING.md). Clips from any
// module sit on tracks in time; Play BAKES the whole arrangement offline
// (renderTimeline, per-source cache) and plays it. A "vector, not bitmap"
// arranger: each clip references its source MODEL and renders on demand.
//
// It seeds demo clips (a beat + a tune) and receives real clips from every
// module's "Send to DAW". A to-scale timeline under a second-by-second ruler:
// clips are drawn at their render duration and dragged along the lane to
// reposition in time (with optional grid-snapping); per-track mute; tap a clip
// for its inspector (volume + fades, freeze, remove), ✕ to remove; Merge-all,
// undo/redo, and WAV/MP3 export.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/daw_sources.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/loop_engine.dart'
    show DrumRowsPattern, LoopTiming, kPatternSteps;
import 'package:comet_beat/core/audio/synth.dart' show Drum, wavBytes;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/sound_lab/my_samples_sheet.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:comet_beat/features/sound_lab/sample_extractor_screen.dart';
import 'package:comet_beat/features/sound_lab/sound_lab_screen.dart';
import 'package:comet_beat/features/sound_lab/voice_lab_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart'
    show showAudioExportSheet;
import 'package:crisp_notation/crisp_notation.dart'
    show
        Clef,
        DurationBase,
        Measure,
        NoteDuration,
        NoteElement,
        Pitch,
        Score,
        Step;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:provider/provider.dart';

/// Test handle onto the running arranger.
@visibleForTesting
abstract interface class DawTester {
  int get trackCount;
  int get clipCount;
  bool get isPlaying;

  /// The playhead position (ms); rests at the seek marker when stopped.
  double get playheadMs;

  /// Move the play-start / resting playhead (as clicking the ruler does).
  void seekTo(double ms);

  /// Whether playback loops back to the start at the end of the arrangement.
  bool get loopOn;
  void toggleLoop();
  bool isTrackMuted(int track);
  void toggleTrackMute(int track);

  /// Per-track volume fader (linear gain).
  void setTrackGain(int track, double gain);
  double trackGain(int track);

  /// Solo a track (while any track is soloed, only soloed tracks are heard).
  void toggleTrackSolo(int track);
  bool isTrackSoloed(int track);

  /// Track management: add an empty lane, remove one (min one kept), rename.
  void addTrack();
  void removeTrack(int track);
  void renameTrack(int track, String name);
  String trackName(int track);
  void addDemoBeat();
  void addDemoTune();
  void addSampleClip(SampleClip clip);
  void clear();
  void play();
  void stop();

  /// Merge/convert: flatten every clip into one baked audio take; freeze a
  /// single live clip to audio; whether a clip is already baked; remove a clip.
  void mergeAll();
  void freezeClip(int track, int index);
  bool isClipFrozen(int track, int index);
  void removeClip(int track, int index);
  void duplicateClip(int track, int index);

  /// Split the clip at [atMs] (timeline ms) into two; [canSplitClip] is true
  /// only when the cut falls strictly inside the clip.
  void splitClip(int track, int index, double atMs);
  bool canSplitClip(int track, int index, double atMs);

  /// Reverse the clip's audio (bakes it to a backwards take).
  void reverseClip(int track, int index);

  /// Resample the clip by [factor] — tape-style speed/pitch (2× faster, 0.5×
  /// slower). Bakes to a fixed take.
  void resampleClip(int track, int index, double factor);

  /// Timeline: move a clip in time, and read a clip's start + to-scale duration.
  void moveClip(int track, int index, double startMs);
  double clipStartMs(int track, int index);
  double clipDurationMs(int track, int index);

  /// Whether the arrangement can be exported (has audible content).
  bool get canExport;

  /// Undo / redo the last edits.
  void undo();
  void redo();
  bool get canUndo;
  bool get canRedo;

  /// Per-clip gain + fade lengths.
  void setClipGain(int track, int index, double gain);
  double clipGain(int track, int index);
  void setClipFades(
    int track,
    int index, {
    double? fadeInMs,
    double? fadeOutMs,
  });
  double clipFadeInMs(int track, int index);
  double clipFadeOutMs(int track, int index);

  /// Non-destructive per-clip trim (ms into the source render).
  void setClipTrim(
    int track,
    int index, {
    double? trimStartMs,
    double? trimEndMs,
  });
  double clipTrimStartMs(int track, int index);
  double clipTrimEndMs(int track, int index);
  double clipSourceMs(int track, int index);

  /// Drag-snapping to the beat grid, and the project tempo that defines it.
  void toggleSnap();
  bool get snapOn;
  double get bpm;
  void setBpm(double value);

  /// Test seam: the length (samples) the arrangement bakes to.
  int debugBakeLength();
}

class DawScreen extends StatefulWidget {
  const DawScreen({super.key});

  @override
  State<DawScreen> createState() => _DawScreenState();
}

class _DawScreenState extends State<DawScreen>
    with SingleTickerProviderStateMixin
    implements DawTester {
  bool _playing = false;

  // Playhead: driven by the Ticker's own elapsed (NOT wall-clock), so it stays
  // in step with the baked audio AND is deterministic under `tester.pump`.
  late final Ticker _ticker;
  final ValueNotifier<double> _positionMs = ValueNotifier<double>(0);
  double _totalMs = 0;
  bool _loop = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _positionMs.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final ms = _seekMs + elapsed.inMilliseconds.toDouble();
    if (_totalMs > 0 && ms >= _totalMs) {
      // Reached the end: loop restarts (from the seek point), else stop. The
      // re-bake in play() is cheap (every clip is served from the cache).
      if (_loop) {
        play();
      } else {
        stop();
      }
      return;
    }
    _positionMs.value = ms;
  }

  AudioService get _audio => context.read<AudioService>();
  DawService get _daw => context.read<DawService>();

  // --- DawTester -------------------------------------------------------------

  @override
  int get trackCount => _daw.timeline.tracks.length;

  @override
  int get clipCount => _daw.clipCount;

  @override
  bool get isPlaying => _playing;

  @override
  bool isTrackMuted(int track) => _daw.timeline.tracks[track].muted;

  @override
  void toggleTrackMute(int track) {
    _daw.toggleTrackMute(track);
    if (_playing) play(); // re-bake with the change
  }

  @override
  void setTrackGain(int track, double gain) {
    _daw.setTrackGain(track, gain);
    if (_playing) play(); // re-bake with the level change
  }

  @override
  double trackGain(int track) => _daw.trackGain(track);

  @override
  void toggleTrackSolo(int track) {
    _daw.toggleTrackSolo(track);
    if (_playing) play(); // re-bake — solo changes what's audible
  }

  @override
  bool isTrackSoloed(int track) => _daw.isTrackSoloed(track);

  @override
  void addTrack() => _daw.addTrack();

  @override
  void removeTrack(int track) {
    _daw.removeTrack(track);
    if (_playing) play();
  }

  @override
  void renameTrack(int track, String name) => _daw.renameTrack(track, name);

  @override
  String trackName(int track) => _daw.trackName(track);

  /// Track name → a small menu to rename the lane or remove it.
  Future<void> _trackMenu(int i) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: _daw.trackName(i));
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.dawTrackTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.dawTrackName),
          onSubmitted: (_) => Navigator.of(ctx).pop('rename'),
        ),
        actions: [
          TextButton(
            onPressed: _daw.timeline.tracks.length <= 1
                ? null
                : () => Navigator.of(ctx).pop('remove'),
            child: Text(l10n.dawRemoveTrack),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.dawCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('rename'),
            child: Text(l10n.dawRename),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'rename') {
      final name = controller.text.trim();
      if (name.isNotEmpty) renameTrack(i, name);
    } else if (action == 'remove') {
      removeTrack(i);
    }
  }

  DrumRowsPattern _demoBeat() {
    final rows = {
      for (final d in Drum.values) d: List<bool>.filled(kPatternSteps, false),
    };
    for (var s = 0; s < kPatternSteps; s += 4) {
      rows[Drum.kick]![s] = true;
    }
    for (var s = 2; s < kPatternSteps; s += 4) {
      rows[Drum.snare]![s] = true;
    }
    for (var s = 0; s < kPatternSteps; s += 2) {
      rows[Drum.hat]![s] = true;
    }
    return DrumRowsPattern(rows);
  }

  Score _demoTune() {
    const q = NoteDuration(DurationBase.quarter);
    return Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement.note(const Pitch(Step.c), q),
          NoteElement.note(const Pitch(Step.e), q),
          NoteElement.note(const Pitch(Step.g), q),
          NoteElement.note(const Pitch(Step.c, octave: 5), q),
        ]),
      ],
    );
  }

  @override
  void addDemoBeat() => _daw.addClip(
        DrumSource(_demoBeat(), const LoopTiming(tempoBpm: 100)),
      );

  @override
  void addDemoTune() => _daw.addClip(ScoreSource.single(_demoTune()), track: 1);

  @override
  void addSampleClip(SampleClip clip) {
    // Clips carry their own rate; the timeline renders at kDawSampleRate, so
    // resample first (SampleSource assumes it's already at the timeline rate).
    final pcm = clip.sampleRate == kDawSampleRate
        ? clip.pcm
        : resampleCubic(clip.pcm, clip.sampleRate / kDawSampleRate);
    // A fresh lane so a dropped-in sample never lands on top of another clip.
    _daw.addClip(
      SampleSource(pcm, key: 'sample:${clip.name}'),
      track: _daw.timeline.tracks.length,
    );
  }

  /// Picks a sample from the shared "My Samples" library and arranges it.
  Future<void> addSample() async {
    final clip = await showMySamplesSheet(context);
    if (clip == null || clip.pcm.isEmpty || !mounted) return;
    addSampleClip(clip);
  }

  /// Opens one of the Sound/Voice Lab creation tools full-screen; whatever the
  /// user saves lands in the shared "My Samples" library, so on return we open
  /// the sample picker to drop the fresh sound straight onto the timeline. This
  /// is how the Audio Editor consumes the Sound Lab (generate FX), Voice Lab
  /// (shape a voice) and Sample Extractor (lift a module sample) as clip sources.
  Future<void> _createThenPick(Widget tool) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => tool),
    );
    if (!mounted) return;
    await addSample();
  }

  Future<void> _addFromSoundLab() => _createThenPick(const SoundLabScreen());
  Future<void> _addFromVoiceLab() => _createThenPick(const VoiceLabScreen());
  Future<void> _addFromExtractor() =>
      _createThenPick(const SampleExtractorScreen());

  @override
  void clear() => _daw.clear();

  @override
  void mergeAll() {
    _daw.mergeAll();
    if (_playing) play(); // the merged take is bit-identical, but re-sync state
  }

  @override
  void freezeClip(int track, int index) => _daw.freezeClip(track, index);

  @override
  bool isClipFrozen(int track, int index) => _daw.isClipFrozen(track, index);

  @override
  void removeClip(int track, int index) => _daw.removeClip(track, index);

  @override
  void duplicateClip(int track, int index) => _daw.duplicateClip(track, index);

  @override
  void splitClip(int track, int index, double atMs) =>
      _daw.splitClip(track, index, atMs);

  @override
  bool canSplitClip(int track, int index, double atMs) =>
      _daw.canSplitClip(track, index, atMs);

  @override
  void reverseClip(int track, int index) => _daw.reverseClip(track, index);

  @override
  void resampleClip(int track, int index, double factor) =>
      _daw.resampleClip(track, index, factor);

  @override
  void moveClip(int track, int index, double startMs) =>
      _daw.moveClip(track, index, startMs);

  @override
  double clipStartMs(int track, int index) => _daw.clipStartMs(track, index);

  @override
  double clipDurationMs(int track, int index) =>
      _daw.clipDurationMs(track, index);

  @override
  bool get canExport => _daw.clipCount > 0;

  @override
  void undo() => _daw.undo();

  @override
  void redo() => _daw.redo();

  @override
  bool get canUndo => _daw.canUndo;

  @override
  bool get canRedo => _daw.canRedo;

  @override
  void setClipGain(int track, int index, double gain) =>
      _daw.setClipGain(track, index, gain);

  @override
  double clipGain(int track, int index) => _daw.clipGain(track, index);

  @override
  void setClipFades(
    int track,
    int index, {
    double? fadeInMs,
    double? fadeOutMs,
  }) =>
      _daw.setClipFades(
        track,
        index,
        fadeInMs: fadeInMs,
        fadeOutMs: fadeOutMs,
      );

  @override
  double clipFadeInMs(int track, int index) => _daw.clipFadeInMs(track, index);

  @override
  double clipFadeOutMs(int track, int index) =>
      _daw.clipFadeOutMs(track, index);

  @override
  void setClipTrim(
    int track,
    int index, {
    double? trimStartMs,
    double? trimEndMs,
  }) =>
      _daw.setClipTrim(
        track,
        index,
        trimStartMs: trimStartMs,
        trimEndMs: trimEndMs,
      );

  @override
  double clipTrimStartMs(int track, int index) =>
      _daw.clipTrimStartMs(track, index);

  @override
  double clipTrimEndMs(int track, int index) =>
      _daw.clipTrimEndMs(track, index);

  @override
  double clipSourceMs(int track, int index) => _daw.clipSourceMs(track, index);

  @override
  void toggleSnap() => _daw.toggleSnap();

  @override
  bool get snapOn => _daw.snapOn;

  @override
  double get bpm => _daw.bpm;

  @override
  void setBpm(double value) => _daw.setBpm(value);

  Float64List _bake() => _daw.bake();

  Int16List _toPcm16(Float64List pcm) {
    final out = Int16List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      out[i] = (pcm[i].clamp(-1.0, 1.0) * 32767).round();
    }
    return out;
  }

  @override
  int debugBakeLength() => _bake().length;

  // Where playback starts (set by clicking the ruler); the playhead rests here
  // when stopped and playback resumes from it.
  double _seekMs = 0;

  @override
  void play() {
    final pcm = _bake();
    if (pcm.isEmpty) return;
    _totalMs = pcm.length / kDawSampleRate * 1000;
    final from = (_seekMs.clamp(0, _totalMs) * kDawSampleRate / 1000).round();
    // Play from the seek point onward. The transport (playhead) runs whenever
    // Play is engaged; only the audible output is gated on the sound toggle.
    if (_audio.soundOn && from < pcm.length) {
      _audio
          .playWavBytes(wavBytes(_toPcm16(Float64List.sublistView(pcm, from))));
    }
    _positionMs.value = _seekMs;
    _ticker
      ..stop()
      ..start(); // elapsed restarts at 0; _onTick adds _seekMs
    setState(() => _playing = true);
  }

  @override
  void stop() {
    _ticker.stop();
    _positionMs.value = _seekMs; // rest at the seek marker
    _audio.stop();
    setState(() => _playing = false);
  }

  /// Move the play start (and the resting playhead) to [ms] on the timeline.
  @override
  void seekTo(double ms) {
    _seekMs = ms < 0 ? 0 : ms;
    _positionMs.value = _seekMs;
    if (_playing) play(); // restart from the new point
  }

  @override
  double get playheadMs => _positionMs.value;

  @override
  bool get loopOn => _loop;

  @override
  void toggleLoop() => setState(() => _loop = !_loop);

  // --- UI --------------------------------------------------------------------

  // Bake the arrangement and offer WAV/MP3 export via the shared sheet.
  void _export() {
    final pcm = _bake();
    showAudioExportSheet(context, pcm: pcm, baseName: 'multitrack');
  }

  static const _kProjectGroup = XTypeGroup(
    label: 'Multitrack project',
    extensions: ['cbdaw', 'json'],
  );

  Future<void> _saveProject() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = _daw.saveProject();
      final loc = await getSaveLocation(
        suggestedName: 'project.cbdaw',
        acceptedTypeGroups: const [_kProjectGroup],
      );
      if (loc == null) return;
      await XFile.fromData(
        Uint8List.fromList(utf8.encode(json)),
        name: 'project.cbdaw',
      ).saveTo(loc.path);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.dawProjectSaved)),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.dawProjectSaveFailed)),
      );
    }
  }

  Future<void> _openProject() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await openFile(acceptedTypeGroups: const [_kProjectGroup]);
      if (file == null) return;
      _daw.loadProject(utf8.decode(await file.readAsBytes()));
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.dawProjectOpenFailed)),
      );
    }
  }

  void _mergeAllWithToast() {
    final l10n = AppLocalizations.of(context)!;
    mergeAll();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.dawMerged)),
    );
  }

  void _freezeWithToast(int track, int index) {
    if (isClipFrozen(track, index)) return;
    final l10n = AppLocalizations.of(context)!;
    freezeClip(track, index);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.dawFrozen)),
    );
  }

  // Tap a clip → gain + fade sliders, freeze, remove.
  void _openClipInspector(int track, int index) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          // The clip may have been removed while the sheet is open.
          if (index >= _daw.timeline.tracks[track].clips.length) {
            return const SizedBox.shrink();
          }
          final frozen = _daw.isClipFrozen(track, index);
          Widget slider(
            String label,
            double value,
            double max,
            String Function(double) fmt,
            void Function(double) onChanged,
          ) =>
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$label — ${fmt(value)}'),
                  Slider(
                    value: value.clamp(0, max),
                    max: max,
                    onChanged: (v) => setSheet(() => onChanged(v)),
                  ),
                ],
              );

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  slider(
                    l10n.dawGain,
                    _daw.clipGain(track, index),
                    1.5,
                    (v) => '${(v * 100).round()}%',
                    (v) => setClipGain(track, index, v),
                  ),
                  slider(
                    l10n.dawFadeIn,
                    _daw.clipFadeInMs(track, index),
                    2000,
                    (v) => '${v.round()} ms',
                    (v) => setClipFades(track, index, fadeInMs: v),
                  ),
                  slider(
                    l10n.dawFadeOut,
                    _daw.clipFadeOutMs(track, index),
                    2000,
                    (v) => '${v.round()} ms',
                    (v) => setClipFades(track, index, fadeOutMs: v),
                  ),
                  // Trim: bound both edges to the untrimmed source length. The
                  // end slider shows the full length when unset (0 = to end).
                  ...() {
                    final srcMs = _daw.clipSourceMs(track, index);
                    final endMs = _daw.clipTrimEndMs(track, index);
                    return [
                      slider(
                        l10n.dawTrimStart,
                        _daw.clipTrimStartMs(track, index),
                        srcMs,
                        (v) => '${v.round()} ms',
                        (v) => setClipTrim(track, index, trimStartMs: v),
                      ),
                      slider(
                        l10n.dawTrimEnd,
                        endMs <= 0 ? srcMs : endMs,
                        srcMs,
                        (v) => '${v.round()} ms',
                        // At or past the full length ⇒ clear the trim (0 = to end).
                        (v) => setClipTrim(
                          track,
                          index,
                          trimEndMs: v >= srcMs ? 0 : v,
                        ),
                      ),
                    ];
                  }(),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: frozen
                            ? null
                            : () {
                                Navigator.of(sheetCtx).pop();
                                _freezeWithToast(track, index);
                              },
                        icon: Icon(frozen ? Icons.lock : Icons.ac_unit),
                        label: Text(l10n.dawFreeze),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          duplicateClip(track, index);
                        },
                        icon: const Icon(Icons.control_point_duplicate),
                        label: Text(l10n.dawDuplicate),
                      ),
                      // Split at the playhead — only when it falls inside the clip.
                      TextButton.icon(
                        onPressed: canSplitClip(track, index, playheadMs)
                            ? () {
                                Navigator.of(sheetCtx).pop();
                                splitClip(track, index, playheadMs);
                              }
                            : null,
                        icon: const Icon(Icons.content_cut),
                        label: Text(l10n.dawSplit),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          reverseClip(track, index);
                        },
                        icon: const Icon(Icons.fast_rewind),
                        label: Text(l10n.dawReverse),
                      ),
                      // Tape-style speed: slower (½×) / faster (2×).
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          resampleClip(track, index, 0.5);
                        },
                        icon: const Icon(Icons.slow_motion_video),
                        label: Text(l10n.dawSlower),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          resampleClip(track, index, 2.0);
                        },
                        icon: const Icon(Icons.speed),
                        label: Text(l10n.dawFaster),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          removeClip(track, index);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: Text(l10n.dawRemoveClip),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _clipKind(Clip clip) {
    final s = clip.source;
    return s is DrumSource
        ? '🥁'
        : s is ScoreSource
            ? '🎼'
            : s is GrooveSource
                ? '🎛️'
                : s is TrackerSource
                    ? '🎹'
                    : '🎵';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final daw = context.watch<DawService>(); // rebuild as clips are sent

    return Scaffold(
      appBar: GameAppBar(
        title: l10n.dawTitle,
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: l10n.dawUndo,
            onPressed: daw.canUndo ? undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: l10n.dawRedo,
            onPressed: daw.canRedo ? redo : null,
          ),
          IconButton(
            icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
            tooltip: _playing ? l10n.songStop : l10n.myMelodyPlay,
            onPressed: _playing ? stop : play,
          ),
          IconButton(
            icon: const Icon(Icons.repeat),
            color: _loop ? scheme.primary : null,
            tooltip: l10n.dawLoop,
            onPressed: toggleLoop,
          ),
          IconButton(
            icon: Icon(daw.snapOn ? Icons.grid_on : Icons.grid_off),
            color: daw.snapOn ? scheme.primary : null,
            tooltip: l10n.dawSnap,
            onPressed: toggleSnap,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: l10n.audioExportTitle,
            onPressed: daw.clipCount == 0 ? null : _export,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.trackerClear,
            onPressed: daw.clipCount == 0 ? null : clear,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // A DAW look from the first frame: the lanes/ruler are always shown
            // (even empty), with a gentle hint banner until the first clip lands.
            if (daw.clipCount == 0)
              Container(
                width: double.infinity,
                color: scheme.surfaceContainerHighest,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.dawEmpty,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(child: _timeline(daw, scheme)),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // One "Add clip" menu gathers every clip source: the demo
                  // beat/tune, the Sound Library, and the Sound/Voice Lab +
                  // Sample Extractor creation tools (the "SoundFX modals").
                  MenuAnchor(
                    menuChildren: [
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.graphic_eq),
                        onPressed: addSample,
                        child: Text(l10n.dawAddFromLibrary),
                      ),
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.auto_awesome),
                        onPressed: _addFromSoundLab,
                        child: Text(l10n.dawAddFx),
                      ),
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.record_voice_over),
                        onPressed: _addFromVoiceLab,
                        child: Text(l10n.dawAddVoice),
                      ),
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.colorize),
                        onPressed: _addFromExtractor,
                        child: Text(l10n.dawExtractSample),
                      ),
                      const Divider(height: 1),
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.music_note),
                        onPressed: addDemoBeat,
                        child: Text(l10n.dawAddBeat),
                      ),
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.piano),
                        onPressed: addDemoTune,
                        child: Text(l10n.dawAddTune),
                      ),
                    ],
                    builder: (context, controller, _) => FilledButton.icon(
                      onPressed: () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.dawAddClip),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: daw.clipCount < 2 ? null : _mergeAllWithToast,
                    icon: const Icon(Icons.layers),
                    label: Text(l10n.dawMergeAll),
                  ),
                  OutlinedButton.icon(
                    onPressed: daw.clipCount == 0 ? null : _saveProject,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(l10n.dawSaveProject),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openProject,
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.dawOpenProject),
                  ),
                  OutlinedButton.icon(
                    onPressed: addTrack,
                    icon: const Icon(Icons.add_road),
                    label: Text(l10n.dawAddTrack),
                  ),
                  // Project tempo — defines the beat snap grid.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        tooltip: l10n.dawTempoDown,
                        onPressed: () => setBpm(daw.bpm - 5),
                      ),
                      Text(l10n.dawBpm(daw.bpm.round())),
                      IconButton(
                        icon: const Icon(Icons.add),
                        tooltip: l10n.dawTempoUp,
                        onPressed: () => setBpm(daw.bpm + 5),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Timeline (to-scale clips, draggable in time) --------------------------

  static const double _pxPerSecond = 80;
  static const double _laneHeight = 60;
  static const double _gutterWidth = 84;
  static const double _rulerHeight = 20;

  // The clip's start when a long-press drag begins (offsets are relative to it).
  double _dragOriginMs = 0;

  Widget _timeline(DawService daw, ColorScheme scheme) {
    // Total arrangement length → the shared lane width.
    var maxEndMs = 0.0;
    for (var i = 0; i < daw.timeline.tracks.length; i++) {
      for (var j = 0; j < daw.timeline.tracks[i].clips.length; j++) {
        final end = daw.clipStartMs(i, j) + daw.clipDurationMs(i, j);
        if (end > maxEndMs) maxEndMs = end;
      }
    }
    final laneWidth = math.max(320.0, maxEndMs / 1000 * _pxPerSecond + 48);

    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fixed left gutter: a ruler-height spacer, then per-track name + mute.
          Column(
            children: [
              const SizedBox(height: _rulerHeight, width: _gutterWidth),
              for (var i = 0; i < daw.timeline.tracks.length; i++)
                _gutterHeader(daw, i, scheme),
            ],
          ),
          // Shared, horizontally-scrolling ruler + lanes (they scroll together).
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: laneWidth,
                child: Stack(
                  children: [
                    // Faint beat gridlines behind the lanes, when snapping.
                    if (daw.snapOn)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _BeatGridPainter(
                            beatPx: daw.beatMs / 1000 * _pxPerSecond,
                            color: scheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    Column(
                      children: [
                        _ruler(laneWidth, scheme),
                        for (var i = 0; i < daw.timeline.tracks.length; i++)
                          _lane(daw, i, scheme, laneWidth),
                      ],
                    ),
                    // The playhead: a thin line that sweeps across during play.
                    Positioned.fill(
                      child: ValueListenableBuilder<double>(
                        valueListenable: _positionMs,
                        builder: (context, ms, _) {
                          // Show while playing, or resting at a seek marker.
                          if (!_playing && ms <= 0) {
                            return const SizedBox.shrink();
                          }
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: ms / 1000 * _pxPerSecond,
                              ),
                              child: Container(width: 2, color: scheme.primary),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // A second-by-second time ruler aligned with the lanes below it.
  Widget _ruler(double laneWidth, ColorScheme scheme) {
    final seconds = (laneWidth / _pxPerSecond).ceil();
    return GestureDetector(
      // Click the ruler to move the playhead / play-start marker.
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => seekTo(d.localPosition.dx / _pxPerSecond * 1000),
      child: Container(
        width: laneWidth,
        height: _rulerHeight,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Stack(
          children: [
            for (var s = 0; s <= seconds; s++)
              Positioned(
                left: s * _pxPerSecond,
                top: 0,
                bottom: 0,
                child: Row(
                  children: [
                    Container(width: 1, color: scheme.outlineVariant),
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Text(
                        '${s}s',
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
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

  Widget _gutterHeader(DawService daw, int i, ColorScheme scheme) {
    final track = daw.timeline.tracks[i];
    return SizedBox(
      width: _gutterWidth,
      height: _laneHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _trackMenu(i),
                  child: Text(
                    track.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              InkWell(
                onTap: () => toggleTrackSolo(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    'S',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: track.soloed ? scheme.primary : scheme.outline,
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: () => toggleTrackMute(i),
                child: Icon(
                  track.muted ? Icons.volume_off : Icons.volume_up,
                  size: 18,
                  color: track.muted ? scheme.error : null,
                ),
              ),
            ],
          ),
          // Per-track volume fader (0 – 150%).
          SliderTheme(
            data: const SliderThemeData(
              trackHeight: 2,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: track.gain.clamp(0.0, 1.5),
              max: 1.5,
              onChanged: (v) => setTrackGain(i, v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lane(DawService daw, int i, ColorScheme scheme, double laneWidth) {
    final clips = daw.timeline.tracks[i].clips;
    return Container(
      width: laneWidth,
      height: _laneHeight,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Stack(
        children: [
          for (var j = 0; j < clips.length; j++) _clipBox(daw, i, j, scheme),
        ],
      ),
    );
  }

  Widget _clipBox(DawService daw, int i, int j, ColorScheme scheme) {
    final clip = daw.timeline.tracks[i].clips[j];
    final frozen = daw.isClipFrozen(i, j);
    final startPx = daw.clipStartMs(i, j) / 1000 * _pxPerSecond;
    final widthPx =
        math.max(30.0, daw.clipDurationMs(i, j) / 1000 * _pxPerSecond);
    final bg = frozen ? scheme.secondaryContainer : scheme.primaryContainer;
    final fg = frozen ? scheme.onSecondaryContainer : scheme.onPrimaryContainer;

    return Positioned(
      left: startPx,
      top: 6,
      height: _laneHeight - 12,
      width: widthPx,
      child: GestureDetector(
        // Long-press then drag to reposition in time (a plain drag over the lane
        // still scrolls it); tap to freeze to audio.
        onLongPressStart: (_) => _dragOriginMs = daw.clipStartMs(i, j),
        onLongPressMoveUpdate: (d) => moveClip(
          i,
          j,
          _dragOriginMs + d.localOffsetFromOrigin.dx / _pxPerSecond * 1000,
        ),
        onTap: () => _openClipInspector(i, j),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: scheme.outline),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                // The clip's audio shape, filling the box behind the label.
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ClipWaveformPainter(
                      daw.clipPeaks(i, j, buckets: math.max(8, widthPx ~/ 2)),
                      fg.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Row(
                    children: [
                      if (frozen)
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Icon(Icons.lock, size: 14, color: fg),
                        ),
                      Expanded(
                        child: Text(
                          _clipKind(clip),
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: TextStyle(color: fg),
                        ),
                      ),
                      InkWell(
                        onTap: () => removeClip(i, j),
                        child: Icon(Icons.close, size: 16, color: fg),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Faint vertical lines every [beatPx], marking the beat grid clips snap to.
class _BeatGridPainter extends CustomPainter {
  _BeatGridPainter({required this.beatPx, required this.color});
  final double beatPx;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (beatPx < 4) return; // too dense to be useful
    final paint = Paint()..color = color;
    for (var x = beatPx; x < size.width; x += beatPx) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_BeatGridPainter old) =>
      old.beatPx != beatPx || old.color != color;
}

/// Draws a clip's downsampled [peaks] (0..1) as a centre-line waveform that
/// fills the clip box. Repaints only when the peak list identity changes.
class _ClipWaveformPainter extends CustomPainter {
  _ClipWaveformPainter(this.peaks, this.color);
  final List<double> peaks;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final paint = Paint()..color = color;
    final mid = size.height / 2;
    final dx = size.width / peaks.length;
    for (var i = 0; i < peaks.length; i++) {
      final h = (peaks[i] * size.height).clamp(1.0, size.height);
      canvas.drawRect(
        Rect.fromLTWH(i * dx, mid - h / 2, dx <= 1 ? 1 : dx - 0.5, h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ClipWaveformPainter old) =>
      !identical(old.peaks, peaks) || old.color != color;
}
