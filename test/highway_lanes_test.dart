// test/highway_lanes_test.dart
//
// Lane geometry. These tests are the guarantee behind the whole view: a block
// lands exactly on the key it names, black keys sit on the boundary between
// their neighbours and win a tap in their own row, and string lanes rise to
// the right like a keyboard does.

import 'package:comet_beat/core/games/highway/highway_chart.dart';
import 'package:comet_beat/core/games/highway/highway_instrument.dart';
import 'package:comet_beat/core/games/highway/highway_lanes.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart' show Tuning;
import 'package:flutter_test/flutter_test.dart';

HighwayEvent _note(int midi, {int? lane}) =>
    HighwayEvent(startBeat: 0, beats: 1, midi: midi, lane: lane);

void main() {
  group('KeyboardLaneMap', () {
    // C4..B4 — exactly one octave, 7 white keys.
    final map = KeyboardLaneMap(lowMidi: 60, highMidi: 71);

    test('white keys tile the width in order, edge to edge', () {
      final c = map.slotForMidi(60)!;
      final d = map.slotForMidi(62)!;
      final b = map.slotForMidi(71)!;
      expect(c.width, closeTo(1 / 7, 1e-9));
      expect(c.center, closeTo(0.5 / 7, 1e-9));
      expect(d.left, closeTo(c.right, 1e-9)); // no gaps between white keys
      expect(b.right, closeTo(1.0, 1e-9));
      expect(c.raised, isFalse);
    });

    test('a black key is narrower, raised, and on the boundary above its white',
        () {
      final c = map.slotForMidi(60)!;
      final cSharp = map.slotForMidi(61)!;
      expect(cSharp.raised, isTrue);
      expect(cSharp.width, lessThan(c.width));
      expect(cSharp.center, closeTo(c.right, 1e-9));
    });

    test('pitches outside the drawn keyboard have no slot at all', () {
      expect(map.slotForMidi(59), isNull);
      expect(map.slotForMidi(72), isNull);
      expect(map.slotFor(const HighwayEvent(startBeat: 0, beats: 1)), isNull);
    });

    test('a tap high on a black key beats the white key underneath it', () {
      final black = map.slotForMidi(61)!;
      expect(map.hitTest(black.center, 0.1)?.midi, 61); // upper row → black
      expect(map.hitTest(black.center, 0.9)?.midi, isNot(61)); // lower → white
    });

    test('every C gets a labelled octave rule', () {
      final wide = KeyboardLaneMap(lowMidi: 48, highMidi: 83);
      final labels = wide
          .gridLines()
          .where((l) => l.label != null)
          .map((l) => l.label)
          .toList();
      expect(labels, ['C3', 'C4', 'C5']);
      expect(wide.gridLines().where((l) => l.major).length, 3);
    });

    test('forRange pads a narrow piece out to a playable keyboard', () {
      final map = KeyboardLaneMap.forRange(60, 64);
      expect(map.whiteKeyCount, greaterThanOrEqualTo(15));
      expect(map.lowMidi % 12, 0); // snapped to a C
      expect(map.slotForMidi(60), isNotNull);
      expect(map.slotForMidi(64), isNotNull);
    });

    test('the rail draws every key, black ones last so they sit on top', () {
      final keys = map.railKeys();
      expect(keys.length, 12); // 7 white + 5 black
      expect(keys.take(7).every((k) => !k.slot.raised), isTrue);
      expect(keys.skip(7).every((k) => k.slot.raised), isTrue);
    });

    test('matching is by pitch — the key you pressed is the note you meant',
        () {
      final key = map.railKeys().firstWhere((k) => k.midi == 64);
      expect(map.matches(_note(64), key), isTrue);
      expect(map.matches(_note(65), key), isFalse);
    });
  });

  group('StringLaneMap', () {
    final map = StringLaneMap(Tuning.standardGuitar);

    test('lane 0 of the tuning (high E) is drawn on the RIGHT', () {
      final high = map.slotFor(_note(64, lane: 0))!;
      final low = map.slotFor(_note(40, lane: 5))!;
      expect(high.center, greaterThan(low.center)); // pitch rises rightward
    });

    test('an unfretted chart still lands on a plausible string', () {
      // E4 with no arranger input → the high E string, open.
      expect(
        map.slotForMidi(64)!.center,
        closeTo(map.slotFor(_note(64, lane: 0))!.center, 1e-9),
      );
    });

    test('a pitch below the instrument has no lane', () {
      expect(map.slotForMidi(20), isNull);
    });

    test('grading compares the STRING, because that is what a tap chooses', () {
      final key = map.railKeys().firstWhere((k) => k.lane == 3); // D string
      expect(map.matches(_note(55, lane: 3), key), isTrue);
      expect(map.matches(_note(55, lane: 2), key), isFalse);
    });

    test('one grid rule between each pair of strings', () {
      expect(map.gridLines().length, 5);
      expect(map.railKeys().length, 6);
    });

    test('the cello tuning gives four lanes, low C at the left', () {
      final cello = StringLaneMap(kCelloTuning);
      expect(cello.laneCount, 4);
      final lowC = cello.slotFor(_note(36, lane: 3))!;
      final highA = cello.slotFor(_note(57, lane: 0))!;
      expect(lowC.center, lessThan(highA.center));
    });
  });

  group('keyForMidi (what the microphone heard)', () {
    test('a keyboard answers with that very key', () {
      final map = KeyboardLaneMap(lowMidi: 60, highMidi: 71);
      expect(map.keyForMidi(64)?.midi, 64);
      expect(map.keyForMidi(61)?.midi, 61); // black keys too
      expect(map.keyForMidi(90), isNull); // not on this keyboard
    });

    test('a fretted instrument answers with the STRING it is played on', () {
      final map = StringLaneMap(Tuning.standardGuitar);
      // E4 is the open high E — string 0.
      expect(map.keyForMidi(64)?.lane, 0);
      // G3 sits on the D string at the 5th fret for a first-position hand.
      expect(map.keyForMidi(55)?.lane, isNotNull);
      expect(map.keyForMidi(20), isNull, reason: 'below the instrument');
    });

    test('grading accepts what keyForMidi returned', () {
      final map = StringLaneMap(Tuning.standardGuitar);
      final key = map.keyForMidi(64)!;
      expect(map.matches(_note(64, lane: 0), key), isTrue);
    });
  });

  group('PadLaneMap', () {
    test('collapses a melody onto lanes by contour', () {
      const chart = HighwayChart(
        name: 'x',
        bpm: 100,
        events: [
          HighwayEvent(startBeat: 0, beats: 1, midi: 60),
          HighwayEvent(startBeat: 1, beats: 1, midi: 72),
        ],
      );
      final map = PadLaneMap.forChart(chart);
      final low = map.slotFor(chart.events.first)!;
      final high = map.slotFor(chart.events.last)!;
      expect(low.center, lessThan(high.center));
      expect(map.laneCount, 4);
    });

    test('an explicit lane wins over the pitch (drum pieces)', () {
      final map = PadLaneMap(laneCount: 4, lowMidi: 60, highMidi: 72);
      final key = map.hitTest(0.9, 0.5)!;
      expect(key.lane, 3);
      expect(map.matches(_note(60, lane: 3), key), isTrue);
    });
  });

  group('PitchLaneMap', () {
    const map = PitchLaneMap(lowMidi: 48, highMidi: 72);

    test('pitch is continuous, so a live reading has an x of its own', () {
      expect(map.xForPitch(48), closeTo(0, 1e-9));
      expect(map.xForPitch(60), closeTo(0.5, 1e-9));
      expect(map.xForPitch(60.5), greaterThan(map.xForPitch(60)));
      expect(map.xForPitch(200), 1.0); // clamped, never off-canvas
    });

    test('octave rules are labelled', () {
      expect(
        map.gridLines().map((l) => l.label),
        containsAll(['C3', 'C4', 'C5']),
      );
    });
  });
}
