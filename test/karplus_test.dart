// Karplus-Strong plucked-string synthesis (crisp_dsp/karplus.dart) — a pure,
// deterministic DSP generator, so its contract (length, silence edges,
// determinism, peak-normalisation, attack declick) is unit-testable without
// audio hardware.
import 'dart:math';

import 'package:comet_beat/core/audio/crisp_dsp/karplus.dart';
import 'package:flutter_test/flutter_test.dart';

double _peak(List<double> xs) => xs.fold(0.0, (m, x) => max(m, x.abs()));

void main() {
  test('output length matches the requested sample count', () {
    expect(karplusPluck(freq: 220, samples: 1000).length, 1000);
    expect(karplusPluck(freq: 440, samples: 1).length, 1);
  });

  test('degenerate requests are silent, not a crash', () {
    expect(karplusPluck(freq: 220, samples: 0), isEmpty);
    expect(karplusPluck(freq: 220, samples: -5), isEmpty);
    // freq <= 0 has no pitch → a zero-filled buffer of the asked length.
    final dead = karplusPluck(freq: 0, samples: 64);
    expect(dead.length, 64);
    expect(dead.every((x) => x == 0.0), isTrue);
  });

  test('a real pluck actually rings (non-trivial signal)', () {
    final note = karplusPluck(freq: 220, samples: 4096);
    expect(_peak(note), greaterThan(0.1));
  });

  test('the same seed is byte-for-byte reproducible (stable stem cache)', () {
    final a = karplusPluck(freq: 196, samples: 2048, seed: 7);
    final b = karplusPluck(freq: 196, samples: 2048, seed: 7);
    expect(a, orderedEquals(b));
  });

  test('a different seed gives a different burst', () {
    final a = karplusPluck(freq: 196, samples: 2048, seed: 1);
    final b = karplusPluck(freq: 196, samples: 2048, seed: 2);
    expect(a, isNot(orderedEquals(b)));
  });

  test('output is peak-normalised to amp (never louder)', () {
    // A tiny epsilon for float rounding; the declick can only pull the peak
    // DOWN (it scales early samples), so the bound holds either way.
    expect(
      _peak(karplusPluck(freq: 330, samples: 8192)),
      lessThanOrEqualTo(0.9 + 1e-9),
    );
    expect(
      _peak(karplusPluck(freq: 330, samples: 8192, amp: 0.5)),
      lessThanOrEqualTo(0.5 + 1e-9),
    );
  });

  test('the attack declick starts the burst at silence (no onset click)', () {
    final note = karplusPluck(freq: 330, samples: 8192);
    expect(note.first, 0.0); // i=0 → gain 0
    // ...and it has ramped up by the end of the ~3 ms attack window.
    final attack = (0.003 * 44100).round();
    expect(_peak(note.sublist(attack)), greaterThan(0.1));
  });

  test('lower damping decays faster than higher damping', () {
    // Tail energy after the first 8th of the note: a plukkier (low-damping)
    // string should have less left than a sustained (high-damping) one.
    double tailEnergy(double d) {
      final n = karplusPluck(freq: 220, samples: 8192, damping: d);
      final tail = n.sublist(n.length ~/ 8);
      return tail.fold(0.0, (s, x) => s + x * x);
    }

    expect(tailEnergy(0.90), lessThan(tailEnergy(0.999)));
  });
}
