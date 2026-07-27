// Where a MOD's pitch actually comes from.
//
// The Amiga has no notion of equal temperament. A Paula voice fed period *p*
// plays at `3546895 / p` (PAL), so the pitch of every note in a `.mod` is a
// property of the hardware clock. We instead pitch from the conventional
// 8363 Hz reference, which is NOT the same thing:
//
//   3546895 / 428 = 8287.1 Hz   (what the hardware does for the reference note)
//   1200 * log2(8287.1 / 8363)  = -15.8 cents
//
// So our playback sits ~16 cents SHARP of the hardware. Measured against
// openmpt123 we render +17.1 cents sharp, which the arithmetic accounts for to
// within ~1.3 cents — the remainder being ProTracker's period table not being
// exactly geometric.
//
// `kPaulaClockPitch` (--dart-define=PAULA_CLOCK=1) switches the base over so
// the difference can be A/B'd rather than argued about. Measured both ways on
// test/fixtures/musical.mod:
//
//              detune     spectral   envelope
//   gate off   -17.0c     0.922      0.233
//   gate on     -1.3c     0.962      0.619
//
// and on effects.mod, -25.4c -> -5.3c. Every metric improves, which is why the
// gate exists: the claim is checkable instead of a matter of taste.

import 'dart:math' as math;

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:flutter_test/flutter_test.dart';

double _cents(double ratio) => 1200 * math.log(ratio) / math.ln2;

void main() {
  group('Paula clock vs the conventional reference', () {
    test('the hardware rate for the reference period is NOT 8363 Hz', () {
      const hardware = kPaulaClockPal / kModReferencePeriod;
      expect(hardware, closeTo(8287.1, 0.1));
      // The whole finding in one number.
      expect(_cents(hardware / kModC5Speed), closeTo(-15.8, 0.2));
    });

    test('the offset is CONSTANT across the octave, not a per-note wobble', () {
      // If it varied by note it would be a table bug and a global base change
      // would be the wrong fix. Octave-related periods must give the same
      // offset, because both sides halve together.
      for (final period in [856, 428, 214]) {
        final hardware = kPaulaClockPal / period;
        final nominal = kModC5Speed * (428 / period);
        expect(
          _cents(hardware / nominal),
          closeTo(-15.8, 0.3),
          reason: 'period $period',
        );
      }
    });

    test('finetune stays a RATIO whichever base is in force', () {
      // Finetune is ±1/8 semitone per step and must scale the base, not shift
      // it — otherwise switching the base would silently retune finetuned
      // samples relative to plain ones.
      final base = finetuneToC5speed(0);
      for (final ft in [-8, -4, 4, 7]) {
        final expected = base * math.pow(2, ft / (12 * 8));
        expect(
          finetuneToC5speed(ft),
          closeTo(expected, 1.0),
          reason: 'finetune $ft',
        );
      }
    });

    test('the base follows the gate, and OFF is the default', () {
      // A rendering change this broad must be opted into: with no
      // --dart-define, `flutter test` renders exactly as it always has. The
      // A/B numbers in this file's header are the argument for flipping it.
      //
      // Asserted in BOTH modes rather than just the default, so a
      // PAULA_CLOCK=1 run is clean too — a suite that reports a failure when
      // you turn the flag on teaches people to ignore the failure.
      if (kPaulaClockPitch) {
        expect(
          finetuneToC5speed(0),
          (kPaulaClockPal / kModReferencePeriod).round(),
          reason: 'gate on: pitch must come from the Paula clock',
        );
        expect(finetuneToC5speed(0), 8287);
      } else {
        expect(
          finetuneToC5speed(0),
          kModC5Speed,
          reason: 'gate off: the conventional reference, unchanged',
        );
        expect(finetuneToC5speed(0), 8363);
      }
    });
  });
}
