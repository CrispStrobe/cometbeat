// Opt-in deterministic TPDF dither at the float→Int16 quantisation
// ([PcmDither] in tracker_replayer.dart).
//
// Three properties, one test each:
//
//  1. DECORRELATION — plain rounding of a low-level sine turns the quantisation
//     error into DISTORTION concentrated at odd harmonics of the signal; TPDF
//     dither spreads that same error into a flat, signal-independent noise floor.
//     We quantise a ~3-LSB sine both ways, take a small DFT of the quantisation
//     ERROR, and assert the odd-harmonic energy collapses with dither (and that
//     the dithered harmonics sit at the noise floor, while the plain ones tower
//     over it).
//
//  2. DETERMINISM — the PRNG is a seeded xorshift32, NOT Math.random: the same
//     seed yields the same sequence (reproducible dithered renders); a different
//     seed diverges.
//
//  3. DITHER-OFF == PLAIN ROUNDING — with no ditherer, [pcm16Sample] is
//     bit-identical to plain `round(tanh(x)·0.95·32767)` (an INDEPENDENT
//     reference here), so the default render is untouched.

import 'dart:math';

import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Magnitude of the length-[x] DFT at integer [bin] (one bin, not a full FFT).
double _dftMag(List<double> x, int bin) {
  final n = x.length;
  var re = 0.0, im = 0.0;
  for (var i = 0; i < n; i++) {
    final a = 2 * pi * bin * i / n;
    re += x[i] * cos(a);
    im -= x[i] * sin(a);
  }
  return sqrt(re * re + im * im) / n;
}

/// The average error-spectrum magnitude over a band of NON-harmonic bins — the
/// white noise floor.
double _noiseFloor(List<double> err) {
  var sum = 0.0;
  var c = 0;
  for (var b = 100; b < 300; b++) {
    sum += _dftMag(err, b);
    c++;
  }
  return sum / c;
}

/// Independent reference for the production quantiser's soft-knee (mirrors the
/// private `_tanh` in tracker_replayer.dart: (e^2x−1)/(e^2x+1)), used to prove the
/// dither-OFF path is bit-identical to plain rounding.
int _plainPcm16(double x) {
  final e = exp(2 * x);
  final t = (e - 1) / (e + 1);
  return (t * 0.95 * 32767).round();
}

void main() {
  group('TPDF dither', () {
    test('decorrelates the quantisation error of a low-level sine', () {
      const n = 4096;
      const k = 8; // signal at DFT bin 8
      const amp = 3.0; // ~3 LSB — small, so quantisation matters
      // The signal in the int16 (already-scaled) domain.
      final sig = List<double>.generate(
        n,
        (i) => amp * sin(2 * pi * k * i / n),
      );

      final dither = PcmDither(seed: 20250726);
      final errPlain = <double>[];
      final errDither = <double>[];
      for (var i = 0; i < n; i++) {
        errPlain.add(sig[i].round() - sig[i]); // plain rounding error
        errDither.add(dither.quantizeScaled(sig[i]) - sig[i]); // dithered error
      }

      // Odd-harmonic distortion energy (3rd/5th/7th/9th/11th harmonics of the
      // signal) — where plain quantisation dumps its correlated distortion.
      double harmonicEnergy(List<double> err) {
        var e = 0.0;
        for (final h in [3, 5, 7, 9, 11]) {
          final m = _dftMag(err, h * k);
          e += m * m;
        }
        return e;
      }

      final plainE = harmonicEnergy(errPlain);
      final ditherE = harmonicEnergy(errDither);

      // Plain rounding really does produce harmonic distortion (sanity), and
      // dither collapses it by a wide margin (measured ~38x; assert >4x).
      expect(plainE, greaterThan(0.0));
      expect(
        ditherE,
        lessThan(plainE * 0.25),
        reason: 'dither should decorrelate: harmonic energy '
            '$ditherE should be << plain $plainE',
      );

      // The distortion "drops into the noise floor": plain harmonics tower over
      // their floor; dithered harmonics sit at it.
      final plainFloor = _noiseFloor(errPlain);
      final ditherFloor = _noiseFloor(errDither);
      final plainPeakHarm = [
        for (final h in [3, 5, 7]) _dftMag(errPlain, h * k),
      ].reduce(max);
      final ditherPeakHarm = [
        for (final h in [3, 5, 7]) _dftMag(errDither, h * k),
      ].reduce(max);

      expect(
        plainPeakHarm,
        greaterThan(plainFloor * 3),
        reason: 'plain quantisation concentrates distortion above the floor',
      );
      expect(
        ditherPeakHarm,
        lessThan(ditherFloor * 2),
        reason: 'dithered harmonics should sit at the (raised) noise floor',
      );
    });

    test('seeded PRNG is deterministic; different seeds diverge', () {
      final inputs = List<double>.generate(2000, (i) => sin(i * 0.37) * 6000);

      // Same seed → identical quantised sequence.
      final a = PcmDither(seed: 42);
      final b = PcmDither(seed: 42);
      for (final x in inputs) {
        expect(a.quantizeScaled(x), b.quantizeScaled(x));
      }

      // Same seed → identical raw triangular sequence too.
      final t1 = PcmDither(seed: 7);
      final t2 = PcmDither(seed: 7);
      for (var i = 0; i < 500; i++) {
        expect(t1.nextTriangular(), t2.nextTriangular());
      }

      // Different seed → the sequence differs somewhere.
      final c = PcmDither(seed: 42);
      final e = PcmDither(seed: 43);
      var diverged = false;
      for (final x in inputs) {
        if (c.quantizeScaled(x) != e.quantizeScaled(x)) diverged = true;
      }
      expect(diverged, isTrue);
    });

    test('dither-off is bit-identical to plain rounding', () {
      // Sweep the full soft-knee range, including hot values that saturate tanh.
      for (var i = -600; i <= 600; i++) {
        final x = i / 100.0; // -6.0 .. 6.0
        expect(
          pcm16Sample(x), // no ditherer → the production default path
          _plainPcm16(x), // independent plain-rounding reference
          reason: 'off-path must equal plain rounding at x=$x',
        );
      }

      // The dithered value never departs from plain rounding by more than one
      // quantisation step (TPDF support is [-1,+1] LSB), and is unbiased on
      // average (mean deviation ~0) — the hallmark of subtractive-free dither.
      final d = PcmDither(seed: 99);
      var sumDev = 0.0;
      var cnt = 0;
      for (var i = -500; i <= 500; i++) {
        final x = i / 200.0;
        final plain = pcm16Sample(x);
        final dithered = pcm16Sample(x, d);
        expect((dithered - plain).abs(), lessThanOrEqualTo(1));
        sumDev += dithered - plain;
        cnt++;
      }
      expect(
        (sumDev / cnt).abs(),
        lessThan(0.1),
        reason: 'TPDF dither should be unbiased (mean deviation ~0)',
      );
    });
  });
}
