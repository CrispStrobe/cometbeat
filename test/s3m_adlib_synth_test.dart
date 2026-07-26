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
/// (low nibble of bytes 0/1), modulator total-level attenuation (byte 2, 0..63),
/// modulator/carrier waveform-select (low 2 bits of bytes 8/9), connection
/// (bit 0 of byte 10) and feedback (bits 1..3 of byte 10).
List<int> _patch({
  required int modMult,
  required int carMult,
  int modTotalLevel = 0,
  int feedback = 0,
  int modWave = 0,
  int carWave = 0,
  int connection = 0,
}) {
  final d = List<int>.filled(12, 0);
  d[0] = modMult & 0x0F;
  d[1] = carMult & 0x0F;
  d[2] = modTotalLevel & 0x3F;
  d[8] = modWave & 0x03;
  d[9] = carWave & 0x03;
  d[10] = ((feedback & 0x07) << 1) | (connection & 0x01);
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

/// Fraction of samples whose magnitude is below [eps] (≈ the "zeroed" portion).
double _fracNearZero(Float64List w, {double eps = 0.02}) {
  var n = 0;
  for (final v in w) {
    if (v.abs() < eps) n++;
  }
  return n / w.length;
}

/// The smallest (most negative) sample value.
double _minVal(Float64List w) => w.reduce(math.min);

/// Length of the longest run of consecutive samples with magnitude >= [eps].
int _maxNonZeroRun(Float64List w, {double eps = 0.02}) {
  var best = 0, cur = 0;
  for (final v in w) {
    if (v.abs() >= eps) {
      cur++;
      if (cur > best) best = cur;
    } else {
      cur = 0;
    }
  }
  return best;
}

/// Largest element-wise magnitude difference between two equal-length buffers.
double _maxAbsDiff(Float64List a, Float64List b) {
  var m = 0.0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > m) m = d;
  }
  return m;
}

/// A near-pure carrier of the given waveform: silence the modulator (max
/// attenuation) in FM mode so the output is essentially the carrier shape.
Float64List _carrierOnly(int carWave) => synthesizeAdlibWaveform(
      _patch(modMult: 1, carMult: 1, modTotalLevel: 63, carWave: carWave),
    );

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

  group('OPL2 waveform-select (bytes 8/9)', () {
    test('full sine (0) is a symmetric bipolar carrier', () {
      final w = _carrierOnly(0);
      expect(w, isNotEmpty);
      // A sine swings well negative and positive.
      expect(_minVal(w), lessThan(-0.5));
      // Few samples are near zero (only the crossings).
      expect(_fracNearZero(w), lessThan(0.1));
    });

    test(
        'half sine (1) zeroes the negative half → non-negative with a '
        'contiguous silent half', () {
      final w = _carrierOnly(1);
      expect(w, isNotEmpty);
      // Never meaningfully negative.
      expect(_minVal(w), greaterThan(-0.02));
      // Roughly half the period is the zeroed negative half.
      expect(_fracNearZero(w), closeTo(0.5, 0.1));
    });

    test('absolute sine (2) is non-negative with (almost) no zeroed span', () {
      final w = _carrierOnly(2);
      expect(w, isNotEmpty);
      expect(_minVal(w), greaterThan(-0.02));
      // |sin| only touches zero at the crossings, so very little is near-zero.
      expect(_fracNearZero(w), lessThan(0.12));
    });

    test(
        'quarter/pulse sine (3) is non-negative and pulses twice as often as '
        'the half-sine (shorter nonzero runs)', () {
      final wQuarter = _carrierOnly(3);
      final wHalf = _carrierOnly(1);
      expect(wQuarter, isNotEmpty);
      // Non-negative like the other rectified shapes.
      expect(_minVal(wQuarter), greaterThan(-0.02));
      // About half the period is zeroed (the falling quarter of each hump).
      expect(_fracNearZero(wQuarter), closeTo(0.5, 0.12));
      // Two rising-quarter pulses per base cycle vs the half-sine's single
      // hump → the longest nonzero run is roughly half as long.
      final runQuarter = _maxNonZeroRun(wQuarter);
      final runHalf = _maxNonZeroRun(wHalf);
      expect(runQuarter, lessThan(runHalf * 0.75));
      expect(runQuarter, greaterThan(runHalf * 0.25));
    });

    test('the modulator waveform-select changes the FM timbre', () {
      // Loud modulator, FM mode: swapping the modulator shape (sine vs abs-sine)
      // changes the modulating signal and hence the rendered waveform.
      final wSineMod = synthesizeAdlibWaveform(
        _patch(modMult: 1, carMult: 2),
      );
      final wAbsMod = synthesizeAdlibWaveform(
        _patch(modMult: 1, carMult: 2, modWave: 2),
      );
      expect(wSineMod.length, wAbsMod.length);
      expect(_maxAbsDiff(wSineMod, wAbsMod), greaterThan(0.1));
    });
  });

  group('connection topology (byte 10, bit 0)', () {
    test('additive (connection=1) differs from FM (connection=0)', () {
      final fm = synthesizeAdlibWaveform(
        _patch(modMult: 1, carMult: 2, modTotalLevel: 4),
      );
      final additive = synthesizeAdlibWaveform(
        _patch(modMult: 1, carMult: 2, modTotalLevel: 4, connection: 1),
      );
      expect(fm, isNotEmpty);
      expect(additive, isNotEmpty);
      expect(fm.length, additive.length);
      // The two topologies produce audibly different waveforms.
      expect(_maxAbsDiff(fm, additive), greaterThan(0.3));
    });

    test('additive mode exposes the modulator frequency as a real partial', () {
      // In additive mode the modulator sounds directly, so its bin (modMult ×
      // base cycles) carries real energy alongside the carrier bin.
      final additive = synthesizeAdlibWaveform(
        _patch(modMult: 1, carMult: 3, connection: 1),
      );
      const modBin = 1 * _baseCycles; // modMult 1 → bin 2
      const carBin = 3 * _baseCycles; // carMult 3 → bin 6
      expect(_dftMag(additive, modBin), greaterThan(0.0));
      expect(_dftMag(additive, carBin), greaterThan(0.0));
    });

    test('additive and FM alike stay finite, normalized and loopable', () {
      for (final conn in [0, 1]) {
        final w = synthesizeAdlibWaveform(
          _patch(
            modMult: 2,
            carMult: 1,
            modTotalLevel: 6,
            feedback: 2,
            modWave: 1,
            carWave: 2,
            connection: conn,
          ),
        );
        expect(w, isNotEmpty, reason: 'connection=$conn');
        expect(
          w.every((v) => v.isFinite && v.abs() <= 1.0 + 1e-9),
          isTrue,
          reason: 'connection=$conn',
        );
        final peak = w.map((v) => v.abs()).reduce(math.max);
        expect(peak, closeTo(1.0, 1e-9), reason: 'connection=$conn');
        expect(
          (w.first - w.last).abs(),
          lessThan(0.2),
          reason: 'connection=$conn loop',
        );
      }
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
