// StreamingFilter — the live seam-continuous master filter (§C-1b). Verified
// against synth tones, listen.dart-style: does a low-pass actually kill highs,
// a high-pass kill lows, and does the state carry across blocks without a click?

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/streaming_filter.dart';
import 'package:flutter_test/flutter_test.dart';

const _sr = 44100.0;

Float64List _tone(double freq, {int samples = 8192, double amp = 0.5}) {
  final out = Float64List(samples);
  for (var i = 0; i < samples; i++) {
    out[i] = amp * math.sin(2 * math.pi * freq * i / _sr);
  }
  return out;
}

/// RMS over the settled tail (skips the filter's start-up transient).
double _rmsTail(Float64List x) {
  final start = x.length ~/ 2;
  var sum = 0.0;
  for (var i = start; i < x.length; i++) {
    sum += x[i] * x[i];
  }
  return math.sqrt(sum / (x.length - start));
}

void main() {
  test('bypass (cutoff 0) passes the signal through unchanged', () {
    final f = StreamingFilter();
    expect(f.isBypassed, isTrue);
    final input = _tone(1000);
    final out = f.process(input);
    for (var i = 0; i < input.length; i++) {
      expect(out[i], closeTo(input[i], 1e-9));
    }
  });

  test('low-pass sweep kills highs and keeps lows', () {
    final low = _tone(150), high = _tone(6000);
    final fLow = StreamingFilter()..setCutoff(-0.8);
    final fHigh = StreamingFilter()..setCutoff(-0.8);
    final lowOut = _rmsTail(fLow.process(low));
    final highOut = _rmsTail(fHigh.process(high));
    expect(lowOut, greaterThan(0.7 * _rmsTail(low)), reason: 'lows pass');
    expect(highOut, lessThan(0.3 * _rmsTail(high)), reason: 'highs cut');
    expect(highOut, lessThan(lowOut), reason: 'high < low through a low-pass');
  });

  test('high-pass sweep kills lows and keeps highs', () {
    final low = _tone(150), high = _tone(6000);
    final fLow = StreamingFilter()..setCutoff(0.8);
    final fHigh = StreamingFilter()..setCutoff(0.8);
    final lowOut = _rmsTail(fLow.process(low));
    final highOut = _rmsTail(fHigh.process(high));
    expect(highOut, greaterThan(0.7 * _rmsTail(high)), reason: 'highs pass');
    expect(lowOut, lessThan(0.3 * _rmsTail(low)), reason: 'lows cut');
    expect(lowOut, lessThan(highOut), reason: 'low < high through a high-pass');
  });

  test('state carries across blocks: one-shot == split, no seam click', () {
    final tone = _tone(800, samples: 4096);
    final whole = (StreamingFilter()..setCutoff(-0.5)).process(tone);
    final split = StreamingFilter()..setCutoff(-0.5);
    final a = split.process(Float64List.sublistView(tone, 0, 2048));
    final b = split.process(Float64List.sublistView(tone, 2048));
    for (var i = 0; i < 2048; i++) {
      expect(a[i], closeTo(whole[i], 1e-12), reason: 'block 1 sample $i');
      expect(
        b[i],
        closeTo(whole[i + 2048], 1e-12),
        reason: 'block 2 sample $i',
      );
    }
  });

  test('sweeping the cutoff every block stays finite and bounded', () {
    final f = StreamingFilter();
    final tone = _tone(1000, samples: 512);
    for (var block = 0; block < 40; block++) {
      f.setCutoff(-1 + block / 20); // sweep -1 → +1 across the blocks
      final out = f.process(tone);
      for (final y in out) {
        expect(y.isFinite, isTrue);
        expect(y.abs(), lessThan(8.0), reason: 'no runaway resonance');
      }
    }
  });
}
