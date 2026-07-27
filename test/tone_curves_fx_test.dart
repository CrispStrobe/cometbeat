// A2/A6 — the broad tone curves, and a pitch envelope.
//
// The biquads answer "remove this frequency"; these answer "make it darker",
// "make it sound right quietly", "make it cut through". So the assertions are
// about the BALANCE between bands rather than about one band, plus the property
// that distinguishes each from the nearest thing it could be confused with — a
// tilt from a low-pass, presence from distortion, a bend from a pitch shift.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/tone_curves.dart';
import 'package:comet_beat/core/audio/fx/fx_chain.dart';
import 'package:comet_beat/core/audio/fx/fx_params.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:flutter_test/flutter_test.dart';

const int _sr = 44100;

Float64List _tone(double hz, {int ms = 500, double amp = 0.4}) {
  final n = ms * _sr ~/ 1000;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amp * math.sin(2 * math.pi * hz * i / _sr);
  }
  return out;
}

Float64List _mix(List<Float64List> parts) {
  final n = parts.map((p) => p.length).reduce(math.max);
  final out = Float64List(n);
  for (final p in parts) {
    for (var i = 0; i < p.length; i++) {
      out[i] += p[i];
    }
  }
  return out;
}

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

double _rms(Float64List x) {
  if (x.isEmpty) return 0;
  var sum = 0.0;
  for (final v in x) {
    sum += v * v;
  }
  return math.sqrt(sum / x.length);
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
  group('tilt', () {
    test('positive lifts the treble AND drops the bass', () {
      final input = _mix([_tone(100), _tone(6000)]);
      final out = _fx(FxType.tilt, {'tiltDb': 10, 'pivotHz': 1000}, input);
      expect(_magnitudeAt(out, 6000), greaterThan(_magnitudeAt(input, 6000)));
      expect(_magnitudeAt(out, 100), lessThan(_magnitudeAt(input, 100)));
    });

    test('negative does the reverse', () {
      final input = _mix([_tone(100), _tone(6000)]);
      final out = _fx(FxType.tilt, {'tiltDb': -10, 'pivotHz': 1000}, input);
      expect(_magnitudeAt(out, 100), greaterThan(_magnitudeAt(input, 100)));
      expect(_magnitudeAt(out, 6000), lessThan(_magnitudeAt(input, 6000)));
    });

    test('it is NOT a low-pass — the top survives', () {
      // The distinction worth having: a low-pass removes the treble, a tilt
      // just moves it down relative to the bass. Even at a strong negative
      // tilt, 8 kHz must still be plainly there.
      final input = _tone(8000);
      final out = _fx(FxType.tilt, {'tiltDb': -12, 'pivotHz': 1000}, input);
      expect(
        _magnitudeAt(out, 8000),
        greaterThan(_magnitudeAt(input, 8000) * 0.3),
      );
    });

    test('the pivot roughly holds still', () {
      // What makes it a TILT rather than a shelf plus a level change.
      final input = _tone(1000);
      final out = _fx(FxType.tilt, {'tiltDb': 12, 'pivotHz': 1000}, input);
      expect(
        _magnitudeAt(out, 1000),
        closeTo(_magnitudeAt(input, 1000), _magnitudeAt(input, 1000) * 0.3),
      );
    });

    test('zero tilt is an exact copy', () {
      final input = _tone(1000);
      expect(_fx(FxType.tilt, {'tiltDb': 0}, input), orderedEquals(input));
    });
  });

  group('loudness', () {
    test('it lifts the extremes and leaves the middle', () {
      final input = _mix([_tone(60), _tone(1000), _tone(12000)]);
      final out = _fx(FxType.loudness, {'amount': 20}, input);
      expect(_magnitudeAt(out, 60), greaterThan(_magnitudeAt(input, 60) * 1.5));
      expect(
        _magnitudeAt(out, 12000),
        greaterThan(_magnitudeAt(input, 12000)),
      );
      // The midrange is the reference — it should barely move.
      expect(
        _magnitudeAt(out, 1000),
        closeTo(_magnitudeAt(input, 1000), _magnitudeAt(input, 1000) * 0.25),
      );
    });

    test('the bass is lifted MORE than the treble', () {
      // The contours steepen faster at the bottom; equal shelves would be a
      // different (and wrong) effect.
      final input = _mix([_tone(60), _tone(12000)]);
      final out = _fx(FxType.loudness, {'amount': 20}, input);
      final bassLift = _magnitudeAt(out, 60) / _magnitudeAt(input, 60);
      final trebleLift = _magnitudeAt(out, 12000) / _magnitudeAt(input, 12000);
      expect(bassLift, greaterThan(trebleLift));
    });

    test('amount 0 is an exact copy', () {
      final input = _tone(1000);
      expect(_fx(FxType.loudness, {'amount': 0}, input), orderedEquals(input));
    });
  });

  group('de-emphasis', () {
    test('it rolls the treble off and leaves the bass', () {
      final input = _mix([_tone(100), _tone(10000)]);
      final out = _fx(FxType.deEmphasis, const {}, input);
      expect(
        _magnitudeAt(out, 10000),
        lessThan(_magnitudeAt(input, 10000) * 0.5),
      );
      expect(
        _magnitudeAt(out, 100),
        closeTo(_magnitudeAt(input, 100), _magnitudeAt(input, 100) * 0.2),
      );
    });

    test('75 µs rolls off EARLIER than 50 µs', () {
      // The two constants are the whole vocabulary, so they have to differ in
      // the direction the physics says: a longer time constant is a lower
      // corner, hence more roll-off at a given frequency.
      final input = _tone(6000);
      final fifty = _fx(FxType.deEmphasis, {'curve': 0}, input);
      final seventyFive = _fx(FxType.deEmphasis, {'curve': 1}, input);
      expect(
        _magnitudeAt(seventyFive, 6000),
        lessThan(_magnitudeAt(fifty, 6000)),
      );
    });
  });

  group('presence', () {
    test('it raises the level of mid-scale material', () {
      final input = _tone(1000);
      final out = _fx(FxType.contrast, {'amount': 1}, input);
      expect(_rms(out), greaterThan(_rms(input)));
    });

    test('it leaves the PEAKS alone — that is the point', () {
      // "Louder without louder": a full-scale sample must come back full scale,
      // or this is just a gain stage with extra steps.
      final input = Float64List.fromList([1.0, -1.0, 0.5, -0.5, 0.0]);
      final out = contrastFx(input, amount: 1);
      expect(out[0], closeTo(1.0, 1e-9));
      expect(out[1], closeTo(-1.0, 1e-9));
      expect(out[4], closeTo(0.0, 1e-9));
      // …while the mid-scale samples came up.
      expect(out[2], greaterThan(0.5));
    });

    test('it is odd-symmetric — no DC is introduced', () {
      // An asymmetric shaper adds a DC offset, which is a defect the repair
      // tools then have to remove.
      final input = _tone(1000);
      final out = _fx(FxType.contrast, {'amount': 1}, input);
      var mean = 0.0;
      for (final v in out) {
        mean += v;
      }
      expect(mean / out.length, closeTo(0, 1e-6));
    });

    test('amount 0 is an exact copy', () {
      final input = _tone(1000);
      expect(_fx(FxType.contrast, {'amount': 0}, input), orderedEquals(input));
    });
  });

  group('pitch bend', () {
    test('the pitch really moves across the clip', () {
      final input = _tone(1000, ms: 1000);
      final out = _fx(
        FxType.pitchBend,
        {'semitones': 0, 'endSemitones': -12},
        input,
      );
      // Early on it is still near the original pitch…
      final early = Float64List.sublistView(out, 0, 8000);
      expect(_magnitudeAt(early, 1000), greaterThan(_magnitudeAt(early, 500)));
      // …and by the end it has fallen toward an octave down.
      final late = Float64List.sublistView(out, out.length - 8000);
      expect(_magnitudeAt(late, 500), greaterThan(_magnitudeAt(late, 1000)));
    });

    test('it preserves the clip LENGTH', () {
      // The design choice: a bend must not silently change a clip's length
      // under the arrangement. Reading faster runs out of source and fades,
      // which is what a tape stop sounds like anyway.
      final input = _tone(1000);
      for (final end in [-12.0, 12.0]) {
        final out = _fx(FxType.pitchBend, {'endSemitones': end}, input);
        expect(out.length, input.length, reason: 'end=$end');
      }
    });

    test('a bend to nowhere is an exact copy', () {
      final input = _tone(1000);
      expect(
        _fx(FxType.pitchBend, {'semitones': 0, 'endSemitones': 0}, input),
        orderedEquals(input),
      );
    });
  });

  group('registry', () {
    test('the new effects are categorised, labelled and described', () {
      const added = {
        FxType.tilt: FxCategory.filter,
        FxType.loudness: FxCategory.filter,
        FxType.deEmphasis: FxCategory.filter,
        FxType.contrast: FxCategory.filter,
        FxType.pitchBend: FxCategory.pitch,
      };
      for (final entry in added.entries) {
        expect(fxCategory(entry.key), entry.value, reason: entry.key.name);
        expect(fxTypeLabel(entry.key), isNotEmpty, reason: entry.key.name);
        for (final key in defaultFx(entry.key).params.keys) {
          expect(
            hasFxParamSpec(entry.key, key),
            isTrue,
            reason: '${entry.key.name}.$key has no descriptor',
          );
        }
      }
    });

    test('the de-emphasis curve is a CHOICE, not a free number', () {
      // 50 and 75 µs are the only two that exist; a slider from 10 to 200 would
      // invite settings that mean nothing.
      final spec = fxParamSpec(FxType.deEmphasis, 'curve');
      expect(spec.isChoice, isTrue);
      expect(spec.choices, hasLength(2));
    });
  });
}
