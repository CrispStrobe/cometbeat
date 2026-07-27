// A1 — the automation model and its codec.
//
// No audio here: this is the shape that has to survive a share token and a save
// slot, and the point of testing it alone is that a codec is only trustworthy
// when it can be read without the renderer in the way.
//
// The properties that matter are the ones a later slice will lean on: a lane
// shorter than the loop repeats (so it tiles like a pattern, including over a
// polymeter track), values stay normalised whatever is thrown at them, and a
// groove with NO automation serialises to nothing at all — because "renders
// byte-for-byte as before" is the guarantee A2 has to make.

import 'package:comet_beat/core/audio/loop_automation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a lane holds normalised values', () {
    test('out-of-range values are clamped on the way in', () {
      final lane = AutomationLane([-1, 0.5, 2]);
      expect(lane.values, [0.0, 0.5, 1.0]);
    });

    test('it is immutable — editing returns a new lane', () {
      final lane = AutomationLane([0, 0, 0]);
      final edited = lane.withStep(1, 1);
      expect(lane.values, [0.0, 0.0, 0.0],
          reason: 'the original must not move');
      expect(edited.values, [0.0, 1.0, 0.0]);
      expect(() => lane.values[0] = 1, throwsUnsupportedError);
    });

    test('editing off the end is ignored rather than growing the lane', () {
      final lane = AutomationLane([0, 1]);
      expect(lane.withStep(5, 1), lane);
      expect(lane.withStep(-1, 1), lane);
    });

    test('value equality, so a spec can be compared by it', () {
      expect(AutomationLane([0, 1]), AutomationLane([0, 1]));
      expect(AutomationLane([0, 1]).hashCode, AutomationLane([0, 1]).hashCode);
      expect(AutomationLane([0, 1]), isNot(AutomationLane([1, 0])));
    });
  });

  group('a short lane repeats across the loop', () {
    test('it wraps, exactly as a pattern tiles', () {
      // This is what lets a lane sit on a polymeter track without special
      // cases: index by step, wrap, done.
      final lane = AutomationLane([0, 1, 0.5]);
      expect([for (var s = 0; s < 7; s++) lane.at(s)],
          [0.0, 1.0, 0.5, 0.0, 1.0, 0.5, 0.0]);
    });

    test('a negative step wraps too, it does not throw', () {
      final lane = AutomationLane([0, 1]);
      expect(lane.at(-1), 1.0);
    });
  });

  group('parameters map the lane onto their own range', () {
    test('level is one-sided; pan and filter are two-sided', () {
      expect(AutomationParam.level.valueAt(0), 0);
      expect(AutomationParam.level.valueAt(1), 1);
      expect(AutomationParam.pan.valueAt(0.5), 0, reason: 'centre');
      expect(AutomationParam.pan.valueAt(0), -1);
      expect(AutomationParam.pan.valueAt(1), 1);
      expect(AutomationParam.filter.valueAt(0.5), 0, reason: 'unfiltered');
    });

    test("each parameter knows the value that leaves it alone", () {
      for (final p in AutomationParam.values) {
        expect(p.valueAt(p.neutral), 0 == p.valueAt(p.neutral) ? 0 : 1,
            reason: '${p.name} neutral should be a no-op value');
      }
      expect(AutomationParam.level.neutral, 1);
      expect(AutomationParam.pan.neutral, 0.5);
    });

    test('a neutral lane is recognised as doing nothing', () {
      expect(
        AutomationLane.neutral(AutomationParam.pan, 4)
            .isNeutralFor(AutomationParam.pan),
        isTrue,
      );
      expect(
        AutomationLane([0, 1]).isNeutralFor(AutomationParam.pan),
        isFalse,
      );
    });
  });

  group('the codec', () {
    test('round-trips every parameter', () {
      final lanes = <String, Map<AutomationParam, AutomationLane>>{
        'bass': {
          AutomationParam.level: AutomationLane([0, 0.5, 1]),
          AutomationParam.pan: AutomationLane([1, 0]),
        },
        'drums': {
          AutomationParam.filter: AutomationLane([0.25])
        },
      };
      expect(automationFromJson(automationToJson(lanes)), lanes);
    });

    test('a groove with NO automation serialises to nothing', () {
      // So an existing share token is unchanged by this feature existing —
      // which is the same "costs nothing when unused" rule polymeter follows.
      expect(automationToJson({}), isEmpty);
      expect(automationToJson({'bass': {}}), isEmpty);
    });

    test('an unknown parameter is dropped, not fatal', () {
      // A token from a newer build should lose the lane it cannot read rather
      // than refuse to load the groove.
      final decoded = automationFromJson({
        'bass': {
          'level': [0, 1],
          'tempo': [0, 1],
        },
      });
      expect(decoded['bass']!.keys, [AutomationParam.level]);
    });

    test('malformed lanes are skipped rather than throwing', () {
      expect(automationFromJson(null), isEmpty);
      expect(automationFromJson('nonsense'), isEmpty);
      expect(automationFromJson({'bass': 'nope'}), isEmpty);
      expect(
          automationFromJson({
            'bass': {'level': 'nope'}
          }),
          isEmpty);
      expect(
          automationFromJson({
            'bass': {'level': <double>[]}
          }),
          isEmpty);
      expect(
          automationFromJson({
            'bass': {
              'level': [null]
            }
          }),
          isEmpty);
    });

    test('numbers survive a JSON round trip as ints or strings', () {
      // Tokens are base64 JSON, so 1 can come back as an int and a value can
      // come back stringified depending on who wrote it.
      final lane = AutomationLane.fromJson([0, 1, '0.5']);
      expect(lane?.values, [0.0, 1.0, 0.5]);
    });
  });
}
