// The tempo map — where the beat actually falls when the tempo is not one
// number.
//
// A single `bpm` is enough to draw a grid for a loop and nothing else. The
// moment a piece slows into a section, or a recording drifts, or someone wants
// a ritardando, "one beat = 60000/bpm milliseconds" stops being true — and
// every feature built on it (the grid, snapping, any future bar/beat readout or
// tempo-aware quantisation) inherits the error.
//
// The model is a list of tempo CHANGES at points in time, and the two questions
// worth asking of it are inverses: given a moment, which beat is it
// ([beatAtMs]); given a beat, when does it happen ([msAtBeat]). Both are exact
// under piecewise-constant tempo, which is what a tempo map is.
//
// Deliberately NOT modelled: gradual tempo curves (an accelerando as a ramp
// rather than a staircase). They are a different integral, they need a curve
// shape per segment, and every consumer here wants "which beat is this" —
// which a fine-grained staircase answers to any precision anyone can hear.
// Stated so the absence reads as a decision rather than an oversight.

import 'dart:math' as math;

/// The tempo from [ms] onward, until the next change.
class TempoChange {
  const TempoChange({required this.ms, required this.bpm});

  /// Where this tempo takes effect, in ms from the timeline start.
  final double ms;

  /// Beats per minute from here on.
  final double bpm;

  TempoChange copyWith({double? ms, double? bpm}) =>
      TempoChange(ms: ms ?? this.ms, bpm: bpm ?? this.bpm);

  Map<String, dynamic> toJson() => {'ms': ms, 'bpm': bpm};

  static TempoChange? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final ms = raw['ms'];
    final bpm = raw['bpm'];
    if (ms is! num || bpm is! num || !ms.isFinite || !bpm.isFinite) return null;
    if (bpm <= 0) return null;
    return TempoChange(
      ms: math.max(0, ms.toDouble()),
      bpm: bpm.toDouble().clamp(kMinBpm, kMaxBpm),
    );
  }
}

/// The tempo range the app accepts anywhere — below 40 the "beat" stops being
/// perceived as a pulse, above 300 it is being counted in half-time by anyone
/// listening.
const double kMinBpm = 40;
const double kMaxBpm = 300;

/// A piecewise-constant tempo over the timeline.
///
/// Always has a tempo at 0 — a map that starts partway through would leave the
/// opening bars undefined, and every caller would need a fallback. Constructing
/// one from an empty or 0-less list inserts the default at the start.
class TempoMap {
  TempoMap([List<TempoChange>? changes]) : changes = _normalise(changes);

  /// A map with one tempo throughout — what a project has until someone adds a
  /// change, and what the old single-`bpm` field meant.
  TempoMap.constant(double bpm)
      : changes = [
          TempoChange(ms: 0, bpm: bpm.clamp(kMinBpm, kMaxBpm)),
        ];

  /// Sorted by [TempoChange.ms], first entry always at 0.
  final List<TempoChange> changes;

  static List<TempoChange> _normalise(List<TempoChange>? input) {
    final sorted = [...?input]..sort((a, b) => a.ms.compareTo(b.ms));
    // Drop duplicates at the same instant — the later one wins, since that is
    // what "set the tempo here" means when it is done twice.
    final out = <TempoChange>[];
    for (final change in sorted) {
      if (out.isNotEmpty && (out.last.ms - change.ms).abs() < 1e-9) {
        out[out.length - 1] = change;
      } else {
        out.add(change);
      }
    }
    if (out.isEmpty || out.first.ms > 0) {
      out.insert(0, TempoChange(ms: 0, bpm: out.isEmpty ? 120 : out.first.bpm));
    }
    return out;
  }

  /// Whether this is a single tempo throughout — the common case, and worth
  /// asking so callers can keep their fast path.
  bool get isConstant => changes.length == 1;

  /// The tempo in force at [ms].
  double bpmAt(double ms) {
    var bpm = changes.first.bpm;
    for (final change in changes) {
      if (change.ms > ms + 1e-9) break;
      bpm = change.bpm;
    }
    return bpm;
  }

  /// The musical position of [ms], in beats from the start.
  ///
  /// Accumulated segment by segment, because beats do not scale linearly with
  /// time once the tempo changes — which is the entire reason this class
  /// exists.
  double beatAtMs(double ms) {
    if (ms <= 0) return 0;
    var beats = 0.0;
    for (var i = 0; i < changes.length; i++) {
      final start = changes[i].ms;
      if (start >= ms) break;
      final end = i + 1 < changes.length ? math.min(changes[i + 1].ms, ms) : ms;
      beats += (end - start) / (60000 / changes[i].bpm);
    }
    return beats;
  }

  /// When [beat] happens, in ms — the inverse of [beatAtMs].
  double msAtBeat(double beat) {
    if (beat <= 0) return 0;
    var remaining = beat;
    for (var i = 0; i < changes.length; i++) {
      final beatMs = 60000 / changes[i].bpm;
      final segmentMs = i + 1 < changes.length
          ? changes[i + 1].ms - changes[i].ms
          : double.infinity;
      final segmentBeats = segmentMs / beatMs;
      if (remaining <= segmentBeats) {
        return changes[i].ms + remaining * beatMs;
      }
      remaining -= segmentBeats;
    }
    // Unreachable: the last segment is unbounded.
    return changes.last.ms + remaining * (60000 / changes.last.bpm);
  }

  /// [ms] snapped to the nearest beat — what a drag should land on.
  double snapToBeat(double ms) => msAtBeat(beatAtMs(ms).roundToDouble());

  /// The times of every beat line from 0 up to [untilMs], for drawing a grid.
  ///
  /// Returned as positions rather than a spacing because the spacing is not
  /// constant any more; a painter that takes one number cannot draw this.
  /// [maxLines] bounds the work — at 300 BPM a twenty-minute arrangement is
  /// 6000 beats, and past a few thousand lines the grid is a grey wash anyway.
  List<double> beatTimes(double untilMs, {int maxLines = 4096}) {
    final out = <double>[];
    if (untilMs <= 0) return out;
    var beat = 0.0;
    while (out.length < maxLines) {
      final ms = msAtBeat(beat);
      if (ms > untilMs) break;
      out.add(ms);
      beat += 1;
    }
    return out;
  }

  /// A copy with [change] added (replacing any at the same instant).
  TempoMap withChange(TempoChange change) => TempoMap([...changes, change]);

  /// A copy without the change at [ms]. The one at 0 cannot be removed — the
  /// opening tempo has to come from somewhere.
  TempoMap withoutChangeAt(double ms) {
    if (ms <= 0) return this;
    return TempoMap([
      for (final change in changes)
        if ((change.ms - ms).abs() > 1e-9) change,
    ]);
  }

  List<Map<String, dynamic>> toJson() => [
        for (final change in changes) change.toJson(),
      ];

  static TempoMap fromJson(Object? raw) {
    if (raw is! List) return TempoMap.constant(120);
    return TempoMap([
      for (final entry in raw)
        if (TempoChange.fromJson(entry) case final change?) change,
    ]);
  }
}
