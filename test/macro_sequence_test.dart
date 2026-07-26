// MacroSequence (macro_sequence.dart) — the per-tick instrument macro model.
// Pure model + evaluation, so every branch of the sustain/loop/release semantics
// is pinned here before any voice depends on it.

import 'package:comet_beat/core/audio/macro_sequence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('empty', () {
    test('an empty macro is empty and returns the fallback', () {
      const m = MacroSequence(target: MacroTarget.volume, values: []);
      expect(m.isEmpty, isTrue);
      expect(m.valueAt(0, fallback: 42), 42);
      expect(m.valueAt(99, fallback: 7), 7);
    });
  });

  group('sustain, no loop', () {
    const m = MacroSequence(target: MacroTarget.volume, values: [10, 20, 30]);

    test('steps one value per tick', () {
      expect(m.valueAt(0), 10);
      expect(m.valueAt(1), 20);
      expect(m.valueAt(2), 30);
    });

    test('holds the last value past the end', () {
      expect(m.valueAt(3), 30);
      expect(m.valueAt(1000), 30);
    });

    test('a negative tick clamps to the first value', () {
      expect(m.valueAt(-5), 10);
    });
  });

  group('sustain loop', () {
    // Linear 0,1 then loop the [2..4] segment: 20,30,40,20,30,40,...
    const m = MacroSequence(
      target: MacroTarget.arpeggio,
      values: [0, 10, 20, 30, 40],
      loopStart: 2,
      loopEnd: 4,
    );

    test('plays linearly up to loopEnd', () {
      expect([for (var t = 0; t <= 4; t++) m.valueAt(t)], [0, 10, 20, 30, 40]);
    });

    test('wraps the loop segment forever', () {
      // tick 5 → back to loopStart (index 2), etc.
      expect(m.valueAt(5), 20);
      expect(m.valueAt(6), 30);
      expect(m.valueAt(7), 40);
      expect(m.valueAt(8), 20);
      expect(m.valueAt(100), m.valueAt(100 - 3)); // period == loop length 3
    });

    test('a single-entry loop holds that entry', () {
      const one = MacroSequence(
        target: MacroTarget.volume,
        values: [5, 9],
        loopStart: 1,
        loopEnd: 1,
      );
      expect(one.valueAt(1), 9);
      expect(one.valueAt(50), 9);
    });

    test('an out-of-range or inverted loop is ignored (plays linearly)', () {
      const bad = MacroSequence(
        target: MacroTarget.volume,
        values: [1, 2, 3],
        loopStart: 2,
        loopEnd: 1, // le < ls
      );
      expect(bad.hasLoop, isFalse);
      expect(bad.valueAt(5), 3); // held at end, not looped
    });
  });

  group('release', () {
    // Sustain loops [1..2]; on release, jump to index 3 and run 3,4 then hold.
    const m = MacroSequence(
      target: MacroTarget.volume,
      values: [64, 48, 32, 16, 0],
      loopStart: 1,
      loopEnd: 2,
      releaseStart: 3,
    );

    test('before release it sustains (and loops)', () {
      expect(m.valueAt(0), 64);
      expect(m.valueAt(1), 48);
      expect(m.valueAt(3), 48); // (3-1)%2==0 → index 1, still looping
    });

    test('on release it plays the release segment then holds', () {
      // released at tick 4: tick4→index3 (16), tick5→index4 (0), tick6→hold 0.
      expect(m.valueAt(4, releaseTick: 4), 16);
      expect(m.valueAt(5, releaseTick: 4), 0);
      expect(m.valueAt(6, releaseTick: 4), 0);
    });

    test('with no releaseStart, release does not change the sustain path', () {
      const noRel = MacroSequence(
        target: MacroTarget.volume,
        values: [9, 8, 7],
        loopStart: 0,
        loopEnd: 2,
      );
      expect(noRel.valueAt(4, releaseTick: 2), noRel.valueAt(4));
    });
  });

  group('json', () {
    test('round-trips a full macro', () {
      const m = MacroSequence(
        target: MacroTarget.pitch,
        values: [-2, 0, 3, 7],
        loopStart: 1,
        loopEnd: 3,
        releaseStart: 2,
      );
      final back = MacroSequence.fromJson(m.toJson())!;
      expect(back.target, m.target);
      expect(back.values, m.values);
      expect(back.loopStart, 1);
      expect(back.loopEnd, 3);
      expect(back.releaseStart, 2);
    });

    test('omits absent optional fields', () {
      const m = MacroSequence(target: MacroTarget.duty, values: [1, 2]);
      final json = m.toJson();
      expect(json.containsKey('loopStart'), isFalse);
      expect(json.containsKey('releaseStart'), isFalse);
    });

    test('malformed input degrades to null, never throws', () {
      expect(MacroSequence.fromJson(null), isNull);
      expect(MacroSequence.fromJson('x'), isNull);
      expect(MacroSequence.fromJson({'target': 'nope', 'values': []}), isNull);
      expect(MacroSequence.fromJson({'target': 'volume'}), isNull); // no values
    });
  });
}
