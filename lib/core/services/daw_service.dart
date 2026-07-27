// lib/core/services/daw_service.dart
//
// The shared Multitrack (DAW) arrangement. Any module adds clips to it via
// "Send to DAW"; the Multitrack screen displays + bakes it. App-wide (a
// Provider), so a clip sent from the DrumKit or Song Book is still there when
// you open the arranger, and successive sends accumulate into one project.

import 'dart:math' as math;

import 'package:comet_beat/core/audio/daw_edits.dart';
import 'package:comet_beat/core/audio/daw_project.dart';
import 'package:comet_beat/core/audio/daw_sources.dart'
    show DrumSource, GrooveSource, ScoreSource, TrackerSource;
import 'package:comet_beat/core/audio/daw_tempo_map.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/loop_engine.dart'
    show DrumRowsPattern, GrooveSpec, LoopTiming;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:comet_beat/core/audio/tracker_song.dart' show TrackerSong;
import 'package:comet_beat/core/licensing/license_obligations.dart';
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
  final Map<String, Object> _peaks = {};

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
        // The tempo map is immutable and replaced wholesale, so holding the
        // instance IS the copy — and it must be here, or `setTempoAt`'s
        // `_record()` would promise an undo it cannot deliver.
        tempoMap: tempoMap,
        effects: _cloneEffectChain(timeline.effects),
        buses: _cloneBuses(timeline.buses),
        tracks: [
          for (final t in timeline.tracks)
            DawTrack(
              name: t.name,
              gain: t.gain,
              pan: t.pan,
              muted: t.muted,
              soloed: t.soloed,
              instrument: t.instrument,
              busIndex: t.busIndex,
              busSends: {...t.busSends},
              effect: t.effect,
              effects: [...t.effects],
              gainAutomation: _cloneAutomation(t.gainAutomation),
              clips: [...t.clips],
            ),
        ],
        nextStartMs: _nextStartMs,
        markers: [...timeline.markers],
      );

  void _restore(_Snapshot s) {
    tempoMap = s.tempoMap;
    timeline.effects = _cloneEffectChain(s.effects);
    timeline.buses
      ..clear()
      ..addAll(_cloneBuses(s.buses));
    timeline.tracks
      ..clear()
      ..addAll(s.tracks);
    timeline.markers
      ..clear()
      ..addAll(s.markers);
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
  void addClip(ClipSource source, {int track = 0, LicensedWork? provenance}) {
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
    lane.clips.add(
      Clip(source: placed, startMs: _nextStartMs, provenance: provenance),
    );
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

  /// Set a track's constant-power pan (-1 left .. +1 right).
  void setTrackPan(int track, double pan) {
    _coalesced(('trackPan', track));
    timeline.tracks[track].pan = pan.clamp(-1.0, 1.0);
    notifyListeners();
  }

  List<DawAutomationPoint> trackGainAutomation(int track) =>
      List.unmodifiable(timeline.tracks[track].gainAutomation);

  int setTrackGainAutomationInRange(
    Iterable<int> tracks,
    double startMs,
    double endMs,
    double startGain,
    double endGain,
  ) {
    final from = math.min(startMs, endMs);
    final to = math.max(startMs, endMs);
    if (to <= from) return 0;
    final targets = tracks
        .where((track) => track >= 0 && track < timeline.tracks.length)
        .toSet()
        .toList()
      ..sort();
    if (targets.isEmpty) return 0;
    final startValue = startGain < 0 ? 0.0 : startGain;
    final endValue = endGain < 0 ? 0.0 : endGain;
    _record();
    for (final track in targets) {
      final lane = timeline.tracks[track];
      final kept = [
        for (final point in lane.gainAutomation)
          if (point.ms < from || point.ms > to) point,
      ];
      kept
        ..add(DawAutomationPoint(ms: from, value: startValue))
        ..add(DawAutomationPoint(ms: to, value: endValue))
        ..sort((a, b) => a.ms.compareTo(b.ms));
      lane.gainAutomation = kept;
    }
    notifyListeners();
    return targets.length;
  }

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

  int removeClipTargets(Iterable<DawClipTarget> targets) {
    final valid = _validClipTargets(targets);
    if (valid.isEmpty) return 0;
    _record();
    final byTrack = <int, List<int>>{};
    for (final target in valid) {
      byTrack.putIfAbsent(target.track, () => <int>[]).add(target.index);
    }
    var removed = 0;
    for (final entry in byTrack.entries) {
      final clips = timeline.tracks[entry.key].clips;
      final indices = entry.value.toSet().toList()
        ..sort((a, b) => b.compareTo(a));
      for (final index in indices) {
        if (index < 0 || index >= clips.length) continue;
        clips.removeAt(index);
        removed++;
      }
    }
    if (removed == 0) return 0;
    notifyListeners();
    return removed;
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

  /// The project's tempo over time (D6). A new project has one tempo
  /// throughout, which is what the old single-`bpm` field meant.
  TempoMap tempoMap = TempoMap.constant(120);

  /// The tempo at the START of the project.
  ///
  /// Kept as a plain get/set because almost everything — the toolbar, the
  /// snap grid on a loop, every existing caller — wants exactly this and
  /// should not have to know about the map. Setting it re-tempos the OPENING
  /// segment only; later changes stay where the user put them.
  double get bpm => tempoMap.changes.first.bpm;

  /// One beat in ms at the opening tempo. Only meaningful where the tempo is
  /// constant — use [tempoMap] for anything that spans a change.
  double get beatMs => 60000 / bpm;

  /// Drag-snap grid in ms (0 = off). When on, [moveClip] rounds a clip's start
  /// to the nearest beat.
  ///
  /// Still a millisecond value because it doubles as the on/off flag and as the
  /// grid for a constant-tempo project, which is the overwhelming majority.
  /// Where the tempo VARIES, [snapPosition] uses the map instead, so the two
  /// cannot disagree.
  double snapMs = 0;

  bool get snapOn => snapMs > 0;

  /// [ms] snapped to the musical grid — the beat, wherever it actually falls.
  double snapPosition(double ms) {
    if (!snapOn) return ms;
    if (tempoMap.isConstant) return (ms / snapMs).roundToDouble() * snapMs;
    return tempoMap.snapToBeat(ms);
  }

  /// Toggle drag-snapping on/off (a view preference — not an undoable edit).
  void toggleSnap() {
    snapMs = snapMs > 0 ? 0 : beatMs;
    notifyListeners();
  }

  /// Set the opening tempo (clamped to a sane 40–300 BPM); if snapping is on,
  /// the grid follows the new beat length.
  void setBpm(double value) {
    final clamped = value.clamp(kMinBpm, kMaxBpm);
    tempoMap = tempoMap.withChange(TempoChange(ms: 0, bpm: clamped));
    if (snapMs > 0) snapMs = beatMs;
    notifyListeners();
  }

  /// Add or replace a tempo change at [ms] (D6). Undoable, unlike [setBpm]:
  /// changing the opening tempo is a setting, but putting a tempo change in the
  /// middle of an arrangement is an EDIT to the piece.
  void setTempoAt(double ms, double bpm) {
    _record();
    tempoMap = tempoMap.withChange(
      TempoChange(ms: math.max(0, ms), bpm: bpm.clamp(kMinBpm, kMaxBpm)),
    );
    notifyListeners();
  }

  /// Remove the tempo change at [ms]. The opening one cannot be removed — the
  /// piece has to start at some tempo.
  void removeTempoAt(double ms) {
    if (ms <= 0 || tempoMap.isConstant) return;
    _record();
    tempoMap = tempoMap.withoutChangeAt(ms);
    notifyListeners();
  }

  /// Move a clip along the timeline (drag-in-time). [startMs] is clamped to ≥ 0
  /// and snapped to [snapMs] when snapping is on. Consecutive moves of the same
  /// clip coalesce into a single undo entry.
  /// D2 — link [targets] so they move together. Returns the new group id.
  ///
  /// Any clip already in a group is re-grouped into this one, which is what
  /// selecting a grouped clip plus a loose one and pressing Group should do.
  int groupClips(Iterable<DawClipTarget> targets) {
    final valid = [
      for (final t in targets)
        if (_validClipTarget(t.track, t.index)) t,
    ];
    if (valid.length < 2) return -1;
    _record();
    final id = ++_lastGroupId;
    for (final t in valid) {
      final clips = timeline.tracks[t.track].clips;
      clips[t.index] = clips[t.index].copyWith(groupId: id);
    }
    notifyListeners();
    return id;
  }

  /// Break the link on [targets] (and on anything grouped WITH them — a group
  /// with one member left is not a group).
  void ungroupClips(Iterable<DawClipTarget> targets) {
    final ids = <int>{};
    for (final t in targets) {
      if (!_validClipTarget(t.track, t.index)) continue;
      final id = timeline.tracks[t.track].clips[t.index].groupId;
      if (id != null) ids.add(id);
    }
    if (ids.isEmpty) return;
    _record();
    for (final track in timeline.tracks) {
      for (var i = 0; i < track.clips.length; i++) {
        if (ids.contains(track.clips[i].groupId)) {
          track.clips[i] = _clearGroup(track.clips[i]);
        }
      }
    }
    notifyListeners();
  }

  /// `copyWith` cannot set a field back to null, so clearing a group needs the
  /// long form. (Worth the noise: the alternative is a sentinel group id, which
  /// every reader would then have to know about.)
  Clip _clearGroup(Clip clip) => Clip(
        source: clip.source,
        startMs: clip.startMs,
        gain: clip.gain,
        pan: clip.pan,
        width: clip.width,
        muted: clip.muted,
        fadeInMs: clip.fadeInMs,
        fadeOutMs: clip.fadeOutMs,
        fadeInCurve: clip.fadeInCurve,
        fadeOutCurve: clip.fadeOutCurve,
        trimStartMs: clip.trimStartMs,
        trimEndMs: clip.trimEndMs,
        effects: clip.effects,
        gainAutomation: clip.gainAutomation,
        provenance: clip.provenance,
      );

  int _lastGroupId = 0;

  /// D2 — shift [targets] along the timeline by [deltaMs], group-aware and
  /// clamped at 0.
  ///
  /// The keyboard counterpart to dragging, and the only way to move a clip by a
  /// known amount: a drag lands where the finger lands. Snapping deliberately
  /// does NOT apply — a nudge is for the case where the grid is not where you
  /// want to be, so re-snapping it would defeat the verb.
  void nudgeClips(Iterable<DawClipTarget> targets, double deltaMs) {
    if (deltaMs == 0) return;
    final valid = [
      for (final t in targets)
        if (_validClipTarget(t.track, t.index)) t,
    ];
    if (valid.isEmpty) return;
    _record();
    // Collect first: moving changes the starts the group logic reads.
    final moved = <(int, int)>{};
    for (final t in valid) {
      for (final member in _groupMembersOf(t)) {
        moved.add((member.track, member.index));
      }
    }
    for (final (track, index) in moved) {
      final clips = timeline.tracks[track].clips;
      final start = math.max(0.0, clips[index].startMs + deltaMs);
      clips[index] = clips[index].copyWith(startMs: start);
    }
    notifyListeners();
  }

  /// [target] plus everything sharing its group.
  List<DawClipTarget> _groupMembersOf(DawClipTarget target) {
    if (!_validClipTarget(target.track, target.index)) return const [];
    final id = timeline.tracks[target.track].clips[target.index].groupId;
    if (id == null) return [target];
    return [
      for (var t = 0; t < timeline.tracks.length; t++)
        for (var i = 0; i < timeline.tracks[t].clips.length; i++)
          if (timeline.tracks[t].clips[i].groupId == id) (track: t, index: i),
    ];
  }

  void moveClip(int track, int index, double startMs) {
    _coalesced(('move', track, index));
    // Snapping goes through the tempo map, so a drag lands on the beat even
    // where the tempo changes — the millisecond grid is only correct while the
    // tempo is constant.
    final v = snapPosition(startMs < 0 ? 0.0 : startMs);
    final clips = timeline.tracks[track].clips;
    // D2 — a grouped clip carries its partners by the SAME delta, so the
    // relationship that made them a group survives the move. Computed before
    // the dragged clip is written, since the delta is relative to where it was.
    final delta = v - clips[index].startMs;
    final members = _groupMembersOf((track: track, index: index));
    clips[index] = clips[index].copyWith(startMs: v);
    if (members.length > 1 && delta != 0) {
      for (final member in members) {
        if (member.track == track && member.index == index) continue;
        final others = timeline.tracks[member.track].clips;
        others[member.index] = others[member.index].copyWith(
          startMs: math.max(0.0, others[member.index].startMs + delta),
        );
      }
    }
    notifyListeners();
  }

  /// Move a clip to another lane, optionally to a new time — the thing a
  /// timeline has to do that [moveClip] can't: that one only slides a clip
  /// along the lane it's already on.
  ///
  /// The clip keeps everything about itself (source, trim, gain, pan, fades,
  /// FX); only which lane plays it changes. Returns its index in the new lane,
  /// or -1 if the move wasn't possible. Dropping a clip back on its own lane is
  /// just a time move, so it coalesces like a drag instead of stacking undo.
  int moveClipToTrack(
    int fromTrack,
    int index,
    int toTrack, {
    double? startMs,
  }) {
    if (fromTrack < 0 || fromTrack >= timeline.tracks.length) return -1;
    if (toTrack < 0 || toTrack >= timeline.tracks.length) return -1;
    final from = timeline.tracks[fromTrack].clips;
    if (index < 0 || index >= from.length) return -1;

    if (fromTrack == toTrack) {
      if (startMs != null) moveClip(fromTrack, index, startMs);
      return index;
    }

    _record();
    final clip = from.removeAt(index);
    var at = startMs ?? clip.startMs;
    if (at < 0) at = 0;
    if (snapMs > 0) at = (at / snapMs).round() * snapMs;
    final to = timeline.tracks[toTrack].clips..add(clip.copyWith(startMs: at));
    _peaks.clear();
    notifyListeners();
    return to.length - 1;
  }

  /// Set a clip's linear [gain] (0 = silent). A slider sweep coalesces to one
  /// undo entry.
  void setClipGain(int track, int index, double gain) {
    _coalesced(('gain', track, index));
    final clips = timeline.tracks[track].clips;
    clips[index] = clips[index].copyWith(gain: gain < 0 ? 0 : gain);
    notifyListeners();
  }

  /// Set a clip's constant-power pan. Track pan and clip pan are summed and
  /// clamped at render time; this edit remains non-destructive and undoable.
  void setClipPan(int track, int index, double pan) {
    _coalesced(('pan', track, index));
    final clips = timeline.tracks[track].clips;
    clips[index] = clips[index].copyWith(pan: pan.clamp(-1.0, 1.0));
    notifyListeners();
  }

  double clipPan(int track, int index) =>
      timeline.tracks[track].clips[index].pan;

  void setClipWidth(int track, int index, double width) {
    _coalesced(('width', track, index));
    final clips = timeline.tracks[track].clips;
    clips[index] = clips[index].copyWith(width: width.clamp(0.0, 2.0));
    notifyListeners();
  }

  double clipWidth(int track, int index) =>
      timeline.tracks[track].clips[index].width;

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
    final stereo = clipStereoPeaks(track, index, buckets: buckets);
    return [
      for (var i = 0; i < stereo.left.length; i++)
        math.max(stereo.left[i], stereo.right[i]),
    ];
  }

  /// Separate channel peaks for the DAW stereo waveform renderer. Mono clips
  /// return the same data for both lanes, keeping callers simple.
  ({List<double> left, List<double> right}) clipStereoPeaks(
    int track,
    int index, {
    int buckets = 120,
  }) {
    final clip = timeline.tracks[track].clips[index];
    final n = buckets < 1 ? 1 : buckets;
    final baseKey = '${clip.source.cacheKey}|${clip.trimStartMs}|'
        '${clip.trimEndMs}|${Object.hashAll(clip.effects.map((e) => e.cacheKey))}|$n';
    return _peaks.putIfAbsent('$baseKey|stereo', () {
      final rendered = _cache.putIfAbsent(
        clip.source.cacheKey,
        () => clip.source.render(kDawSampleRate),
      );
      final dry = trimmedPcm(clip, rendered);
      final rightRendered = clip.source is StereoSampleSource
          ? (clip.source as StereoSampleSource).right
          : rendered;
      final rightDry = trimmedPcm(clip, rightRendered);
      final stereo = clip.source is StereoSampleSource;
      final effected = clip.effects.isEmpty
          ? (left: dry, right: rightDry)
          : stereo
              ? applyStereoClipEffectChain(
                  dry,
                  rightDry,
                  clip.effects,
                  kDawSampleRate,
                )
              : (
                  left: applyClipEffectChain(dry, clip.effects, kDawSampleRate),
                  right: dry,
                );
      final left = List<double>.filled(n, 0);
      final right = List<double>.filled(n, 0);
      if (effected.left.isEmpty) return (left: left, right: right);
      for (var b = 0; b < n; b++) {
        final lo = effected.left.length * b ~/ n;
        final hi = effected.left.length * (b + 1) ~/ n;
        var leftPeak = 0.0;
        var rightPeak = 0.0;
        for (var i = lo; i < hi; i++) {
          leftPeak = math.max(leftPeak, effected.left[i].abs());
          if (i < effected.right.length) {
            rightPeak = math.max(rightPeak, effected.right[i].abs());
          }
        }
        left[b] = leftPeak > 1 ? 1 : leftPeak;
        right[b] = rightPeak > 1 ? 1 : rightPeak;
      }
      return (left: left, right: right);
    }) as ({List<double> left, List<double> right});
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
    final right = clip.source is StereoSampleSource
        ? (clip.source as StereoSampleSource).right
        : null;
    _record();
    timeline.tracks[track].clips[index] = Clip(
      source:
          right == null ? SampleSource(pcm) : StereoSampleSource(pcm, right),
      startMs: clip.startMs,
      gain: clip.gain,
      pan: clip.pan,
      width: clip.width,
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
    final rightRendered = _renderedRight(clip, rendered);
    final rightWindow = trimmedPcm(clip, rightRendered);
    _record();
    final flipped = Float64List(window.length);
    final flippedRight = Float64List(rightWindow.length);
    for (var i = 0; i < window.length; i++) {
      flipped[i] = window[window.length - 1 - i];
    }
    for (var i = 0; i < rightWindow.length; i++) {
      flippedRight[i] = rightWindow[rightWindow.length - 1 - i];
    }
    timeline.tracks[track].clips[index] = Clip(
      source: clip.source is StereoSampleSource
          ? StereoSampleSource(flipped, flippedRight)
          : SampleSource(flipped),
      startMs: clip.startMs,
      gain: clip.gain,
      pan: clip.pan,
      width: clip.width,
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
    final rightRendered = _renderedRight(clip, rendered);
    final rightWindow = trimmedPcm(clip, rightRendered);
    final outLen = (window.length / factor).round();
    if (outLen < 1) return;
    _record();
    // Linear-interpolated resample: out[i] samples the source at i * factor.
    final out = Float64List(outLen);
    final rightOut = Float64List(outLen);
    for (var i = 0; i < outLen; i++) {
      final pos = i * factor;
      final j = pos.floor();
      if (j + 1 < window.length) {
        final frac = pos - j;
        out[i] = window[j] * (1 - frac) + window[j + 1] * frac;
      } else {
        out[i] = window[window.length - 1];
      }
      final rightPos = i * factor;
      final rightIndex = rightPos.floor();
      if (rightIndex + 1 < rightWindow.length) {
        final frac = rightPos - rightIndex;
        rightOut[i] = rightWindow[rightIndex] * (1 - frac) +
            rightWindow[rightIndex + 1] * frac;
      } else {
        rightOut[i] = rightWindow[rightWindow.length - 1];
      }
    }
    timeline.tracks[track].clips[index] = Clip(
      source: clip.source is StereoSampleSource
          ? StereoSampleSource(out, rightOut)
          : SampleSource(out),
      startMs: clip.startMs,
      gain: clip.gain,
      pan: clip.pan,
      width: clip.width,
      muted: clip.muted,
      fadeInMs: clip.fadeInMs,
      fadeOutMs: clip.fadeOutMs,
      fadeInCurve: clip.fadeInCurve,
      fadeOutCurve: clip.fadeOutCurve,
      effects: clip.effects,
    );
    notifyListeners();
  }

  /// Bake the clip's playing window (both channels) to a fixed [SampleSource]
  /// take produced by [transform], preserving placement/gain/pan/width/mute/
  /// fades/effects (the trim is folded in, like [reverseClip]). [transform]
  /// receives the left and — for a stereo clip — right windows and returns the
  /// processed pair; returning an empty left aborts. Shared by the destructive
  /// amplitude tools (normalize / invert / remove-DC / trim-silence / amplify).
  /// The maths itself lives in `daw_edits.dart` so the CLI and headless tests
  /// run exactly the same code; this only owns undo, the cache and notify.
  void _bakeClip(
    int track,
    int index,
    BakedTake Function(Float64List left, Float64List? right) transform,
  ) {
    final clip = timeline.tracks[track].clips[index];
    final rendered = _cache.putIfAbsent(
      clip.source.cacheKey,
      () => clip.source.render(kDawSampleRate),
    );
    final left = trimmedPcm(clip, rendered);
    if (left.isEmpty) return;
    final stereo = clip.source is StereoSampleSource;
    final right =
        stereo ? trimmedPcm(clip, _renderedRight(clip, rendered)) : null;
    final take = transform(left, right);
    final newLeft = take.left;
    final newRight = take.right;
    if (newLeft.isEmpty) return;
    _record();
    timeline.tracks[track].clips[index] = Clip(
      source: (stereo && newRight != null)
          ? StereoSampleSource(newLeft, newRight)
          : SampleSource(newLeft),
      startMs: clip.startMs + take.startShiftMs,
      gain: clip.gain,
      pan: clip.pan,
      width: clip.width,
      muted: clip.muted,
      fadeInMs: clip.fadeInMs,
      fadeOutMs: clip.fadeOutMs,
      fadeInCurve: clip.fadeInCurve,
      fadeOutCurve: clip.fadeOutCurve,
      effects: clip.effects,
    );
    notifyListeners();
  }

  /// **Normalize** a clip to [targetPeak] of full scale (default 0.98) using one
  /// gain from the loudest sample across BOTH channels, so the stereo image is
  /// preserved. No-op on a silent clip.
  void normalizeClip(int track, int index, {double targetPeak = 0.98}) =>
      _bakeClip(
        track,
        index,
        (left, right) => normalizeTake(left, right, targetPeak: targetPeak),
      );

  /// **Amplify** a clip by [db] (bake). Unlike the non-destructive Gain FX this
  /// rewrites the samples, so a later normalize/statistic sees the new level.
  /// Not clamped — the master limiter still catches an over-loud result.
  void amplifyClip(int track, int index, double db) {
    if (db == 0) return;
    _bakeClip(track, index, (left, right) => amplifyTake(left, right, db));
  }

  /// **Trim silence** from a clip's edges: everything quieter than [threshold]
  /// (fraction of full scale) before the first and after the last audible sample
  /// is removed. A stereo clip is judged on BOTH channels at once so they stay
  /// sample-aligned. The clip slides later by exactly the leading silence, so
  /// the surviving audio keeps its place in the arrangement. All-silent → no-op.
  void trimSilenceFromClip(int track, int index, {double threshold = 0.01}) =>
      _bakeClip(
        track,
        index,
        (left, right) => trimSilenceTake(
          left,
          right,
          threshold: threshold,
          sampleRate: kDawSampleRate,
        ),
      );

  /// **Invert** a clip's phase (× −1 on every sample). Inaudible alone, but
  /// flips cancellation when layered; inverting twice restores it.
  void invertClip(int track, int index) => _bakeClip(track, index, invertTake);

  /// **Remove the DC offset** from a clip (centre each channel on zero) — fixes
  /// an off-centre waveform and the clicks / lost headroom it causes.
  void removeClipDcOffset(int track, int index) =>
      _bakeClip(track, index, removeDcTake);

  /// Peak / RMS / duration / clipped-sample count for a clip's played window —
  /// what the inspector shows and what an export decision is made on.
  ClipStats clipStats(int track, int index) {
    final (left, right) = _clipWindows(track, index);
    return clipStatsOf(left, right, sampleRate: kDawSampleRate);
  }

  /// A clip's played window as mono PCM (trim folded in, channels averaged) —
  /// what an analysis view (spectrogram) should look at.
  Float64List clipWindowPcm(int track, int index) {
    final (left, right) = _clipWindows(track, index);
    if (right == null) return left;
    final frames = math.min(left.length, right.length);
    final mono = Float64List(frames);
    for (var i = 0; i < frames; i++) {
      mono[i] = (left[i] + right[i]) * 0.5;
    }
    return mono;
  }

  (Float64List, Float64List?) _clipWindows(int track, int index) {
    final clip = timeline.tracks[track].clips[index];
    final rendered = _cache.putIfAbsent(
      clip.source.cacheKey,
      () => clip.source.render(kDawSampleRate),
    );
    return (
      trimmedPcm(clip, rendered),
      clip.source is StereoSampleSource
          ? trimmedPcm(clip, _renderedRight(clip, rendered))
          : null,
    );
  }

  /// **Generate** a steady tone / noise / silence as a new clip. It lands on its
  /// own new lane unless [track] says otherwise, and carries a short fade so the
  /// hard edges of a synthetic waveform don't click.
  void addGeneratedClip({
    required GeneratorShape shape,
    double freq = 440,
    double endFreq = 20000,
    double seconds = 2,
    double amp = 0.5,
    int seed = 0,
    int? track,
    double startMs = 0,
    double fadeMs = 5,
  }) {
    final pcm = generateWave(
      shape: shape,
      samples: (seconds * kDawSampleRate).round(),
      freq: freq,
      endFreq: endFreq,
      sampleRate: kDawSampleRate,
      amp: amp,
      seed: seed,
    );
    _addPcmOnLane(pcm, track: track, startMs: startMs, fadeMs: fadeMs);
  }

  /// **Record** — drop a captured mic take on its own new lane (O14). Same
  /// placement as [addGeneratedClip]; the short fade keeps the take's hard
  /// start/stop from clicking.
  void addRecordedClip(
    Float64List pcm, {
    int? track,
    double startMs = 0,
    double fadeMs = 5,
  }) =>
      _addPcmOnLane(pcm, track: track, startMs: startMs, fadeMs: fadeMs);

  void _addPcmOnLane(
    Float64List pcm, {
    required int? track,
    required double startMs,
    required double fadeMs,
  }) {
    if (pcm.isEmpty) return;
    _record();
    final lane = track ?? timeline.tracks.length;
    while (timeline.tracks.length <= lane) {
      timeline.tracks.add(DawTrack(name: '${timeline.tracks.length + 1}'));
    }
    timeline.tracks[lane].clips.add(
      Clip(
        source: SampleSource(pcm),
        startMs: startMs,
        fadeInMs: fadeMs,
        fadeOutMs: fadeMs,
      ),
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
    final hasStereo = live.any((clip) => clip.source is StereoSampleSource);
    if (!hasStereo) {
      final pcm = renderTimeline(
        DawTimeline(tracks: [DawTrack(clips: shifted)]),
        cache: _cache,
        limit: false,
      );
      if (pcm.isEmpty) return null;
      return Clip(source: SampleSource(pcm), startMs: minStart);
    }
    final stereo = renderTimelineStereo(
      DawTimeline(tracks: [DawTrack(clips: shifted)]),
      cache: _cache,
      limit: false,
    );
    if (stereo.left.isEmpty) return null;
    return Clip(
      source: StereoSampleSource(stereo.left, stereo.right),
      startMs: minStart,
    );
  }

  Float64List _renderedRight(Clip clip, Float64List rendered) =>
      clip.source is StereoSampleSource
          ? (clip.source as StereoSampleSource).right
          : rendered;

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

  /// Whether the clip is a tracker pattern — sent here from the Tracker, and so
  /// still holding the song itself rather than only its render.
  bool isTrackerClip(int track, int index) =>
      timeline.tracks[track].clips[index].source is TrackerSource;

  /// The pattern song behind a tracker clip (null on any other clip).
  ///
  /// A clip that arrived via the Tracker's "Send to Audio Editor" keeps the
  /// live [TrackerSong], not a bounce of it. Treating such a clip as opaque
  /// audio would have made Tracker → Audio Editor → Tracker a one-way trip
  /// while the exact song sat in the clip, so the way back is exact retrieval —
  /// nothing is transcribed and nothing is approximated.
  TrackerSong? clipTrackerSong(int track, int index) {
    final src = timeline.tracks[track].clips[index].source;
    return src is TrackerSource ? src.song : null;
  }

  /// Whether the clip is a DrumKit beat, still holding the grid it was built
  /// from rather than only its render.
  bool isDrumClip(int track, int index) =>
      timeline.tracks[track].clips[index].source is DrumSource;

  /// The drum grid behind a drum clip (null on any other clip).
  DrumRowsPattern? clipDrumPattern(int track, int index) {
    final src = timeline.tracks[track].clips[index].source;
    return src is DrumSource ? src.pattern : null;
  }

  /// The tempo/swing/bars a drum clip plays at (null on any other clip). Sent
  /// to the Drum Kit with the grid so a round trip does not reset the feel.
  LoopTiming? clipDrumTiming(int track, int index) {
    final src = timeline.tracks[track].clips[index].source;
    return src is DrumSource ? src.timing : null;
  }

  /// Whether the clip is a Loop Mixer groove, still holding its spec.
  bool isGrooveClip(int track, int index) =>
      timeline.tracks[track].clips[index].source is GrooveSource;

  /// The groove spec behind a groove clip (null on any other clip).
  GrooveSpec? clipGroove(int track, int index) {
    final src = timeline.tracks[track].clips[index].source;
    return src is GrooveSource ? src.spec : null;
  }

  /// The raw source of a clip — captured before opening it in an editor so the
  /// edit can be routed back to the SAME clip via [replaceScoreClipSource],
  /// [replaceTrackerClipSource], [replaceDrumClipSource] or
  /// [replaceGrooveClipSource], robustly against the clip being
  /// moved/reordered meanwhile.
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

  /// The tracker twin of [replaceScoreClipSource]: put the edited [song] back
  /// into the clip it came from, keeping placement/gain/fades/trim/provenance.
  /// If that clip is gone, the edit lands as a new clip so nothing is lost.
  void replaceTrackerClipSource(ClipSource oldSource, TrackerSong song) {
    for (final t in timeline.tracks) {
      for (var i = 0; i < t.clips.length; i++) {
        if (identical(t.clips[i].source, oldSource)) {
          _record();
          t.clips[i] = _reSource(t.clips[i], TrackerSource(song));
          notifyListeners();
          return;
        }
      }
    }
    addClip(TrackerSource(song));
  }

  /// Put an edited beat back into the clip it came from — the drum twin of
  /// [replaceScoreClipSource]. If that clip is gone, the edit lands as a new
  /// clip so nothing is lost.
  void replaceDrumClipSource(
    ClipSource oldSource,
    DrumRowsPattern pattern,
    LoopTiming timing,
  ) =>
      _replaceClipSource(oldSource, DrumSource(pattern, timing));

  /// Put an edited groove back into the clip it came from.
  void replaceGrooveClipSource(ClipSource oldSource, GrooveSpec spec) =>
      _replaceClipSource(oldSource, GrooveSource(spec));

  /// Swap the clip whose source is [oldSource] onto [next], keeping everything
  /// about its placement. Falls back to adding a clip when the original is gone
  /// — a user who edited something and pressed Done must not lose the edit
  /// because they deleted the clip meanwhile.
  ///
  /// Shared by every in-place round trip; the score and tracker versions predate
  /// it and keep their own bodies only because they also carry an instrument.
  void _replaceClipSource(ClipSource oldSource, ClipSource next) {
    for (final t in timeline.tracks) {
      for (var i = 0; i < t.clips.length; i++) {
        if (identical(t.clips[i].source, oldSource)) {
          _record();
          t.clips[i] = _reSource(t.clips[i], next);
          notifyListeners();
          return;
        }
      }
    }
    addClip(next);
  }

  /// Re-source [clip] onto [source], preserving placement/gain/mute/fades/trim.
  ///
  /// [Clip.provenance] rides along deliberately: editing borrowed music in the
  /// Score Workshop and sending it back is an ARRANGEMENT of that music, not a
  /// new work. Dropping the licence here would have laundered it — the clip
  /// would return looking unencumbered and the export gate would stop asking
  /// for the attribution/share-alike the source still requires.
  Clip _reSource(Clip clip, ClipSource source) => Clip(
        source: source,
        startMs: clip.startMs,
        gain: clip.gain,
        pan: clip.pan,
        width: clip.width,
        muted: clip.muted,
        fadeInMs: clip.fadeInMs,
        fadeOutMs: clip.fadeOutMs,
        fadeInCurve: clip.fadeInCurve,
        fadeOutCurve: clip.fadeOutCurve,
        trimStartMs: clip.trimStartMs,
        trimEndMs: clip.trimEndMs,
        effects: clip.effects,
        gainAutomation: clip.gainAutomation,
        provenance: clip.provenance,
      );

  /// D3 — set a clip's own gain envelope (points in ms from the CLIP's start).
  ///
  /// Distinct from [setTrackGainAutomationInRange], which is anchored to the
  /// timeline: this shape belongs to the take and moves with it. Pass an empty
  /// list to clear.
  void setClipGainAutomation(
    int track,
    int index,
    List<DawAutomationPoint> points,
  ) {
    if (!_validClipTarget(track, index)) return;
    _record();
    final clips = timeline.tracks[track].clips;
    clips[index] = clips[index].copyWith(
      gainAutomation: [...points]..sort((a, b) => a.ms.compareTo(b.ms)),
    );
    notifyListeners();
  }

  /// A clip's own gain envelope (empty when it has none).
  List<DawAutomationPoint> clipGainAutomation(int track, int index) =>
      _validClipTarget(track, index)
          ? timeline.tracks[track].clips[index].gainAutomation
          : const [];

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

  void setTrackEffectAutomation(
    int track,
    int effectIndex,
    String key,
    List<DawAutomationPoint> points,
  ) {
    final lane = timeline.tracks[track];
    if (effectIndex < 0 || effectIndex >= lane.effects.length) return;
    _record();
    final effects = [...lane.effects];
    effects[effectIndex] = _effectWithAutomation(
      effects[effectIndex],
      key,
      points,
    );
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

  void setBusEffectAutomation(
    int bus,
    int effectIndex,
    String key,
    List<DawAutomationPoint> points,
  ) {
    if (bus < 0 || bus >= timeline.buses.length) return;
    final effects = timeline.buses[bus].effects;
    if (effectIndex < 0 || effectIndex >= effects.length) return;
    _record();
    final next = [...effects];
    next[effectIndex] = _effectWithAutomation(next[effectIndex], key, points);
    timeline.buses[bus].effects = next;
    notifyListeners();
  }

  void addMasterEffect(DawClipEffectType type) {
    _record();
    timeline.effects.add(defaultDawClipEffect(type));
    notifyListeners();
  }

  /// Replace the master chain wholesale — what pasting a chain string does.
  ///
  /// Cloned on the way in, like the preset path: a caller that keeps a
  /// reference to the list it passed must not be able to mutate the timeline
  /// behind the service's back and skip the undo snapshot.
  void setMasterEffects(List<DawClipEffect> effects) {
    _record();
    timeline.effects = _cloneEffectChain(effects);
    notifyListeners();
  }

  /// The track twin of [setMasterEffects].
  void setTrackEffects(int track, List<DawClipEffect> effects) {
    if (track < 0 || track >= timeline.tracks.length) return;
    _record();
    timeline.tracks[track].effects = _cloneEffectChain(effects);
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

  void setMasterEffectAutomation(
    int effectIndex,
    String key,
    List<DawAutomationPoint> points,
  ) {
    if (effectIndex < 0 || effectIndex >= timeline.effects.length) return;
    _record();
    final effects = [...timeline.effects];
    effects[effectIndex] =
        _effectWithAutomation(effects[effectIndex], key, points);
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
        for (final fx in chain)
          fx.copyWith(
            params: {...fx.params},
            automation: _cloneEffectAutomation(fx.automation),
          ),
      ];

  DawClipEffect _effectWithAutomation(
    DawClipEffect fx,
    String key,
    List<DawAutomationPoint> points,
  ) {
    final automation = _cloneEffectAutomation(fx.automation);
    final clean = _cloneAutomation(points)
      ..removeWhere((point) => !point.ms.isFinite || !point.value.isFinite)
      ..sort((a, b) => a.ms.compareTo(b.ms));
    if (clean.isEmpty) {
      automation.remove(key);
    } else {
      automation[key] = clean;
    }
    return fx.copyWith(automation: automation);
  }

  Map<String, List<DawAutomationPoint>> _cloneEffectAutomation(
    Map<String, List<DawAutomationPoint>> automation,
  ) =>
      {
        for (final entry in automation.entries)
          entry.key: _cloneAutomation(entry.value),
      };

  List<DawAutomationPoint> _cloneAutomation(
    List<DawAutomationPoint> points,
  ) =>
      [
        for (final point in points)
          DawAutomationPoint(
            ms: point.ms,
            value: point.value,
            curve: point.curve,
          ),
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

  /// **Silence the marked range**: the covered clip segments are cut out, so
  /// what played there is gone and everything around it stays exactly where it
  /// was (no ripple). Clips straddling a boundary are split first, so only the
  /// marked part goes. Returns how many clip segments were removed.
  ///
  /// Distinct from [setClipMutedInRange], which flags the same segments muted
  /// (reversible, clips stay in the arrangement).
  int silenceRange(Iterable<int> tracks, double startMs, double endMs) =>
      _removeClipsAroundRange(tracks, startMs, endMs, removeInside: true);

  /// **Crop to the marked range**: on the given tracks, keep only what plays
  /// inside the range and drop everything outside it (splitting at the
  /// boundaries first). Returns how many clip segments were removed.
  int cropToRange(Iterable<int> tracks, double startMs, double endMs) =>
      _removeClipsAroundRange(tracks, startMs, endMs, removeInside: false);

  /// **Ripple delete**: cut the range out AND close the gap — everything after
  /// it slides earlier by the range's length.
  ///
  /// The difference from [silenceRange] is the whole point, and it is the
  /// difference between two different edits. Silencing leaves a hole, so
  /// anything later keeps the time it was recorded at; rippling removes TIME
  /// itself, so a passage cut from the middle of an arrangement does not leave
  /// a bar of nothing where it was. Both are wanted, which is why both exist.
  ///
  /// Applies to EVERY lane, not the selected ones. A ripple on some lanes and
  /// not others would slide the arrangement out of sync with itself, which is
  /// never what anyone means — the selection-scoped verb for "just here" is
  /// [silenceRange].
  ///
  /// Markers ripple too: a marker is a position in time, and leaving one
  /// pointing at a bar that has moved is worse than not having it.
  int rippleDelete(double startMs, double endMs) {
    final rangeStart = math.min(startMs, endMs);
    final rangeEnd = math.max(startMs, endMs);
    final span = rangeEnd - rangeStart;
    if (span <= _minSplitMs || timeline.tracks.isEmpty) return 0;

    _record();
    var removed = 0;
    for (final track in timeline.tracks) {
      removed += editClipsAroundRange(
        track.clips,
        rangeStart,
        rangeEnd,
        removeInside: true,
        durationOf: _durationOf,
        minSplitMs: _minSplitMs,
      );
      // Close the gap: everything that began at or after the cut moves back by
      // exactly what was removed.
      for (var i = 0; i < track.clips.length; i++) {
        final clip = track.clips[i];
        if (clip.startMs >= rangeEnd - 1e-9) {
          track.clips[i] = clip.copyWith(startMs: clip.startMs - span);
        }
      }
    }
    _rippleMarkers(rangeEnd, -span, dropBetween: (rangeStart, rangeEnd));
    notifyListeners();
    return removed;
  }

  /// **Ripple insert**: open [durationMs] of empty time at [atMs], sliding
  /// everything from there onward later.
  ///
  /// The complement of [rippleDelete] — room for a bar that was forgotten.
  /// A clip straddling the insertion point is SPLIT, because the alternative
  /// (moving it whole) would silently relocate audio the user did not select.
  void rippleInsert(double atMs, double durationMs) {
    if (durationMs <= 0 || timeline.tracks.isEmpty) return;
    _record();
    for (final track in timeline.tracks) {
      // Split anything that spans the point, so the halves can part company.
      for (var i = 0; i < track.clips.length; i++) {
        final clip = track.clips[i];
        final duration = _durationOf(clip);
        if (_canSplitClipWindow(clip.startMs, duration, atMs)) {
          final offset = atMs - clip.startMs;
          final cut = clip.trimStartMs + offset;
          track.clips[i] = clip.copyWith(trimEndMs: cut, fadeOutMs: 0);
          track.clips.insert(
            i + 1,
            clip.copyWith(
              startMs: clip.startMs + offset,
              trimStartMs: cut,
              fadeInMs: 0,
            ),
          );
          i++;
        }
      }
      for (var i = 0; i < track.clips.length; i++) {
        final clip = track.clips[i];
        if (clip.startMs >= atMs - 1e-9) {
          track.clips[i] = clip.copyWith(startMs: clip.startMs + durationMs);
        }
      }
    }
    _rippleMarkers(atMs, durationMs);
    notifyListeners();
  }

  /// Slide markers at or after [fromMs] by [deltaMs], dropping any that fell
  /// inside a removed range (they point at nothing now).
  void _rippleMarkers(
    double fromMs,
    double deltaMs, {
    (double, double)? dropBetween,
  }) {
    final kept = <DawMarker>[];
    for (final marker in timeline.markers) {
      if (dropBetween != null &&
          marker.ms > dropBetween.$1 &&
          marker.ms < dropBetween.$2) {
        continue;
      }
      kept.add(
        marker.ms >= fromMs - 1e-9
            ? marker.copyWith(ms: math.max(0, marker.ms + deltaMs))
            : marker,
      );
    }
    timeline.markers
      ..clear()
      ..addAll(kept..sort((a, b) => a.ms.compareTo(b.ms)));
  }

  /// Split every clip at both range bounds, then drop the segments on one side.
  /// A sliver too short to split (< [_minSplitMs] from a bound) is decided by
  /// its midpoint, so it lands on whichever side it mostly belongs to.
  int _removeClipsAroundRange(
    Iterable<int> tracks,
    double startMs,
    double endMs, {
    required bool removeInside,
  }) {
    final indices = _validTrackIndices(tracks);
    final rangeStart = math.min(startMs, endMs);
    final rangeEnd = math.max(startMs, endMs);
    if (indices.isEmpty || rangeEnd - rangeStart <= _minSplitMs) return 0;
    if (!_rangeHitsAnyClip(indices, rangeStart, rangeEnd)) return 0;

    _record();
    var removed = 0;
    for (final track in indices) {
      removed += editClipsAroundRange(
        timeline.tracks[track].clips,
        rangeStart,
        rangeEnd,
        removeInside: removeInside,
        durationOf: _durationOf,
        minSplitMs: _minSplitMs,
      );
    }
    _peaks.clear();
    notifyListeners();
    return removed;
  }

  /// A clip's played length, served from the render cache.
  double _durationOf(Clip clip) => trimmedDurationMs(
        clip,
        _cache.putIfAbsent(
          clip.source.cacheKey,
          () => clip.source.render(kDawSampleRate),
        ),
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

  void setClipEffectAutomation(
    int track,
    int index,
    int effectIndex,
    String key,
    List<DawAutomationPoint> points,
  ) {
    final clips = timeline.tracks[track].clips;
    final clip = clips[index];
    if (effectIndex < 0 || effectIndex >= clip.effects.length) return;
    _record();
    final effects = [...clip.effects];
    effects[effectIndex] = _effectWithAutomation(
      effects[effectIndex],
      key,
      points,
    );
    clips[index] = clip.copyWith(effects: effects);
    _peaks.clear();
    notifyListeners();
  }

  // --- Markers (O13) ---------------------------------------------------------
  // Navigation only: markers never reach the render, so adding one can't change
  // how the arrangement sounds. Kept sorted by time and covered by undo.

  List<DawMarker> get markers => List.unmodifiable(timeline.markers);

  /// Add a labelled marker at [ms]. Returns its index after sorting.
  int addMarker(double ms, [String label = '']) {
    _record();
    timeline.markers.add(DawMarker(ms: math.max(0, ms), label: label));
    timeline.markers.sort((a, b) => a.ms.compareTo(b.ms));
    notifyListeners();
    return timeline.markers.indexWhere((m) => m.ms == math.max(0, ms));
  }

  void removeMarker(int index) {
    if (index < 0 || index >= timeline.markers.length) return;
    _record();
    timeline.markers.removeAt(index);
    notifyListeners();
  }

  void renameMarker(int index, String label) {
    if (index < 0 || index >= timeline.markers.length) return;
    _record();
    timeline.markers[index] = timeline.markers[index].copyWith(label: label);
    notifyListeners();
  }

  /// Move a marker in time; the list stays sorted, so the index may change.
  void moveMarker(int index, double ms) {
    if (index < 0 || index >= timeline.markers.length) return;
    _record();
    timeline.markers[index] =
        timeline.markers[index].copyWith(ms: math.max(0, ms));
    timeline.markers.sort((a, b) => a.ms.compareTo(b.ms));
    notifyListeners();
  }

  void clearMarkers() {
    if (timeline.markers.isEmpty) return;
    _record();
    timeline.markers.clear();
    notifyListeners();
  }

  /// The nearest marker before / after [ms] — what "jump to previous/next
  /// marker" needs. Null when there is none in that direction.
  DawMarker? markerBefore(double ms) {
    DawMarker? found;
    for (final m in timeline.markers) {
      if (m.ms < ms - 1) found = m; // 1 ms slack: don't re-find where we are
    }
    return found;
  }

  DawMarker? markerAfter(double ms) {
    for (final m in timeline.markers) {
      if (m.ms > ms + 1) return m;
    }
    return null;
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

  /// What exporting/saving/sharing this arrangement owes: attribution,
  /// share-alike on the OUTPUT, and anything that can't lawfully be included.
  ///
  /// Collected from the clips' own [Clip.provenance], so it reflects what is
  /// actually in the arrangement right now — delete the share-alike clip and
  /// the obligation goes with it. Clips the user recorded or generated carry no
  /// provenance and contribute nothing.
  ///
  /// This is the app-side half of the SA-propagation requirement in
  /// `docs/CORPUS_LICENSING.md`; the rule itself lives in
  /// `core/licensing/license_obligations.dart`.
  LicenseObligations licenseObligations() => obligationsFor([
        for (final track in timeline.tracks)
          for (final clip in track.clips)
            if (clip.provenance != null) clip.provenance!,
      ]);

  /// Bake the whole arrangement to one mono PCM buffer (only changed clips
  /// re-render, thanks to the per-source cache).
  Float64List bake() => renderTimeline(timeline, cache: _cache);

  /// Bake the arrangement as separate left/right channels for stereo export.
  DawStereoMix bakeStereo() => renderTimelineStereo(timeline, cache: _cache);

  /// Bake ONE lane on its own — a stem. Everything that lane carries applies
  /// (its clips' FX, its own track insert, its gain/pan); what's dropped is the
  /// other lanes, so stems sum back to something close to the full mix rather
  /// than each being a separate mastered mix.
  ///
  /// Solo/mute on OTHER tracks is ignored on purpose: asking for track 3's stem
  /// means track 3, even if track 1 happens to be soloed. The lane's own mute is
  /// honoured, so a muted lane stems to silence.
  ///
  /// The master soft-limiter is NOT applied. Limiting each stem on its own would
  /// be mastering a part — and it would stop the stems summing back to the mix,
  /// which is the whole point of stems. The limiter belongs on the sum, so
  /// whoever recombines them applies it once.
  Float64List bakeTrack(int track) {
    if (track < 0 || track >= timeline.tracks.length) return Float64List(0);
    return renderTimeline(_soloTimeline(track), cache: _cache, limit: false);
  }

  /// Stereo [bakeTrack] — same no-limiter rule.
  DawStereoMix bakeTrackStereo(int track) {
    if (track < 0 || track >= timeline.tracks.length) {
      return DawStereoMix(Float64List(0), Float64List(0));
    }
    return renderTimelineStereo(
      _soloTimeline(track),
      cache: _cache,
      limit: false,
    );
  }

  /// A one-lane view of the arrangement, keeping the buses and master FX the
  /// lane routes through so a stem sounds like it does in the mix.
  DawTimeline _soloTimeline(int track) {
    final lane = timeline.tracks[track];
    return DawTimeline(
      tracks: [
        DawTrack(
          name: lane.name,
          gain: lane.gain,
          pan: lane.pan,
          muted: lane.muted,
          instrument: lane.instrument,
          busIndex: lane.busIndex,
          busSends: {...lane.busSends},
          effect: lane.effect,
          effects: [...lane.effects],
          gainAutomation: _cloneAutomation(lane.gainAutomation),
          clips: [...lane.clips],
        ),
      ],
      buses: _cloneBuses(timeline.buses),
      effects: _cloneEffectChain(timeline.effects),
    );
  }

  // --- Project save / load ---------------------------------------------------

  /// Serialize the arrangement to a portable project string: every clip's MODEL
  /// (when it has one) plus its baked PCM. Renders through the per-source cache
  /// so a save is cheap.
  String saveProject() => projectToJson(
        timeline,
        tempoMap: tempoMap,
        render: (s) => _cache.putIfAbsent(
          s.cacheKey,
          () => s.render(kDawSampleRate),
        ),
      );

  /// Replace the arrangement with a saved project. Throws [FormatException] on
  /// a bad file; on success the timeline, cache and undo history are reset.
  void loadProject(String json) {
    // Restored models render themselves, which for a tracker song or a groove
    // is not free — so the project's baked audio is handed straight to the
    // render cache under each restored source's key. A reopened arrangement
    // therefore plays immediately AND is editable, instead of trading one for
    // the other.
    final warm = <Object, Float64List>{};
    // May throw before we mutate anything.
    final loaded = projectFromJson(json, warmCache: warm);
    // A project written before D6, or one with a constant tempo, carries no
    // map — keep the opening tempo the app already has rather than resetting it.
    tempoMap = projectTempoFromJson(json) ?? TempoMap.constant(bpm);
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
    // Group ids are assigned by an incrementing counter, so a loaded project
    // whose ids run higher than the counter would let the NEXT group collide
    // with an existing one — silently linking clips the user never linked.
    _lastGroupId = 0;
    for (final track in timeline.tracks) {
      for (final clip in track.clips) {
        final id = clip.groupId;
        if (id != null && id > _lastGroupId) _lastGroupId = id;
      }
    }
    _cache
      ..clear()
      ..addAll(warm);
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
    required this.tempoMap,
    required this.effects,
    required this.buses,
    required this.tracks,
    required this.nextStartMs,
    required this.markers,
  });

  /// Immutable and replaced wholesale, so the instance is the copy.
  final TempoMap tempoMap;
  final List<DawClipEffect> effects;
  final List<DawBus> buses;
  final List<DawTrack> tracks;
  final double nextStartMs;

  /// Markers are immutable, so sharing the instances is a deep-enough copy.
  final List<DawMarker> markers;
}
