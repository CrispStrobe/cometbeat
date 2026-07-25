// test/s3m_adlib_synth_test.dart
//
// Unit tests for the AdLib/OPL type-2 instrument FM approximation in
// s3m_reader.dart: synthesizeAdlibWaveform (rendered directly) plus the
// end-to-end guarantee that a type-2 instrument comes back from parseS3m with a
// non-empty pcm. The synthesizer is a STATIC 2-operator FM approximation, not a
// cycle-exact OPL emulator — these tests pin its shape, not chip fidelity.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/s3m_adlib_synth_test.dart

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/mod/s3m_reader.dart';
import 'package:comet_beat/core/audio/mod/s3m_writer.dart';
import 'package:flutter_test/flutter_test.dart';

/// synthesizeAdlibWaveform spans this many cycles of the base frequency, so the
/// carrier oscillator sits at `carrierMult ×` that (documented in the reader).
const int _baseCycles = 2;

/// Builds a 12-byte OPL register block: modulator/carrier frequency multiples
/// (low nibble of bytes 0/1), modulator total-level attenuation (byte 2, 0..63)
/// and feedback (bits 1..3 of byte 10).
List<int> _patch({
  required int modMult,
  required int carMult,
  int modTotalLevel = 0,
  int feedback = 0,
}) {
  final d = List<int>.filled(12, 0);
  d[0] = modMult & 0x0F;
  d[1] = carMult & 0x0F;
  d[2] = modTotalLevel & 0x3F;
  d[10] = (feedback & 0x07) << 1;
  return d;
}

/// Magnitude of DFT bin [k] (k cycles across the whole buffer).
double _dftMag(Float64List w, int k) {
  var re = 0.0, im = 0.0;
  final n = w.length;
  for (var i = 0; i < n; i++) {
    final a = 2 * math.pi * k * i / n;
    re += w[i] * math.cos(a);
    im -= w[i] * math.sin(a);
  }
  return math.sqrt(re * re + im * im);
}

/// The bin (1..[maxBin]) with the largest DFT magnitude — the dominant pitch.
int _dominantBin(Float64List w, {int maxBin = 48}) {
  var best = 1;
  var bestMag = -1.0;
  for (var k = 1; k <= maxBin; k++) {
    final m = _dftMag(w, k);
    if (m > bestMag) {
      bestMag = m;
      best = k;
    }
  }
  return best;
}

/// A 0x50-byte type-2 (AdLib) instrument header with [opl] at 0x10..0x1B.
List<int> _adlibHeader(List<int> opl) {
  final h = List<int>.filled(0x50, 0);
  h[0x00] = 2; // type = AdLib
  for (var i = 0; i < opl.length && i < 12; i++) {
    h[0x10 + i] = opl[i] & 0xFF;
  }
  h[0x1C] = 48; // volume
  h[0x4C] = 0x53; // "SCRS"
  h[0x4D] = 0x43;
  h[0x4E] = 0x52;
  h[0x4F] = 0x53;
  return h;
}

S3mModule _module(S3mSample sample) => S3mModule(
      title: 'ADLIB',
      channelCount: 1,
      order: const [0],
      samples: [sample],
      patterns: [
        S3mPattern(
          List.generate(
            64,
            (_) => List<S3mCell>.filled(1, S3mCell.empty),
            growable: false,
          ),
        ),
      ],
    );

void main() {
  group('synthesizeAdlibWaveform', () {
    test(
        'a representative patch yields a normalized, non-silent, finite, '
        'loopable waveform', () {
      final w = synthesizeAdlibWaveform(
        _patch(modMult: 1, carMult: 2, modTotalLevel: 4, feedback: 3),
      );
      expect(w, isNotEmpty);
      expect(w.length, 2048);
      // Finite and within [-1, 1].
      expect(w.every((v) => v.isFinite && v.abs() <= 1.0 + 1e-9), isTrue);
      // Normalized: the peak magnitude reaches 1.
      final peak = w.map((v) => v.abs()).reduce(math.max);
      expect(peak, closeTo(1.0, 1e-9));
      // Non-silent: real signal energy present.
      final rms = math.sqrt(
        w.map((v) => v * v).reduce((a, b) => a + b) / w.length,
      );
      expect(rms, greaterThan(0.1));
      // Loopable: the endpoints meet without a large step discontinuity.
      expect((w.first - w.last).abs(), lessThan(0.2));
    });

    test('honours the requested frame count', () {
      final w =
          synthesizeAdlibWaveform(_patch(modMult: 1, carMult: 1), samples: 512);
      expect(w.length, 512);
    });

    test('dominant frequency reflects the carrier multiple', () {
      // Quiet modulator (high attenuation) → nearly pure carrier, so the DFT
      // peak lands squarely on the carrier bin (carrierMult × base cycles).
      final w2 = synthesizeAdlibWaveform(
        _patch(modMult: 1, carMult: 2, modTotalLevel: 60),
      );
      final w4 = synthesizeAdlibWaveform(
        _patch(modMult: 1, carMult: 4, modTotalLevel: 60),
      );
      expect(_dominantBin(w2), 2 * _baseCycles); // carMult 2 → bin 4
      expect(_dominantBin(w4), 4 * _baseCycles); // carMult 4 → bin 8
      // Doubling the carrier multiple doubles the dominant frequency.
      expect(_dominantBin(w4), 2 * _dominantBin(w2));
    });

    test('feedback stays bounded and finite', () {
      final w = synthesizeAdlibWaveform(
        _patch(modMult: 1, carMult: 1, feedback: 7),
      );
      expect(w, isNotEmpty);
      expect(w.every((v) => v.isFinite && v.abs() <= 1.0 + 1e-9), isTrue);
    });

    test('degenerate patches return an empty waveform (no garbage)', () {
      expect(synthesizeAdlibWaveform(const []), isEmpty);
      expect(synthesizeAdlibWaveform(List<int>.filled(12, 0)), isEmpty);
      expect(synthesizeAdlibWaveform(const [1, 2, 3]), isEmpty); // too short
      expect(
        synthesizeAdlibWaveform(_patch(modMult: 1, carMult: 1), samples: 0),
        isEmpty,
      );
    });
  });

  group('parseS3m end-to-end', () {
    test('an AdLib instrument comes back with a non-empty synth pcm', () {
      final opl = _patch(modMult: 1, carMult: 2, modTotalLevel: 8, feedback: 2);
      final sample = S3mSample(
        name: 'opl',
        volume: 48,
        pcm: Float64List(0),
        adlib: true,
        adlibData: opl,
        rawHeader: _adlibHeader(opl),
      );
      final parsed = parseS3m(writeS3m(_module(sample)));
      final s = parsed.samples.single;
      expect(s.adlib, isTrue);
      expect(s.adlibData, opl); // 12 OPL bytes preserved
      expect(s.pcm, isNotEmpty); // now audible
      expect(s.loop, isTrue);
      expect(s.loopStart, 0);
      expect(s.loopEnd, s.pcm.length);
      expect(s.pcm.every((v) => v.isFinite && v.abs() <= 1.0 + 1e-9), isTrue);
    });
  });
}
