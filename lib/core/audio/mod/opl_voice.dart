// lib/core/audio/mod/opl_voice.dart
//
// A DYNAMIC OPL2 two-operator FM voice for Scream Tracker 3 AdLib (type-2)
// instruments. This is the follow-up to the STATIC single-period approximation
// in s3m_reader.dart ([synthesizeAdlibWaveform], retained there as a preview /
// fallback): where that renders one looped waveform with no envelopes, this
// renders each note DYNAMICALLY — two operators, each with a phase accumulator
// and its own ADSR envelope derived from the OPL rate registers, the four OPL2
// waveform-select shapes, key-scaling of both level and envelope rate, the
// per-operator tremolo (AM) / vibrato (VIB) LFOs, and FM (connection 0) or
// additive (connection 1) mixing with modulator feedback.
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
// ── The ADSR envelope model ─────────────────────────────────────────────────
// Each operator carries an independent 4-phase envelope in the LINEAR-amplitude
// domain (1 = full, 0 = silent):
//   • ATTACK  — a one-pole rise toward 1.0 (key-on), rate from AR.
//   • DECAY   — a one-pole fall toward the sustain level, rate from DR.
//   • SUSTAIN — hold at the sustain level (EGT=1). When EGT=0 (percussive) the
//               envelope keeps decaying toward 0 at the release rate instead.
//   • RELEASE — key-off → a one-pole fall toward 0, rate from RR.
// The sustain level comes from SL (3 dB per step; SL=15 ≈ silent). Each phase's
// time constant is the OPL rate→time approximation in [_rateToCoefficient]:
// every register step quadruples the effective rate and each effective-rate
// step of 4 doubles the slope, so rate 0 never moves, rate 15 is near-instant.
// The played note contributes a rate offset (KSR) and a level attenuation (KSL),
// so higher notes decay faster and sound quieter — real OPL key-scaling.
//
// This is a FAITHFUL DYNAMIC voice, NOT a bit-exact hardware emulation. The
// documented residual vs a real YMF262/YM3812: the envelope uses continuous
// one-pole time constants rather than the chip's 0.1875 dB logarithmic DAC
// ladder and 15.7 kHz update grid; the LFO depths use the datasheet nominal
// (AM ≈ 1 dB @ 3.7 Hz, VIB ≈ 7 cents @ 6.4 Hz) rather than the exact
// tremolo/vibrato tables; KSL uses a per-octave attenuation instead of the
// block/f-number table; only OPL2's four waveforms are modelled (no OPL3
// waveforms 4–7, no 4-operator connections, no rhythm-mode percussion).
//
// Flutter-free and allocation-lean (each note renders directly into the output
// window, no per-note temporaries), so it drops onto the same [TrackerInstrument]
// seam as the sampled / procedural voices and streams under the row-chunk
// renderer. Like the other per-note procedural voices ([FmInstrument] etc.) each
// note is self-contained: OPL operator/envelope state is NOT threaded across a
// streamer chunk boundary (a note re-attacks at a chunk edge) — the same
// documented trade-off those voices make.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart'
    show kSampleRate, midiToFrequency;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerCell, TrackerInstrument, TrackerTiming, noteRuns;

/// OPL frequency-multiplication factor per the 4-bit `MULT` field. Index 11/13
/// alias 10/12; 14/15 both mean 15.
const List<double> _multTable = <double>[
  0.5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 12, 12, 15, 15, //
];

/// Key-scale-level attenuation in dB PER OCTAVE for the 2-bit KSL field. The
/// OPL famously swaps the 1 and 2 settings, so the order is 0, 3, 1.5, 6.
const List<double> _kslDbPerOctave = <double>[0.0, 3.0, 1.5, 6.0];

/// FM modulation depth: a full-scale modulator output (±1) deviates the carrier
/// phase by this many CYCLES. Bounded so feedback + modulation stay finite.
const double _kModDepth = 1.0;

