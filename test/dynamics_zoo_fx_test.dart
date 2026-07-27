// A3 — the dynamics the rack was missing: a limiter that actually limits, a
// de-esser, and a multiband compressor.
//
// Dynamics are the easiest DSP to test wrongly, because "it got quieter" passes
// for almost any bug. So each assertion here is about the PROPERTY that makes
// the effect the thing it claims to be:
//
//   limiter    nothing leaves above the ceiling — including the first transient,
//              which is exactly what a fast compressor gets wrong.
//   de-esser   the sibilant band ducks and the body does NOT.
//   multiband  a loud low band does not duck the high band with it.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/dynamics.dart';
import 'package:comet_beat/core/audio/fx/fx_chain.dart';
import 'package:comet_beat/core/audio/fx/fx_params.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:flutter_test/flutter_test.dart';

const int _sr = 44100;

Float64List _tone(double hz, {int samples = 22050, double amp = 0.5}) {
  final out = Float64List(samples);
  for (var i = 0; i < samples; i++) {
    out[i] = amp * math.sin(2 * math.pi * hz * i / _sr);
  }
  return out;
}

Float64List _sum(Float64List a, Float64List b) {
  final out = Float64List(math.max(a.length, b.length));
  for (var i = 0; i < out.length; i++) {
    out[i] = (i < a.length ? a[i] : 0) + (i < b.length ? b[i] : 0);
  }
  return out;
}

double _peak(Float64List x) {
  var peak = 0.0;
  for (final v in x) {
    if (v.abs() > peak) peak = v.abs();
  }
  return peak;
}

/// The magnitude of [hz] in [signal] (Goertzel).
double _magnitudeAt(Float64List signal, double hz) {
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
  return 2 * math.sqrt(real * real + imag * imag) / signal.length;
}

Float64List _fx(FxType type, Map<String, double> params, Float64List input) =>
    applyFxChain(
      input,
      [
        defaultFx(type)
            .copyWith(params: {...defaultFx(type).params, ...params}),
      ],
      _sr,
    );

