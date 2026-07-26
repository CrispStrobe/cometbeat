// test/opl_voice_test.dart
//
// Unit tests for the DYNAMIC OPL2 2-operator voice ([OplInstrument] in
// opl_voice.dart) that replaces the static-PCM AdLib approximation for S3M
// type-2 instruments. These pin the DYNAMIC behaviour the static synth cannot
// reproduce: a real per-operator ADSR envelope (attack rise → decay to sustain →
// release after key-off), the four OPL2 waveform-select spectra, FM vs additive
// connection, key-scale/level attenuation, the import wiring (an S3M AdLib
// instrument becomes an OplInstrument and renders non-silent through
// songFromModuleBytes), and a safe degenerate patch.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/opl_voice_test.dart

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/opl_voice.dart';
import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/mod/s3m_writer.dart';
import 'package:comet_beat/core/audio/synth.dart'
    show kSampleRate, midiToFrequency;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a 12-byte S3M AdLib register block from operator fields.
List<int> _patch({
  int modMult = 1,
  int carMult = 1,
  int modTL = 63, // silence the modulator by default (carrier-only)
  int carTL = 0,
  int modAR = 15,
  int modDR = 15,
  int modSL = 0,
  int modRR = 15,
  int carAR = 15,
  int carDR = 15,
  int carSL = 0,
  int carRR = 15,
  bool modSustaining = true,
  bool carSustaining = true,
  int modWave = 0,
  int carWave = 0,
  int feedback = 0,
  int connection = 0,
  int carKsl = 0,
}) {
  int reg20(int mult, bool sustaining) =>
      (mult & 0x0F) | (sustaining ? 0x20 : 0);
  final d = List<int>.filled(12, 0);
  d[0] = reg20(modMult, modSustaining);
  d[1] = reg20(carMult, carSustaining);
  d[2] = modTL & 0x3F;
  d[3] = ((carKsl & 0x03) << 6) | (carTL & 0x3F);
  d[4] = (modAR << 4) | modDR;
  d[5] = (carAR << 4) | carDR;
  d[6] = (modSL << 4) | modRR;
  d[7] = (carSL << 4) | carRR;
  d[8] = modWave & 0x07;
  d[9] = carWave & 0x07;
  d[10] = ((feedback & 0x07) << 1) | (connection & 0x01);
  return d;
}

/// A note held for the first four rows (1s each at 60 BPM / 1 step-per-beat),
/// then a Note Cut, then rung out — an 8-second key-on/key-off/release run.
const _timing = TrackerTiming(tempoBpm: 60, rows: 8, stepsPerBeat: 1);
List<TrackerCell> _noteCells() => <TrackerCell>[
      const TrackerCell(midi: 60),
      TrackerCell.empty,
      TrackerCell.empty,
      TrackerCell.empty,
      TrackerCell.noteCut, // key-off → release
      TrackerCell.empty,
      TrackerCell.empty,
      TrackerCell.empty,
    ];

Float64List _render(List<int> patch) =>
    OplInstrument('t', patch).renderChannel(_noteCells(), _timing);

double _rms(Float64List b, double startSec, double lenSec) {
  final start = (startSec * kSampleRate).round();
  final len = (lenSec * kSampleRate).round();
  var sum = 0.0;
  var n = 0;
  for (var i = start; i < start + len && i < b.length; i++) {
    sum += b[i] * b[i];
    n++;
  }
  return n == 0 ? 0 : math.sqrt(sum / n);
}

/// Windowed DFT magnitude (per sample) at [cyclesPerSample] over [lenSec] from
/// [startSec] — used to read a partial's strength in the sustain region.
double _dft(Float64List b, double startSec, double lenSec, double cps) {
  final start = (startSec * kSampleRate).round();
  final len = (lenSec * kSampleRate).round();
  var re = 0.0, im = 0.0;
  for (var i = 0; i < len; i++) {
    final a = 2 * math.pi * cps * i;
    re += b[start + i] * math.cos(a);
    im -= b[start + i] * math.sin(a);
  }
  return math.sqrt(re * re + im * im) / len;
}

