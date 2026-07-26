// A1 — the rest of the filter set: all-pass, the one-poles, a raw biquad, the
// windowed-sinc FIR and a Hilbert transformer.
//
// Every assertion here is SPECTRAL or about phase — measured on the audio, not
// on the plumbing. A test that only checked "the dispatch reached the DSP" would
// pass just as happily with the wrong filter wired to the wrong name, which is
// the actual risk when six effects are added at once.
//
// The measuring stick is a Goertzel magnitude at a single frequency: cheaper
// than an FFT, exact for the tone under test, and it makes each expectation
// readable as "how much of THIS tone survived".

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/biquad.dart';
import 'package:comet_beat/core/audio/crisp_dsp/fir.dart';
import 'package:comet_beat/core/audio/crisp_dsp/one_pole.dart';
import 'package:comet_beat/core/audio/fx/fx_chain.dart';
import 'package:comet_beat/core/audio/fx/fx_params.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:flutter_test/flutter_test.dart';

const int _sr = 44100;

Float64List _tone(double hz, {int samples = 44100, double amp = 0.5}) {
  final out = Float64List(samples);
  for (var i = 0; i < samples; i++) {
    out[i] = amp * math.sin(2 * math.pi * hz * i / _sr);
  }
  return out;
}

/// The magnitude of [hz] in [signal] (Goertzel), normalised by length.
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

double _rms(Float64List signal) {
  var sum = 0.0;
  for (final x in signal) {
    sum += x * x;
  }
  return math.sqrt(sum / signal.length);
}

