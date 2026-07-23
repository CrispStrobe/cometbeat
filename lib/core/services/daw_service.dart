// lib/core/services/daw_service.dart
//
// The shared Multitrack (DAW) arrangement. Any module adds clips to it via
// "Send to DAW"; the Multitrack screen displays + bakes it. App-wide (a
// Provider), so a clip sent from the DrumKit or Song Book is still there when
// you open the arranger, and successive sends accumulate into one project.

import 'dart:math' as math;

import 'package:comet_beat/core/audio/daw_project.dart';
import 'package:comet_beat/core/audio/daw_sources.dart' show ScoreSource;
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show MultiPartScore;
import 'package:flutter/foundation.dart';

typedef DawClipTarget = ({int track, int index});
typedef DawClipCopy = ({int track, Clip clip});

class DawService extends ChangeNotifier {
  /// The arrangement — starts with two empty named lanes.
  final DawTimeline timeline = DawTimeline(
    tracks: [DawTrack(name: 'A'), DawTrack(name: 'B')],
  );

  // Per-source render cache (the "vector" optimisation): an unchanged clip is
  // served from here instead of re-rendering on every bake.
  final Map<Object, Float64List> _cache = {};

  // Downsampled peaks per (source, trim, resolution) for drawing a clip's
  // waveform without re-scanning the PCM on every rebuild.
  final Map<String, List<double>> _peaks = {};

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
        effects: _cloneEffectChain(timeline.effects),
        buses: _cloneBuses(timeline.buses),
        tracks: [
          for (final t in timeline.tracks)
            DawTrack(
              name: t.name,
              gain: t.gain,
              muted: t.muted,
              soloed: t.soloed,
              instrument: t.instrument,
              busIndex: t.busIndex,
              busSends: {...t.busSends},
              effect: t.effect,
              effects: [...t.effects],
              clips: [...t.clips],
            ),
        ],
        nextStartMs: _nextStartMs,
      );

  void _restore(_Snapshot s) {
    timeline.effects = _cloneEffectChain(s.effects);
    timeline.buses
      ..clear()
      ..addAll(_cloneBuses(s.buses));
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
    // An engraved clip with no voice of its own adopts the lane's instrument, so
    // a track behaves like an instrument lane.
    final lane = timeline.tracks[track];
    var placed = source;
    if (lane.instrument != null &&
        source is ScoreSource &&
        source.instrument == null) {
      placed = source.withInstrument(lane.instrument);
    }
    lane.clips.add(Clip(source: placed, startMs: _nextStartMs));
    _nextStartMs += 2000;
    notifyListeners();
  }

  /// Append a new empty track (auto-named by position).
  void addTrack() {
    _record();
    timeline.tracks.add(DawTrack(name: '${timeline.tracks.length + 1}'));
    notifyListeners();
  }

  /// Remove a whole track and its clips. Keeps at least one track so the
  /// arranger always has a lane.
  void removeTrack(int track) {
    if (timeline.tracks.length <= 1) return;
    _record();
    timeline.tracks.removeAt(track);
    notifyListeners();
  }

  /// Rename a track.
  void renameTrack(int track, String name) {
    _record();
    timeline.tracks[track].name = name;
    notifyListeners();
  }

  String trackName(int track) => timeline.tracks[track].name;

  /// Mute / unmute a whole track.
  void toggleTrackMute(int track) {
    _record();
    timeline.tracks[track].muted = !timeline.tracks[track].muted;
    notifyListeners();
  }

  /// Set a whole track's linear volume [gain] (0 = silent). A fader sweep
  /// coalesces to one undo entry.
  void setTrackGain(int track, double gain) {
    _coalesced(('trackGain', track));
    timeline.tracks[track].gain = gain < 0 ? 0 : gain;
    notifyListeners();
  }

  double trackGain(int track) => timeline.tracks[track].gain;

  /// Solo / unsolo a track. While any track is soloed, only soloed tracks are
  /// heard — the quickest way to isolate one lane.
  void toggleTrackSolo(int track) {
    _record();
    timeline.tracks[track].soloed = !timeline.tracks[track].soloed;
    notifyListeners();
  }

  bool isTrackSoloed(int track) => timeline.tracks[track].soloed;

  /// Remove one clip.
  void removeClip(int track, int index) {
    _record();
    timeline.tracks[track].clips.removeAt(index);
    notifyListeners();
  }

  /// Duplicate a clip, dropping the copy on the same track right after the
  /// original (same source/gain/fades/trim). Cheap — the copy shares the
  /// source's cache entry.
  void duplicateClip(int track, int index) {
    _record();
    final clips = timeline.tracks[track].clips;
    final clip = clips[index];
    final pcm = _cache.putIfAbsent(
      clip.source.cacheKey,
      () => clip.source.render(kDawSampleRate),
    );
    final dur = trimmedDurationMs(clip, pcm);
    clips.insert(index + 1, clip.copyWith(startMs: clip.startMs + dur));
    notifyListeners();
  }

  List<DawClipTarget> pasteClipCopies(
    Iterable<DawClipCopy> copies,
    double atMs,
  ) {
    final valid = [
      for (final copy in copies)
        if (copy.track >= 0 && copy.track < timeline.tracks.length) copy,
    ];
    if (valid.isEmpty) return const [];
    final minStart = valid.fold<double>(
      double.infinity,
      (min, copy) => math.min(min, copy.clip.startMs),
    );
    final offset = (atMs < 0 ? 0.0 : atMs) - minStart;
    _record();
    final pasted = <DawClipTarget>[];
    for (final copy in valid) {
      final clips = timeline.tracks[copy.track].clips;
      final newIndex = clips.length;
      clips.add(
        copy.clip.copyWith(
          startMs: math.max(0, copy.clip.startMs + offset),
          effects: _cloneEffectChain(copy.clip.effects),
        ),
      );
      pasted.add((track: copy.track, index: newIndex));
    }
    notifyListeners();
    return pasted;
  }

  /// Whether the clip spans [atTimelineMs] with room to split on both sides —
  /// the UI enables "Split at playhead" only then.
  bool canSplitClip(int track, int index, double atTimelineMs) {
    if (track >= timeline.tracks.length) return false;
    final clips = timeline.tracks[track].clips;
    if (index >= clips.length) return false;
    final clip = clips[index];
    final offset = atTimelineMs - clip.startMs;
    return offset > _minSplitMs &&
        offset < clipDurationMs(track, index) - _minSplitMs;
  }

  static const double _minSplitMs = 5;

  /// Split the clip at absolute timeline position [atTimelineMs] into two
  /// source-sharing clips (non-destructive — both are just trim windows onto the
  /// same render): the left keeps its start + fade-in and ends at the cut; the
  /// right is placed at the cut, plays from the cut to the original end, and
  /// keeps the fade-out. The seam carries no fade, so the split is inaudible.
  /// No-op when the cut isn't strictly inside the clip ([canSplitClip]).
  void splitClip(int track, int index, double atTimelineMs) {
    if (!canSplitClip(track, index, atTimelineMs)) return;
    _record();
    _splitClipAt(track, index, atTimelineMs);
    notifyListeners();
  }

  void _splitClipAt(int track, int index, double atTimelineMs) {
    final clips = timeline.tracks[track].clips;
    final clip = clips[index];
    final offset = atTimelineMs - clip.startMs; // ms into the played window
    final cut = clip.trimStartMs + offset; // the split point in source ms
    // Left: [trimStart, cut) — drop the fade-out at the seam.
    clips[index] = clip.copyWith(trimEndMs: cut, fadeOutMs: 0);
    // Right: [cut, original end), placed at the cut — drop the fade-in.
    clips.insert(
      index + 1,
      clip.copyWith(
        startMs: clip.startMs + offset,
        trimStartMs: cut,
        fadeInMs: 0,
      ),
    );
  }

  /// Project tempo — the snap grid is one beat at this tempo, so clips line up
  /// rhythmically rather than to an arbitrary millisecond grid.
  double bpm = 120;

  /// One beat in ms at [bpm].
  double get beatMs => 60000 / bpm;

  /// Drag-snap grid in ms (0 = off). When on, [moveClip] rounds a clip's start
  /// to the nearest [beatMs], so clips land on the beat.
  double snapMs = 0;

  bool get snapOn => snapMs > 0;

  /// Toggle drag-snapping on/off (a view preference — not an undoable edit).
  void toggleSnap() {
    snapMs = snapMs > 0 ? 0 : beatMs;
    notifyListeners();
  }

  /// Set the project tempo (clamped to a sane 40–300 BPM); if snapping is on,
  /// the grid follows the new beat length.
  void setBpm(double value) {
    bpm = value.clamp(40, 300);
    if (snapMs > 0) snapMs = beatMs;
    notifyListeners();
  }

  /// Move a clip along the timeline (drag-in-time). [startMs] is clamped to ≥ 0
  /// and snapped to [snapMs] when snapping is on. Consecutive moves of the same
  /// clip coalesce into a single undo entry.
  void moveClip(int track, int index, double startMs) {
    _coalesced(('move', track, index));
    var v = startMs < 0 ? 0.0 : startMs;
    if (snapMs > 0) v = (v / snapMs).round() * snapMs;
    final clips = timeline.tracks[track].clips;
    clips[index] = clips[index].copyWith(startMs: v);
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
    DawFadeCurve? fadeInCurve,
    DawFadeCurve? fadeOutCurve,
  }) {
    _coalesced(
      ('fade', track, index, fadeInMs != null || fadeInCurve != null),
    );
    final clips = timeline.tracks[track].clips;
    clips[index] = clips[index].copyWith(
      fadeInMs: fadeInMs == null ? null : (fadeInMs < 0 ? 0 : fadeInMs),
      fadeOutMs: fadeOutMs == null ? null : (fadeOutMs < 0 ? 0 : fadeOutMs),
      fadeInCurve: fadeInCurve,
      fadeOutCurve: fadeOutCurve,
    );
    notifyListeners();
  }

  /// Set a clip's non-destructive trim window (ms into the source render).
  /// Pass only the edge you're changing; a slider sweep coalesces per side.
  /// The source is untouched, so clearing the trim restores the full clip.
  void setClipTrim(
    int track,
    int index, {
    double? trimStartMs,
    double? trimEndMs,
  }) {
    _coalesced(('trim', track, index, trimStartMs != null));
    final clips = timeline.tracks[track].clips;
    clips[index] = clips[index].copyWith(
      trimStartMs:
          trimStartMs == null ? null : (trimStartMs < 0 ? 0 : trimStartMs),
      trimEndMs: trimEndMs == null ? null : (trimEndMs < 0 ? 0 : trimEndMs),
    );
    notifyListeners();
  }

  double clipTrimStartMs(int track, int index) =>
      timeline.tracks[track].clips[index].trimStartMs;
  double clipTrimEndMs(int track, int index) =>
      timeline.tracks[track].clips[index].trimEndMs;

  /// The full (untrimmed) source length in ms — the ceiling for a trim slider.
  double clipSourceMs(int track, int index) {
    final source = timeline.tracks[track].clips[index].source;
    final pcm = _cache.putIfAbsent(
      source.cacheKey,
      () => source.render(kDawSampleRate),
    );
    return pcm.length * 1000 / kDawSampleRate;
  }

  /// Peak amplitudes (0..1) for a clip's audible (trimmed) audio, downsampled
  /// to [buckets] — for drawing its waveform. Memoised per source/trim/res, so
  /// a rebuild is O(1) after the first scan; recomputed only when the source or
  /// trim changes (its key changes).
  List<double> clipPeaks(int track, int index, {int buckets = 120}) {
    final clip = timeline.tracks[track].clips[index];
    final n = buckets < 1 ? 1 : buckets;
    final key = '${clip.source.cacheKey}|${clip.trimStartMs}|${clip.trimEndMs}|'
        '${Object.hashAll(clip.effects.map((e) => e.cacheKey))}|$n';
    return _peaks.putIfAbsent(key, () {
      final rendered = _cache.putIfAbsent(
        clip.source.cacheKey,
        () => clip.source.render(kDawSampleRate),
      );
      final dry = trimmedPcm(clip, rendered);
      final pcm = clip.effects.isEmpty
          ? dry
          : applyClipEffectChain(dry, clip.effects, kDawSampleRate);
      final out = List<double>.filled(n, 0);
      if (pcm.isEmpty) return out;
      for (var b = 0; b < n; b++) {
        final lo = pcm.length * b ~/ n;
        final hi = pcm.length * (b + 1) ~/ n;
        var peak = 0.0;
        for (var i = lo; i < hi; i++) {
          final a = pcm[i].abs();
          if (a > peak) peak = a;
        }
        out[b] = peak > 1 ? 1 : peak;
      }
      return out;
    });
  }

  /// A clip's current gain / fade lengths.
  double clipGain(int track, int index) =>
      timeline.tracks[track].clips[index].gain;
  double clipFadeInMs(int track, int index) =>
      timeline.tracks[track].clips[index].fadeInMs;
  double clipFadeOutMs(int track, int index) =>
      timeline.tracks[track].clips[index].fadeOutMs;
  DawFadeCurve clipFadeInCurve(int track, int index) =>
      timeline.tracks[track].clips[index].fadeInCurve;
  DawFadeCurve clipFadeOutCurve(int track, int index) =>
      timeline.tracks[track].clips[index].fadeOutCurve;

  /// A clip's start on the timeline, in ms.
  double clipStartMs(int track, int index) =>
      timeline.tracks[track].clips[index].startMs;

  /// A clip's duration in ms — its render length, taken from the per-source
  /// cache (rendering once if cold, then O(1)). Cheap after the first bake,
  /// which warms the same cache. Used to draw clips to scale.
  double clipDurationMs(int track, int index) {
    final clip = timeline.tracks[track].clips[index];
    final pcm = _cache.putIfAbsent(
      clip.source.cacheKey,
      () => clip.source.render(kDawSampleRate),
    );
    return trimmedDurationMs(clip, pcm); // to-scale even when trimmed
  }

  bool canCrossfadeWithNext(int track, int index) {
    if (track < 0 || track >= timeline.tracks.length) return false;
    final clips = timeline.tracks[track].clips;
    return index >= 0 && index + 1 < clips.length;
  }

  /// Create a same-track crossfade from clip [index] into the following clip.
  /// The next clip is moved left so it overlaps the selected clip by [overlapMs],
  /// then the selected clip gets a fade-out and the next clip gets a fade-in of
  /// the same length. This is non-destructive: sources/trims stay untouched.
  void crossfadeWithNext(int track, int index, {double overlapMs = 250}) {
    if (!canCrossfadeWithNext(track, index)) return;
    final clips = timeline.tracks[track].clips;
    final a = clips[index];
    final b = clips[index + 1];
    final aDur = clipDurationMs(track, index);
    final bDur = clipDurationMs(track, index + 1);
    if (aDur <= 0 || bDur <= 0) return;
    final maxOverlap = math.min(aDur, bDur);
    final minOverlap = math.min(5.0, maxOverlap);
    final overlap = overlapMs.clamp(minOverlap, maxOverlap).toDouble();
    _record();
    final aEnd = a.startMs + aDur;
    clips[index] = a.copyWith(fadeOutMs: overlap);
    clips[index + 1] = b.copyWith(
      startMs: math.max(0, aEnd - overlap),
      fadeInMs: overlap,
    );
    notifyListeners();
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
      fadeInMs: clip.fadeInMs,
      fadeOutMs: clip.fadeOutMs,
      fadeInCurve: clip.fadeInCurve,
      fadeOutCurve: clip.fadeOutCurve,
      trimStartMs: clip.trimStartMs,
      trimEndMs: clip.trimEndMs,
      effects: clip.effects,
    );
    notifyListeners();
  }

  /// **Reverse** a clip: bake what it currently plays (its trimmed window) to
  /// audio and flip it end-to-end — a fun creative effect (a backwards beat /
  /// sample). Like [freezeClip], the result is a fixed [SampleSource] take, so
  /// the trim is folded in (reset) while gain/mute/fades carry over. Reversing
  /// twice restores the audio. No-op on a silent clip.
  void reverseClip(int track, int index) {
    final clip = timeline.tracks[track].clips[index];
    final rendered = _cache.putIfAbsent(
      clip.source.cacheKey,
      () => clip.source.render(kDawSampleRate),
    );
    final window = trimmedPcm(clip, rendered); // what actually plays
    if (window.isEmpty) return;
    _record();
    final flipped = Float64List(window.length);
    for (var i = 0; i < window.length; i++) {
      flipped[i] = window[window.length - 1 - i];
    }
    timeline.tracks[track].clips[index] = Clip(
      source: SampleSource(flipped),
      startMs: clip.startMs,
      gain: clip.gain,
      muted: clip.muted,
      fadeInMs: clip.fadeInMs,
      fadeOutMs: clip.fadeOutMs,
      fadeInCurve: clip.fadeInCurve,
      fadeOutCurve: clip.fadeOutCurve,
      effects: clip.effects,
    );
    notifyListeners();
  }

  /// **Re-speed** a clip: bake what it plays and resample it by [factor] — a
  /// tape-style effect where speed and pitch move together (2× = faster + an
  /// octave up + half as long; 0.5× = slower + an octave down + twice as long).
  /// Like [reverseClip] the result is a fixed [SampleSource] take; taps compound
  /// (Faster twice = 4×). No-op on a silent clip or a non-positive [factor].
  void resampleClip(int track, int index, double factor) {
    if (factor <= 0) return;
    final clip = timeline.tracks[track].clips[index];
    final rendered = _cache.putIfAbsent(
      clip.source.cacheKey,
      () => clip.source.render(kDawSampleRate),
    );
    final window = trimmedPcm(clip, rendered);
    if (window.isEmpty) return;
    final outLen = (window.length / factor).round();
    if (outLen < 1) return;
    _record();
    // Linear-interpolated resample: out[i] samples the source at i * factor.
    final out = Float64List(outLen);
    for (var i = 0; i < outLen; i++) {
      final pos = i * factor;
      final j = pos.floor();
      if (j + 1 < window.length) {
        final frac = pos - j;
        out[i] = window[j] * (1 - frac) + window[j + 1] * frac;
      } else {
        out[i] = window[window.length - 1];
      }
    }
    timeline.tracks[track].clips[index] = Clip(
      source: SampleSource(out),
      startMs: clip.startMs,
      gain: clip.gain,
      muted: clip.muted,
      fadeInMs: clip.fadeInMs,
      fadeOutMs: clip.fadeOutMs,
      fadeInCurve: clip.fadeInCurve,
      fadeOutCurve: clip.fadeOutCurve,
      effects: clip.effects,
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

  // --- Instrument sound (score clips) ---------------------------------------
  // A clip that wraps engraved music ([ScoreSource]) can be voiced through an
  // instrument picked from the assets library; baked audio (samples), drum,
  // groove and tracker clips carry their own sound and are left untouched.

  /// Whether the clip is engraved music that can be re-voiced with an instrument.
  bool isScoreClip(int track, int index) =>
      timeline.tracks[track].clips[index].source is ScoreSource;

  /// The instrument a score clip currently plays through (null = default synth,
  /// or a non-score clip).
  TrackerInstrument? clipInstrument(int track, int index) {
    final src = timeline.tracks[track].clips[index].source;
    return src is ScoreSource ? src.instrument : null;
  }

  /// The engraved music behind a score clip (null on a non-score clip) — so it
  /// can be opened/edited in the Score or Tab editor and sent back.
  MultiPartScore? clipScore(int track, int index) {
    final src = timeline.tracks[track].clips[index].source;
    return src is ScoreSource ? src.score : null;
  }

  /// The raw source of a clip — captured before opening it in an editor so the
  /// edit can be routed back to the SAME clip via [replaceScoreClipSource],
  /// robustly against the clip being moved/reordered meanwhile.
  ClipSource clipSourceAt(int track, int index) =>
      timeline.tracks[track].clips[index].source;

  /// Replace (in place) the clip whose source is [oldSource] with the edited
  /// [score], preserving its placement/gain/fades/trim and its voice — the "send
  /// back" half of an in-editor round-trip. If that clip is gone, the edit lands
  /// as a new clip so nothing is lost.
  void replaceScoreClipSource(ClipSource oldSource, MultiPartScore score) {
    final inst = oldSource is ScoreSource ? oldSource.instrument : null;
    for (final t in timeline.tracks) {
      for (var i = 0; i < t.clips.length; i++) {
        if (identical(t.clips[i].source, oldSource)) {
          _record();
          t.clips[i] = _reSource(
            t.clips[i],
            ScoreSource(score, instrument: inst),
          );
          notifyListeners();
          return;
        }
      }
    }
    addClip(ScoreSource(score, instrument: inst));
  }

  /// Re-source [clip] onto [source], preserving placement/gain/mute/fades/trim.
  Clip _reSource(Clip clip, ScoreSource source) => Clip(
        source: source,
        startMs: clip.startMs,
        gain: clip.gain,
        muted: clip.muted,
        fadeInMs: clip.fadeInMs,
        fadeOutMs: clip.fadeOutMs,
        fadeInCurve: clip.fadeInCurve,
        fadeOutCurve: clip.fadeOutCurve,
        trimStartMs: clip.trimStartMs,
        trimEndMs: clip.trimEndMs,
        effects: clip.effects,
      );

  /// Voice one score clip through [inst] (null = default synth). No-op on a
  /// non-score clip.
  void setClipInstrument(int track, int index, TrackerInstrument? inst) {
    final clips = timeline.tracks[track].clips;
    final src = clips[index].source;
    if (src is! ScoreSource) return;
    _record();
    clips[index] = _reSource(clips[index], src.withInstrument(inst));
    notifyListeners();
  }

  /// The lane's default instrument voice (null = default synth).
  TrackerInstrument? trackInstrument(int track) =>
      timeline.tracks[track].instrument;

  /// Set [track]'s instrument sound: it becomes the lane default (so new score
  /// clips adopt it) AND re-voices every score clip already on the lane. Baked
  /// audio / drum / groove / tracker clips are unaffected.
  void setTrackInstrument(int track, TrackerInstrument? inst) {
    _record();
    final lane = timeline.tracks[track];
    lane.instrument = inst;
    for (var i = 0; i < lane.clips.length; i++) {
      final src = lane.clips[i].source;
      if (src is ScoreSource) {
        lane.clips[i] = _reSource(lane.clips[i], src.withInstrument(inst));
      }
    }
    notifyListeners();
  }

  /// The lane's legacy single insert. Prefer [trackEffects] for new UI.
  TrackEffect trackEffect(int track) => timeline.tracks[track].effect;

  /// Set [track]'s legacy insert effect. Applied as a one-module track chain.
  void setTrackEffect(int track, TrackEffect effect) {
    final chain = trackEffectChainForLegacy(effect);
    if (timeline.tracks[track].effect == effect &&
        _sameEffectChain(timeline.tracks[track].effects, chain)) {
      return;
    }
    _record();
    final lane = timeline.tracks[track];
    lane.effect = effect;
    lane.effects = chain;
    notifyListeners();
  }

  List<DawClipEffect> trackEffects(int track) => timeline.tracks[track].effects;

  void addTrackEffect(int track, DawClipEffectType type) {
    addTrackEffectToTracks([track], type);
  }

  void addTrackEffectToTracks(Iterable<int> tracks, DawClipEffectType type) {
    final indices = _validTrackIndices(tracks);
    if (indices.isEmpty) return;
    _record();
    for (final i in indices) {
      final lane = timeline.tracks[i];
      lane
        ..effect = TrackEffect.none
        ..effects = [...lane.effects, defaultDawClipEffect(type)];
    }
    notifyListeners();
  }

  void applyTrackEffectPreset(
    int track,
    DawClipEffectPreset preset, {
    bool append = false,
  }) {
    applyTrackEffectPresetToTracks([track], preset, append: append);
  }

  void applyTrackEffectPresetToTracks(
    Iterable<int> tracks,
    DawClipEffectPreset preset, {
    bool append = false,
  }) {
    final indices = _validTrackIndices(tracks);
    if (indices.isEmpty) return;
    _record();
    final chain = dawClipEffectPresetChain(preset);
    for (final i in indices) {
      final lane = timeline.tracks[i];
      lane
        ..effect = TrackEffect.none
        ..effects = append ? [...lane.effects, ...chain] : [...chain];
    }
    notifyListeners();
  }

  void copyTrackEffectsToTracks(int sourceTrack, Iterable<int> tracks) {
    if (sourceTrack < 0 || sourceTrack >= timeline.tracks.length) return;
    final indices = _validTrackIndices(tracks);
    if (indices.isEmpty) return;
    _record();
    final chain = [...timeline.tracks[sourceTrack].effects];
    for (final i in indices) {
      final lane = timeline.tracks[i];
      lane
        ..effect = TrackEffect.none
        ..effects = _cloneEffectChain(chain);
    }
    notifyListeners();
  }

  void removeTrackEffect(int track, int effectIndex) {
    final lane = timeline.tracks[track];
    if (effectIndex < 0 || effectIndex >= lane.effects.length) return;
    _record();
    lane
      ..effect = TrackEffect.none
      ..effects = ([...lane.effects]..removeAt(effectIndex));
    notifyListeners();
  }

  void moveTrackEffect(int track, int effectIndex, int delta) {
    final lane = timeline.tracks[track];
    final to = effectIndex + delta;
    if (effectIndex < 0 ||
        effectIndex >= lane.effects.length ||
        to < 0 ||
        to >= lane.effects.length ||
        delta == 0) {
      return;
    }
    _record();
    final effects = [...lane.effects];
    final fx = effects.removeAt(effectIndex);
    effects.insert(to, fx);
    lane
      ..effect = TrackEffect.none
      ..effects = effects;
    notifyListeners();
  }

  void toggleTrackEffect(int track, int effectIndex) {
    final lane = timeline.tracks[track];
    if (effectIndex < 0 || effectIndex >= lane.effects.length) return;
    _record();
    final effects = [...lane.effects];
    effects[effectIndex] = effects[effectIndex].copyWith(
      enabled: !effects[effectIndex].enabled,
    );
    lane
      ..effect = TrackEffect.none
      ..effects = effects;
    notifyListeners();
  }

  void setTrackEffectParam(
    int track,
    int effectIndex,
    String key,
    double value,
  ) {
    final lane = timeline.tracks[track];
    if (effectIndex < 0 || effectIndex >= lane.effects.length) return;
    _coalesced(('trackFxParam', track, effectIndex, key));
    final effects = [...lane.effects];
    final fx = effects[effectIndex];
    effects[effectIndex] = fx.copyWith(params: {...fx.params, key: value});
    lane
      ..effect = TrackEffect.none
      ..effects = effects;
    notifyListeners();
  }

  List<DawClipEffect> masterEffects() => timeline.effects;

  List<DawBus> buses() => timeline.buses;

  void addBus({String? name}) {
    _record();
    timeline.buses
        .add(DawBus(name: name ?? 'Bus ${timeline.buses.length + 1}'));
    notifyListeners();
  }

  void renameBus(int bus, String name) {
    if (bus < 0 || bus >= timeline.buses.length) return;
    _record();
    timeline.buses[bus].name = name;
    notifyListeners();
  }

  void removeBus(int bus) {
    if (bus < 0 || bus >= timeline.buses.length) return;
    _record();
    timeline.buses.removeAt(bus);
    for (final track in timeline.tracks) {
      final route = track.busIndex;
      if (route == bus) {
        track.busIndex = null;
      } else if (route != null && route > bus) {
        track.busIndex = route - 1;
      }
      track.busSends = _shiftSendsAfterBusRemoval(track.busSends, bus);
    }
    notifyListeners();
  }

  int? trackBus(int track) => timeline.tracks[track].busIndex;

  void setTrackBus(int track, int? bus) {
    setTrackBusForTracks([track], bus);
  }

  void setTrackBusForTracks(Iterable<int> tracks, int? bus) {
    final indices = _validTrackIndices(tracks);
    if (indices.isEmpty) return;
    final route =
        bus != null && bus >= 0 && bus < timeline.buses.length ? bus : null;
    _record();
    for (final i in indices) {
      timeline.tracks[i].busIndex = route;
    }
    notifyListeners();
  }

  double trackSend(int track, int bus) {
    if (track < 0 || track >= timeline.tracks.length) return 0;
    return timeline.tracks[track].busSends[bus] ?? 0;
  }

  void setTrackSend(int track, int bus, double amount) {
    setTrackSendForTracks([track], bus, amount);
  }

  void setTrackSendForTracks(Iterable<int> tracks, int bus, double amount) {
    final indices = _validTrackIndices(tracks);
    if (indices.isEmpty || bus < 0 || bus >= timeline.buses.length) return;
    final gain = amount.clamp(0.0, 1.5).toDouble();
    _coalesced(('trackSend', bus, indices.join(',')));
    for (final i in indices) {
      final sends = {...timeline.tracks[i].busSends};
      if (gain <= 0) {
        sends.remove(bus);
      } else {
        sends[bus] = gain;
      }
      timeline.tracks[i].busSends = sends;
    }
    notifyListeners();
  }

  List<DawClipEffect> busEffects(int bus) => timeline.buses[bus].effects;

  void addBusEffect(int bus, DawClipEffectType type) {
    if (bus < 0 || bus >= timeline.buses.length) return;
    _record();
    timeline.buses[bus].effects.add(defaultDawClipEffect(type));
    notifyListeners();
  }

  void applyBusEffectPreset(
    int bus,
    DawClipEffectPreset preset, {
    bool append = false,
  }) {
    if (bus < 0 || bus >= timeline.buses.length) return;
    _record();
    final chain = dawClipEffectPresetChain(preset);
    timeline.buses[bus].effects = append
        ? [...timeline.buses[bus].effects, ..._cloneEffectChain(chain)]
        : _cloneEffectChain(chain);
    notifyListeners();
  }

  void removeBusEffect(int bus, int effectIndex) {
    if (bus < 0 || bus >= timeline.buses.length) return;
    final effects = timeline.buses[bus].effects;
    if (effectIndex < 0 || effectIndex >= effects.length) return;
    _record();
    timeline.buses[bus].effects = [...effects]..removeAt(effectIndex);
    notifyListeners();
  }

  void moveBusEffect(int bus, int effectIndex, int delta) {
    if (bus < 0 || bus >= timeline.buses.length) return;
    final effects = timeline.buses[bus].effects;
    final to = effectIndex + delta;
    if (effectIndex < 0 ||
        effectIndex >= effects.length ||
        to < 0 ||
        to >= effects.length ||
        delta == 0) {
      return;
    }
    _record();
    final next = [...effects];
    final fx = next.removeAt(effectIndex);
    next.insert(to, fx);
    timeline.buses[bus].effects = next;
    notifyListeners();
  }

  void toggleBusEffect(int bus, int effectIndex) {
    if (bus < 0 || bus >= timeline.buses.length) return;
    final effects = timeline.buses[bus].effects;
    if (effectIndex < 0 || effectIndex >= effects.length) return;
    _record();
    final next = [...effects];
    next[effectIndex] = next[effectIndex].copyWith(
      enabled: !next[effectIndex].enabled,
    );
    timeline.buses[bus].effects = next;
    notifyListeners();
  }

  void setBusEffectParam(int bus, int effectIndex, String key, double value) {
    if (bus < 0 || bus >= timeline.buses.length) return;
    final effects = timeline.buses[bus].effects;
    if (effectIndex < 0 || effectIndex >= effects.length) return;
    _coalesced(('busFxParam', bus, effectIndex, key));
    final next = [...effects];
    final fx = next[effectIndex];
    next[effectIndex] = fx.copyWith(params: {...fx.params, key: value});
    timeline.buses[bus].effects = next;
    notifyListeners();
  }

  void addMasterEffect(DawClipEffectType type) {
    _record();
    timeline.effects.add(defaultDawClipEffect(type));
    notifyListeners();
  }

  void applyMasterEffectPreset(
    DawClipEffectPreset preset, {
    bool append = false,
  }) {
    _record();
    final chain = dawClipEffectPresetChain(preset);
    timeline.effects = append
        ? [...timeline.effects, ..._cloneEffectChain(chain)]
        : _cloneEffectChain(chain);
    notifyListeners();
  }

  void removeMasterEffect(int effectIndex) {
    if (effectIndex < 0 || effectIndex >= timeline.effects.length) return;
    _record();
    timeline.effects = [...timeline.effects]..removeAt(effectIndex);
    notifyListeners();
  }

  void moveMasterEffect(int effectIndex, int delta) {
    final to = effectIndex + delta;
    if (effectIndex < 0 ||
        effectIndex >= timeline.effects.length ||
        to < 0 ||
        to >= timeline.effects.length ||
        delta == 0) {
      return;
    }
    _record();
    final effects = [...timeline.effects];
    final fx = effects.removeAt(effectIndex);
    effects.insert(to, fx);
    timeline.effects = effects;
    notifyListeners();
  }

  void toggleMasterEffect(int effectIndex) {
    if (effectIndex < 0 || effectIndex >= timeline.effects.length) return;
    _record();
    final effects = [...timeline.effects];
    effects[effectIndex] = effects[effectIndex].copyWith(
      enabled: !effects[effectIndex].enabled,
    );
    timeline.effects = effects;
    notifyListeners();
  }

  void setMasterEffectParam(int effectIndex, String key, double value) {
    if (effectIndex < 0 || effectIndex >= timeline.effects.length) return;
    _coalesced(('masterFxParam', effectIndex, key));
    final effects = [...timeline.effects];
    final fx = effects[effectIndex];
    effects[effectIndex] = fx.copyWith(params: {...fx.params, key: value});
    timeline.effects = effects;
    notifyListeners();
  }

  List<int> _validTrackIndices(Iterable<int> tracks) {
    final seen = <int>{};
    final out = <int>[];
    for (final i in tracks) {
      if (i >= 0 && i < timeline.tracks.length && seen.add(i)) out.add(i);
    }
    return out;
  }

  bool _validClipTarget(int track, int index) =>
      track >= 0 &&
      track < timeline.tracks.length &&
      index >= 0 &&
      index < timeline.tracks[track].clips.length;

  List<DawClipTarget> _validClipTargets(Iterable<DawClipTarget> targets) {
    final seen = <String>{};
    final out = <DawClipTarget>[];
    for (final target in targets) {
      final key = '${target.track}:${target.index}';
      if (_validClipTarget(target.track, target.index) && seen.add(key)) {
        out.add(target);
      }
    }
    return out;
  }

  bool _canSplitClipWindow(double clipStart, double duration, double atMs) {
    final offset = atMs - clipStart;
    return offset > _minSplitMs && offset < duration - _minSplitMs;
  }

  bool _rangeHitsAnyClip(List<int> tracks, double startMs, double endMs) {
    for (final track in tracks) {
      for (var index = 0;
          index < timeline.tracks[track].clips.length;
          index++) {
        final clipStart = clipStartMs(track, index);
        final clipEnd = clipStart + clipDurationMs(track, index);
        if (clipEnd > startMs && clipStart < endMs) return true;
      }
    }
    return false;
  }

  List<DawClipEffect> _cloneEffectChain(List<DawClipEffect> chain) => [
        for (final fx in chain) fx.copyWith(params: {...fx.params}),
      ];

  List<DawBus> _cloneBuses(List<DawBus> buses) => [
        for (final bus in buses)
          DawBus(name: bus.name, effects: _cloneEffectChain(bus.effects)),
      ];

  Map<int, double> _shiftSendsAfterBusRemoval(
    Map<int, double> sends,
    int removedBus,
  ) {
    final shifted = <int, double>{};
    for (final send in sends.entries) {
      if (send.key == removedBus) continue;
      shifted[send.key > removedBus ? send.key - 1 : send.key] = send.value;
    }
    return shifted;
  }

  bool _sameEffectChain(List<DawClipEffect> a, List<DawClipEffect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].cacheKey != b[i].cacheKey) return false;
    }
    return true;
  }

  List<DawClipEffect> clipEffects(int track, int index) =>
      timeline.tracks[track].clips[index].effects;

  void addClipEffect(int track, int index, DawClipEffectType type) {
    addClipEffectToClips([(track: track, index: index)], type);
  }

  void addClipEffectToClips(
    Iterable<DawClipTarget> targets,
    DawClipEffectType type,
  ) {
    final validTargets = _validClipTargets(targets);
    if (validTargets.isEmpty) return;
    _record();
    for (final target in validTargets) {
      final clips = timeline.tracks[target.track].clips;
      final clip = clips[target.index];
      clips[target.index] = clip.copyWith(
        effects: [...clip.effects, defaultDawClipEffect(type)],
      );
    }
    _peaks.clear();
    notifyListeners();
  }

  void applyClipEffectPreset(
    int track,
    int index,
    DawClipEffectPreset preset, {
    bool append = false,
  }) {
    applyClipEffectPresetToClips(
      [(track: track, index: index)],
      preset,
      append: append,
    );
  }

  void applyClipEffectPresetToClips(
    Iterable<DawClipTarget> targets,
    DawClipEffectPreset preset, {
    bool append = false,
  }) {
    final validTargets = _validClipTargets(targets);
    if (validTargets.isEmpty) return;
    _record();
    final chain = dawClipEffectPresetChain(preset);
    for (final target in validTargets) {
      final clips = timeline.tracks[target.track].clips;
      final clip = clips[target.index];
      clips[target.index] = clip.copyWith(
        effects: append
            ? [...clip.effects, ..._cloneEffectChain(chain)]
            : _cloneEffectChain(chain),
      );
    }
    _peaks.clear();
    notifyListeners();
  }

  void copyClipEffectsToClips(
    int sourceTrack,
    int sourceIndex,
    Iterable<DawClipTarget> targets,
  ) {
    if (!_validClipTarget(sourceTrack, sourceIndex)) return;
    final validTargets = _validClipTargets(targets);
    if (validTargets.isEmpty) return;
    _record();
    final chain = timeline.tracks[sourceTrack].clips[sourceIndex].effects;
    for (final target in validTargets) {
      final clips = timeline.tracks[target.track].clips;
      clips[target.index] = clips[target.index].copyWith(
        effects: _cloneEffectChain(chain),
      );
    }
    _peaks.clear();
    notifyListeners();
  }

  int addClipEffectToRange(
    Iterable<int> tracks,
    double startMs,
    double endMs,
    DawClipEffectType type,
  ) {
    final effect = defaultDawClipEffect(type);
    return _applyClipEffectsToRange(
      tracks,
      startMs,
      endMs,
      (clip) => [
        ...clip.effects,
        effect.copyWith(params: {...effect.params}),
      ],
    );
  }

  int applyClipEffectPresetToRange(
    Iterable<int> tracks,
    double startMs,
    double endMs,
    DawClipEffectPreset preset, {
    bool append = false,
  }) {
    final chain = dawClipEffectPresetChain(preset);
    return _applyClipEffectsToRange(
      tracks,
      startMs,
      endMs,
      (clip) => append
          ? [...clip.effects, ..._cloneEffectChain(chain)]
          : _cloneEffectChain(chain),
    );
  }

  int multiplyClipGainInRange(
    Iterable<int> tracks,
    double startMs,
    double endMs,
    double multiplier,
  ) {
    final gain = multiplier < 0 ? 0.0 : multiplier;
    return _applyClipTransformToRange(
      tracks,
      startMs,
      endMs,
      (clip, _) => clip.copyWith(gain: clip.gain * gain),
    );
  }

  int setClipMutedInRange(
    Iterable<int> tracks,
    double startMs,
    double endMs,
    bool muted,
  ) =>
      _applyClipTransformToRange(
        tracks,
        startMs,
        endMs,
        (clip, _) => clip.copyWith(muted: muted),
      );

  int applyFadeInToRange(
    Iterable<int> tracks,
    double startMs,
    double endMs, [
    DawFadeCurve curve = DawFadeCurve.linear,
  ]) =>
      _applyClipTransformToRange(
        tracks,
        startMs,
        endMs,
        (clip, durationMs) => clip.copyWith(
          fadeInMs: durationMs,
          fadeInCurve: curve,
        ),
      );

  int applyFadeOutToRange(
    Iterable<int> tracks,
    double startMs,
    double endMs, [
    DawFadeCurve curve = DawFadeCurve.linear,
  ]) =>
      _applyClipTransformToRange(
        tracks,
        startMs,
        endMs,
        (clip, durationMs) => clip.copyWith(
          fadeOutMs: durationMs,
          fadeOutCurve: curve,
        ),
      );

  int _applyClipEffectsToRange(
    Iterable<int> tracks,
    double startMs,
    double endMs,
    List<DawClipEffect> Function(Clip clip) effectsFor,
  ) =>
      _applyClipTransformToRange(
        tracks,
        startMs,
        endMs,
        (clip, _) => clip.copyWith(effects: effectsFor(clip)),
      );

  int _applyClipTransformToRange(
    Iterable<int> tracks,
    double startMs,
    double endMs,
    Clip Function(Clip clip, double durationMs) transform,
  ) {
    final indices = _validTrackIndices(tracks);
    final rangeStart = math.min(startMs, endMs);
    final rangeEnd = math.max(startMs, endMs);
    if (indices.isEmpty || rangeEnd - rangeStart <= _minSplitMs) return 0;
    if (!_rangeHitsAnyClip(indices, rangeStart, rangeEnd)) return 0;

    _record();
    var changed = 0;
    for (final track in indices) {
      final clips = timeline.tracks[track].clips;
      var index = 0;
      while (index < clips.length) {
        final clip = clips[index];
        final duration = clipDurationMs(track, index);
        final clipStart = clip.startMs;
        final clipEnd = clipStart + duration;
        if (clipEnd <= rangeStart || clipStart >= rangeEnd) {
          index++;
          continue;
        }
        if (_canSplitClipWindow(clipStart, duration, rangeStart)) {
          _splitClipAt(track, index, rangeStart);
          index++;
          continue;
        }
        if (_canSplitClipWindow(clipStart, duration, rangeEnd)) {
          _splitClipAt(track, index, rangeEnd);
        }
        final target = clips[index];
        clips[index] = transform(target, clipDurationMs(track, index));
        changed++;
        index++;
      }
    }
    _peaks.clear();
    notifyListeners();
    return changed;
  }

  void removeClipEffect(int track, int index, int effectIndex) {
    final clips = timeline.tracks[track].clips;
    final clip = clips[index];
    if (effectIndex < 0 || effectIndex >= clip.effects.length) return;
    _record();
    final effects = [...clip.effects]..removeAt(effectIndex);
    clips[index] = clip.copyWith(effects: effects);
    _peaks.clear();
    notifyListeners();
  }

  void moveClipEffect(int track, int index, int effectIndex, int delta) {
    final clips = timeline.tracks[track].clips;
    final clip = clips[index];
    final to = effectIndex + delta;
    if (effectIndex < 0 ||
        effectIndex >= clip.effects.length ||
        to < 0 ||
        to >= clip.effects.length ||
        delta == 0) {
      return;
    }
    _record();
    final effects = [...clip.effects];
    final fx = effects.removeAt(effectIndex);
    effects.insert(to, fx);
    clips[index] = clip.copyWith(effects: effects);
    _peaks.clear();
    notifyListeners();
  }

  void toggleClipEffect(int track, int index, int effectIndex) {
    final clips = timeline.tracks[track].clips;
    final clip = clips[index];
    if (effectIndex < 0 || effectIndex >= clip.effects.length) return;
    _record();
    final effects = [...clip.effects];
    effects[effectIndex] = effects[effectIndex].copyWith(
      enabled: !effects[effectIndex].enabled,
    );
    clips[index] = clip.copyWith(effects: effects);
    _peaks.clear();
    notifyListeners();
  }

  void setClipEffectParam(
    int track,
    int index,
    int effectIndex,
    String key,
    double value,
  ) {
    final clips = timeline.tracks[track].clips;
    final clip = clips[index];
    if (effectIndex < 0 || effectIndex >= clip.effects.length) return;
    _coalesced(('clipFxParam', track, index, effectIndex, key));
    final effects = [...clip.effects];
    final fx = effects[effectIndex];
    effects[effectIndex] = fx.copyWith(params: {...fx.params, key: value});
    clips[index] = clip.copyWith(effects: effects);
    _peaks.clear();
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
    _peaks.clear();
    notifyListeners();
  }

  /// Bake the whole arrangement to one mono PCM buffer (only changed clips
  /// re-render, thanks to the per-source cache).
  Float64List bake() => renderTimeline(timeline, cache: _cache);

  // --- Project save / load ---------------------------------------------------

  /// Serialize the arrangement to a portable project string (every clip baked
  /// to PCM). Renders through the per-source cache so a save is cheap.
  String saveProject() => projectToJson(
        timeline,
        render: (s) => _cache.putIfAbsent(
          s.cacheKey,
          () => s.render(kDawSampleRate),
        ),
      );

  /// Replace the arrangement with a saved project. Throws [FormatException] on
  /// a bad file; on success the timeline, cache and undo history are reset.
  void loadProject(String json) {
    final loaded = projectFromJson(json); // may throw before we mutate anything
    timeline.effects = _cloneEffectChain(loaded.effects);
    timeline.buses
      ..clear()
      ..addAll(_cloneBuses(loaded.buses));
    timeline.tracks
      ..clear()
      ..addAll(loaded.tracks);
    if (timeline.tracks.isEmpty) {
      timeline.tracks.addAll([DawTrack(name: 'A'), DawTrack(name: 'B')]);
    }
    _cache.clear();
    _peaks.clear();
    _undo.clear();
    _redo.clear();
    _coalesceToken = null;
    _nextStartMs = 0;
    notifyListeners();
  }
}

/// A structural snapshot of the arrangement for undo/redo.
class _Snapshot {
  _Snapshot({
    required this.effects,
    required this.buses,
    required this.tracks,
    required this.nextStartMs,
  });
  final List<DawClipEffect> effects;
  final List<DawBus> buses;
  final List<DawTrack> tracks;
  final double nextStartMs;
}
