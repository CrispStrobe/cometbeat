// test/fx_chain_test.dart
//
// A1 — the shared FX dispatch. The invariants here are what let an effect
// authored in one mode be rendered by another:
//
//  * SAME LENGTH out as in — stems stay aligned (`mixStems`) and clips stay on
//    the timeline grid. This is the single hardest constraint; length-changing
//    DSP (pitch shift, time stretch) must be refitted before the wet/dry blend.
//  * `enabled: false` and an empty chain are EXACT identity, so a bypassed rack
//    re-renders bit-identically and caches hit.
//  * nothing produces NaN/Inf, whatever the input.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/fx/fx_chain.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleRate = 44100;

Float64List _sine({int n = 4410, double hz = 440, double amp = 0.5}) {
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amp * math.sin(2 * math.pi * hz * i / _sampleRate);
  }
  return out;
}

void main() {
  group('length invariant', () {
    test('every FxType returns exactly its input length (mono)', () {
      final input = _sine();
      for (final type in FxType.values) {
        final out = applyFxChain(input, [defaultFx(type)], _sampleRate);
        expect(
          out.length,
          input.length,
          reason: '$type changed the buffer length — stems would drift apart',
        );
      }
    });

    test('every FxType returns exactly its input length (stereo)', () {
      final left = _sine();
      final right = _sine(hz: 660);
      for (final type in FxType.values) {
        final out =
            applyFxChainStereo(left, right, [defaultFx(type)], _sampleRate);
        expect(out.left.length, left.length, reason: '$type left');
        expect(out.right.length, right.length, reason: '$type right');
      }
    });

    test('a stacked chain of every effect still preserves length', () {
      final input = _sine();
      final chain = [for (final t in FxType.values) defaultFx(t)];
      expect(applyFxChain(input, chain, _sampleRate).length, input.length);
    });
  });

  group('identity', () {
    test('an empty chain returns the input untouched', () {
      final input = _sine();
      expect(applyFxChain(input, const [], _sampleRate), same(input));
    });

    test('a fully bypassed chain is bit-identical', () {
      final input = _sine();
      final chain = [
        for (final t in FxType.values) defaultFx(t).copyWith(enabled: false),
      ];
      final out = applyFxChain(input, chain, _sampleRate);
      expect(out.length, input.length);
      for (var i = 0; i < input.length; i++) {
        expect(out[i], input[i], reason: 'sample $i changed while bypassed');
      }
    });

    test('a bypassed stereo chain is bit-identical on both sides', () {
      final left = _sine();
      final right = _sine(hz: 660);
      final chain = [
        for (final t in FxType.values) defaultFx(t).copyWith(enabled: false),
      ];
      final out = applyFxChainStereo(left, right, chain, _sampleRate);
      for (var i = 0; i < left.length; i++) {
        expect(out.left[i], left[i]);
        expect(out.right[i], right[i]);
      }
    });
  });

  group('numerical safety', () {
    test('no effect produces NaN or Inf on a normal signal', () {
      final input = _sine();
      for (final type in FxType.values) {
        final out = applyFxChain(input, [defaultFx(type)], _sampleRate);
        for (final v in out) {
          expect(v.isFinite, isTrue, reason: '$type produced $v');
        }
      }
    });

    test('no effect produces NaN or Inf on silence', () {
      final silence = Float64List(2048);
      for (final type in FxType.values) {
        final out = applyFxChain(silence, [defaultFx(type)], _sampleRate);
        for (final v in out) {
          expect(v.isFinite, isTrue, reason: '$type produced $v on silence');
        }
      }
    });

    test('no effect produces NaN or Inf on a hot/clipped signal', () {
      final hot = Float64List.fromList([
        for (var i = 0; i < 2048; i++) (i.isEven ? 1.0 : -1.0),
      ]);
      for (final type in FxType.values) {
        final out = applyFxChain(hot, [defaultFx(type)], _sampleRate);
        for (final v in out) {
          expect(v.isFinite, isTrue, reason: '$type produced $v on a square');
        }
      }
    });

    test('an empty buffer is handled by every effect', () {
      final empty = Float64List(0);
      for (final type in FxType.values) {
        expect(
          applyFxChain(empty, [defaultFx(type)], _sampleRate).length,
          0,
          reason: '$type on an empty buffer',
        );
      }
    });
  });

  group('audible behaviour (sanity, not golden)', () {
    double rms(Float64List b) {
      if (b.isEmpty) return 0;
      var s = 0.0;
      for (final v in b) {
        s += v * v;
      }
      return math.sqrt(s / b.length);
    }

    test('gain at -20 dB really attenuates', () {
      final input = _sine();
      final out = applyFxChain(
        input,
        [
          defaultFx(FxType.gain).copyWith(params: {'gainDb': -20, 'mix': 1}),
        ],
        _sampleRate,
      );
      expect(rms(out), lessThan(rms(input) * 0.2));
    });

    test('a lowpass at 200 Hz kills a 4 kHz tone', () {
      final input = _sine(hz: 4000);
      final out = applyFxChain(
        input,
        [
          defaultFx(FxType.lowpass)
              .copyWith(params: {'freq': 200, 'q': 0.707, 'mix': 1}),
        ],
        _sampleRate,
      );
      expect(rms(out), lessThan(rms(input) * 0.5));
    });

    test('chain order matters when an effect is nonlinear', () {
      // Gain and reverb are both LINEAR, so they commute exactly — ordering is
      // only observable across a nonlinear stage. Driving a distortion hard and
      // then attenuating is not the same as attenuating and then driving it.
      final input = _sine(amp: 0.9);
      final boost =
          defaultFx(FxType.gain).copyWith(params: {'gainDb': 18, 'mix': 1});
      final crunch = defaultFx(FxType.distortion);
      final boostFirst = applyFxChain(input, [boost, crunch], _sampleRate);
      final crunchFirst = applyFxChain(input, [crunch, boost], _sampleRate);
      expect(boostFirst.length, crunchFirst.length);
      var maxDelta = 0.0;
      for (var i = 0; i < boostFirst.length; i++) {
        maxDelta = math.max(maxDelta, (boostFirst[i] - crunchFirst[i]).abs());
      }
      expect(maxDelta, greaterThan(1e-6));
    });
  });

  group('automation', () {
    test('a mix ramp is applied over time, not as a constant', () {
      final input = _sine();
      final durationMs = input.length * 1000 / _sampleRate;
      final fx = defaultFx(FxType.gain).copyWith(
        params: {'gainDb': -60, 'mix': 1},
        automation: {
          'gainDb': [
            const FxAutomationPoint(ms: 0, value: 0),
            FxAutomationPoint(ms: durationMs, value: -60),
          ],
        },
      );
      final out = applyFxChain(input, [fx], _sampleRate);
      expect(out.length, input.length);
      // Early samples keep roughly their level, late samples are crushed.
      var head = 0.0;
      var tail = 0.0;
      for (var i = 0; i < 500; i++) {
        head = math.max(head, out[i].abs());
        tail = math.max(tail, out[out.length - 1 - i].abs());
      }
      expect(head, greaterThan(tail * 10));
    });

    // Reads the level at a point one QUARTER of the way along the ramp. That
    // is where the three curves genuinely separate: at the midpoint linear and
    // sCurve both sit at 0.5, so a midpoint probe cannot tell them apart.
    double quarterLevel(FxFadeCurve curve) {
      final input = Float64List(_sampleRate)..fillRange(0, _sampleRate, 1);
      final durationMs = input.length * 1000 / _sampleRate;
      final fx = defaultFx(FxType.gain).copyWith(
        params: {'gainDb': 0, 'mix': 1},
        automation: {
          'gainDb': [
            FxAutomationPoint(ms: 0, value: -60, curve: curve),
            FxAutomationPoint(ms: durationMs, value: 0),
          ],
        },
      );
      final out = applyFxChain(input, [fx], _sampleRate);
      return out[(_sampleRate * 0.25).round()].abs();
    }

    test('the authored curve shapes the ramp — it is not always linear', () {
      // The curve survives save/load and the editor draws it, so if it were
      // dropped on the way to the DSP the ramp would still SOUND fine — just
      // never like the one that was drawn. Nothing else would report it.
      final linear = quarterLevel(FxFadeCurve.linear);
      final exponential = quarterLevel(FxFadeCurve.exponential);
      final sCurve = quarterLevel(FxFadeCurve.sCurve);

      // t=0.25: linear→0.25, exponential→0.0625, sCurve→0.156. In dB terms
      // that is a strictly quieter quarter-point for the curved ramps.
      expect(
        exponential,
        lessThan(linear),
        reason: 'an exponential ramp rises later than a linear one',
      );
      expect(
        sCurve,
        lessThan(linear),
        reason: 'an S-curve eases in, so it is below linear at a quarter',
      );
      expect(sCurve, greaterThan(exponential));
    });

    test('mono and stereo render the same automation identically', () {
      // Two code paths sample the same breakpoints. If they sanitise or read
      // the curve differently, a clip changes shape the moment a pan makes it
      // stereo — which is exactly when nobody is listening for it.
      final mono = Float64List(_sampleRate)..fillRange(0, _sampleRate, 1);
      final durationMs = mono.length * 1000 / _sampleRate;
      final fx = defaultFx(FxType.gain).copyWith(
        params: {'gainDb': 0, 'mix': 1},
        automation: {
          'gainDb': [
            const FxAutomationPoint(
              ms: 0,
              value: -60,
              curve: FxFadeCurve.exponential,
            ),
            FxAutomationPoint(ms: durationMs, value: 0),
          ],
        },
      );

      final monoOut = applyFxChain(mono, [fx], _sampleRate);
      final stereoOut = applyFxChainStereo(
        mono,
        Float64List.fromList(mono),
        [fx],
        _sampleRate,
      );
      for (var i = 0; i < mono.length; i += 97) {
        expect(
          stereoOut.left[i],
          closeTo(monoOut[i], 1e-12),
          reason: 'stereo diverged from mono at sample $i',
        );
      }
    });

    test('malformed points are survived, not rendered', () {
      // A hand-edited or truncated project file can carry these. The mono path
      // already sorted/filtered them; the stereo path must not crash or emit
      // NaN on the same input.
      final mono = Float64List(1000)..fillRange(0, 1000, 1);
      final fx = defaultFx(FxType.gain).copyWith(
        params: {'gainDb': 0, 'mix': 1},
        automation: {
          'gainDb': [
            const FxAutomationPoint(ms: 20, value: -12), // out of order
            const FxAutomationPoint(ms: -5, value: 0), // negative time
            const FxAutomationPoint(ms: double.nan, value: -6), // not finite
          ],
          'mix': const <FxAutomationPoint>[], // authored then emptied
        },
      );

      for (final out in [
        applyFxChain(mono, [fx], _sampleRate),
        applyFxChainStereo(
          mono,
          Float64List.fromList(mono),
          [fx],
          _sampleRate,
        ).left,
      ]) {
        expect(out.length, mono.length);
        expect(out.every((v) => v.isFinite), isTrue);
      }
    });

    test('automation on a bypassed effect does nothing', () {
      final input = _sine();
      final fx = defaultFx(FxType.gain).copyWith(
        enabled: false,
        automation: {
          'gainDb': const [
            FxAutomationPoint(ms: 0, value: 0),
            FxAutomationPoint(ms: 100, value: -60),
          ],
        },
      );
      final out = applyFxChain(input, [fx], _sampleRate);
      for (var i = 0; i < input.length; i++) {
        expect(out[i], input[i]);
      }
    });
  });
}
