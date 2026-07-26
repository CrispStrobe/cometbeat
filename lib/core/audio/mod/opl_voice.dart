// lib/core/audio/mod/opl_voice.dart
//
// The S3M AdLib (type-2) instrument [OplInstrument]: it decodes the 12-byte OPL
// register block into an [OplPatch] (this file) and renders each note through
// the YM3812 / OPL2 chip-emulation core in opl2_core.dart ([Opl2Voice]) — a
// log-sin/exp sine reconstruction, a fixed-point phase generator, an
// attenuation-domain envelope generator with key-scale rate/level, feedback,
// FM (connection 0) / additive (connection 1) mixing and AM/VIB LFOs. The core
// runs at the native OPL rate (~49716 Hz); this file resamples each note to
// [kSampleRate]. It is the successor to the STATIC single-period approximation
// in s3m_reader.dart ([synthesizeAdlibWaveform], retained there as a preview /
// re-export fallback) and to the earlier faithful-FLOAT one-pole voice that
// lived entirely here (now superseded by the chip core).
//
// ── The 12-byte S3M AdLib patch → OPL register mapping ──────────────────────
// The block lives at instrument-header 0x10..0x1B (see s3m_reader.dart). It is
// SBI-style: modulator byte then carrier byte for each register pair.
//
//   byte  OPL reg        operator   fields (bit 7 … bit 0)
//   ────  ─────────────  ─────────  ─────────────────────────────────────────
//    0    0x20 modulator modulator  AM VIB EGT KSR | MULT(4)
//    1    0x23 carrier   carrier    AM VIB EGT KSR | MULT(4)
//    2    0x40 modulator modulator  KSL(2) | TL(6)          (TL 0=loud..63=off)
//    3    0x43 carrier   carrier    KSL(2) | TL(6)
//    4    0x60 modulator modulator  AR(4) | DR(4)
//    5    0x63 carrier   carrier    AR(4) | DR(4)
//    6    0x80 modulator modulator  SL(4) | RR(4)
//    7    0x83 carrier   carrier    SL(4) | RR(4)
//    8    0xE0 modulator modulator  ---- | WS(3)   (OPL2 uses the low 2 bits)
//    9    0xE3 carrier   carrier    ---- | WS(3)
//   10    0xC0           (shared)   ---- | FB(3) CNT(1)      (CNT 0=FM,1=add)
//   11    reserved / unused
//
//   AM  bit 7 of 0x20 — tremolo (amplitude LFO) enable
//   VIB bit 6 of 0x20 — vibrato (pitch LFO) enable
//   EGT bit 5 of 0x20 — envelope type: 1 = sustaining, 0 = percussive/decaying
//   KSR bit 4 of 0x20 — key-scale rate: envelope rates rise with the played note
//   MULT       0x20   — frequency multiple (see [_multTable])
//   KSL        0x40   — key-scale level: higher notes are attenuated
//   TL         0x40   — total level, this operator's static output attenuation
//   AR/DR      0x60   — attack / decay rate (0 = slowest / none, 15 = fastest)
//   SL/RR      0x80   — sustain level / release rate
//   WS         0xE0   — waveform select (0 sine, 1 half, 2 abs, 3 quarter)
//   FB/CNT     0xC0   — modulator self-feedback depth / carrier connection
//
// ── Synthesis model ─────────────────────────────────────────────────────────
// The actual chip model — the log-sin/exp tables, the phase generator, the
// attenuation-domain envelope generator with KSR/KSL, feedback, connection and
// the AM/VIB LFOs — lives in opl2_core.dart; see that file's header for the
// algorithm and its honest residual (algorithm-faithful, NOT reference-verified
// bit-exact; OPL3 4-op/waveforms 4–7 and rhythm mode are out of scope).
//
// Flutter-free and allocation-lean: the OPL2 tables are computed once at load,
// and each note builds one small [Opl2Voice] whose sample loop allocates
// nothing (it resamples native→output in place). It drops onto the same
// [TrackerInstrument] seam as the sampled / procedural voices and streams under
// the row-chunk renderer. Like the other per-note procedural voices
// ([FmInstrument] etc.) each note is self-contained: OPL operator/envelope state
// is NOT threaded across a streamer chunk boundary (a note re-attacks at a chunk
// edge) — the same documented trade-off those voices make.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/opl2_core.dart'
    show Opl2Voice, kOplSampleRate;
