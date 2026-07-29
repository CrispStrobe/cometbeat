// WS-T6 — where the beat and bar lines go.
//
// Two views draw a beat grid over the same pattern, and before this they
// disagreed: the tracker grid read `_highlightEvery ?? stepsPerBeat` and then
// hardcoded FOUR beats to a bar, while the piano roll hardcoded 4 and 16 and
// read neither. A pattern at 3 rows to the beat, or a piece in 3/4, got bar
// lines in different wrong places depending on which view you looked at.
//
// The arithmetic is tiny, which is exactly why it is worth pinning: an
// off-by-one in `isBar` is invisible in a screenshot and changes what the music
// appears to be.

import 'package:comet_beat/features/games/composition/tracker_meter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('beats and bars in 4/4', () {
    const meter = TrackerMeter();

    test('a beat line every four rows', () {
      expect(meter.isBeat(0), isTrue);
      expect(meter.isBeat(4), isTrue);
      expect(meter.isBeat(1), isFalse);
      expect(meter.isBeat(3), isFalse);
    });

    test('a bar line every sixteen', () {
      expect(meter.isBar(0), isTrue);
      expect(meter.isBar(16), isTrue);
      expect(meter.isBar(4), isFalse, reason: 'that is a beat, not a bar');
      expect(meter.rowsPerBar, 16);
    });
  });

  group('a meter that is NOT 4/4 — the case that was broken', () {
    test('3/4 bars every twelve rows, not sixteen', () {
      // The grid computed `row % (highlightEvery * 4)`, so this pattern's bar
      // lines landed on 16 and 32 — a waltz drawn as common time.
      const waltz = TrackerMeter(beatsPerBar: 3);
      expect(waltz.rowsPerBar, 12);
      expect(waltz.isBar(12), isTrue);
      expect(waltz.isBar(16), isFalse);
    });

    test('three rows to the beat still bars correctly', () {
      // Triplet-feel patterns: the beat is not four rows, and the roll ignored
      // that entirely.
      const triplets = TrackerMeter(rowsPerBeat: 3);
      expect(triplets.isBeat(3), isTrue);
      expect(triplets.isBeat(4), isFalse);
      expect(triplets.rowsPerBar, 12);
    });

    test('6/8 groups as six beats', () {
      const sixEight = TrackerMeter(beatsPerBar: 6);
      expect(sixEight.rowsPerBar, 24);
      expect(sixEight.isBar(24), isTrue);
      expect(sixEight.isBar(16), isFalse);
    });
  });

  group('every bar row is also a beat row', () {
    test('so a drawer must test isBar FIRST', () {
      // If a painter tests isBeat first it draws every bar as a beat, and the
      // meter reads as 4/4 whatever it actually is. Both painters do bar-first;
      // this is the fact that makes that necessary.
      for (final meter in kCommonMeters) {
        for (var row = 0; row < 64; row++) {
          if (meter.isBar(row)) {
            expect(
              meter.isBeat(row),
              isTrue,
              reason: 'row $row of ${meter.label}',
            );
          }
        }
      }
    });
  });

  group('counting for a person', () {
    test('bars and beats count from one, as musicians do', () {
      const meter = TrackerMeter();
      expect(meter.barOf(0), 1);
      expect(meter.beatInBar(0), 1);
      expect(meter.beatInBar(4), 2);
      expect(meter.barOf(16), 2);
      expect(meter.beatInBar(16), 1);
    });

    test('it counts right in 3/4 too', () {
      const waltz = TrackerMeter(beatsPerBar: 3);
      expect(waltz.barOf(11), 1);
      expect(waltz.barOf(12), 2);
      expect(waltz.beatInBar(8), 3);
    });

    test('a negative row does not produce bar zero or a crash', () {
      const meter = TrackerMeter();
      expect(meter.barOf(-1), 1);
      expect(meter.beatInBar(-1), 1);
      expect(meter.isBeat(-4), isFalse);
      expect(meter.isBar(-16), isFalse);
    });
  });

  group('value semantics', () {
    test('two meters with the same numbers are equal', () {
      // The painters repaint on inequality; a meter that never compared equal
      // would repaint every frame.
      expect(const TrackerMeter(), const TrackerMeter());
      expect(const TrackerMeter(beatsPerBar: 3), isNot(const TrackerMeter()));
      expect(const TrackerMeter().hashCode, const TrackerMeter().hashCode);
    });

    test('copyWith changes one axis at a time', () {
      const meter = TrackerMeter(rowsPerBeat: 8, beatsPerBar: 3);
      expect(meter.copyWith(beatsPerBar: 4).rowsPerBeat, 8);
      expect(meter.copyWith(rowsPerBeat: 4).beatsPerBar, 3);
    });

    test('the offered meters are distinct and sane', () {
      expect(kCommonMeters.toSet().length, kCommonMeters.length);
      for (final meter in kCommonMeters) {
        expect(meter.rowsPerBeat, greaterThan(0));
        expect(meter.beatsPerBar, greaterThan(0));
        expect(meter.label, isNotEmpty);
      }
    });
  });
}
