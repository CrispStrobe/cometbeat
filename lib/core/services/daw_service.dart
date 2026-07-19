// lib/core/services/daw_service.dart
//
// The shared Multitrack (DAW) arrangement. Any module adds clips to it via
// "Send to DAW"; the Multitrack screen displays + bakes it. App-wide (a
// Provider), so a clip sent from the DrumKit or Song Book is still there when
// you open the arranger, and successive sends accumulate into one project.

import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:flutter/foundation.dart';

class DawService extends ChangeNotifier {
  /// The arrangement — starts with two empty named lanes.
  final DawTimeline timeline = DawTimeline(
    tracks: [DawTrack(name: 'A'), DawTrack(name: 'B')],
  );

  // Per-source render cache (the "vector" optimisation): an unchanged clip is
  // served from here instead of re-rendering on every bake.
  final Map<Object, Float64List> _cache = {};

  // Where the next sent clip lands, so successive sends lay out along the
  // timeline rather than stacking at 0.
  double _nextStartMs = 0;

  // --- Undo / redo -----------------------------------------------------------
  // Each discrete edit snapshots the arrangement first. Clips are immutable
  // (replaced, never mutated in place) so a snapshot shares Clip instances — a
  // deep copy of the *structure* (tracks + clip lists) is enough.
  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];
  static const int _maxUndo = 50;

  // Consecutive edits sharing a token (a clip drag, a gain-slider sweep)
  // coalesce into one undo entry. Any discrete edit or undo/redo resets it.
  Object? _coalesceToken;

  // Snapshot only when a coalescing run starts (the token changes).
  void _coalesced(Object token) {
    if (_coalesceToken != token) {
      _pushUndo();
      _coalesceToken = token;
    }
  }

  _Snapshot _capture() => _Snapshot(
        tracks: [
          for (final t in timeline.tracks)
            DawTrack(
              name: t.name,
              gain: t.gain,
              muted: t.muted,
              clips: [...t.clips],
            ),
        ],
        nextStartMs: _nextStartMs,
      );

  void _restore(_Snapshot s) {
    timeline.tracks
      ..clear()
      ..addAll(s.tracks);
    _nextStartMs = s.nextStartMs;
  }

  void _pushUndo() {
    _undo.add(_capture());
    if (_undo.length > _maxUndo) _undo.removeAt(0);
    _redo.clear();
  }

  // A discrete edit: snapshot + break any move-coalescing run.
  void _record() {
    _pushUndo();
    _coalesceToken = null;
  }

  /// Whether there is anything to undo / redo.
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Step back / forward through edits.
  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_capture());
    _restore(_undo.removeLast());
    _coalesceToken = null;
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_capture());
    _restore(_redo.removeLast());
    _coalesceToken = null;
    notifyListeners();
  }

  /// Total clips across all tracks.
  int get clipCount => timeline.tracks.fold(0, (n, t) => n + t.clips.length);

  /// Append a clip from a module to [track] (auto-creating tracks up to it), at
  /// the next free slot. Modules send a SNAPSHOT source (a copy of their model),
  /// so further edits in the module don't retroactively change the sent clip.
  void addClip(ClipSource source, {int track = 0}) {
    _record();
    while (timeline.tracks.length <= track) {
      timeline.tracks.add(DawTrack(name: '${timeline.tracks.length + 1}'));
    }
    timeline.tracks[track].clips
        .add(Clip(source: source, startMs: _nextStartMs));
    _nextStartMs += 2000;
    notifyListeners();
  }

  /// Mute / unmute a whole track.
  void toggleTrackMute(int track) {
    _record();
    timeline.tracks[track].muted = !timeline.tracks[track].muted;
    notifyListeners();
  }

  /// Remove one clip.
  void removeClip(int track, int index) {
    _record();
    timeline.tracks[track].clips.removeAt(index);
    notifyListeners();
  }

  /// Move a clip along the timeline (drag-in-time). [startMs] is clamped to ≥ 0.
  /// Consecutive moves of the same clip coalesce into a single undo entry.
  void moveClip(int track, int index, double startMs) {
    _coalesced(('move', track, index));
    final clips = timeline.tracks[track].clips;
    clips[index] = clips[index].copyWith(startMs: startMs < 0 ? 0 : startMs);
    notifyListeners();
  }

  /// Set a clip's linear [gain] (0 = silent). A slider sweep coalesces to one
  /// undo entry.
  void setClipGain(int track, int index, double gain) {
    _coalesced(('gain', track, index));
    final clips = timeline.tracks[track].clips;
    clips[index] = clips[index].copyWith(gain: gain < 0 ? 0 : gain);
    notifyListeners();
  }

  /// Set a clip's fade-in / fade-out ramp length in ms (each clamped to ≥ 0).
  /// Pass only the one you're changing; a slider sweep coalesces per side.
  void setClipFades(
    int track,
    int index, {
    double? fadeInMs,
    double? fadeOutMs,
  }) {
    _coalesced(('fade', track, index, fadeInMs != null));
    final clips = timeline.tracks[track].clips;
    clips[index] = clips[index].copyWith(
      fadeInMs: fadeInMs == null ? null : (fadeInMs < 0 ? 0 : fadeInMs),
      fadeOutMs: fadeOutMs == null ? null : (fadeOutMs < 0 ? 0 : fadeOutMs),
    );
    notifyListeners();
  }

  /// A clip's current gain / fade lengths.
  double clipGain(int track, int index) =>
      timeline.tracks[track].clips[index].gain;
  double clipFadeInMs(int track, int index) =>
      timeline.tracks[track].clips[index].fadeInMs;
  double clipFadeOutMs(int track, int index) =>
      timeline.tracks[track].clips[index].fadeOutMs;

  /// A clip's start on the timeline, in ms.
  double clipStartMs(int track, int index) =>
      timeline.tracks[track].clips[index].startMs;

  /// A clip's duration in ms — its render length, taken from the per-source
  /// cache (rendering once if cold, then O(1)). Cheap after the first bake,
  /// which warms the same cache. Used to draw clips to scale.
  double clipDurationMs(int track, int index) {
    final source = timeline.tracks[track].clips[index].source;
    final pcm = _cache.putIfAbsent(
      source.cacheKey,
      () => source.render(kDawSampleRate),
    );
    return pcm.length * 1000 / kDawSampleRate;
  }

  /// Whether a clip is already a baked audio take (a [SampleSource]) rather than
  /// a live "vector" source that re-renders on edit.
  bool isClipFrozen(int track, int index) =>
      timeline.tracks[track].clips[index].source is SampleSource;

  /// **Convert** (freeze) a live clip to a fixed audio take: bake its current
  /// render and replace the vector source with a [SampleSource] of it. The clip
  /// keeps its place/gain/mute but stops tracking edits in its source module and
  /// needs no re-render. One of the maintainer's verbs — a mutable take made
  /// permanent. No-op if already frozen or silent.
  void freezeClip(int track, int index) {
    final clip = timeline.tracks[track].clips[index];
    if (clip.source is SampleSource) return;
    final pcm = _cache.putIfAbsent(
      clip.source.cacheKey,
      () => clip.source.render(kDawSampleRate),
    );
    if (pcm.isEmpty) return;
    _record();
    timeline.tracks[track].clips[index] = Clip(
      source: SampleSource(pcm),
      startMs: clip.startMs,
      gain: clip.gain,
      muted: clip.muted,
    );
    notifyListeners();
  }

  /// **Merge** clips into one baked audio take, preserving their relative
  /// timing: the group renders (unlimited, so the master limiter still applies
  /// once at final bake) to a single [SampleSource] placed at the earliest
  /// start. Returns null and changes nothing if the group is silent.
  Clip? _mergeGroup(List<Clip> clips) {
    final live = clips.where((c) => !c.muted).toList();
    if (live.isEmpty) return null;
    var minStart = double.infinity;
    for (final c in live) {
      if (c.startMs < minStart) minStart = c.startMs;
    }
    final shifted = [
      for (final c in live) c.copyWith(startMs: c.startMs - minStart),
    ];
    final pcm = renderTimeline(
      DawTimeline(tracks: [DawTrack(clips: shifted)]),
      cache: _cache,
      limit: false,
    );
    if (pcm.isEmpty) return null;
    return Clip(source: SampleSource(pcm), startMs: minStart);
  }

  /// Merge one track's clips into a single audio take on that track.
  void mergeTrack(int track) {
    _record();
    final merged = _mergeGroup(timeline.tracks[track].clips);
    timeline.tracks[track].clips
      ..clear()
      ..addAll([if (merged != null) merged]);
    notifyListeners();
  }

  /// Merge **every** clip across all tracks into one audio take on track 0
  /// (\"one or many, including all\"). Other lanes are left empty.
  void mergeAll() {
    _record();
    final all = [for (final t in timeline.tracks) ...t.clips];
    final merged = _mergeGroup(all);
    for (final t in timeline.tracks) {
      t.clips.clear();
    }
    if (merged != null) timeline.tracks[0].clips.add(merged);
    notifyListeners();
  }

  /// Drop every clip (and the render cache).
  void clear() {
    _record();
    for (final t in timeline.tracks) {
      t.clips.clear();
    }
    _nextStartMs = 0;
    _cache.clear();
    notifyListeners();
  }

  /// Bake the whole arrangement to one mono PCM buffer (only changed clips
  /// re-render, thanks to the per-source cache).
  Float64List bake() => renderTimeline(timeline, cache: _cache);
}

/// A structural snapshot of the arrangement for undo/redo.
class _Snapshot {
  _Snapshot({required this.tracks, required this.nextStartMs});
  final List<DawTrack> tracks;
  final double nextStartMs;
}
