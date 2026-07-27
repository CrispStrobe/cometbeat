// A7 — the rest of the generators: noise colours, sweeps, a plucked string, an
// impulse.
//
// A generator is easy to test shallowly ("it produced samples") and the shallow
// version catches nothing. What each of these claims is a SPECTRAL SHAPE or a
// trajectory, so that is what is measured: which end of the spectrum a noise
// colour leans on, where a sweep actually is at its midpoint, that a pluck is
// pitched and decays, and that an impulse is one sample.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_edits.dart';
import 'package:comet_beat/core/audio/fx/fx_chain.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:flutter_test/flutter_test.dart';

const int _sr = 44100;

Float64List _make(
  GeneratorShape shape, {
  int ms = 1000,
  double freq = 440,
  double endFreq = 20000,
  double amp = 0.5,
  int seed = 1,
}) =>
    generateWave(
      shape: shape,
      samples: ms * _sr ~/ 1000,
      sampleRate: _sr,
      freq: freq,
      endFreq: endFreq,
      amp: amp,
      seed: seed,
    );

/// Energy across a band, summed from several Goertzel probes.
double _band(Float64List signal, double fromHz, double toHz) {
  var total = 0.0;
  final step = (toHz - fromHz) / 10;
  for (var hz = fromHz; hz <= toHz; hz += step) {
    final w = 2 * math.pi * hz / _sr;
    final coeff = 2 * math.cos(w);
    var s1 = 0.0, s2 = 0.0;
    for (final x in signal) {
      final s0 = x + coeff * s1 - s2;
      s2 = s1;
      s1 = s0;
    }
    final real = s1 - s2 * math.cos(w);
    final imag = s2 * math.sin(w);
    total += math.sqrt(real * real + imag * imag) / signal.length;
  }
  return total;
}

double _rms(Float64List x) {
  if (x.isEmpty) return 0;
  var sum = 0.0;
  for (final v in x) {
    sum += v * v;
  }
  return math.sqrt(sum / x.length);
}

/// The dominant frequency of a slice, by scanning candidate probes.
double _dominant(Float64List slice, List<double> candidates) {
  var best = candidates.first;
  var bestEnergy = -1.0;
  for (final hz in candidates) {
    final e = _band(slice, hz * 0.98, hz * 1.02);
    if (e > bestEnergy) {
      bestEnergy = e;
      best = hz;
    }
  }
  return best;
}

