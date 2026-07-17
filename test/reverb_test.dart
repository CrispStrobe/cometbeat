// test/reverb_test.dart
//
// Freeverb-style reverb: pure, same-length, deterministic. Synthetic buffers only.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/reverb_test.dart

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/audio/crisp_dsp/reverb.dart';

Float64List _impulse(int n) {
  final b = Float64List(n);
  b[0] = 1.0;
  return b;
}

Float64List _sine(int n, double hz, {int sr = 44100}) {
  final b = Float64List(n);
  for (var i = 0; i < n; i++) {
    b[i] = 0.7 * sin(2 * pi * hz * i / sr);
  }
  return b;
}

bool _finite(Float64List b) => b.every((v) => v.isFinite);
double _peak(Float64List b) => b.fold(0.0, (p, v) => max(p, v.abs()));
double _energy(Float64List b, int from, int to) {
  var e = 0.0;
  for (var i = from; i < to && i < b.length; i++) {
    e += b[i] * b[i];
  }
  return e;
}

bool _differs(Float64List a, Float64List b) {
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 1e-6) return true;
  }
  return false;
}

void main() {
  group('reverbFx', () {
    test('an impulse spreads into a decaying tail', () {
      const n = 12000;
      final out = reverbFx(_impulse(n), mix: 1.0); // fully wet to see the tail
      // Significant energy well AFTER the input impulse (reverb spread it out).
      final tail = _energy(out, 2000, n);
      expect(tail, greaterThan(1e-4));
      // And the tail decays: earlier part of the tail holds more energy than the
      // later part.
      final early = _energy(out, 2000, 6000);
      final late = _energy(out, 8000, 12000);
      expect(early, greaterThan(late));
    });

    test('mix 0 is the dry signal; length preserved', () {
      final dry = _sine(6000, 220);
      final out = reverbFx(dry, mix: 0);
      expect(out.length, dry.length);
      expect(_differs(dry, out), isFalse);
    });

    test('finite, bounded, deterministic', () {
      final s = _sine(6000, 330);
      final a = reverbFx(s, roomSize: 0.8, damping: 0.3, mix: 0.5);
      final b = reverbFx(s, roomSize: 0.8, damping: 0.3, mix: 0.5);
      expect(_finite(a), isTrue);
      expect(_peak(a), lessThan(4.0));
      expect(_differs(a, b), isFalse);
    });
  });
}
