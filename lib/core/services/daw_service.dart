// lib/core/services/daw_service.dart
//
// The shared Multitrack (DAW) arrangement. Any module adds clips to it via
// "Send to DAW"; the Multitrack screen displays + bakes it. App-wide (a
// Provider), so a clip sent from the DrumKit or Song Book is still there when
// you open the arranger, and successive sends accumulate into one project.

import 'package:comet_beat/core/audio/daw_project.dart';
import 'package:comet_beat/core/audio/daw_sources.dart' show ScoreSource;
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:flutter/foundation.dart';

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
        tracks: [
          for (final t in timeline.tracks)
            DawTrack(
              name: t.name,
              gain: t.gain,
              muted: t.muted,
              soloed: t.soloed,
              instrument: t.instrument,
              effect: t.effect,
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
    final clips = timeline.tracks[track].clips;
    final clip = clips[index];
    final offset = atTimelineMs - clip.startMs; // ms into the played window
    final cut = clip.trimStartMs + offset; // the split point in source ms
    _record();
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
    notifyListeners();
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
  }) {
    _coalesced(('fade', track, index, fadeInMs != null));
    final clips = timeline.tracks[track].clips;
    clips[index] = clips[index].copyWith(
      fadeInMs: fadeInMs == null ? null : (fadeInMs < 0 ? 0 : fadeInMs),
      fadeOutMs: fadeOutMs == null ? null : (fadeOutMs < 0 ? 0 : fadeOutMs),
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

  /// Re-source [clip] onto [source], preserving placement/gain/mute/fades/trim.
  Clip _reSource(Clip clip, ScoreSource source) => Clip(
        source: source,
        startMs: clip.startMs,
        gain: clip.gain,
        muted: clip.muted,
        fadeInMs: clip.fadeInMs,
        fadeOutMs: clip.fadeOutMs,
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

  /// The lane's insert effect (reverb / echo / none).
  TrackEffect trackEffect(int track) => timeline.tracks[track].effect;

  /// Set [track]'s insert effect. Applied to the lane's summed audio at bake.
  void setTrackEffect(int track, TrackEffect effect) {
    if (timeline.tracks[track].effect == effect) return;
    _record();
    timeline.tracks[track].effect = effect;
    notifyListeners();
  }

  List<DawClipEffect> clipEffects(int track, int index) =>
      timeline.tracks[track].clips[index].effects;

  void addClipEffect(int track, int index, DawClipEffectType type) {
    _record();
    final clips = timeline.tracks[track].clips;
    final clip = clips[index];
    clips[index] = clip.copyWith(
      effects: [...clip.effects, defaultDawClipEffect(type)],
    );
    _peaks.clear();
    notifyListeners();
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
  _Snapshot({required this.tracks, required this.nextStartMs});
  final List<DawTrack> tracks;
  final double nextStartMs;
}
