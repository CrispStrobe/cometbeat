// test/step_duration_test.dart
//
// B2 — one step/duration ladder. `durationToSteps`, the ladder, and the greedy
// decomposition were a verbatim copy in `tracker_notation.dart` and
// `mod/module_notation.dart`. These tests pin the behaviour both copies had, so
// the consolidation is provably a no-op, and cover the one place they DIFFERED:
// an unrepresentable remainder threw a StateError in the Tracker's copy and fell
// back to the smallest value in the module importer's. The shared version keeps
// the non-throwing behaviour.

import 'package:comet_beat/core/audio/mod/module_notation.dart' as module;
import 'package:comet_beat/features/games/composition/tracker_notation.dart'
    as tracker;
import 'package:comet_beat/shared/step_duration.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('durationToSteps', () {
    test('a whole note is four beats worth of steps at any resolution', () {
      for (final spb in [1, 2, 4, 8]) {
        expect(
          durationToSteps(const NoteDuration(DurationBase.whole), spb),
          spb * 4,
        );
      }
    });

    test('the standard values on the eighth-step grid (the Loop/Tracker grid)',
        () {
      const spb = 2;
      expect(durationToSteps(const NoteDuration(DurationBase.whole), spb), 8);
      expect(durationToSteps(const NoteDuration(DurationBase.half), spb), 4);
      expect(durationToSteps(const NoteDuration(DurationBase.quarter), spb), 2);
      expect(durationToSteps(const NoteDuration(DurationBase.eighth), spb), 1);
      expect(
        durationToSteps(const NoteDuration(DurationBase.half, dots: 1), spb),
        6,
      );
      expect(
        durationToSteps(const NoteDuration(DurationBase.quarter, dots: 1), spb),
        3,
      );
    });

    test('an off-grid value quantizes to the nearest step, it does not throw',
        () {
      // A sixteenth is half a step on the eighth grid — rounds to 1, not 0, so
      // an imported 16th still occupies time instead of vanishing.
      expect(
        durationToSteps(const NoteDuration(DurationBase.sixteenth), 2),
        1,
      );
    });
  });

  group('durationLadder', () {
    test('only values that land on whole steps are offered', () {
      // At stepsPerBeat 2 a step IS an eighth, so nothing shorter and no
      // dotted-eighth can be expressed.
      final ladder = durationLadder(2);
      final lengths = ladder.map((e) => e.$2).toList();
      expect(lengths, [8, 6, 4, 3, 2, 1]);
    });

    test('a finer grid offers more values', () {
      expect(
        durationLadder(4).map((e) => e.$2).toList(),
        [16, 12, 8, 6, 4, 3, 2, 1],
      );
      expect(
        durationLadder(8).map((e) => e.$2).toList(),
        [32, 24, 16, 12, 8, 6, 4, 3, 2],
      );
    });

    test('the 32nd grid cannot express a single step — a real gap, pinned', () {
      // At stepsPerBeat 8 a step is a 32nd, but the candidate list stops at the
      // sixteenth, so the smallest ladder value is TWO steps. A lone 32nd
      // therefore engraves as a sixteenth (see decomposeSteps' fallback). This
      // is why the Tab editor, which works on a 32nd grid, computes its own
      // step count from the exact note fraction instead of using this ladder.
      expect(durationLadder(8).last.$2, 2);
      expect(durationLadder(4).last.$2, 1);
      expect(durationLadder(2).last.$2, 1);
    });

    test('it is always largest-first — the greedy split depends on it', () {
      for (final spb in [1, 2, 4, 8]) {
        final lengths = durationLadder(spb).map((e) => e.$2).toList();
        for (var i = 1; i < lengths.length; i++) {
          expect(lengths[i], lessThan(lengths[i - 1]), reason: 'spb $spb');
        }
      }
    });
  });

  group('decomposeSteps', () {
    test('the pieces sum back exactly whenever the grid can express a step',
        () {
      // Ladders whose smallest value is one step (stepsPerBeat 1/2/4) can tile
      // any step count exactly.
      for (final spb in [1, 2, 4]) {
        final ladder = durationLadder(spb);
        expect(ladder.last.$2, 1, reason: 'spb $spb precondition');
        for (var steps = 1; steps <= 64; steps++) {
          final total = decomposeSteps(steps, ladder).fold<int>(
            0,
            (sum, d) => sum + durationToSteps(d, spb),
          );
          expect(total, steps, reason: 'spb $spb, steps $steps');
        }
      }
    });

    test('it never engraves SHORT, and overshoots by less than one value', () {
      // On the 32nd grid the smallest value is two steps, so an odd count
      // cannot tile exactly. The guarantee is one-sided: the run is never cut
      // short (which would drop audible time), and the overshoot is bounded by
      // the ladder's smallest value.
      final ladder = durationLadder(8);
      final smallest = ladder.last.$2;
      for (var steps = 1; steps <= 64; steps++) {
        final total = decomposeSteps(steps, ladder).fold<int>(
          0,
          (sum, d) => sum + durationToSteps(d, 8),
        );
        expect(total, greaterThanOrEqualTo(steps), reason: 'steps $steps');
        expect(total - steps, lessThan(smallest), reason: 'steps $steps');
      }
    });

    test('golden splits on the eighth grid', () {
      final ladder = durationLadder(2);
      List<String> split(int steps) =>
          decomposeSteps(steps, ladder).map((d) => '$d').toList();
      // 1 step = one eighth; 8 = a whole; 7 = whole-minus-an-eighth becomes
      // dotted-half + quarter (greedy: 6 then 2 fits in 7? no — 6 then 1).
      expect(split(1).length, 1);
      expect(split(8).length, 1);
      expect(
        decomposeSteps(7, ladder).map((d) => durationToSteps(d, 2)).toList(),
        [6, 1],
      );
      expect(
        decomposeSteps(5, ladder).map((d) => durationToSteps(d, 2)).toList(),
        [4, 1],
      );
      expect(
        decomposeSteps(11, ladder).map((d) => durationToSteps(d, 2)).toList(),
        [8, 3],
      );
    });

    test('a non-positive step count yields nothing', () {
      final ladder = durationLadder(2);
      expect(decomposeSteps(0, ladder), isEmpty);
      expect(decomposeSteps(-3, ladder), isEmpty);
    });

    test('an unrepresentable remainder falls back instead of throwing', () {
      // The Tracker's old copy called firstWhere with no orElse here and threw
      // a StateError. A malformed import should engrave slightly long, not
      // crash the importer.
      final coarse = [
        (const NoteDuration(DurationBase.whole), 8),
        (const NoteDuration(DurationBase.half), 4),
      ];
      final pieces = decomposeSteps(2, coarse);
      expect(pieces, hasLength(1));
      expect(pieces.single, const NoteDuration(DurationBase.half));
    });
  });

  group('the two ex-copies now resolve to the one implementation', () {
    test('function identity', () {
      expect(module.durationToSteps, same(durationToSteps));
      expect(tracker.durationToSteps, same(durationToSteps));
      expect(module.durationLadder, same(durationLadder));
      expect(tracker.durationLadder, same(durationLadder));
      expect(module.decomposeSteps, same(decomposeSteps));
      expect(tracker.decomposeSteps, same(decomposeSteps));
    });
  });
}
