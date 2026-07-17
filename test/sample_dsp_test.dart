// crisp_dsp sample effects — resampler, granular pitch shift, formant shift, and
// the voice-effect palette. Pure Dart, tested against a synthetic sample.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/formant_shift.dart';
import 'package:comet_beat/core/audio/crisp_dsp/pitch_shift.dart';
import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [seconds]-long sine at [hz] (44.1 kHz), a stand-in for a recording.
Float64List _sine(double seconds, double hz, {int sr = 44100}) {
  final n = (seconds * sr).floor();
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = sin(2 * pi * hz * i / sr);
  }
  return out;
}

double _peak(Float64List b) {
  var p = 0.0;
  for (final v in b) {
    if (v.abs() > p) p = v.abs();
  }
  return p;
}

bool _finite(Float64List b) => b.every((v) => v.isFinite);

void main() {
  group('resampleLinear', () {
    test('ratio > 1 shortens, ratio < 1 lengthens', () {
      final s = _sine(0.1, 220);
      expect(resampleLinear(s, 2.0).length, (s.length / 2).floor());
      expect(resampleLinear(s, 0.5).length, s.length * 2);
    });

    test('ratio 1 preserves a constant signal', () {
      final dc = Float64List.fromList(List.filled(100, 0.5));
      final out = resampleLinear(dc, 1.0);
      expect(out.length, 100);
      expect(out.every((v) => (v - 0.5).abs() < 1e-9), isTrue);
    });

    test('degenerate input is empty, not a crash', () {
      expect(resampleLinear(Float64List(0), 2).length, 0);
      expect(resampleLinear(_sine(0.01, 220), 0).length, 0);
    });
  });

  group('resampleCubic', () {
    test('same length semantics as linear + finite', () {
      final s = _sine(0.1, 220);
      expect(resampleCubic(s, 2.0).length, (s.length / 2).floor());
      expect(resampleCubic(s, 0.5).length, s.length * 2);
      expect(_finite(resampleCubic(s, 1.5)), isTrue);
    });

    test('ratio 1 preserves a constant signal', () {
      final dc = Float64List.fromList(List.filled(100, 0.5));
      final out = resampleCubic(dc, 1.0);
      expect(out.length, 100);
      expect(out.every((v) => (v - 0.5).abs() < 1e-9), isTrue);
    });

    test('degenerate input is safe', () {
      expect(resampleCubic(Float64List(0), 2).length, 0);
      expect(resampleCubic(_sine(0.01, 220), 0).length, 0);
      expect(resampleCubic(Float64List.fromList([0.7]), 1.0), [0.7]);
    });

    test('reconstructs a pitched sine more accurately than linear', () {
      const hz = 3000.0, sr = 44100, ratio = 1.5;
      final s = _sine(0.05, hz); // _sine defaults to 44100 Hz
      final lin = resampleLinear(s, ratio);
      final cub = resampleCubic(s, ratio);
      expect(cub.length, lin.length);
      double rms(Float64List b) {
        var sum = 0.0;
        for (var i = 2; i < b.length - 2; i++) {
          final truth = sin(2 * pi * hz * (i * ratio) / sr);
          final e = b[i] - truth;
          sum += e * e;
        }
        return sqrt(sum / (b.length - 4));
      }

      final eLin = rms(lin), eCub = rms(cub);
      // Cubic is clearly closer to the true resampled sine than linear.
      expect(eCub, lessThan(eLin * 0.5));
    });
  });

  group('granularPitchShift', () {
    test('zero semitones is identity', () {
      final s = _sine(0.2, 220);
      expect(identical(granularPitchShift(s, 0), s), isTrue);
    });

    test('a shift produces finite, audible output', () {
      final s = _sine(0.2, 220);
      final up = granularPitchShift(s, 12);
      expect(up.isNotEmpty, isTrue);
      expect(_finite(up), isTrue);
      expect(_peak(up), greaterThan(0.0));
    });
  });

  group('formantShift', () {
    test('zero shift is identity', () {
      final s = _sine(0.2, 220);
      expect(identical(formantShift(s, 0), s), isTrue);
    });

    test('a shift keeps the length, changes the content, stays finite', () {
      final s = _sine(0.2, 220);
      final shifted = formantShift(s, 0.5);
      expect(shifted.length, s.length);
      expect(_finite(shifted), isTrue);
      var same = true;
      for (var i = 0; i < s.length; i++) {
        if ((s[i] - shifted[i]).abs() > 1e-6) {
          same = false;
          break;
        }
      }
      expect(same, isFalse);
    });
  });

  group('applyVoiceEffect', () {
    final raw = _sine(0.2, 220);

    test('every effect yields finite, audible output', () {
      for (final fx in VoiceEffect.values) {
        final out = applyVoiceEffect(raw, fx);
        expect(out.isNotEmpty, isTrue, reason: '$fx empty');
        expect(_finite(out), isTrue, reason: '$fx not finite');
        expect(_peak(out), greaterThan(0.0), reason: '$fx silent');
      }
    });

    test('normal is a faithful copy; robot changes the signal', () {
      final normal = applyVoiceEffect(raw, VoiceEffect.normal);
      expect(normal, equals(raw));
      final robot = applyVoiceEffect(raw, VoiceEffect.robot);
      expect(robot, isNot(equals(raw)));
      expect(robot.length, raw.length); // pitch/length preserving
    });
  });
}