void main() {
  group('limiter — nothing gets out above the ceiling', () {
    test('a steady loud tone is brought under the ceiling', () {
      final loud = _tone(440, amp: 0.9);
      final out = _fx(FxType.limiter, {'ceilingDb': -6}, loud);
      // −6 dBFS is 0.501; allow a hair for the release curve.
      expect(_peak(out), lessThanOrEqualTo(0.51));
    });

    test('the FIRST transient does not escape — the whole point', () {
      // A compressor-as-limiter computes its gain from a peak it has already
      // passed, so a sudden burst goes out over the ceiling and only its tail
      // is caught. Look-ahead is what fixes that, so this is THE test that
      // separates the two.
      final signal = Float64List(_sr);
      for (var i = 0; i < signal.length; i++) {
        // Silence, then an instant full-scale burst at 100 ms.
        signal[i] = i < 4410 ? 0.0 : math.sin(2 * math.pi * 440 * i / _sr);
      }
      final limited = lookaheadLimiterFx(
        signal,
        sampleRate: 44100,
        ceilingDb: -6,
      );
      expect(_peak(limited), lessThanOrEqualTo(0.51));

      // And the point of comparison: the fast compressor DOES let it through.
      final compressed = limiterFx(
        signal,
        sampleRate: 44100,
        ceilingDb: -6,
      );
      expect(
        _peak(compressed),
        greaterThan(0.6),
        reason: 'the fast-compressor limiter is expected to overshoot — if it '
            'no longer does, this comparison has lost its meaning',
      );
    });

    test('quiet material passes through untouched', () {
      final quiet = _tone(440, amp: 0.05);
      final out = _fx(FxType.limiter, {'ceilingDb': -6}, quiet);
      for (var i = 0; i < quiet.length; i++) {
        expect(out[i], closeTo(quiet[i], 1e-9));
      }
    });

    test('mix=0 is an exact copy', () {
      final input = _tone(440, amp: 0.9);
      expect(_fx(FxType.limiter, {'mix': 0}, input), orderedEquals(input));
    });
  });

  group('the band splitter reconstructs', () {
    test('low + high is the input, sample for sample', () {
      // Everything multiband rests on this: a splitter whose bands do not sum
      // back puts a notch at every crossover.
      final input = _sum(_tone(100), _tone(5000, amp: 0.3));
      final bands = splitAt(input, 800, sampleRate: 44100);
      for (var i = 0; i < input.length; i++) {
        expect(bands.low[i] + bands.high[i], closeTo(input[i], 1e-12));
      }
    });

    test('and it really splits — each band keeps its own tone', () {
      final input = _sum(_tone(100), _tone(5000, amp: 0.3));
      final bands = splitAt(input, 800, sampleRate: 44100);
      expect(_magnitudeAt(bands.low, 100), greaterThan(0.3));
      expect(_magnitudeAt(bands.low, 5000), lessThan(0.05));
      expect(_magnitudeAt(bands.high, 5000), greaterThan(0.1));
      expect(_magnitudeAt(bands.high, 100), lessThan(0.1));
    });
  });

  group('de-esser — the band ducks, the body does not', () {
    test('a loud high band is tamed while the low band is left alone', () {
      final body = _tone(200, amp: 0.3);
      final sibilance = _tone(7000, amp: 0.6);
      final input = _sum(body, sibilance);
      final out = _fx(
        FxType.deEsser,
        {'freq': 4000, 'thresholdDb': -30, 'ratio': 8},
        input,
      );
      // The sibilant band came down…
      expect(
        _magnitudeAt(out, 7000),
        lessThan(_magnitudeAt(input, 7000) * 0.8),
      );
      // …and the body did not move. A full-band compressor would have ducked
      // this too, which is the pumping a de-esser exists to avoid.
      expect(
        _magnitudeAt(out, 200),
        closeTo(_magnitudeAt(input, 200), 0.02),
      );
    });

    test('material with no sibilance is left alone', () {
      final input = _tone(200, amp: 0.3);
      final out = _fx(FxType.deEsser, const {}, input);
      expect(_magnitudeAt(out, 200), closeTo(_magnitudeAt(input, 200), 0.01));
    });
  });

  group('multiband compressor', () {
    test('all ratios at 1 returns the input EXACTLY', () {
      // Because the splitter reconstructs, an untouched multiband is a no-op —
      // so adding one to a chain cannot colour anything until it is dialled in.
      final input = _sum(_tone(100), _tone(5000, amp: 0.3));
      final out = _fx(FxType.multibandCompressor, const {}, input);
      for (var i = 0; i < input.length; i++) {
        expect(out[i], closeTo(input[i], 1e-9));
      }
    });

    test('a loud LOW band does not duck the high band with it', () {
      // The reason to want one: a full-band compressor is steered by whatever
      // is loudest, so every bass note pulls the whole mix down.
      final quietHigh = _tone(6000, amp: 0.08);
      final loudLow = _tone(80, amp: 0.9);
      final input = _sum(loudLow, quietHigh);

      final multiband = _fx(
        FxType.multibandCompressor,
        {'lowHz': 300, 'highHz': 2000, 'thresholdDb': -30, 'lowRatio': 12},
        input,
      );
      final fullBand = _fx(
        FxType.compressor,
        {'thresholdDb': -30, 'ratio': 12, 'attackMs': 10, 'releaseMs': 120},
        input,
      );

      // The low band was compressed in both.
      expect(
        _magnitudeAt(multiband, 80),
        lessThan(_magnitudeAt(input, 80) * 0.9),
      );
      // But only the full-band one dragged the high tone down with it.
      final highKept = _magnitudeAt(multiband, 6000);
      final highDucked = _magnitudeAt(fullBand, 6000);
      expect(highKept, greaterThan(highDucked * 1.5));
      expect(highKept, closeTo(_magnitudeAt(input, 6000), 0.02));
    });

    test('mix=0 is an exact copy', () {
      final input = _sum(_tone(100), _tone(5000, amp: 0.3));
      final out = _fx(
        FxType.multibandCompressor,
        {'lowRatio': 8, 'mix': 0},
        input,
      );
      expect(out, orderedEquals(input));
    });
  });

  group('registry', () {
    test('all three are dynamics, labelled, with described params', () {
      const added = [
        FxType.limiter,
        FxType.deEsser,
        FxType.multibandCompressor,
      ];
      for (final type in added) {
        expect(fxCategory(type), FxCategory.dynamics, reason: type.name);
        expect(fxTypeLabel(type), isNotEmpty, reason: type.name);
        for (final key in defaultFx(type).params.keys) {
          expect(
            hasFxParamSpec(type, key),
            isTrue,
            reason: '${type.name}.$key has no descriptor',
          );
        }
      }
    });

    test('every default sits inside its own range', () {
      for (final type in FxType.values) {
        for (final spec in fxParamSpecs(type)) {
          final value = defaultFx(type).params[spec.key]!;
          expect(
            value,
            inInclusiveRange(spec.min, spec.max),
            reason: '${type.name}.${spec.key} default $value is out of range',
          );
        }
      }
    });
  });
}