/// dB → linear amplitude (0 dB → 1.0).
double _linearFromDb(double db) => math.pow(10.0, -db / 20.0).toDouble();

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

  double get multiple => _multTable[mult & 0x0F];

  /// The static output attenuation (linear amplitude) for a note whose OPL
  /// key-scale number is [keyScaleNumber] (block<<1 | f-number MSB): the total
  /// level plus the key-scale-level attenuation.
  double outputLevel(int keyScaleNumber) {
    final block = keyScaleNumber >> 1;
    final kslDb = _kslDbPerOctave[keyScaleLevel] * block;
    return _linearFromDb(totalLevel * 0.75 + kslDb);
  }

  /// The key-scale rate offset (0..15) added to a rate register before it is
  /// converted to a slope: KSR uses the whole key-scale number, else its top
  /// 2 bits — so higher notes decay faster.
  int rateOffset(int keyScaleNumber) =>
      keyScaleRate ? keyScaleNumber : (keyScaleNumber >> 2);
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

/// Evaluates one of the four OPL2 operator waveforms at [phaseCycles] (in whole
/// cycles; the fractional part selects the point in the period):
///   0 = full sine, 1 = half sine (negative half zeroed), 2 = absolute sine
///   (full-wave rectified), 3 = quarter/pulse sine (rising quarter of each hump).
double _oplWaveform(int select, double phaseCycles) {
  var p = phaseCycles - phaseCycles.floorToDouble(); // [0, 1)
  if (p < 0) p += 1.0;
  final angle = p * 2 * math.pi;
  switch (select & 0x03) {
    case 1:
      return p < 0.5 ? math.sin(angle) : 0.0;
    case 2:
      return math.sin(angle).abs();
    case 3:
      final quadrant = (p * 4).floor();
      return (quadrant == 0 || quadrant == 2) ? math.sin(angle).abs() : 0.0;
    case 0:
    default:
      return math.sin(angle);
  }
}

/// The one-pole coefficient (0..1) that advances an OPL envelope one sample for
/// a 4-bit register [rate] with key-scale [offset]. Every register step
/// quadruples the effective rate, and each effective-rate step of 4 doubles the
/// dB/second slope; rate 0 never moves (coefficient 0). Continuous approximation
/// of the chip's stepped envelope clock (documented residual).
double _rateToCoefficient(int rate, int offset) {
  if (rate <= 0) return 0.0;
  final effective = math.min(63, rate * 4 + offset);
  // ~30 dB/s at the slowest audible effective rate, doubling every 4 steps.
  final dbPerSecond = 30.0 * math.pow(2.0, effective / 4.0);
  // Time constant to traverse a nominal 48 dB span, as a one-pole per sample.
  final tau = 48.0 / dbPerSecond;
  final coefficient = 1.0 - math.exp(-1.0 / (tau * kSampleRate));
  return coefficient.clamp(0.0, 1.0);
}

enum _EnvPhase { attack, decay, sustain, release, done }

/// A running ADSR envelope for one operator over one note.
class _Envelope {
  _Envelope(OplOperator op, int keyScaleNumber)
      : _sustaining = op.sustaining,
        _attackCoef =
            _rateToCoefficient(op.attack, op.rateOffset(keyScaleNumber)),
        _decayCoef =
            _rateToCoefficient(op.decay, op.rateOffset(keyScaleNumber)),
        _releaseCoef =
            _rateToCoefficient(op.release, op.rateOffset(keyScaleNumber)),
        _sustainAmp =
            op.sustainLevel >= 15 ? 0.0 : _linearFromDb(op.sustainLevel * 3.0),
        // Attack rate 0 = no attack: the operator never sounds.
        _phase = op.attack <= 0 ? _EnvPhase.done : _EnvPhase.attack;

  final bool _sustaining;
  final double _attackCoef;
  final double _decayCoef;
  final double _releaseCoef;
  final double _sustainAmp;

  _EnvPhase _phase;
  double amp = 0.0;

  bool get done => _phase == _EnvPhase.done;

