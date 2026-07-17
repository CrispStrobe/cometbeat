// test/echo_canceller_test.dart
//
// Proves the AEC core works on a perfectly-aligned digital mix: it cancels a
// linear echo (high ERLE) and preserves an independent near-end signal. This is
// the algorithm validation; real-device alignment is a separate (native) concern.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/echo_canceller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const b = 1024; // matches EchoCanceller's default block size

  // A short synthetic speaker→mic impulse response (the "room"), < one block.
  final h = Float64List.fromList(
    [0.6, 0.0, -0.35, 0.0, 0.2, 0.0, -0.12, 0.08, 0.05, -0.03],
  );
  double echoAt(List<double> ref, int t) {
    var s = 0.0;
    for (var j = 0; j < h.length; j++) {
      if (t - j >= 0) s += h[j] * ref[t - j];
    }
    return s;
  }

  test('cancels a linear echo — high ERLE (echo only)', () {
    final rng = Random(7);
    final aec = EchoCanceller();
    const blocks = 80;
    final ref =
        List<double>.generate(blocks * b, (_) => rng.nextDouble() * 2 - 1);

    var micEnergy = 0.0, outEnergy = 0.0;
    for (var bi = 0; bi < blocks; bi++) {
      final rb = Float64List(b);
      final mb = Float64List(b);
      for (var i = 0; i < b; i++) {
        final t = bi * b + i;
        rb[i] = ref[t];
        mb[i] = echoAt(ref, t); // mic = echo, no near-end
      }
      final out = aec.process(rb, mb);
      if (bi >= blocks - 10) {
        for (var i = 0; i < b; i++) {
          micEnergy += mb[i] * mb[i];
          outEnergy += out[i] * out[i];
        }
      }
    }
    final erleDb = 10 * (log(micEnergy / (outEnergy + 1e-12)) / ln10);
    expect(
      erleDb,
      greaterThan(20),
      reason: 'ERLE = ${erleDb.toStringAsFixed(1)} dB (want > 20)',
    );
  });

  test('preserves the near-end while removing the echo (double-talk)', () {
    final rng = Random(11);
    final aec = EchoCanceller();
    const blocks = 80;
    final ref =
        List<double>.generate(blocks * b, (_) => rng.nextDouble() * 2 - 1);
    double near(int t) => 0.3 * sin(2 * pi * 220 * t / 44100); // the "user"

    var nearErr = 0.0, nearEnergy = 0.0;
    for (var bi = 0; bi < blocks; bi++) {
      final rb = Float64List(b);
      final mb = Float64List(b);
      for (var i = 0; i < b; i++) {
        final t = bi * b + i;
        rb[i] = ref[t];
        mb[i] = echoAt(ref, t) + near(t); // double-talk
      }
      final out = aec.process(rb, mb);
      if (bi >= blocks - 10) {
        for (var i = 0; i < b; i++) {
          final t = bi * b + i;
          nearErr += (out[i] - near(t)) * (out[i] - near(t));
          nearEnergy += near(t) * near(t);
        }
      }
    }
    // The output should be (mostly) the near-end: residual ≪ near energy.
    expect(
      nearErr,
      lessThan(nearEnergy * 0.3),
      reason:
          'near-end error ${(nearErr / nearEnergy * 100).toStringAsFixed(0)}%',
    );
  });
}
