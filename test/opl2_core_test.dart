// test/opl2_core_test.dart
//
// Unit tests for the YM3812 / OPL2 emulation core (opl2_core.dart): the
// log-sin / exp table identity, the attenuation-domain envelope generator
// (monotone attack → decay-to-sustain → release, faster rate → shorter time),
// KSL / total-level attenuation, a known patch rendering a non-silent, finite,
// bounded waveform with the expected fundamental, a degenerate patch staying
// safe, and the end-to-end S3M AdLib import playing through the core.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/opl2_core_test.dart

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/opl2_core.dart';
import 'package:comet_beat/core/audio/mod/opl_voice.dart';
import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/mod/s3m_writer.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs the envelope for [samples] native steps (keyed on for [keyOnSamples]),
/// returning the attenuation trace (0 = loud, 511 = silent).
List<double> _egTrace(
  OplEg eg,
  int samples, {
  required int keyOnSamples,
}) {
  final out = <double>[];
  for (var i = 0; i < samples; i++) {
    eg.advance(i < keyOnSamples);
    out.add(eg.atten);
  }
  return out;
}

OplEg _eg({
  int attack = 8,
  int decay = 6,
  int sustainLevel = 4,
  int release = 6,
  bool sustaining = true,
  bool ksr = false,
  int ksn = 8,
}) =>
    OplEg(
      attack: attack,
      decay: decay,
      sustainLevel: sustainLevel,
      release: release,
      keyScaleRate: ksr,
      sustaining: sustaining,
      keyScaleNumber: ksn,
    );

/// The first native-sample index at which [trace] reaches (>=) [value].
int _firstAtLeast(List<double> trace, double value) {
  for (var i = 0; i < trace.length; i++) {
    if (trace[i] >= value) return i;
  }
  return trace.length;
}

