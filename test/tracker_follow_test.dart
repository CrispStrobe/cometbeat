// WS-T1 — the playing row stays in view, and moves WITH the music.
//
// The card called this "the follow scroll is jumpTo". That is not the defect:
// jumpTo with a continuously-moving target is exactly right, and animateTo per
// frame would fight itself. The defect was that `_followPlayhead` only ran when
// the INTEGER row changed, so the view sat still for a whole row and then
// lurched a row's height — worst at slow tempos, which is when someone is
// reading along. A bigger one turned up on the way: the SONG branch never
// called it at all, so following silently did nothing in the mode people
// actually listen in.
//
// ⚠️ These are unit tests over `followScrollOffset`, deliberately. My first
// attempt drove the real widget and asserted the scroll offset moved. It passed
// alone and failed under `--concurrency`, because how far a playhead advances
// per pump depends on how much time the harness delivers — it was measuring the
// harness, not the code. Worse, an earlier version guarded on
// `maxScrollExtent <= 0` and returned early: on the shared 1400x2400 test
// surface the grid never overflowed, so all three tests passed while asserting
// NOTHING. The arithmetic below is the part that is actually interesting, and
// it is exact.

import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:flutter_test/flutter_test.dart';

const double _row = 30;

double? _at(double exactRow, {double current = 0, double maxExtent = 5000}) =>
    followScrollOffset(
      exactRow: exactRow,
      rowHeight: _row,
      current: current,
      maxExtent: maxExtent,
    );

void main() {
  group('it follows the SUB-ROW position', () {
    test('two points inside one row give two different targets', () {
      // The whole fix. Row-quantised following cannot tell 4.0 from 4.5, so
      // both would give the same answer and the view would sit still.
      final quarter = _at(4.25, current: 100);
      final half = _at(4.5, current: 100);
      expect(quarter, isNotNull);
      expect(half, isNotNull);
      expect(quarter, isNot(half));
    });

    test('it moves monotonically as the playhead advances', () {
      var previous = -1.0;
      for (var r = 5.0; r < 40; r += 0.25) {
        // Follow from where the previous step left us, as the real loop does.
        final next = _at(r, current: previous < 0 ? 0 : previous) ?? previous;
        expect(next, greaterThanOrEqualTo(previous));
        previous = next;
      }
    });
  });

  group('easing', () {
    test('it covers a FRACTION of the distance, not all of it', () {
      // Rigid tracking would land exactly on the target every frame; that is
      // what makes a follow feel glued rather than smooth.
      //
      // Row 8, not 20: row 20 is 480 px away, which is PAST the snap threshold
      // and therefore correctly jumps. My first version of this test asked for
      // easing at a distance the design says to snap.
      const target = (8 * _row) - kFollowMarginPx;
      expect(target, lessThan(kFollowSnapPx), reason: 'inside the ease band');
      final next = _at(8)!;
      expect(next, lessThan(target));
      expect(next, closeTo(target * kFollowEase, 1e-9));
    });

    test('repeated steps converge on the target', () {
      // Easing that never arrives would leave the playhead permanently off
      // its mark.
      const target = (8 * _row) - kFollowMarginPx;
      var current = 0.0;
      for (var i = 0; i < 60; i++) {
        current = _at(8, current: current) ?? current;
      }
      expect(current, closeTo(target, 1));
    });
  });

  group('when easing is the WRONG answer', () {
    test('a big jump snaps instead of gliding', () {
      // A wrap or a Bxx/Dxx order jump is not the music advancing. Gliding
      // across the whole pattern would arrive after it had moved on again.
      // 200 rows is 5880 px, past this viewport's 5000 — so the answer is the
      // clamp, and it arrives in ONE step rather than easing there.
      final far = _at(200);
      expect(far, 5000);
    });

    test('the snap threshold is what decides, not the row count', () {
      const justUnder = kFollowSnapPx - 10;
      final eased = _at((justUnder + kFollowMarginPx) / _row)!;
      expect(eased, lessThan(justUnder), reason: 'under the threshold: eased');
    });
  });

  group('what it must NOT do', () {
    test('a stationary playhead returns null — it does not fight the user', () {
      // Someone scrolling by hand while the music sits still must not be
      // dragged back.
      const target = (10 * _row) - kFollowMarginPx;
      expect(_at(10, current: target), isNull);
      expect(_at(10, current: target + 0.2), isNull);
    });

    test('it never scrolls past the end', () {
      // It APPROACHES the clamp rather than snapping to it — the clamp bounds
      // the target, and the easing still applies. (My first expectation here
      // asserted an exact 300 and was simply wrong about the design.)
      var current = 0.0;
      for (var i = 0; i < 60; i++) {
        current = _at(500, current: current, maxExtent: 300) ?? current;
        expect(current, lessThanOrEqualTo(300));
      }
      expect(current, closeTo(300, 1));
    });

    test('early rows ease back to the top, never past it', () {
      // Row 0 wants a NEGATIVE offset once the margin is applied, so the clamp
      // is what keeps it at 0 — and the view eases back rather than jumping.
      expect(_at(0), isNull, reason: 'already at the top');
      var current = 50.0;
      for (var i = 0; i < 60; i++) {
        current = _at(1, current: current) ?? current;
        expect(current, greaterThanOrEqualTo(0));
      }
      expect(current, closeTo(0, 1));
    });
  });
}
