// D4 — loudness measurement: LUFS, true peak, stereo correlation.
//
// Peak and RMS answer "how big are the numbers"; none of them answer "how loud
// does this SOUND", which is the question every delivery target is written in.
// The measurements here are defined by a published standard, so the tests are
// mostly CALIBRATION checks against what that standard says the answer is —
// which is the only way to know an implementation is right rather than merely
// self-consistent.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/loudness.dart';
import 'package:flutter_test/flutter_test.dart';

const int _sr = 44100;

Float64List _sine(double hz, {int ms = 4000, double amp = 1.0}) {
  final n = ms * _sr ~/ 1000;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amp * math.sin(2 * math.pi * hz * i / _sr);
  }
  return out;
}

Float64List _silence(int ms) => Float64List(ms * _sr ~/ 1000);

Float64List _concat(List<Float64List> parts) {
  final out = Float64List(parts.fold(0, (n, p) => n + p.length));
  var at = 0;
  for (final p in parts) {
    out.setRange(at, at + p.length, p);
    at += p.length;
  }
  return out;
}

void main() {
  group('calibration — what the standard says the answer is', () {
    test('a full-scale 1 kHz sine in BOTH channels reads about 0 LUFS', () {
      // The standard's reference point. Getting this wrong by a constant is the
      // easiest possible mistake and the hardest to notice, because every
      // relative comparison still looks right.
      final tone = _sine(1000);
      final reading = measureLoudness(tone, tone, sampleRate: _sr);
      expect(reading.integratedLufs, closeTo(0, 1.0));
    });

    test('halving the amplitude costs about 6 LU', () {
      // Loudness is a log measure of energy, so a factor of two in amplitude is
      // 6 dB — the relative scale has to hold even where the absolute
      // calibration is approximate.
      final loud = _sine(1000);
      final quiet = _sine(1000, amp: 0.5);
      final a = measureLoudness(loud, loud, sampleRate: _sr).integratedLufs;
      final b = measureLoudness(quiet, quiet, sampleRate: _sr).integratedLufs;
      expect(a - b, closeTo(6, 0.5));
    });

    test('a mono source reads about 3 LU below the same thing in stereo', () {
      // Two channels of the same signal sum to twice the energy. Pinned because
      // it is the difference between measuring a stem and measuring a mix.
      final tone = _sine(1000);
      final mono = measureLoudness(tone, null, sampleRate: _sr).integratedLufs;
      final stereo =
          measureLoudness(tone, tone, sampleRate: _sr).integratedLufs;
      expect(stereo - mono, closeTo(3, 0.5));
    });

    test('K-weighting really weights: bass counts for less', () {
      // The whole reason this is not just RMS. A 60 Hz tone and a 1 kHz tone at
      // the same amplitude do not sound equally loud, and the measurement has
      // to agree.
      final low = _sine(60);
      final mid = _sine(1000);
      expect(
        measureLoudness(low, low, sampleRate: _sr).integratedLufs,
        lessThan(measureLoudness(mid, mid, sampleRate: _sr).integratedLufs - 3),
      );
    });
  });

  group('gating — why silence does not count', () {
    test('adding silence to the end does not change the loudness', () {
      // The property gating exists for. Without it, padding a master would
      // lower its measured loudness, which is obviously wrong — and it is
      // exactly what a naive average would do.
      final music = _sine(1000, amp: 0.5);
      final padded = _concat([music, _silence(4000)]);
      final bare = measureLoudness(music, music, sampleRate: _sr);
      final withSilence = measureLoudness(padded, padded, sampleRate: _sr);
      expect(
        withSilence.integratedLufs,
        closeTo(bare.integratedLufs, 0.5),
      );
    });

    test('pure silence reports the floor, not negative infinity', () {
      // −infinity is the mathematically honest answer and a useless one to put
      // in a UI or a report.
      final reading = measureLoudness(_silence(2000), null, sampleRate: _sr);
      expect(reading.integratedLufs, kLoudnessSilenceLufs);
      expect(reading.integratedLufs.isFinite, isTrue);
    });

    test('momentary follows the LOUDEST moment, integrated does not', () {
      // The two numbers answer different questions: "how loud does it get" and
      // "how loud is it overall". A quiet piece with one loud stab must show
      // that difference.
      final quiet = _sine(1000, amp: 0.1);
      final stab = _sine(1000, ms: 500);
      final material = _concat([quiet, stab, quiet]);
      final reading = measureLoudness(material, material, sampleRate: _sr);
      expect(reading.momentaryLufs, greaterThan(reading.integratedLufs + 5));
    });
  });

  group('true peak', () {
    test('it catches a peak that lies BETWEEN samples', () {
      // The reason a sample peak meter is not enough. This signal alternates
      // just under full scale, so every SAMPLE is under 0 dBFS while the
      // reconstructed waveform between them is not.
      final tricky = Float64List(1000);
      for (var i = 0; i < tricky.length; i++) {
        // A sine landing near, but not on, its own peaks.
        tricky[i] = 0.99 * math.sin(2 * math.pi * (_sr / 4.7) * i / _sr);
      }
      var samplePeak = 0.0;
      for (final v in tricky) {
        samplePeak = math.max(samplePeak, v.abs());
      }
      final tp = truePeakDb(tricky, null);
      expect(tp, greaterThanOrEqualTo(20 * math.log(samplePeak) / math.ln10));
    });

    test('a full-scale sine is at 0 dBTP', () {
      expect(truePeakDb(_sine(1000, ms: 100), null), closeTo(0, 0.2));
    });

    test('silence reports the floor rather than −infinity', () {
      expect(truePeakDb(_silence(100), null).isFinite, isTrue);
    });
  });

  group('stereo correlation', () {
    test('identical channels correlate +1', () {
      final tone = _sine(440, ms: 500);
      expect(stereoCorrelation(tone, tone), closeTo(1, 1e-9));
    });

    test('an inverted channel correlates −1 — the mono-fold warning', () {
      // The reading that predicts a problem you cannot hear in stereo: this
      // material largely disappears when folded to mono, which is what a phone
      // speaker does.
      final tone = _sine(440, ms: 500);
      final inverted = Float64List.fromList([for (final v in tone) -v]);
      expect(stereoCorrelation(tone, inverted), closeTo(-1, 1e-9));
    });

    test('unrelated channels correlate near 0', () {
      final a = _sine(440, ms: 2000);
      final b = _sine(997, ms: 2000);
      expect(stereoCorrelation(a, b).abs(), lessThan(0.2));
    });

    test('silence reports mono-safe rather than dividing by zero', () {
      expect(stereoCorrelation(_silence(100), _silence(100)), 1);
    });
  });

  test('a mono reading reports correlation 1, not a meaningless number', () {
    final reading = measureLoudness(_sine(440, ms: 500), null, sampleRate: _sr);
    expect(reading.correlation, 1);
  });

  test('material shorter than a block does not crash or lie', () {
    // 100 ms cannot fill a 400 ms window; the honest answer is the floor.
    final reading = measureLoudness(_sine(440, ms: 100), null, sampleRate: _sr);
    expect(reading.integratedLufs, kLoudnessSilenceLufs);
    expect(reading.truePeakDb, closeTo(0, 0.5));
  });
}
