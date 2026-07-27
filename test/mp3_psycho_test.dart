// mp3_psycho — the MP3 psychoacoustic model the quantizer optimises against.
// Its exact output is a heuristic, but its invariants are contracts the
// encoder relies on: per-band energy is non-negative and Parseval-consistent,
// tonality is a spectral-flatness measure bounded in [0,1] (tonal > noisy),
// and the mask is always floored at the absolute threshold and grows with the
// source energy. Golden roundtrips exercise these transitively; this pins them.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_psycho.dart';
import 'package:flutter_test/flutter_test.dart';

double _sum(Float64List x) => x.fold(0.0, (a, b) => a + b);
double _mean(Float64List x) => _sum(x) / x.length;

void main() {
  const sr = 0; // 44.1 kHz long-block scalefactor bands.

  group('mp3ComputeSrcBand', () {
    test('returns 21 non-negative bands', () {
      final mdct = Float64List(576);
      for (var i = 0; i < 576; i++) {
        mdct[i] = math.sin(i * 0.1) * (i.isEven ? 1.0 : -0.7);
      }
      final band = mp3ComputeSrcBand(mdct, sr);
      expect(band.length, 21);
      expect(band, everyElement(greaterThanOrEqualTo(0.0)));
    });

    test('silence maps to zero energy in every band', () {
      final band = mp3ComputeSrcBand(Float64List(576), sr);
      expect(band, everyElement(0.0));
    });

    test('a single bin lands in exactly one band, energy = amplitude²', () {
      final mdct = Float64List(576);
      mdct[100] = 2.0;
      final band = mp3ComputeSrcBand(mdct, sr);
      expect(band.where((e) => e > 0).length, 1);
      expect(_sum(band), closeTo(4.0, 1e-12)); // 2.0²
    });

    test('band energy sums to the total spectral energy (Parseval)', () {
      final mdct = Float64List(576);
      var total = 0.0;
      for (var i = 0; i < 576; i++) {
        mdct[i] = (i % 7) - 3.0;
        total += mdct[i] * mdct[i];
      }
      expect(_sum(mp3ComputeSrcBand(mdct, sr)), closeTo(total, 1e-6));
    });
  });

  group('mp3ComputeBandTonality', () {
    test('returns 21 values, each within [0, 1]', () {
      final mdct = Float64List(576);
      for (var i = 0; i < 576; i++) {
        mdct[i] = math.sin(i * 0.37);
      }
      final alpha = mp3ComputeBandTonality(mdct, sr);
      expect(alpha.length, 21);
      expect(alpha, everyElement(inInclusiveRange(0.0, 1.0)));
    });

    test('a flat spectrum reads as noisy (tonality ≈ 0)', () {
      final flat = Float64List(576)..fillRange(0, 576, 1.0);
      final alpha = mp3ComputeBandTonality(flat, sr);
      expect(_mean(alpha), lessThan(0.05));
    });

    test('a spiky spectrum reads as more tonal than a flat one', () {
      final flat = Float64List(576)..fillRange(0, 576, 1.0);
      final spiky = Float64List(576)..fillRange(0, 576, 1e-6);
      for (var i = 0; i < 576; i += 8) {
        spiky[i] = 100.0; // one dominant line per band
      }
      final flatAlpha = _mean(mp3ComputeBandTonality(flat, sr));
      final spikyAlpha = _mean(mp3ComputeBandTonality(spiky, sr));
      expect(spikyAlpha, greaterThan(flatAlpha + 0.3));
      expect(spikyAlpha, greaterThan(0.5));
    });
  });

  group('mp3ComputeBandMasks', () {
    test('zero source energy still yields positive masks (ATH floor)', () {
      final mask = mp3ComputeBandMasks(Float64List(21), sr);
      expect(mask.length, 21);
      expect(mask, everyElement(greaterThan(0.0)));
    });

    test('doubling the source energy never lowers a mask', () {
      final src = Float64List(21);
      for (var b = 0; b < 21; b++) {
        src[b] = (b + 1).toDouble();
      }
      final base = mp3ComputeBandMasks(src, sr);
      final doubled = mp3ComputeBandMasks(
        Float64List.fromList([for (final e in src) e * 2]),
        sr,
      );
      for (var b = 0; b < 21; b++) {
        expect(doubled[b], greaterThanOrEqualTo(base[b]));
      }
    });

    test('per-band tonality offsets keep masks positive and finite', () {
      final src = Float64List(21)..fillRange(0, 21, 1.0);
      final alpha = Float64List(21)..fillRange(0, 21, 0.5);
      final mask = mp3ComputeBandMasks(src, sr, alpha: alpha);
      expect(mask.length, 21);
      expect(mask, everyElement(greaterThan(0.0)));
      expect(mask, everyElement(predicate<double>((v) => v.isFinite)));
    });
  });
}
