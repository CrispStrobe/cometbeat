// crisp_dsp: convolution reverb (FFT overlap-add) + synthesized IR.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/convolution_reverb.dart';
import 'package:flutter_test/flutter_test.dart';

const _sr = 44100.0;

double _energy(Float64List x, int from, int to) {
  var e = 0.0;
  for (var i = from; i < to; i++) {
    e += x[i] * x[i];
  }
  return e;
}

void main() {
  group('convolveFx', () {
    test('mix == 0 is an exact identity copy', () {
      final x = Float64List.fromList([1, 2, 3, 4, 5]);
      expect(convolveFx(x, Float64List.fromList([1, 1, 1]), mix: 0), x);
    });

    test('a unit impulse IR returns the input', () {
      final x = Float64List.fromList([1, -2, 3, -4, 5, 6, 7]);
      final y = convolveFx(x, Float64List.fromList([1]));
      for (var i = 0; i < x.length; i++) {
        expect(y[i], closeTo(x[i], 1e-9), reason: 'i=$i');
      }
    });

    test('a delayed impulse IR shifts the signal by the delay', () {
      final x = Float64List.fromList([1, 2, 3, 4, 5, 0, 0, 0]);
      // ir = [0, 0, 1] → output[i] = input[i-2].
      final y = convolveFx(x, Float64List.fromList([0, 0, 1]));
      const want = [0.0, 0, 1, 2, 3, 4, 5, 0];
      for (var i = 0; i < want.length; i++) {
        expect(y[i], closeTo(want[i], 1e-9), reason: 'i=$i');
      }
    });

    test('output is always the input length', () {
      final x = Float64List(1000);
      final ir = Float64List(500)..[0] = 1;
      expect(convolveFx(x, ir).length, 1000);
    });
  });

  group('synthReverbIr', () {
    test('deterministic for a seed; peak-normalized; right length', () {
      final a = synthReverbIr(seconds: 0.3, seed: 7);
      final b = synthReverbIr(seconds: 0.3, seed: 7);
      expect(a, b); // same seed → identical
      expect(a.length, (0.3 * _sr).round());
      final peak = a.fold<double>(0, (p, v) => math.max(p, v.abs()));
      expect(peak, closeTo(1.0, 1e-9));
    });
  });

  test('convolution reverb spreads a spike into a decaying tail', () {
    final spike = Float64List(4410)..[0] = 1.0; // 0.1 s, energy only at t=0
    final wet =
        convolutionReverbFx(spike, sampleRate: _sr, seconds: 0.3, mix: 1);
    // The dry input has zero energy after the first sample; the reverb fills
    // the tail.
    expect(_energy(wet, 2205, 4410), greaterThan(0));
    // ...and it decays: the first quarter carries more than the last.
    expect(_energy(wet, 0, 1102), greaterThan(_energy(wet, 3308, 4410)));
  });
}