  /// Advances one sample. [keyOn] false triggers/continues the release phase.
  void advance(bool keyOn) {
    if (!keyOn && _phase != _EnvPhase.release && _phase != _EnvPhase.done) {
      _phase = _EnvPhase.release;
    }
    switch (_phase) {
      case _EnvPhase.attack:
        amp += (1.0 - amp) * _attackCoef;
        if (amp >= 0.999 || _attackCoef <= 0.0) {
          amp = _attackCoef <= 0.0 ? amp : 1.0;
          _phase = _EnvPhase.decay;
        }
        break;
      case _EnvPhase.decay:
        amp += (_sustainAmp - amp) * _decayCoef;
        if ((amp - _sustainAmp).abs() < 1e-4 || _decayCoef <= 0.0) {
          amp = _sustainAmp;
          // EGT=1 holds; EGT=0 keeps decaying toward 0 at the release rate.
          _phase = _sustaining ? _EnvPhase.sustain : _EnvPhase.release;
        }
        break;
      case _EnvPhase.sustain:
        // Hold until key-off.
        break;
      case _EnvPhase.release:
        amp += (0.0 - amp) * _releaseCoef;
        if (amp < 1e-4 || _releaseCoef <= 0.0) {
          amp = 0.0;
          _phase = _EnvPhase.done;
        }
        break;
      case _EnvPhase.done:
        amp = 0.0;
        break;
    }
  }
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
  void _renderNote(
    Float64List out,
    int start,
    int runSamples,
    int sustainSamples,
    int midi,
  ) {
    final freq = midiToFrequency(midi);
    // OPL key-scale number: block (octave, 0..7) << 1 | the f-number MSB. The
    // MSB is set for the upper half of an octave — approximate from the note.
    final block = (midi ~/ 12).clamp(0, 7);
    final fNumberMsb = (midi % 12) >= 6 ? 1 : 0;
    final keyScaleNumber = (block << 1) | fNumberMsb;

    final mod = patch.modulator;
    final car = patch.carrier;
    final modLevel = mod.outputLevel(keyScaleNumber);
    final carLevel = car.outputLevel(keyScaleNumber);
    final modEnv = _Envelope(mod, keyScaleNumber);
    final carEnv = _Envelope(car, keyScaleNumber);

    final sr = kSampleRate.toDouble();
    final modInc = freq * mod.multiple / sr; // cycles per sample
    final carInc = freq * car.multiple / sr;
    // Feedback: the modulator self-modulates from its averaged last two outputs.
    final feedbackScale =
        patch.feedback == 0 ? 0.0 : (patch.feedback / 7.0) * 0.5;
    final additive = patch.connection == 1;

    // LFO rates (Hz): datasheet nominals. Depths applied only when the operator
    // enables the LFO. Vibrato ≈ 7 cents peak; tremolo ≈ 1 dB peak.
    const vibHz = 6.4;
    const amHz = 3.7;
    const vibDepth = 0.004; // 2^(7/1200) - 1 ≈ 0.004 fractional pitch
    final amFloor = _linearFromDb(1.0); // tremolo trough (1 dB down)

    var modPhase = 0.0;
    var carPhase = 0.0;
    var fbPrev1 = 0.0;
    var fbPrev2 = 0.0;

    for (var i = 0; i < runSamples; i++) {
      final keyOn = i < sustainSamples;
      final t = i / sr;

      // Shared LFOs.
      final vibLfo = math.sin(2 * math.pi * vibHz * t); // −1..1
      // Tremolo attenuation multiplier: 1.0 at the crest, [amFloor] at trough.
      final amLfo = amFloor +
          (1.0 - amFloor) * (0.5 + 0.5 * math.cos(2 * math.pi * amHz * t));

      modEnv.advance(keyOn);
      carEnv.advance(keyOn);

      // Modulator (with feedback self-modulation).
      final modVib = mod.vibrato ? (1.0 + vibDepth * vibLfo) : 1.0;
      final feedbackPhase = feedbackScale * 0.5 * (fbPrev1 + fbPrev2);
      var modOut = _oplWaveform(mod.waveform, modPhase + feedbackPhase);
      modOut *= modEnv.amp * modLevel * (mod.tremolo ? amLfo : 1.0);
      fbPrev2 = fbPrev1;
      fbPrev1 = modOut;

      // Carrier: phase-modulated by the modulator (FM), or summed (additive).
      final carVib = car.vibrato ? (1.0 + vibDepth * vibLfo) : 1.0;
      final double sample;
      if (additive) {
        final carOut = _oplWaveform(car.waveform, carPhase) *
            carEnv.amp *
            carLevel *
            (car.tremolo ? amLfo : 1.0);
        sample = carOut + modOut;
      } else {
        final carOut =
            _oplWaveform(car.waveform, carPhase + _kModDepth * modOut);
        sample = carOut * carEnv.amp * carLevel * (car.tremolo ? amLfo : 1.0);
      }

      out[start + i] = sample.isFinite ? sample : 0.0;

      modPhase += modInc * modVib;
      carPhase += carInc * carVib;

      // The note is inaudible once both envelopes have run out after key-off.
      if (!keyOn && modEnv.done && carEnv.done) break;
    }
  }
}
