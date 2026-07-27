// lib/core/audio/loop_automation.dart
//
// Automation lanes: a per-track value that CHANGES across the loop, rather than
// one number held for the whole thing.
//
// This is the model and its codec only — nothing here renders audio. It is
// separate from the engine because the shape has to survive a share token and a
// save slot, and a codec is much easier to trust when it can be read on its own.
//
// Design notes worth keeping:
//
// ONE VALUE PER EIGHTH-STEP. The same grid the tune and beat editors already
// use, so a lane can be drawn with the same gesture and read at render time by
// indexing rather than interpolating. A lane shorter than the loop repeats, so
// it tiles like a pattern does — including over a track shortened for polymeter.
//
// NORMALISED 0..1, ALWAYS. Each parameter maps its own range in
// [AutomationParam.valueAt]; the lane itself never stores decibels or hertz.
// That keeps the codec stable if a parameter's range is ever retuned, and keeps
// a drawn lane meaningful when it is copied to another parameter.
//
// ABSENT IS NOT FLAT. A track with no lane must render byte-for-byte as it did
// before automation existed, so "no lane" is null rather than a lane of 1.0 —
// a flat lane still costs a multiply, and byte-identical is a property worth
// being able to assert.

import 'dart:math' as math;

/// A per-track value that automation can move over the loop.
///
/// Deliberately small. Level, pan and filter are already per-track scalars in
/// the mix path, so automating them turns a constant into a lookup and adds no
/// DSP. Tempo and swing are excluded because moving either would change a loop
/// boundary, which is the sample-exactness the gapless seam depends on.
enum AutomationParam {
  /// Track gain, 0 = silent … 1 = the track's authored level.
  level,

  /// Stereo position, 0 = hard left … 0.5 = centre … 1 = hard right.
  pan,

  /// Per-track tone, 0 = darkest … 0.5 = unfiltered … 1 = thinnest.
  filter;

  /// The value a lane of [normalised] means for THIS parameter.
  double valueAt(double normalised) {
    final v = normalised.clamp(0.0, 1.0);
    return switch (this) {
      AutomationParam.level => v,
      // Pan and filter are two-sided: the middle of the lane is neutral.
      AutomationParam.pan => v * 2 - 1,
      AutomationParam.filter => v * 2 - 1,
    };
  }

  /// The lane value that leaves this parameter alone.
  double get neutral => switch (this) {
        AutomationParam.level => 1,
        AutomationParam.pan => 0.5,
        AutomationParam.filter => 0.5,
      };
}

/// One lane: a normalised value per eighth-step.
///
/// Immutable, with value equality, so a spec can be compared and cached by it.
class AutomationLane {
  AutomationLane(List<double> values)
      : values = List<double>.unmodifiable(
          [for (final v in values) v.clamp(0.0, 1.0)],
        );

  /// A lane of [steps] all at [param]'s neutral value.
  factory AutomationLane.neutral(AutomationParam param, int steps) =>
      AutomationLane(List<double>.filled(math.max(1, steps), param.neutral));

  final List<double> values;

  bool get isEmpty => values.isEmpty;

  /// The value at [step], wrapping — so a lane shorter than the loop repeats,
  /// exactly as a pattern does.
  double at(int step) {
    if (values.isEmpty) return 0;
    final i = step % values.length;
    return values[i < 0 ? i + values.length : i];
  }

  /// This lane with [step] set to [value]; the lane itself never changes.
  AutomationLane withStep(int step, double value) {
    if (values.isEmpty || step < 0 || step >= values.length) return this;
    final next = List<double>.of(values);
    next[step] = value.clamp(0.0, 1.0);
    return AutomationLane(next);
  }

  /// Whether every step holds [param]'s neutral value — i.e. the lane exists
  /// but does nothing, which a caller may prefer to drop.
  bool isNeutralFor(AutomationParam param) =>
      values.every((v) => (v - param.neutral).abs() < 1e-9);

  List<double> toJson() => values;

  /// Null when [raw] is not a lane. An empty list is not a lane either: it
  /// would index to nothing at render time.
  static AutomationLane? fromJson(Object? raw) {
    if (raw is! List || raw.isEmpty) return null;
    final out = <double>[];
    for (final v in raw) {
      if (v is num) {
        out.add(v.toDouble());
      } else if (v is String) {
        final parsed = double.tryParse(v);
        if (parsed == null) return null;
        out.add(parsed);
      } else {
        return null;
      }
    }
    return AutomationLane(out);
  }

  @override
  bool operator ==(Object other) {
    if (other is! AutomationLane || other.values.length != values.length) {
      return false;
    }
    for (var i = 0; i < values.length; i++) {
      if (other.values[i] != values[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(values);

  @override
  String toString() => 'AutomationLane(${values.length} steps)';
}

/// Every lane in a groove: track id → parameter → lane.
///
/// A plain nested map rather than a class with behaviour, because it is carried
/// through `GrooveSpec`, a share token and a save slot, and the less it does the
/// less there is to keep in step across those three.
typedef AutomationLanes = Map<String, Map<AutomationParam, AutomationLane>>;

/// Serialises [lanes] for a share token / save slot.
///
/// Tracks with no lanes are omitted entirely, so a groove that uses no
/// automation adds nothing to its token — old tokens and new ones stay
/// byte-identical for the same groove.
Map<String, dynamic> automationToJson(AutomationLanes lanes) => {
      for (final MapEntry(key: track, value: params) in lanes.entries)
        if (params.isNotEmpty)
          track: {
            for (final MapEntry(key: param, value: lane) in params.entries)
              param.name: lane.toJson(),
          },
    };

/// The inverse of [automationToJson]. Unknown parameter names and malformed
/// lanes are skipped rather than throwing: a token from a newer build should
/// lose the lane it cannot read, not refuse to load the groove.
AutomationLanes automationFromJson(Object? raw) {
  final out = <String, Map<AutomationParam, AutomationLane>>{};
  if (raw is! Map) return out;
  for (final entry in raw.entries) {
    final track = entry.key;
    final params = entry.value;
    if (track is! String || params is! Map) continue;
    final byParam = <AutomationParam, AutomationLane>{};
    for (final p in params.entries) {
      final name = p.key;
      if (name is! String) continue;
      final param =
          AutomationParam.values.where((v) => v.name == name).firstOrNull;
      if (param == null) continue;
      final lane = AutomationLane.fromJson(p.value);
      if (lane != null) byParam[param] = lane;
    }
    if (byParam.isNotEmpty) out[track] = byParam;
  }
  return out;
}