import 'package:comet_beat/core/audio/synth.dart'
    show kSampleRate, midiToFrequency;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerCell, TrackerInstrument, TrackerTiming, noteRuns;

/// OPL frequency-multiplication factor per the 4-bit `MULT` field. Index 11/13
/// alias 10/12; 14/15 both mean 15.
const List<double> _multTable = <double>[
  0.5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 12, 12, 15, 15, //
];

/// One OPL operator's decoded register state (modulator or carrier).
class OplOperator {
  const OplOperator({
    required this.mult,
    required this.keyScaleRate,
    required this.sustaining,
    required this.vibrato,
    required this.tremolo,
    required this.keyScaleLevel,
    required this.totalLevel,
    required this.attack,
    required this.decay,
    required this.sustainLevel,
    required this.release,
    required this.waveform,
  });

  /// Decodes the four OPL register bytes for one operator (0x20, 0x40, 0x60,
  /// 0x80) plus its waveform-select byte (0xE0).
  factory OplOperator.fromRegisters(
    int reg20,
    int reg40,
    int reg60,
    int reg80,
    int regE0,
  ) =>
      OplOperator(
        mult: reg20 & 0x0F,
        keyScaleRate: (reg20 & 0x10) != 0,
        sustaining: (reg20 & 0x20) != 0,
        vibrato: (reg20 & 0x40) != 0,
        tremolo: (reg20 & 0x80) != 0,
        keyScaleLevel: (reg40 >> 6) & 0x03,
        totalLevel: reg40 & 0x3F,
        attack: (reg60 >> 4) & 0x0F,
        decay: reg60 & 0x0F,
        sustainLevel: (reg80 >> 4) & 0x0F,
        release: reg80 & 0x0F,
        waveform: regE0 & 0x07,
      );

  final int mult;
  final bool keyScaleRate;
  final bool sustaining; // EGT: true = hold at sustain, false = keep decaying
  final bool vibrato;
  final bool tremolo;
  final int keyScaleLevel; // KSL 0..3
  final int totalLevel; // TL 0..63 (0 = loudest)
  final int attack; // AR 0..15
  final int decay; // DR 0..15
  final int sustainLevel; // SL 0..15
  final int release; // RR 0..15
  final int waveform; // WS 0..7 (OPL2: low 2 bits)

  /// The OPL frequency multiple for this operator's `MULT` field (exposed for
  /// inspection; the synthesis core reads the raw [mult] field directly).
  double get multiple => _multTable[mult & 0x0F];
}

/// A decoded 2-operator OPL patch: modulator + carrier + how they connect.
class OplPatch {
  const OplPatch({
    required this.modulator,
    required this.carrier,
    required this.feedback,
    required this.connection,
  });

  /// Decodes the 12-byte S3M AdLib register block (header 0x10..0x1B). Bytes
  /// beyond what's present read as 0 so a short block is safe.
  factory OplPatch.fromS3m(List<int> data) {
    int at(int i) => (i >= 0 && i < data.length) ? data[i] & 0xFF : 0;
    return OplPatch(
      modulator: OplOperator.fromRegisters(at(0), at(2), at(4), at(6), at(8)),
      carrier: OplOperator.fromRegisters(at(1), at(3), at(5), at(7), at(9)),
      feedback: (at(10) >> 1) & 0x07,
      connection: at(10) & 0x01,
    );
  }

  final OplOperator modulator;
  final OplOperator carrier;
  final int feedback; // 0..7
  final int connection; // 0 = FM, 1 = additive

  /// A patch with no register bits set carries no real instrument.
  static bool isBlank(List<int> data) =>
      data.length < 11 || !data.any((b) => (b & 0xFF) != 0);
}

/// A dynamic OPL2 two-operator FM instrument built from an S3M AdLib patch.
/// Renders each note with real per-operator ADSR envelopes, the selected
/// waveforms, key-scaling, AM/VIB LFOs and FM / additive mixing.
class OplInstrument implements TrackerInstrument {
  OplInstrument(this.id, List<int> adlibData)
      : _blank = OplPatch.isBlank(adlibData),
        patch = OplPatch.fromS3m(adlibData);

  @override
  final String id;

  /// The decoded operator model — exposed for inspection / tests.
  final OplPatch patch;