void main() {
  group('noise colours lean the way they claim', () {
    // Each colour is a spectral TILT, so each is checked as a low-band vs
    // high-band ratio — the one measurement that distinguishes them.
    double tilt(GeneratorShape shape) {
      final noise = _make(shape, ms: 500);
      return _band(noise, 100, 500) /
          math.max(1e-12, _band(noise, 8000, 16000));
    }

    test('white is roughly flat', () {
      expect(tilt(GeneratorShape.whiteNoise), closeTo(1, 0.8));
    });

    test('pink falls, and brown falls harder', () {
      final pink = tilt(GeneratorShape.pinkNoise);
      final brown = tilt(GeneratorShape.brownNoise);
      expect(pink, greaterThan(2));
      expect(brown, greaterThan(pink));
    });

    test('blue rises, and violet rises harder', () {
      final blue = tilt(GeneratorShape.blueNoise);
      final violet = tilt(GeneratorShape.violetNoise);
      expect(blue, lessThan(1));
      expect(violet, lessThan(blue));
    });

    test('every colour is reproducible from its seed', () {
      for (final shape in [
        GeneratorShape.whiteNoise,
        GeneratorShape.pinkNoise,
        GeneratorShape.brownNoise,
        GeneratorShape.blueNoise,
        GeneratorShape.violetNoise,
      ]) {
        expect(
          _make(shape, ms: 50, seed: 7),
          orderedEquals(_make(shape, ms: 50, seed: 7)),
          reason: shape.name,
        );
      }
    });
  });

  group('sweeps', () {
    test('it starts where it was told and ends where it was told', () {
      final sweep = _make(
        GeneratorShape.logSweep,
        ms: 2000,
        freq: 200,
        endFreq: 6400,
      );
      const window = 4000;
      final start = Float64List.sublistView(sweep, 0, window);
      final end = Float64List.sublistView(sweep, sweep.length - window);
      expect(_dominant(start, [200, 800, 3200, 6400]), 200);
      expect(_dominant(end, [200, 800, 3200, 6400]), 6400);
    });

    test('log spends equal time per OCTAVE, linear per Hz', () {
      // The distinction that makes two shapes worth having. Halfway through a
      // 200→6400 sweep: the log one is at the geometric mean (1131 Hz), the
      // linear one at the arithmetic mean (3300 Hz).
      const window = 4000;
      Float64List middle(GeneratorShape shape) {
        final s = _make(shape, ms: 2000, freq: 200, endFreq: 6400);
        final mid = s.length ~/ 2;
        return Float64List.sublistView(s, mid - window ~/ 2, mid + window ~/ 2);
      }

      const probes = [400.0, 1131.0, 3300.0];
      expect(_dominant(middle(GeneratorShape.logSweep), probes), 1131.0);
      expect(_dominant(middle(GeneratorShape.sweep), probes), 3300.0);
    });

    test('the phase is continuous — no click in the middle', () {
      // A sweep written as sin(2π·f(t)·t) instead of integrating the phase
      // jumps, and the jumps are audible. The largest sample-to-sample step
      // must stay in the range a smooth signal can produce.
      final sweep = _make(
        GeneratorShape.logSweep,
        freq: 100,
        endFreq: 2000,
      );
      var biggest = 0.0;
      for (var i = 1; i < sweep.length; i++) {
        biggest = math.max(biggest, (sweep[i] - sweep[i - 1]).abs());
      }
      // At 2 kHz the per-sample step of a 0.5-amplitude sine is ~0.14; a phase
      // discontinuity would show up as something close to a full 1.0.
      expect(biggest, lessThan(0.3));
    });
  });

  group('pluck', () {
    test('it is pitched at the frequency asked for', () {
      final pluck = _make(GeneratorShape.pluck, ms: 500, freq: 220);
      expect(_dominant(pluck, [110, 220, 440]), 220);
    });

    test('it decays, the way a plucked string does', () {
      final pluck = _make(GeneratorShape.pluck, freq: 220);
      final early = _rms(Float64List.sublistView(pluck, 0, 4410));
      final late = _rms(
        Float64List.sublistView(pluck, pluck.length - 4410),
      );
      expect(late, lessThan(early * 0.7));
    });
  });

  group('impulse', () {
    test('one sample, then nothing', () {
      final impulse = _make(GeneratorShape.impulse, ms: 100, amp: 0.8);
      expect(impulse.first, 0.8);
      for (var i = 1; i < impulse.length; i++) {
        expect(impulse[i], 0, reason: 'sample $i should be silent');
      }
    });

    test('it is the measurement signal — what comes out IS the response', () {
      // The reason to have one, demonstrated rather than described: the raw
      // impulse is silent after sample 0, so ANY tail in the output came from
      // the effect. Run it through a reverb and the ring is that reverb's
      // impulse response — which is the whole technique.
      final impulse = _make(GeneratorShape.impulse, ms: 500, amp: 1);
      expect(
        _rms(Float64List.sublistView(impulse, 1000)),
        0,
        reason: 'the raw impulse must have no tail of its own',
      );

      final rung = applyFxChain(
        impulse,
        [defaultFx(FxType.reverb)],
        _sr,
      );
      expect(
        _rms(Float64List.sublistView(rung, 1000)),
        greaterThan(0),
        reason: 'the reverb tail IS its impulse response',
      );
    });
  });

  test('the existing shapes are unchanged', () {
    // A7 appended to the enum and rewrote the noise branch; the shapes that
    // were already there must still be exactly what they were.
    final sine = _make(GeneratorShape.sine, ms: 100, freq: 441);
    expect(sine[0], closeTo(0, 1e-9));
    var peak = 0.0;
    for (final v in sine) {
      peak = math.max(peak, v.abs());
    }
    expect(peak, closeTo(0.5, 0.01));
    expect(_make(GeneratorShape.silence, ms: 10).every((v) => v == 0), isTrue);
  });
}
