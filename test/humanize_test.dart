import 'package:comet_beat/core/harmony/humanize.dart';
import 'package:flutter_test/flutter_test.dart';

/// Humanisation.
///
/// Two hard rules carry this file: it is BOUNDED (no note can be reordered or
/// pushed past the barline) and it is REPRODUCIBLE (a shared chart sounds the
/// same on two devices). Off must be byte-identical to the un-humanised output,
/// not merely close, or the feature cannot be A/B'd at all.
void main() {
  group('off is the identity', () {
    test('nothing moves when the spec is empty', () {
      for (final beat in [0.0, 0.5, 1.0, 1.5, 2.75, 3.5]) {
        final out = humanizeEvent(beat: beat, velocity: 0.7, barBeats: 4);
        expect(out.beat, beat);
        expect(out.velocity, 0.7);
      }
    });

    test('HumanizeSpec.none reports itself as the identity', () {
      expect(HumanizeSpec.none.isIdentity, isTrue);
      expect(const HumanizeSpec(swing: 0.1).isIdentity, isFalse);
      expect(const HumanizeSpec(roleOffset: -0.01).isIdentity, isFalse);
    });
  });

  group('swing', () {
    test('an off-beat eighth moves late, a downbeat does not', () {
      const spec = HumanizeSpec(swing: 1);
      final off = humanizeEvent(
        beat: 0.5,
        velocity: 0.7,
        barBeats: 4,
        spec: spec,
      );
      final on = humanizeEvent(
        beat: 1,
        velocity: 0.7,
        barBeats: 4,
        spec: spec,
      );
      expect(off.beat, closeTo(2 / 3, 1e-9), reason: 'full swing = triplet');
      expect(on.beat, 1);
    });

    test('swing is continuous, not a switch', () {
      double at(double amount) => humanizeEvent(
            beat: 0.5,
            velocity: 0.7,
            barBeats: 4,
            spec: HumanizeSpec(swing: amount),
          ).beat;
      expect(at(0), 0.5);
      expect(at(0.5), greaterThan(0.5));
      expect(at(0.5), lessThan(at(1)));
      // Medium swing sits between straight and triplet, which a boolean could
      // not express at all.
      expect(at(0.67), closeTo(0.5 + 0.67 * (2 / 3 - 0.5), 1e-9));
    });

    test('a sixteenth is left alone — it is a different feel', () {
      const spec = HumanizeSpec(swing: 1);
      expect(
        humanizeEvent(beat: 0.25, velocity: 0.7, barBeats: 4, spec: spec).beat,
        0.25,
      );
    });
  });

  group('role feel', () {
    test('the roles do not all land on the same sample', () {
      // The single biggest reason a sequenced band sounds mechanical.
      final offsets = {
        roleFeelFor('drums'),
        roleFeelFor('bass'),
        roleFeelFor('comp'),
      };
      expect(offsets, hasLength(3));
    });

    test('the bass sits behind and the hat leads', () {
      expect(roleFeelFor('bass'), greaterThan(0));
      expect(roleFeelFor('drums'), lessThan(0));
    });

    test('an unknown role is simply on the grid', () {
      expect(roleFeelFor('nothing-like-this'), 0);
    });

    test('the offset is a constant push, applied to every note alike', () {
      const spec = HumanizeSpec(roleOffset: 0.02);
      for (final beat in [1.0, 2.0, 3.0]) {
        final out =
            humanizeEvent(beat: beat, velocity: 0.7, barBeats: 4, spec: spec);
        expect(out.beat - beat, closeTo(0.02, 1e-9));
      }
    });
  });

  group('bounded', () {
    test('nothing is pushed past the barline', () {
      const spec = HumanizeSpec(roleOffset: 0.5, timingJitter: 0.5);
      for (var i = 0; i < 200; i++) {
        final out = humanizeEvent(
          beat: 3.9,
          velocity: 0.7,
          barBeats: 4,
          spec: spec,
          index: i,
        );
        expect(out.beat, lessThan(4));
      }
    });

    test('nothing is pushed before the bar', () {
      const spec = HumanizeSpec(roleOffset: -0.5, timingJitter: 0.5);
      for (var i = 0; i < 200; i++) {
        final out = humanizeEvent(
          beat: 0,
          velocity: 0.7,
          barBeats: 4,
          spec: spec,
          index: i,
        );
        expect(out.beat, greaterThanOrEqualTo(0));
      }
    });

    test('jitter stays inside its configured bound', () {
      const jitter = 0.02;
      const spec = HumanizeSpec(timingJitter: jitter);
      for (var i = 0; i < 500; i++) {
        final out = humanizeEvent(
          beat: 2,
          velocity: 0.7,
          barBeats: 4,
          spec: spec,
          index: i,
        );
        expect((out.beat - 2).abs(), lessThanOrEqualTo(jitter + 1e-9));
      }
    });

    test('velocity never leaves 0..1', () {
      const spec = HumanizeSpec(velocityJitter: 0.9, accentDownbeat: 1);
      for (var i = 0; i < 300; i++) {
        for (final v in [0.0, 0.5, 1.0]) {
          final out = humanizeEvent(
            beat: i.isEven ? 1 : 1.5,
            velocity: v,
            barBeats: 4,
            spec: spec,
            index: i,
          );
          expect(out.velocity, inInclusiveRange(0, 1));
        }
      }
    });

    test('a zero-length bar cannot produce a negative position', () {
      final out = humanizeEvent(
        beat: 0,
        velocity: 0.7,
        barBeats: 0,
        spec: const HumanizeSpec(roleOffset: 0.1),
      );
      expect(out.beat, 0);
    });
  });

  group('reproducible', () {
    test('the same seed and index give the same result', () {
      const spec = HumanizeSpec(timingJitter: 0.02, velocityJitter: 0.1);
      for (var i = 0; i < 50; i++) {
        final a = humanizeEvent(
          beat: 1.5,
          velocity: 0.6,
          barBeats: 4,
          spec: spec,
          seed: 9,
          index: i,
        );
        final b = humanizeEvent(
          beat: 1.5,
          velocity: 0.6,
          barBeats: 4,
          spec: spec,
          seed: 9,
          index: i,
        );
        expect(a, b);
      }
    });

    test('a different seed gives a different feel', () {
      const spec = HumanizeSpec(timingJitter: 0.02);
      final a = [
        for (var i = 0; i < 20; i++)
          humanizeEvent(
            beat: 1,
            velocity: 0.6,
            barBeats: 4,
            spec: spec,
            seed: 1,
            index: i,
          ).beat,
      ];
      final b = [
        for (var i = 0; i < 20; i++)
          humanizeEvent(
            beat: 1,
            velocity: 0.6,
            barBeats: 4,
            spec: spec,
            seed: 2,
            index: i,
          ).beat,
      ];
      expect(a, isNot(b));
    });

    test('timing and velocity jitter are INDEPENDENT', () {
      // Deriving both from one value correlates them, so every late note would
      // also be loud — an audible pattern rather than a human one.
      const spec = HumanizeSpec(timingJitter: 0.02, velocityJitter: 0.2);
      var bothHigh = 0;
      var disagree = 0;
      for (var i = 0; i < 200; i++) {
        final out = humanizeEvent(
          beat: 1,
          velocity: 0.5,
          barBeats: 4,
          spec: spec,
          index: i,
        );
        final late = out.beat > 1;
        final loud = out.velocity > 0.5;
        if (late && loud) bothHigh++;
        if (late != loud) disagree++;
      }
      // If they were correlated, disagree would be near zero.
      expect(disagree, greaterThan(40));
      expect(bothHigh, greaterThan(20));
    });
  });

  group('accent', () {
    test('a downbeat is louder than an off-beat', () {
      const spec = HumanizeSpec(accentDownbeat: 0.4);
      final on = humanizeEvent(beat: 1, velocity: 0.5, barBeats: 4, spec: spec);
      final off =
          humanizeEvent(beat: 1.5, velocity: 0.5, barBeats: 4, spec: spec);
      expect(on.velocity, greaterThan(off.velocity));
    });
  });
}
