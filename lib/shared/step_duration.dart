// lib/shared/step_duration.dart
//
// B2 — the step/duration ladder, once.
//
// Every mode that turns a STEP GRID into engravable notation needs the same
// three operations: how many grid steps a [NoteDuration] occupies, which note
// values land on whole steps at a given resolution, and how to greedily split a
// run of N steps into those values. The Tracker (`tracker_notation.dart`) and
// the module importer (`mod/module_notation.dart`) each carried a verbatim copy
// of all three; the Tab editor has the same maths at a fixed 32nd grid.
//
// They are one thing now. Pure Dart, no Flutter — headless-testable.
//
// The grid is expressed as [stepsPerBeat] in 4/4, so a whole note is
// `stepsPerBeat * 4` steps: 2 = eighth-note steps (the Loop/Tracker grid),
// 4 = sixteenths, 8 = thirty-seconds (the Tab grid).

import 'package:crisp_notation/crisp_notation.dart';

/// A [NoteDuration] as whole grid steps at [stepsPerBeat] resolution, in 4/4.
///
/// Rounded — a value that does not land on the grid (a triplet at
/// [stepsPerBeat] 2, say) quantizes to the nearest step. Exact for every value
/// the ladder itself yields.
int durationToSteps(NoteDuration d, int stepsPerBeat) {
  final (num, den) = d.fraction;
  return (num * (stepsPerBeat * 4) / den).round();
}

/// Every candidate note value, largest first, as `(duration, lengthInSteps)`.
const _candidates = <(NoteDuration, double)>[
  (NoteDuration(DurationBase.whole), 1.0),
  (NoteDuration(DurationBase.half, dots: 1), 0.75),
  (NoteDuration(DurationBase.half), 0.5),
  (NoteDuration(DurationBase.quarter, dots: 1), 0.375),
  (NoteDuration(DurationBase.quarter), 0.25),
  (NoteDuration(DurationBase.eighth, dots: 1), 0.1875),
  (NoteDuration(DurationBase.eighth), 0.125),
  (NoteDuration(DurationBase.sixteenth, dots: 1), 0.09375),
  (NoteDuration(DurationBase.sixteenth), 0.0625),
];

/// The note values available at [stepsPerBeat] resolution, largest first, as
/// `(duration, lengthInSteps)`.
///
/// Only values spanning a WHOLE number of steps in 4/4 are included, so a
/// dotted eighth is dropped when a step is itself an eighth — engraving a value
/// the grid cannot express would silently misplace everything after it.
List<(NoteDuration, int)> durationLadder(int stepsPerBeat) {
  final stepsPerWhole = stepsPerBeat * 4; // 4/4
  final out = <(NoteDuration, int)>[];
  for (final (dur, frac) in _candidates) {
    final steps = frac * stepsPerWhole;
    if ((steps - steps.roundToDouble()).abs() < 1e-9) {
      out.add((dur, steps.round()));
    }
  }
  return out; // already largest-first
}

/// Greedily splits [steps] grid steps into note values from [ladder], largest
/// first. The caller ties the pieces together.
///
/// A remainder smaller than the ladder's smallest value takes that smallest
/// value rather than throwing — an off-grid import should engrave slightly long,
/// not crash the importer. (The Tracker's old copy threw a `StateError` here;
/// the module importer's did not. This is the module importer's behaviour.)
/// Returns an empty list for a non-positive [steps].
List<NoteDuration> decomposeSteps(
  int steps,
  List<(NoteDuration, int)> ladder,
) {
  final out = <NoteDuration>[];
  var rem = steps;
  while (rem > 0) {
    final piece = ladder.firstWhere(
      (d) => d.$2 <= rem,
      orElse: () => ladder.last,
    );
    out.add(piece.$1);
    rem -= piece.$2;
  }
  return out;
}