({double minV, double maxV, double nearZero}) _windowStats(
  Float64List b,
  double startSec,
  double lenSec,
) {
  final start = (startSec * kSampleRate).round();
  final len = (lenSec * kSampleRate).round();
  var minV = 0.0, maxV = 0.0, nz = 0;
  for (var i = start; i < start + len && i < b.length; i++) {
    minV = math.min(minV, b[i]);
    maxV = math.max(maxV, b[i]);
    if (b[i].abs() < 0.02) nz++;
  }
  return (minV: minV, maxV: maxV, nearZero: nz / len);
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

void main() {
  group('operator/register model', () {
    test('decodes the 12-byte S3M AdLib block into operators', () {
      // modulator 0x20 = AM|VIB|EGT|KSR|mult3 ; carrier mult 2, sustaining.
      final d = List<int>.filled(12, 0);
      d[0] = 0x80 | 0x40 | 0x20 | 0x10 | 0x03; // AM VIB EGT KSR mult=3
      d[1] = 0x20 | 0x02; // EGT, mult=2
      d[2] = (0x02 << 6) | 20; // mod KSL=2 TL=20
      d[3] = 0x00; // car KSL=0 TL=0
      d[4] = (0x0A << 4) | 0x04; // mod AR=10 DR=4
      d[5] = (0x0F << 4) | 0x00; // car AR=15 DR=0
      d[6] = (0x06 << 4) | 0x03; // mod SL=6 RR=3
      d[7] = (0x08 << 4) | 0x05; // car SL=8 RR=5
      d[8] = 0x02; // mod waveform 2
      d[9] = 0x03; // car waveform 3
      d[10] = (0x05 << 1) | 0x01; // feedback 5, additive

      final p = OplPatch.fromS3m(d);
      expect(p.modulator.mult, 3);
      expect(p.modulator.tremolo, isTrue);
      expect(p.modulator.vibrato, isTrue);
      expect(p.modulator.sustaining, isTrue);
      expect(p.modulator.keyScaleRate, isTrue);
      expect(p.modulator.keyScaleLevel, 2);
      expect(p.modulator.totalLevel, 20);
      expect(p.modulator.attack, 10);
      expect(p.modulator.decay, 4);
      expect(p.modulator.sustainLevel, 6);
      expect(p.modulator.release, 3);
      expect(p.modulator.waveform, 2);

      expect(p.carrier.mult, 2);
      expect(p.carrier.tremolo, isFalse);
      expect(p.carrier.attack, 15);
      expect(p.carrier.sustainLevel, 8);
      expect(p.carrier.release, 5);
      expect(p.carrier.waveform, 3);

      expect(p.feedback, 5);
      expect(p.connection, 1);
    });
  });

  group('(a) ADSR envelope', () {
    test(
        'attack rises, decays to a sustain plateau, then releases after '
        'key-off', () {
      // Slow attack (AR=4) so the rise spans measurable time; a gentle decay to
      // a sustain level well below the attack peak (SL=6); slow release (RR=4).
      final b = _render(
        _patch(carAR: 4, carDR: 3, carSL: 6, carRR: 4, connection: 1),
      );
      expect(b.every((v) => v.isFinite), isTrue);

      // Attack takes real time: the peak is not at the very first sample.
      var peakIdx = 0;
      var peakVal = 0.0;
      for (var i = 0; i < b.length; i++) {
        if (b[i].abs() > peakVal) {
          peakVal = b[i].abs();
          peakIdx = i;
        }
      }
      expect(
        peakIdx,
        greaterThan((0.02 * kSampleRate).round()),
        reason: 'attack should ramp up, not jump instantly',
      );

      final early = _rms(b, 0.0, 0.04); // during the attack ramp
      final peak = _rms(b, 0.46, 0.04); // near the attack peak
      final sustain = _rms(b, 2.4, 0.1); // held plateau, key still on
      final sustain2 = _rms(b, 3.0, 0.1); // still held
      final release = _rms(b, 4.3, 0.1); // ~0.3s after key-off

      // Attack: energy rises from the onset toward the peak.
      expect(
        early,
        lessThan(peak * 0.6),
        reason: 'attack rises: $early < $peak',
      );
      // Decay: the peak falls back to the lower sustain plateau.
      expect(
        sustain,
        lessThan(peak * 0.5),
        reason: 'decays to sustain: $sustain < $peak',
      );
      // Sustain: a genuine plateau while the key is held.
      expect(
        (sustain - sustain2).abs(),
        lessThan(sustain * 0.25),
        reason: 'sustain plateau: $sustain ~ $sustain2',
      );
      // Release: decays after key-off, well below the sustain level.
      expect(
        release,
        lessThan(sustain * 0.5),
        reason: 'releases after key-off: $release < $sustain',
      );
    });
  });

  group('(b) waveform-select spectra', () {
    // Carrier-only (silence the modulator) so the sustain window is essentially
    // the raw carrier waveform.
    Float64List carrier(int wave) =>
        _render(_patch(carWave: wave, connection: 1));
    final cps = midiToFrequency(60) / kSampleRate;

    test('full sine (0): symmetric bipolar, strong fundamental', () {
      final b = carrier(0);
      final s = _windowStats(b, 1.0, 0.1);
      expect(s.minV, lessThan(-0.5)); // swings negative
      expect(s.nearZero, lessThan(0.1)); // few zero crossings
      final f1 = _dft(b, 1.0, 0.1, cps);
      final f2 = _dft(b, 1.0, 0.1, cps * 2);
      expect(f1, greaterThan(f2 * 5)); // fundamental dominates
    });

    test('half sine (1): non-negative with a zeroed half', () {
      final b = carrier(1);
      final s = _windowStats(b, 1.0, 0.1);
      expect(s.minV, greaterThan(-0.02)); // never meaningfully negative
      expect(s.nearZero, closeTo(0.5, 0.12)); // half the period silent
    });

    test('absolute sine (2): non-negative, 2nd harmonic dominates', () {
      final b = carrier(2);
      final s = _windowStats(b, 1.0, 0.1);
      expect(s.minV, greaterThan(-0.02));
      expect(s.nearZero, lessThan(0.12)); // only touches zero at crossings
      final f1 = _dft(b, 1.0, 0.1, cps);
      final f2 = _dft(b, 1.0, 0.1, cps * 2);
      // Full-wave rectification pushes energy to twice the fundamental.
      expect(f2, greaterThan(f1 * 5));
    });

    test('quarter/pulse sine (3): non-negative, pulsed', () {
      final b = carrier(3);
      final s = _windowStats(b, 1.0, 0.1);
      expect(s.minV, greaterThan(-0.02));
      expect(s.nearZero, closeTo(0.5, 0.12));
    });

    test('the four waveforms are mutually distinct', () {
      final w = [for (var i = 0; i < 4; i++) carrier(i)];
      final start = (1.0 * kSampleRate).round();
      final len = (0.1 * kSampleRate).round();
      double diff(Float64List a, Float64List b) {
        var m = 0.0;
        for (var i = start; i < start + len; i++) {
          m = math.max(m, (a[i] - b[i]).abs());
        }
        return m;
      }

      for (var i = 0; i < 4; i++) {
        for (var j = i + 1; j < 4; j++) {
          expect(
            diff(w[i], w[j]),
            greaterThan(0.1),
            reason: 'waveform $i vs $j should differ',
          );
        }
      }
    });
  });

  group('(c) connection topology', () {
    test('FM (0) and additive (1) produce different waveforms', () {
      final fm = _render(_patch(carMult: 2, modTL: 4));
      final add = _render(_patch(carMult: 2, modTL: 4, connection: 1));
      expect(fm.every((v) => v.isFinite), isTrue);
      expect(add.every((v) => v.isFinite), isTrue);
      final start = (1.0 * kSampleRate).round();
      final end = (1.5 * kSampleRate).round();
      var maxDiff = 0.0;
      for (var i = start; i < end; i++) {
        maxDiff = math.max(maxDiff, (fm[i] - add[i]).abs());
      }
      expect(maxDiff, greaterThan(0.3));
    });
  });

  group('(d) key-scale / level attenuation', () {
    test('a higher total-level attenuates the output', () {
      final loud = _render(_patch(connection: 1)); // carTL 0 (default)
      final quiet = _render(_patch(carTL: 24, connection: 1));
      final loudRms = _rms(loud, 1.0, 0.1);
      final quietRms = _rms(quiet, 1.0, 0.1);
      // TL 24 = 18 dB of attenuation → ~0.126×.
      expect(quietRms, lessThan(loudRms * 0.3));
      expect(quietRms, greaterThan(0.0));
    });

    test('key-scale-level attenuates higher notes more', () {
      // KSL=3 (6 dB/oct): a note two octaves up is markedly quieter.
      final patch = _patch(carKsl: 3, connection: 1);
      final inst = OplInstrument('ksl', patch);
      Float64List one(int midi) => inst.renderChannel(
            <TrackerCell>[
              TrackerCell(midi: midi),
              TrackerCell.empty,
              TrackerCell.empty,
              TrackerCell.empty,
            ],
            const TrackerTiming(tempoBpm: 60, rows: 4, stepsPerBeat: 1),
          );
      final low = _rms(one(48), 0.5, 0.1);
      final high = _rms(one(72), 0.5, 0.1);
      expect(high, lessThan(low));
    });
  });

  group('(e) S3M AdLib import', () {
    test('an AdLib instrument imports as an OplInstrument and renders sound',
        () {
      final opl = List<int>.filled(12, 0);
      opl[0] = 0x21; // mod: EGT sustaining, mult 1
      opl[1] = 0x21; // car: EGT sustaining, mult 1
      opl[2] = 0x3F; // silence the modulator
      opl[4] = 0xF0; // mod AR=15
      opl[5] = 0xF0; // car AR=15
      opl[10] = 0x01; // additive

      final sample = S3mSample(
        name: 'opl',
        volume: 48,
        pcm: Float64List(0),
        adlib: true,
        adlibData: opl,
        rawHeader: _adlibHeader(opl),
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
      expect(song.instruments.first, isA<OplInstrument>());

      final wav = song.renderSongWav();
      var nonZero = 0;
      for (var i = 44; i < wav.length; i++) {
        if (wav[i] != 0) nonZero++;
      }
      expect(
        nonZero,
        greaterThan(0),
        reason: 'the OPL voice should be audible',
      );
    });
  });

  group('(f) degenerate patch', () {
    test('an all-zero patch is silent and finite (no NaN)', () {
      final inst = OplInstrument('blank', List<int>.filled(12, 0));
      expect(inst.isBlank, isTrue);
      final b = inst.renderChannel(_noteCells(), _timing);
      expect(b.every((v) => v == 0.0), isTrue);
    });

    test('a too-short block is treated as blank', () {
      final inst = OplInstrument('short', const [1, 2, 3]);
      expect(inst.isBlank, isTrue);
      final b = inst.renderChannel(_noteCells(), _timing);
      expect(b.every((v) => v == 0.0 && v.isFinite), isTrue);
    });

    test('an empty cell list renders silence without error', () {
      final inst = OplInstrument('x', _patch());
      final b = inst.renderChannel(
        List<TrackerCell>.filled(8, TrackerCell.empty),
        _timing,
      );
      expect(b.every((v) => v == 0.0), isTrue);
    });
  });
}
