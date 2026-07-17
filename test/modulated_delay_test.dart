// test/modulated_delay_test.dart
//
// The modulated-delay effect family (delay / chorus / flanger): pure, same-length,
// deterministic transforms. Synthetic buffers only (like sample_dsp_test.dart).
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/modulated_delay_test.dart

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/audio/crisp_dsp/modulated_delay.dart';

const _sr = 44100;

Float64List _impulse(int n) {
  final b = Float64List(n);
  b[0] = 1.0;
  return b;
}

Float64List _sine(int n, double hz) {
  final b = Float64List(n);
  for (var i = 0; i < n; i++) {
    b[i] = 0.7 * sin(2 * pi * hz * i / _sr);
  }
  return b;
}

bool _finite(Float64List b) => b.every((v) => v.isFinite);
double _peak(Float64List b) => b.fold(0.0, (p, v) => max(p, v.abs()));
bool _differs(Float64List a, Float64List b) {
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 1e-6) return true;
  }
  return false;
}

void main() {
  group('delayFx', () {
    test('echo lands at the delay time and decays by feedback', () {
      const delayMs = 10.0, feedback = 0.5, mix = 0.4;
      final d = (delayMs * _sr / 1000).round(); // 441
      final out = delayFx(
        _impulse(d * 3 + 100),
        delayMs: delayMs,
        feedback: feedback,
        mix: mix,
      );
      expect(out[0], closeTo(1 - mix, 1e-6)); // dry impulse
      expect(out[d], closeTo(mix, 1e-6)); // first echo = mix
      expect(out[2 * d], closeTo(mix * feedback, 1e-6)); // second echo
      expect(out[3 * d], closeTo(mix * feedback * feedback, 1e-6));
    });

    test('mix 0 is the dry signal; output length is preserved', () {
      final dry = _sine(4000, 220);
      final out = delayFx(dry, mix: 0);
      expect(out.length, dry.length);
      expect(_differs(dry, out), isFalse);
    });

    test('finite, bounded, deterministic', () {
      final s = _sine(4000, 330);
      final a = delayFx(s, feedback: 0.7, mix: 0.6);
      final b = delayFx(s, feedback: 0.7, mix: 0.6);
      expect(_finite(a), isTrue);
      expect(_peak(a), lessThan(4.0));
      expect(_differs(a, b), isFalse); // deterministic
    });
  });

  group('chorusFx', () {
    final dry = _sine(4000, 220);

    test('changes the signal, same length, finite, bounded', () {
      final wet = chorusFx(dry);
      expect(wet.length, dry.length);
      expect(_differs(dry, wet), isTrue);
      expect(_finite(wet), isTrue);
      expect(_peak(wet), lessThan(3.0));
    });

    test('mix 0 is dry; deterministic', () {
      expect(_differs(dry, chorusFx(dry, mix: 0)), isFalse);
      expect(_differs(chorusFx(dry), chorusFx(dry)), isFalse);
    });
  });

  group('flangerFx', () {
    final dry = _sine(4000, 220);

    test('changes the signal, same length, finite, bounded', () {
      final wet = flangerFx(dry);
      expect(wet.length, dry.length);
      expect(_differs(dry, wet), isTrue);
      expect(_finite(wet), isTrue);
      expect(_peak(wet), lessThan(3.0));
    });

    test('mix 0 is dry; deterministic', () {
      expect(_differs(dry, flangerFx(dry, mix: 0)), isFalse);
      expect(_differs(flangerFx(dry), flangerFx(dry)), isFalse);
    });
  });
}