  final bool _blank;

  /// A patch with no register bits set produces silence.
  bool get isBlank => _blank;

  @override
  Float64List renderChannel(
    List<TrackerCell> cells,
    TrackerTiming timing, {
    Float64List? into,
  }) {
    final out = into ?? Float64List(timing.totalSamples);
    if (_blank) return out;

    var startStep = 0;
    for (final (midi, sustainSteps, releaseSteps) in noteRuns(cells)) {
      final steps = sustainSteps + releaseSteps;
      if (midi != null) {
        final startSample = timing.stepStartSample(startStep);
        final runSamples =
            timing.stepStartSample(startStep + steps) - startSample;
        final sustainSamples =
            timing.stepStartSample(startStep + sustainSteps) - startSample;
        final maxOut = math.min(runSamples, out.length - startSample);
        if (maxOut > 0) {
          _renderNote(out, startSample, maxOut, sustainSamples, midi);
        }
      }
      startStep += steps;
    }
    return out;
  }

  /// Renders one note into [out] at [start] for [runSamples] samples, keyed on
  /// for the first [sustainSamples] then released.
  ///
  /// The voice is generated at the native OPL rate ([kOplSampleRate] ≈ 49716 Hz)
  /// by [Opl2Voice] and LINEARLY resampled to [kSampleRate] on the fly (no
  /// intermediate buffer): for each output sample we advance the native
  /// generator to straddle the output position and interpolate the two native
  /// samples. Linear (not cubic) resampling keeps the core allocation-free; the
  /// OPL2 core's own band-limited-ish waveforms make the interpolation error
  /// inaudible for these timbres (documented residual).
  void _renderNote(
    Float64List out,
    int start,
    int runSamples,
    int sustainSamples,
    int midi,
  ) {
    final freq = midiToFrequency(midi);
    final mod = patch.modulator;
    final car = patch.carrier;

    final voice = Opl2Voice(
      frequencyHz: freq,
      nativeRate: kOplSampleRate,
      modMult: mod.mult,
      modWaveform: mod.waveform,
      modTotalLevel: mod.totalLevel,
      modKsl: mod.keyScaleLevel,
      modAttack: mod.attack,
      modDecay: mod.decay,
      modSustainLevel: mod.sustainLevel,
      modRelease: mod.release,
      modKsr: mod.keyScaleRate,
      modSustaining: mod.sustaining,
      modTremolo: mod.tremolo,
      modVibrato: mod.vibrato,
      carMult: car.mult,
      carWaveform: car.waveform,
      carTotalLevel: car.totalLevel,
      carKsl: car.keyScaleLevel,
      carAttack: car.attack,
      carDecay: car.decay,
      carSustainLevel: car.sustainLevel,
      carRelease: car.release,
      carKsr: car.keyScaleRate,
      carSustaining: car.sustaining,
      carTremolo: car.tremolo,
      carVibrato: car.vibrato,
      feedback: patch.feedback,
      additive: patch.connection == 1,
    );

    // Native → output resample ratio (native samples per output sample).
    const ratio = kOplSampleRate / kSampleRate;
    // The keyed-on span, measured in NATIVE samples.
    final sustainNative = sustainSamples * ratio;

    // Rolling native samples straddling the current output position.
    var nativeIndex = 0; // index of [prevNative]
    var prevNative = voice.nextNative(true); // native sample 0
    var curNative = voice.nextNative(sustainNative > 1); // native sample 1
    var producedNative = 2;

    for (var i = 0; i < runSamples; i++) {
      final pos = i * ratio; // native position for output sample i
      final target = pos.floor();
      // Advance the native generator until [nativeIndex] == target.
      while (nativeIndex < target) {
        prevNative = curNative;
        final keyOn = producedNative < sustainNative;
        curNative = voice.nextNative(keyOn);
        producedNative++;
        nativeIndex++;
        // Stop early once released and silent.
        if (!keyOn && voice.done) {
          // Fill the tail with the (silent) last sample and finish.
          for (var j = i; j < runSamples; j++) {
            out[start + j] = curNative.isFinite ? curNative : 0.0;
          }
          return;
        }
      }
      final frac = pos - target;
      final v = prevNative + (curNative - prevNative) * frac;
      out[start + i] = v.isFinite ? v : 0.0;
    }
  }
}
