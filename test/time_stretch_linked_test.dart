// timeStretchLinked: stems/channels stretched with ONE WSOLA plan stay locked.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart';
import 'package:flutter_test/flutter_test.dart';

const _sr = 44100;

Float64List _tone(double hz, double amp, {double seconds = 1.5}) {
  final n = (seconds * _sr).round();
  return Float64List.fromList([
    for (var i = 0; i < n; i++) amp * math.sin(2 * math.pi * hz * i / _sr),
  ]);
}

/// A clicky part: short decaying bursts every 250 ms — what flams first.
Float64List _clicks({double seconds = 1.5}) {
  final n = (seconds * _sr).round();
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = (i / _sr) % 0.25;
    if (t < 0.02) {
      out[i] =
          0.8 * math.exp(-t * 200) * math.sin(2 * math.pi * 1500 * i / _sr);
    }
  }
  return out;
}

double _rmsDiff(Float64List a, Float64List b) {
  final n = math.min(a.length, b.length);
  var e = 0.0;
  for (var i = 0; i < n; i++) {
    e += (a[i] - b[i]) * (a[i] - b[i]);
  }
  return math.sqrt(e / n);
}

Float64List _add(Float64List a, Float64List b) =>
    Float64List.fromList([for (var i = 0; i < a.length; i++) a[i] + b[i]]);

void main() {
  test('one channel guided by itself is exactly timeStretch', () {
    final x = _add(_tone(220, 0.4), _clicks());
    for (final f in [0.75, 1.0, 1.5]) {
      final linked = timeStretchLinked([x], f).single;
      expect(linked, timeStretch(x, f));
    }
  });

  test('locked stems sum to the stretched mix exactly', () {
    final bass = _tone(110, 0.5);
    final drums = _clicks();
    final mix = _add(bass, drums);
    const f = 1.33; // a 75%-speed practice loop
    final out = timeStretchLinked([bass, drums], f);
    expect(out[0].length, (mix.length * f).round());
    expect(out[1].length, out[0].length);
    final stretchedMix = timeStretchLinked([mix], f, guide: mix).single;
    // Rendering is linear once the plan is shared: Σ stretch(stem) =
    // stretch(Σ stems), to rounding.
    expect(_rmsDiff(_add(out[0], out[1]), stretchedMix), lessThan(1e-9));
  });

  test('stretching stems separately does NOT stay locked (why this exists)',
      () {
    final bass = _tone(110, 0.5);
    final drums = _clicks();
    final mix = _add(bass, drums);
    const f = 1.33;
    final separate = _add(timeStretch(bass, f), timeStretch(drums, f));
    final stretchedMix = timeStretchLinked([mix], f, guide: mix).single;
    expect(_rmsDiff(separate, stretchedMix), greaterThan(1e-3));
  });

  test('degenerate input', () {
    expect(timeStretchLinked(const [], 1.2), isEmpty);
    expect(timeStretchLinked([Float64List(0)], 1.2).single, isEmpty);
    expect(timeStretchLinked([_tone(220, 0.3)], 0).single, isEmpty);
  });
}
