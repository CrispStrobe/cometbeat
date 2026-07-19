// lib/features/games/composition/daw_screen.dart
//
// The Multitrack — the DAW Workshop tool (docs/DAW_SCOPING.md). Clips from any
// module sit on tracks in time; Play BAKES the whole arrangement offline
// (renderTimeline, per-source cache) and plays it. A "vector, not bitmap"
// arranger: each clip references its source MODEL and renders on demand.
//
// It seeds demo clips (a beat + a tune) and receives real clips from every
// module's "Send to DAW". A to-scale timeline: clips are drawn at their render
// duration and dragged along the lane to reposition in time; per-track mute;
// tap a clip for its inspector (volume + fades, freeze, remove), ✕ to remove;
// Merge-all, undo/redo, and WAV/MP3 export.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_sources.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/loop_engine.dart'
    show DrumRowsPattern, LoopTiming, kPatternSteps;
import 'package:comet_beat/core/audio/synth.dart' show Drum, wavBytes;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
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
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

/// Test handle onto the running arranger.
@visibleForTesting
abstract interface class DawTester {
  int get trackCount;
  int get clipCount;
  bool get isPlaying;
  bool isTrackMuted(int track);
  void toggleTrackMute(int track);
  void addDemoBeat();
  void addDemoTune();
  void clear();
  void play();
  void stop();

  /// Merge/convert: flatten every clip into one baked audio take; freeze a
  /// single live clip to audio; whether a clip is already baked; remove a clip.
  void mergeAll();
  void freezeClip(int track, int index);
  bool isClipFrozen(int track, int index);
  void removeClip(int track, int index);

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

  /// Test seam: the length (samples) the arrangement bakes to.
  int debugBakeLength();
}

class DawScreen extends StatefulWidget {
  const DawScreen({super.key});

  @override
  State<DawScreen> createState() => _DawScreenState();
}

class _DawScreenState extends State<DawScreen> implements DawTester {
  bool _playing = false;

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

  @override
  void play() {
    final pcm = _bake();
    if (pcm.isEmpty) return;
    if (!_audio.soundOn) return;
    _audio.playWavBytes(wavBytes(_toPcm16(pcm)));
    setState(() => _playing = true);
  }

  @override
  void stop() {
    _audio.stop();
    setState(() => _playing = false);
  }

  // --- UI --------------------------------------------------------------------

  // Bake the arrangement and offer WAV/MP3 export via the shared sheet.
  void _export() {
    final pcm = _bake();
    showAudioExportSheet(context, pcm: pcm, baseName: 'multitrack');
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
                  const SizedBox(height: 8),
                  Row(
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
                      const Spacer(),
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
            Expanded(
              child: daw.clipCount == 0
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.dawEmpty,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    )
                  : _timeline(daw, scheme),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: addDemoBeat,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.dawAddBeat),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: addDemoTune,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.dawAddTune),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: daw.clipCount < 2 ? null : _mergeAllWithToast,
                    icon: const Icon(Icons.layers),
                    label: Text(l10n.dawMergeAll),
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
          // Fixed left gutter: per-track name + mute.
          Column(
            children: [
              for (var i = 0; i < daw.timeline.tracks.length; i++)
                _gutterHeader(daw, i, scheme),
            ],
          ),
          // Shared, horizontally-scrolling lanes (all tracks scroll together).
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: laneWidth,
                child: Column(
                  children: [
                    for (var i = 0; i < daw.timeline.tracks.length; i++)
                      _lane(daw, i, scheme, laneWidth),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gutterHeader(DawService daw, int i, ColorScheme scheme) {
    final track = daw.timeline.tracks[i];
    return SizedBox(
      width: _gutterWidth,
      height: _laneHeight,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              track.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: Icon(track.muted ? Icons.volume_off : Icons.volume_up),
            color: track.muted ? scheme.error : null,
            tooltip: track.name,
            onPressed: () => toggleTrackMute(i),
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
          padding: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: scheme.outline),
          ),
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
      ),
    );
  }
}
