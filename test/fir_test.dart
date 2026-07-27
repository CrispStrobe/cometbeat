// crisp_dsp/fir.dart — FIR convolution and Hilbert-transformer design. Pure,
// deterministic, and defined by exact math, so both are asserted precisely.
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/fir.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('convolveFir', () {
    test('an empty kernel is the identity', () {
      expect(
        convolveFir(Float64List.fromList([1, 2, 3]), Float64List(0)),
        [1, 2, 3],
      );
    });

    test('a single-tap kernel is a gain', () {
      expect(
        convolveFir(Float64List.fromList([1, 2, 3]), Float64List.fromList([2])),
        [2, 4, 6],
      );
    });

    test('output length always equals the input length', () {
      expect(
        convolveFir(Float64List(10), Float64List.fromList([1, 1, 1])).length,
        10,
      );
    });

    test('a centred 3-tap kernel prints the kernel at an impulse', () {
      // Zero-phase (centred) FIR: an impulse at index 1 lays the kernel from
      // index 0.
      final out = convolveFir(
        Float64List.fromList([0, 1, 0, 0]),
        Float64List.fromList([1, 2, 3]),
      );
      expect(out, [1, 2, 3, 0]);
    });
  });

  group('designHilbert', () {
    test('length is odd and clamps small tap counts up to 3', () {
      expect(designHilbert(taps: 1).length, 3);
      expect(designHilbert(taps: 4).length, 5); // forced odd
      expect(designHilbert(taps: 63).length, 63);
    });

    test('the centre tap and every even-offset tap are zero', () {
      final h = designHilbert(taps: 31);
      final half = (h.length - 1) ~/ 2;
      expect(h[half], 0.0);
      for (var i = 0; i < h.length; i++) {
        if ((i - half).isEven) expect(h[i], 0.0, reason: 'tap $i');
      }
    });

    test('the kernel is anti-symmetric about its centre', () {
      final h = designHilbert(taps: 31);
      for (var i = 0; i < h.length; i++) {
        expect(h[i], closeTo(-h[h.length - 1 - i], 1e-12), reason: 'tap $i');
      }
    });
  });
}