void main() {
  group('(a) log-sin / exp table identity', () {
    test('tables have the documented shapes and bounds', () {
      expect(oplLogSinTable.length, 256);
      expect(oplExpTable.length, 256);
      // log-sin is a non-negative, monotone-decreasing quarter-wave (sin rises
      // toward 1 → attenuation falls toward 0).
      expect(
        oplLogSinTable.first,
        greaterThan(2000),
      ); // sin≈0 → big attenuation
      expect(oplLogSinTable.last, lessThan(2)); // sin≈1 → ~0 attenuation
      for (var i = 1; i < 256; i++) {
        expect(oplLogSinTable[i], lessThanOrEqualTo(oplLogSinTable[i - 1]));
      }
      // exp table: round((2^(i/256)-1)*1024), 0 .. ~1018.
      expect(oplExpTable.first, 0);
      expect(oplExpTable.last, inInclusiveRange(1017, 1019));
    });

    test('reconstructs a full sine to a tolerance', () {
      // Walk a whole period (1024 phase steps) with zero added attenuation and
      // compare the reconstructed waveform-0 output to math.sin.
      var maxErr = 0.0;
      for (var p = 0; p < 1024; p++) {
        final got = oplWaveSample(0, p, 0);
        final want = math.sin((p + 0.5) * 2 * math.pi / 1024.0);
        maxErr = math.max(maxErr, (got - want).abs());
      }
      // The chip's own exp/log quantisation (~0.3%) bounds the error.
      expect(maxErr, lessThan(0.02), reason: 'max sine error $maxErr');
    });

    test('exp halves per 256 attenuation units (one octave)', () {
      final full = oplExp(0);
      final half = oplExp(256);
      final quarter = oplExp(512);
      expect(full, closeTo(1.0, 0.01));
      expect(half / full, closeTo(0.5, 0.01));
      expect(quarter / full, closeTo(0.25, 0.01));
      // Large attenuation → silence, finite.
      expect(oplExp(9000), 0.0);
    });

    test('the four waveforms have the expected sign structure', () {
      // Sample each waveform across a period.
      double minOf(int ws) {
        var m = 0.0;
        for (var p = 0; p < 1024; p++) {
          m = math.min(m, oplWaveSample(ws, p, 0));
        }
        return m;
      }

      int nearZeroOf(int ws) {
        var n = 0;
        for (var p = 0; p < 1024; p++) {
          if (oplWaveSample(ws, p, 0).abs() < 0.02) n++;
        }
        return n;
      }

      expect(minOf(0), lessThan(-0.5)); // full sine: bipolar
      expect(minOf(1), greaterThan(-0.02)); // half sine: non-negative
      expect(minOf(2), greaterThan(-0.02)); // |sine|: non-negative
      expect(minOf(3), greaterThan(-0.02)); // quarter: non-negative
      // Half & quarter mute ~half the period; |sine| almost never zero.
      expect(nearZeroOf(1), greaterThan(400));
      expect(nearZeroOf(2), lessThan(120));
      expect(nearZeroOf(3), greaterThan(400));
    });
  });

  group('(b) envelope generator', () {
    test('attack falls monotonically to full volume', () {
      final eg = _eg(attack: 10, decay: 0, sustainLevel: 0);
      var prev = 511.0;
      var reachedFull = false;
      for (var i = 0; i < 20000; i++) {
        eg.advance(true);
        expect(
          eg.atten,
          lessThanOrEqualTo(prev + 1e-9),
          reason: 'attack must not increase attenuation',
        );
        prev = eg.atten;
        if (eg.atten <= 0.5) {
          reachedFull = true;
          break;
        }
      }
      expect(reachedFull, isTrue, reason: 'attack should reach full volume');
    });

    test('attack → decay-to-sustain → release, in order', () {
      // Fast attack, moderate decay to a mid sustain, moderate release.
      final eg = _eg(attack: 15, decay: 8, sustainLevel: 6, release: 8);
      const sustainAtten = 6 * 16.0; // SL=6 → 96 EG units
      final trace = _egTrace(eg, 60000, keyOnSamples: 40000);

      // Attack completes near the start (atten hits ~0).
      final attackEnd = _firstAtLeast(
        [for (final v in trace) 511.0 - v], // invert so "reach" = atten→0
        511.0 - 0.5,
      );
      expect(attackEnd, lessThan(2000), reason: 'fast attack completes early');

      // Decay climbs to the sustain plateau while keyed on.
      final held = trace[35000];
      expect(
        held,
        closeTo(sustainAtten, 2.0),
        reason: 'holds at the sustain level',
      );

      // Release (after key-off at 40000) climbs further toward silence.
      expect(
        trace[45000],
        greaterThan(held),
        reason: 'release increases attenuation past sustain',
      );
      expect(trace.last, closeTo(511.0, 1.0), reason: 'ends silent');
    });

    test('faster decay rate reaches sustain in less time', () {
      int decayTime(int rate) {
        final eg = _eg(attack: 15, decay: rate, sustainLevel: 8, release: 0);
        final trace = _egTrace(eg, 300000, keyOnSamples: 300000);
        return _firstAtLeast(trace, 8 * 16.0 - 1.0);
      }

      final slow = decayTime(3);
      final fast = decayTime(9);
      expect(
        fast,
        lessThan(slow),
        reason: 'faster rate → shorter decay ($fast < $slow)',
      );
    });

    test('key-scale rate makes a higher note decay faster', () {
      int decayTime(int ksn) {
        final eg = _eg(
          attack: 15,
          sustainLevel: 10,
          release: 0,
          ksr: true,
          ksn: ksn,
        );
        final trace = _egTrace(eg, 400000, keyOnSamples: 400000);
        return _firstAtLeast(trace, 10 * 16.0 - 1.0);
      }

      expect(decayTime(15), lessThan(decayTime(1)));
    });

    test('a zero attack rate keeps the operator silent', () {
      final eg = _eg(attack: 0);
      expect(eg.done, isTrue);
      eg.advance(true);
      expect(eg.atten, 511.0);
    });

    test('percussive (EGT=0) keeps decaying past sustain', () {
      final eg = _eg(
        attack: 15,
        decay: 15,
        sustaining: false,
      );
      final trace = _egTrace(eg, 200000, keyOnSamples: 200000);
      // Even though the key stays on, it decays to silence (no sustain hold).
      expect(trace.last, closeTo(511.0, 1.0));
    });
  });

  group('(c) KSL / total-level attenuation', () {
    test('higher total level adds attenuation in the log domain', () {
      // KSL/TL enter as EG units; TL·4 for TL=0 vs TL=16 differ by 64 units.
      final loud = oplExp((0 + 0) << 3);
      final quiet = oplExp((0 + 16 * 4) << 3);
      expect(quiet, lessThan(loud));
      // TL 16 = 12 dB ≈ 0.25×.
      expect(quiet / loud, closeTo(0.25, 0.05));
    });

    test('KSL attenuates higher blocks more, disabled at field 0', () {
      // Field 0 = KSL off everywhere.
      for (var block = 0; block < 8; block++) {
        expect(oplKslAttenuation(block, 512, 0), 0);
      }
      // Field 3 (steepest): attenuation grows with block.
      final low = oplKslAttenuation(2, 512, 3);
      final high = oplKslAttenuation(6, 512, 3);
      expect(high, greaterThan(low));
      // The famous field-order swap: field 1 (3 dB/oct) > field 2 (1.5 dB/oct).
      expect(
        oplKslAttenuation(7, 1023, 1),
        greaterThan(oplKslAttenuation(7, 1023, 2)),
      );
    });
  });

  group('(d) voice render', () {
    // A carrier-only patch (silent modulator via max TL) at ~440 Hz.
    Opl2Voice voice({
      int carWave = 0,
      int carTL = 0,
      double freq = 440.0,
      int feedback = 0,
      bool additive = false,
    }) =>
        Opl2Voice(
          frequencyHz: freq,
          nativeRate: kOplSampleRate,
          modMult: 1,
          modWaveform: 0,
          modTotalLevel: 63, // silence the modulator
          modKsl: 0,
          modAttack: 15,
          modDecay: 0,
          modSustainLevel: 0,
          modRelease: 15,
          modKsr: false,
          modSustaining: true,
          modTremolo: false,
          modVibrato: false,
          carMult: 1,
          carWaveform: carWave,
          carTotalLevel: carTL,
          carKsl: 0,
          carAttack: 15,
          carDecay: 0,
          carSustainLevel: 0,
          carRelease: 15,
          carKsr: false,
          carSustaining: true,
          carTremolo: false,
          carVibrato: false,
          feedback: feedback,
          additive: additive,
        );

    Float64List render(Opl2Voice v, int n) {
      final b = Float64List(n);
      for (var i = 0; i < n; i++) {
        b[i] = v.nextNative(true);
      }
      return b;
    }

    test('a known patch is non-silent, finite, bounded', () {
      final b = render(voice(), 8192);
      expect(b.every((v) => v.isFinite && v.abs() <= 1.001), isTrue);
      final rms =
          math.sqrt(b.map((v) => v * v).reduce((a, c) => a + c) / b.length);
      expect(rms, greaterThan(0.1));
      final peak = b.map((v) => v.abs()).reduce(math.max);
      expect(peak, greaterThan(0.5));
    });

    test('the fundamental lands at the played frequency', () {
      const freq = 440.0;
      final b = render(voice(), 16384);
      // DFT magnitude at k cycles/sample.
      double dft(double cps) {
        var re = 0.0, im = 0.0;
        for (var i = 0; i < b.length; i++) {
          final a = 2 * math.pi * cps * i;
          re += b[i] * math.cos(a);
          im -= b[i] * math.sin(a);
        }
        return math.sqrt(re * re + im * im) / b.length;
      }

      const f0 = freq / kOplSampleRate;
      final f1 = dft(f0);
      final f2 = dft(f0 * 2);
      final half = dft(f0 * 0.5);
      expect(f1, greaterThan(f2 * 4), reason: 'fundamental dominates 2nd');
      expect(
        f1,
        greaterThan(half * 4),
        reason: 'fundamental dominates subharm',
      );
    });

    test('higher total level attenuates the rendered voice', () {
      double rms(Opl2Voice v) {
        final b = render(v, 8192);
        return math
            .sqrt(b.map((x) => x * x).reduce((a, c) => a + c) / b.length);
      }

      final loud = rms(voice());
      final quiet = rms(voice(carTL: 24)); // 18 dB down ≈ 0.126×
      expect(quiet, lessThan(loud * 0.3));
      expect(quiet, greaterThan(0.0));
    });

    test('feedback and additive stay finite and bounded', () {
      for (final add in [false, true]) {
        final b = render(voice(feedback: 7, additive: add), 8192);
        expect(
          b.every((v) => v.isFinite && v.abs() <= 1.001),
          isTrue,
          reason: 'additive=$add',
        );
      }
    });

    test('a degenerate (all-min) voice is safe and finite', () {
      final v = Opl2Voice(
        frequencyHz: 440.0,
        nativeRate: kOplSampleRate,
        modMult: 0,
        modWaveform: 0,
        modTotalLevel: 63,
        modKsl: 0,
        modAttack: 0,
        modDecay: 0,
        modSustainLevel: 15,
        modRelease: 0,
        modKsr: false,
        modSustaining: false,
        modTremolo: false,
        modVibrato: false,
        carMult: 0,
        carWaveform: 0,
        carTotalLevel: 63,
        carKsl: 0,
        carAttack: 0,
        carDecay: 0,
        carSustainLevel: 15,
        carRelease: 0,
        carKsr: false,
        carSustaining: false,
        carTremolo: false,
        carVibrato: false,
        feedback: 0,
        additive: false,
      );
      final b = render(v, 1024);
      expect(b.every((x) => x.isFinite && x.abs() < 0.05), isTrue);
      expect(v.done, isTrue);
    });
  });

  group('(e) S3M AdLib import plays through the OPL2 core', () {
    test('an AdLib instrument imports as an OplInstrument and renders sound',
        () {
      final opl = List<int>.filled(12, 0);
      opl[0] = 0x21; // mod: EGT sustaining, mult 1
      opl[1] = 0x21; // car: EGT sustaining, mult 1
      opl[2] = 0x3F; // silence the modulator
      opl[4] = 0xF0; // mod AR=15
      opl[5] = 0xF0; // car AR=15
      opl[10] = 0x01; // additive

      final header = List<int>.filled(0x50, 0);
      header[0x00] = 2; // type = AdLib
      for (var i = 0; i < 12; i++) {
        header[0x10 + i] = opl[i];
      }
      header[0x1C] = 48; // volume
      header[0x4C] = 0x53; // "SCRS"
      header[0x4D] = 0x43;
      header[0x4E] = 0x52;
      header[0x4F] = 0x53;

      final sample = S3mSample(
        name: 'opl',
        volume: 48,
        pcm: Float64List(0),
        adlib: true,
        adlibData: opl,
        rawHeader: header,
      );
      final rows = List.generate(
        64,
        (r) => <S3mCell>[
          r == 0 ? const S3mCell(note: 0x50, instrument: 1) : S3mCell.empty,
        ],
        growable: false,
      );
      final module = S3mModule(
        title: 'ADLIB',
        channelCount: 1,
        order: const [0],
        samples: [sample],
        patterns: [S3mPattern(rows)],
      );

      final song = songFromModuleBytes(writeS3m(module));
      expect(song.channels.first.instrument, isA<OplInstrument>());

      final wav = song.renderSongWav();
      var nonZero = 0;
      for (var i = 44; i < wav.length; i++) {
        if (wav[i] != 0) nonZero++;
      }
      expect(
        nonZero,
        greaterThan(0),
        reason: 'the OPL2 voice should be audible',
      );
    });
  });
}