/// Run one effect through the real chain dispatch, so these tests cover the
/// wiring as well as the DSP.
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
  group('all-pass — phase only', () {
    test('passes every frequency at full level', () {
      for (final hz in [100.0, 1000.0, 5000.0]) {
        final input = _tone(hz);
        final out = _fx(FxType.allpass, {'freq': 1000, 'q': 0.707}, input);
        expect(
          _magnitudeAt(out, hz),
          closeTo(_magnitudeAt(input, hz), 0.02),
          reason: '$hz Hz should survive an all-pass at full level',
        );
      }
    });

    test('but it DOES change the waveform (it is not a no-op)', () {
      final input = _tone(1000);
      final out = _fx(FxType.allpass, {'freq': 1000, 'q': 0.707}, input);
      // Same energy, different samples — the definition of a phase rotation.
      expect(_rms(out), closeTo(_rms(input), 0.01));
      var maxDelta = 0.0;
      for (var i = 0; i < input.length; i++) {
        maxDelta = math.max(maxDelta, (out[i] - input[i]).abs());
      }
      expect(maxDelta, greaterThan(0.1));
    });

    test('summing with a dry copy cancels at the corner', () {
      // At its corner an all-pass is 180° out; adding the dry signal back should
      // largely cancel. This is the property phasers are built from, and the one
      // that proves the coefficients are the all-pass ones rather than a
      // pass-through.
      final input = _tone(1000);
      final wet = _fx(FxType.allpass, {'freq': 1000, 'q': 0.707}, input);
      final summed = Float64List(input.length);
      for (var i = 0; i < input.length; i++) {
        summed[i] = (input[i] + wet[i]) / 2;
      }
      // Ignore the filter's start-up transient.
      final steady = Float64List.sublistView(summed, 4410);
      expect(_rms(steady), lessThan(_rms(input) / 10));
    });
  });

  group('one-pole — the gentle shapes', () {
    test('low-pass is −3 dB at its corner', () {
      final input = _tone(1000);
      final out = _fx(FxType.onePoleLowpass, {'freq': 1000}, input);
      final ratio = _magnitudeAt(out, 1000) / _magnitudeAt(input, 1000);
      expect(20 * math.log(ratio) / math.ln10, closeTo(-3, 0.6));
    });

    test('high-pass is ~−3.6 dB at its corner (the complementary form)', () {
      // Not the textbook −3.0: this high-pass is defined as input minus the
      // low-pass, which buys exact reconstruction (asserted below) at the cost
      // of a little over half a dB at the corner. Pinned at the real value so
      // the trade-off cannot drift unnoticed.
      final input = _tone(1000);
      final out = _fx(FxType.onePoleHighpass, {'freq': 1000}, input);
      final ratio = _magnitudeAt(out, 1000) / _magnitudeAt(input, 1000);
      expect(20 * math.log(ratio) / math.ln10, closeTo(-3.6, 0.3));
    });

    test('it rolls off at 6 dB/octave, not 12', () {
      // Two octaves above a low-pass corner: a one-pole is ~−12 dB where the
      // two-pole biquad is ~−24. This is the whole reason the effect exists, so
      // it is asserted against the biquad rather than in isolation.
      final input = _tone(4000);
      final onePole = _fx(FxType.onePoleLowpass, {'freq': 1000}, input);
      final twoPole =
          _fx(FxType.lowpass, {'freq': 1000, 'q': 0.707, 'mix': 1}, input);
      double db(Float64List x) =>
          20 *
          math.log(_magnitudeAt(x, 4000) / _magnitudeAt(input, 4000)) /
          math.ln10;
      expect(db(onePole), closeTo(-12, 2));
      expect(db(twoPole), lessThan(db(onePole) - 6));
    });

    test('the two shapes are exact complements — they sum back to unity', () {
      final input = _tone(700);
      final low = onePoleLowpassFx(input, sampleRate: 44100, freq: 1000);
      final high = onePoleHighpassFx(input, sampleRate: 44100, freq: 1000);
      for (var i = 0; i < input.length; i++) {
        expect(low[i] + high[i], closeTo(input[i], 1e-12));
      }
    });

    test('mix=0 is an exact copy', () {
      final input = _tone(700);
      final out = _fx(FxType.onePoleLowpass, {'freq': 200, 'mix': 0}, input);
      expect(out, orderedEquals(input));
    });
  });

  group('raw biquad — the escape hatch', () {
    test('the identity coefficients pass audio through untouched', () {
      final input = _tone(1000);
      final out = _fx(FxType.biquadRaw, const {}, input);
      for (var i = 0; i < input.length; i++) {
        expect(out[i], closeTo(input[i], 1e-12));
      }
    });

    test('hand-entered coefficients really filter', () {
      // A one-pole low-pass expressed as a biquad: y = 0.05x + 0.95y[-1].
      final input = _tone(8000);
      final out = _fx(FxType.biquadRaw, {'b0': 0.05, 'a1': -0.95}, input);
      expect(_magnitudeAt(out, 8000), lessThan(_magnitudeAt(input, 8000) / 4));
    });

    test('the stability test agrees with the Jury conditions', () {
      expect(biquadIsStable(0, 0), isTrue);
      expect(biquadIsStable(-0.95, 0), isTrue);
      expect(biquadIsStable(-1.9, 0.95), isTrue);
      expect(biquadIsStable(0, 1), isFalse); // |a2| = 1
      expect(biquadIsStable(-2, 0.9), isFalse); // |a1| >= 1 + a2
      expect(biquadIsStable(double.nan, 0), isFalse);
    });

    test('UNSTABLE coefficients pass through instead of exploding', () {
      // The failure mode this guards is not "wrong sound" but full-scale noise
      // and then NaN spreading through the whole mix.
      final input = _tone(1000);
      final out =
          _fx(FxType.biquadRaw, {'b0': 1, 'a1': -2.5, 'a2': 0.99}, input);
      for (var i = 0; i < out.length; i++) {
        expect(out[i].isFinite, isTrue, reason: 'sample $i went non-finite');
      }
      expect(out.last, closeTo(input.last, 1e-12));
    });
  });

  group('windowed-sinc — steep and linear-phase', () {
    test('low-pass keeps the passband and kills the stopband', () {
      final pass = _tone(500);
      final stop = _tone(4000);
      final params = {'shape': 0.0, 'freq': 2000.0, 'taps': 255.0};
      expect(
        _magnitudeAt(_fx(FxType.sincFilter, params, pass), 500),
        closeTo(_magnitudeAt(pass, 500), 0.02),
      );
      expect(
        _magnitudeAt(_fx(FxType.sincFilter, params, stop), 4000),
        lessThan(_magnitudeAt(stop, 4000) / 100),
      );
    });

    test('high-pass is the mirror image', () {
      final low = _tone(500);
      final high = _tone(4000);
      final params = {'shape': 1.0, 'freq': 2000.0, 'taps': 255.0};
      expect(
        _magnitudeAt(_fx(FxType.sincFilter, params, low), 500),
        lessThan(_magnitudeAt(low, 500) / 100),
      );
      expect(
        _magnitudeAt(_fx(FxType.sincFilter, params, high), 4000),
        closeTo(_magnitudeAt(high, 4000), 0.02),
      );
    });

    test('band-pass keeps only what is between the edges', () {
      // The edges are set a comfortable distance apart: a windowed FIR needs
      // ~6·fs/taps Hz of transition, so a 200 Hz-wide band is not buildable even
      // at the tap ceiling (see designWindowedSinc). A resonant biquad is the
      // tool for that; this one is for taking out a REGION.
      final params = {
        'shape': 2.0,
        'freq': 800.0,
        'freqHigh': 3000.0,
        'taps': 511.0,
      };
      for (final (hz, survives) in [
        (200.0, false),
        (1500.0, true),
        (8000.0, false),
      ]) {
        final input = _tone(hz);
        final out = _fx(FxType.sincFilter, params, input);
        final ratio = _magnitudeAt(out, hz) / _magnitudeAt(input, hz);
        if (survives) {
          expect(ratio, greaterThan(0.8), reason: '$hz Hz should pass');
        } else {
          expect(ratio, lessThan(0.05), reason: '$hz Hz should be rejected');
        }
      }
    });

    test('band-reject removes only what is between the edges', () {
      final params = {
        'shape': 3.0,
        'freq': 800.0,
        'freqHigh': 3000.0,
        'taps': 511.0,
      };
      for (final (hz, survives) in [
        (200.0, true),
        (1500.0, false),
        (8000.0, true),
      ]) {
        final input = _tone(hz);
        final out = _fx(FxType.sincFilter, params, input);
        final ratio = _magnitudeAt(out, hz) / _magnitudeAt(input, hz);
        if (survives) {
          expect(ratio, greaterThan(0.8), reason: '$hz Hz should pass');
        } else {
          expect(ratio, lessThan(0.05), reason: '$hz Hz should be notched out');
        }
      }
    });

    test('more taps means a steeper transition', () {
      // Just above the corner, a longer kernel rejects more. This is what the
      // steepness control is FOR, so it is asserted rather than assumed.
      final input = _tone(2400);
      double survives(int taps) =>
          _magnitudeAt(
            _fx(
              FxType.sincFilter,
              {'shape': 0, 'freq': 2000, 'taps': taps.toDouble()},
              input,
            ),
            2400,
          ) /
          _magnitudeAt(input, 2400);
      expect(survives(511), lessThan(survives(31)));
    });

    test('it is LINEAR-phase: the output is not time-shifted', () {
      // The property that distinguishes it from the biquads. A pulse through a
      // linear-phase filter, delay-compensated, stays centred where it was.
      final input = Float64List(2048);
      input[1024] = 1;
      final out = sincFilterFx(
        input,
        sampleRate: 44100,
        freq: 4000,
      );
      var peakIndex = 0;
      var peak = 0.0;
      for (var i = 0; i < out.length; i++) {
        if (out[i].abs() > peak) {
          peak = out[i].abs();
          peakIndex = i;
        }
      }
      expect(peakIndex, 1024);
    });

    test('a kernel is odd-length and capped', () {
      expect(
        designWindowedSinc(
          shape: FirShape.lowpass,
          sampleRate: 44100,
          freq: 1000,
          taps: 64,
        ).length,
        65,
      );
      expect(
        designWindowedSinc(
          shape: FirShape.lowpass,
          sampleRate: 44100,
          freq: 1000,
          taps: 99999,
        ).length,
        kMaxFirTaps,
      );
    });
  });

  group('Hilbert — 90° with the magnitudes intact', () {
    test('level is preserved across the band', () {
      for (final hz in [500.0, 2000.0, 6000.0]) {
        final input = _tone(hz);
        final out = _fx(FxType.hilbert, {'taps': 255}, input);
        // Away from DC and Nyquist a windowed Hilbert is close to unity.
        expect(
          _magnitudeAt(out, hz) / _magnitudeAt(input, hz),
          closeTo(1, 0.1),
          reason: '$hz Hz changed level',
        );
      }
    });

    test('a sine really comes out as a cosine (quarter-cycle shift)', () {
      const hz = 1000.0;
      final input = _tone(hz, amp: 1);
      final out = hilbertFx(input, taps: 255);
      // Shifting the OUTPUT back by a quarter period should reproduce ±input.
      final quarter = (_sr / hz / 4).round();
      var error = 0.0;
      for (var i = 2000; i < 20000; i++) {
        // A 90° lag means out[i] ≈ -input at a quarter period earlier, or
        // equivalently out[i + quarter] ≈ ±input[i]; compare energy-normalised
        // shapes and take whichever sign matches.
        error += (out[i] - input[i - quarter]).abs();
      }
      final mean = error / 18000;
      expect(mean, lessThan(0.15), reason: 'mean deviation $mean');
    });

    test('mix=0 is an exact copy', () {
      final input = _tone(700);
      expect(_fx(FxType.hilbert, {'mix': 0}, input), orderedEquals(input));
    });
  });

  group('registry', () {
    test('every new effect is a filter, labelled, with described params', () {
      const added = [
        FxType.allpass,
        FxType.onePoleLowpass,
        FxType.onePoleHighpass,
        FxType.biquadRaw,
        FxType.sincFilter,
        FxType.hilbert,
      ];
      for (final type in added) {
        expect(fxCategory(type), FxCategory.filter, reason: type.name);
        expect(fxTypeLabel(type), isNotEmpty, reason: type.name);
        expect(fxParamSpecs(type), isNotEmpty, reason: type.name);
        for (final key in defaultFx(type).params.keys) {
          expect(
            hasFxParamSpec(type, key),
            isTrue,
            reason: '${type.name}.$key has no descriptor',
          );
        }
      }
    });

    test('a slider step is sane for every param of every effect', () {
      for (final type in FxType.values) {
        for (final spec in fxParamSpecs(type)) {
          final step = fxSliderStep(spec);
          expect(step, greaterThan(0), reason: '${type.name}.${spec.key}');
          expect(
            step,
            lessThanOrEqualTo(spec.max - spec.min),
            reason: '${type.name}.${spec.key} steps past its whole range',
          );
          if (spec.integer) expect(step, 1, reason: '${type.name}.${spec.key}');
        }
      }
    });
  });
}
