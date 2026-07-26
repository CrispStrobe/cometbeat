// lib/core/audio/mod/opl2_core.dart
//
// A YM3812 / OPL2-STYLE two-operator synthesis core for Scream Tracker 3
// AdLib (type-2) instruments. This is the chip-modelled successor to the
// faithful-FLOAT voice that lived entirely in opl_voice.dart: instead of a
// one-pole ADSR and a `math.sin` oscillator, this reconstructs the operator
// output the way the real silicon does — a phase accumulator driving a 10-bit
// sine index, a 256-entry LOG-SIN table taking that index into the log
// (attenuation) domain, an EXP table taking the summed attenuation back to a
// linear sample, and an envelope generator that works entirely in the 0..511
// (9-bit) attenuation domain with the OPL rate model, key-scale rate (KSR) and
// key-scale level (KSL).
//
// ── The sine reconstruction (log-sin → sum → exp) ───────────────────────────
// The OPL does not store a sine. It stores, for the first quarter period, the
// base-2 LOGARITHM of sin, scaled by 256:
//
//   logSin[i] = round( -log2( sin( (i + 0.5) · π/512 ) ) · 256 )   i ∈ 0..255
//
// A whole period is 1024 phase steps (10-bit). Bit 8 mirrors the quarter, bit 9
// negates the half — so the four quadrants of the sine are read out of the one
// quarter-wave table. Attenuation (from the envelope, total level, key-scale
// level, tremolo) is ADDED in this same log domain, then a single EXP lookup
// turns the sum back into a linear amplitude:
//
//   exp[i]    = round( (2^(i/256) − 1) · 1024 )                     i ∈ 0..255
//   2^(−a/256) ≈ ( (exp[255 − (a & 0xFF)] + 1024) >> (a >> 8) ) / 2048
//
// The four OPL2 waveforms are pure INDEX/SIGN transforms on that one table:
// 0 = full sine, 1 = half sine (second half muted), 2 = |sine| (both halves
// rectified positive), 3 = quarter/pulse sine (rising quarter of each hump).
//
// ── The envelope generator ──────────────────────────────────────────────────
// [OplEg] runs in the ATTENUATION domain: 0 = full volume, 511 = silence
// (9-bit, ≈0.1875 dB per step → ~96 dB range). The effective rate for each
// phase is `min(63, 4·rateReg + rof)` where `rof` is the key-scale-rate offset
// (the whole key-scale number when KSR is set, else its top two bits — higher
// notes decay faster). Attack decreases the attenuation PROPORTIONALLY to what
// remains (the chip's attack shape); decay/release move it linearly toward the
// sustain level / silence. Every register step multiplies the rate; the slope
// doubles every four effective-rate steps — so a faster rate reaches its target
// in less time, and rate 0 never moves.
//
// ── Key-scale level (KSL) ───────────────────────────────────────────────────
// [oplKslAttenuation] uses the actual OPL KSL ROM + shift tables (indexed by the
// f-number's top four bits and the block), not a flat per-octave dB — so the
// attenuation follows the real block/f-number staircase (with the famous
// field-order swap: 0, 1.5, 3, 6 dB/oct maps to KSL fields 0, 2, 1, 3).
//
// ── Rendering / resampling ──────────────────────────────────────────────────
// The core generates samples at the native OPL rate (~49716 Hz, the YM3812
// master clock / 288). [Opl2Voice.nextNative] returns one native sample;
// callers resample to [kSampleRate] (opl_voice.dart uses a per-sample linear
// resample so no intermediate buffer is allocated).
//
// ── Honest residual (NOT a reference-verified emulation) ────────────────────
// This is ALGORITHM-FAITHFUL, not proven bit-exact: there is no reference
// YM3812 core in-tree to diff against, so the tables and the log-sin→exp path
// reproduce the DOCUMENTED chip algorithm and carry the chip's own ~0.3% exp
// quantisation, but timing constants for the EG are calibrated to musical
// timescales rather than derived cycle-by-cycle from the chip's envelope clock
// and global counter. The LFO depths use the datasheet nominals rather than the
// exact per-f-number vibrato staircase. OUT OF SCOPE (documented, not modelled):
// OPL3's 4-operator connections and extra waveforms 4–7, and rhythm/percussion
// mode. Allocation-lean: the tables are computed once at load; a voice holds
// only fixed scalar state, so the render loop makes no per-sample heap allocs.

import 'dart:math' as math;

// ─────────────────────────────────────────────────────────────────────────────
//  Tables (computed once at load — no per-sample allocation)
// ─────────────────────────────────────────────────────────────────────────────

/// The native OPL2 sample rate in Hz: the YM3812 master clock (3.579545 MHz)
/// divided by 72·4 = 288.
const double kOplSampleRate = 3579545.0 / 72.0;

/// The 256-entry OPL LOG-SIN table: `round(-log2(sin((i+0.5)·π/512))·256)` for
/// the first quarter period. Non-negative; ~0 where sin≈1 (index 255) up to
/// 2137 where sin≈0 (index 0). Full precision is unnecessary — the chip stores
/// 12-bit integers, and we round to match.
final List<int> oplLogSinTable = _buildLogSin();

/// The 256-entry OPL EXP table: `round((2^(i/256)−1)·1024)`, range 0..1018.
final List<int> oplExpTable = _buildExp();

List<int> _buildLogSin() {
  final t = List<int>.filled(256, 0);
  for (var i = 0; i < 256; i++) {
    final s = math.sin((i + 0.5) * math.pi / 512.0);
    t[i] = (-_log2(s) * 256.0).round();
  }
  return t;
}

List<int> _buildExp() {
  final t = List<int>.filled(256, 0);
  for (var i = 0; i < 256; i++) {
    t[i] = (((math.pow(2.0, i / 256.0) as double) - 1.0) * 1024.0).round();
  }
  return t;
}

double _log2(double x) => math.log(x) / math.ln2;

/// Linear amplitude (0..~1.0) for a log-domain attenuation [a] (in units of
/// 1/256 of an octave, i.e. the log-sin/exp domain; `a ≥ 0`). Reconstructs
/// `2^(−a/256)` from the EXP table exactly the way the chip does: split into an
/// integer power-of-two shift and a fractional table lookup. Saturates to 0 for
/// very large attenuations (silence) so the shift never runs away.
double oplExp(int a) {
  if (a <= 0) return (oplExpTable[255] + 1024) / 2048.0;
  if (a >= 8192) return 0.0;
  final shift = a >> 8;
  final frac = a & 0xFF;
  final raw = (oplExpTable[255 - frac] + 1024) >> shift;
  return raw / 2048.0;
}

/// The signed operator output for OPL2 waveform [ws] at 10-bit phase [phase10]
/// with the log-domain attenuation [atten] added before the exp step. Returns a
/// value in roughly [-1, 1]. The waveform is a pure index/sign transform on the
/// quarter-wave log-sin table:
///   0 full sine · 1 half sine · 2 |sine| · 3 quarter/pulse sine.
double oplWaveSample(int ws, int phase10, int atten) {
  final p = phase10 & 0x3FF;
  switch (ws & 0x03) {
    case 1: // half sine: mute the negative half
      if ((p & 0x200) != 0) return 0.0;
      final idx = (p & 0x100) != 0 ? (p & 0xFF) ^ 0xFF : p & 0xFF;
      return oplExp(oplLogSinTable[idx] + atten);
    case 2: // |sine|: rectify — both halves read positive
      final idx = (p & 0x100) != 0 ? (p & 0xFF) ^ 0xFF : p & 0xFF;
      return oplExp(oplLogSinTable[idx] + atten);
    case 3: // quarter/pulse sine: rising quarter of each hump, rest muted
      if ((p & 0x100) != 0) return 0.0;
      return oplExp(oplLogSinTable[p & 0xFF] + atten);
    case 0:
    default: // full sine
      final idx = (p & 0x100) != 0 ? (p & 0xFF) ^ 0xFF : p & 0xFF;
      final m = oplExp(oplLogSinTable[idx] + atten);
      return (p & 0x200) != 0 ? -m : m;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Key-scale level (KSL)
// ─────────────────────────────────────────────────────────────────────────────

/// KSL ROM: attenuation base indexed by the f-number's top four bits.
const List<int> _kslRom = <int>[
  0, 32, 40, 45, 48, 51, 53, 55, 56, 58, 59, 60, 61, 62, 63, 64, //
];

/// KSL right-shift by the 2-bit KSL field. Field 0 shifts the base to nothing
/// (KSL off); field 3 shifts least (steepest, 6 dB/oct); fields 1 and 2 are
/// swapped relative to their numeric order — the classic OPL 0, 1.5, 3, 6.
const List<int> _kslShift = <int>[8, 1, 2, 0];

/// KSL attenuation in EG (0.1875 dB) units for a note at [block] (0..7) with
/// 10-bit [fnum], under KSL field [kslField] (0..3). Higher notes (larger
/// block) are attenuated more; the low blocks fall below the ROM base and clamp
/// to 0 (no attenuation). Field 0 returns 0 (KSL disabled).
int oplKslAttenuation(int block, int fnum, int kslField) {
  // ymfm/MAME formula: base − 8·(block ^ 7); clamp; then the field shift.
  var v = _kslRom[(fnum >> 6) & 0x0F] - 8 * ((block & 0x07) ^ 7);
  if (v < 0) v = 0;
  return v >> _kslShift[kslField & 0x03];
}

// ─────────────────────────────────────────────────────────────────────────────
//  Envelope generator
// ─────────────────────────────────────────────────────────────────────────────

/// EG timing calibration (native-rate constants). Every effective-rate step of
/// 4 doubles the slope (`2^(eff/4)`). These bases set the absolute timescale so
/// the envelope lands on musically sensible attack/decay/release times; they
/// are the DOCUMENTED calibrated residual vs the chip's exact envelope clock.
const double _kAttackBase = 2.0e-5; // proportional attack coefficient
const double _kDecayBase = 1.3e-4; // linear decay/release step (EG units)

enum _EgPhase { attack, decay, sustain, release, done }

/// One operator's envelope, run entirely in the OPL ATTENUATION domain: 0 = full
/// volume, 511 = silence. [atten] is read every native sample; [advance] steps
/// it one native sample, entering release when [keyOn] goes false.
class OplEg {
  /// Builds an envelope from an operator's decoded rate registers.
  ///
  /// [keyScaleNumber] (block<<1 | f-number MSB, 0..15) drives the key-scale
  /// rate. [sustaining] is the EGT bit: true holds at the sustain level, false
  /// keeps decaying (percussive). A zero attack rate makes the operator silent
  /// (it never keys on) — the chip behaviour for AR=0.
  OplEg({
    required int attack,
    required int decay,
    required int sustainLevel,
    required int release,
    required bool keyScaleRate,
    required this.sustaining,
    required int keyScaleNumber,
  })  : _attackCoef = _attackCoefOf(attack, keyScaleRate, keyScaleNumber),
        _decayInc = _stepOf(decay, keyScaleRate, keyScaleNumber),
        _releaseInc = _stepOf(release, keyScaleRate, keyScaleNumber),
        // SL: 3 dB per step (16 EG units); SL=15 is the full-scale silence rung.
        _sustainAtten = (sustainLevel >= 15 ? 31 : sustainLevel) * 16.0,
        _phase = attack <= 0 ? _EgPhase.done : _EgPhase.attack;

  /// Proportional attack coefficient per native sample for a 4-bit rate.
  static double _attackCoefOf(int rate, bool ksr, int ksn) {
    if (rate <= 0) return 0.0;
    final eff = _effectiveRate(rate, ksr, ksn);
    return (_kAttackBase * math.pow(2.0, eff / 4.0)).clamp(0.0, 1.0);
  }

  /// Linear decay/release step (EG units per native sample) for a 4-bit rate.
  static double _stepOf(int rate, bool ksr, int ksn) {
    if (rate <= 0) return 0.0;
    return _kDecayBase * math.pow(2.0, _effectiveRate(rate, ksr, ksn) / 4.0);
  }

  /// EGT — true holds at the sustain plateau, false keeps decaying past it.
  final bool sustaining;

  final double _attackCoef;
  final double _decayInc;
  final double _releaseInc;
  final double _sustainAtten;

  _EgPhase _phase;

  /// Current attenuation, 0 (full volume) .. 511 (silence).
  double atten = 511.0;

  /// True once the envelope has run out (silence) after release.
  bool get done => _phase == _EgPhase.done;

  /// The effective rate `min(63, 4·rate + rof)` for a 4-bit rate register.
  static int _effectiveRate(int rate, bool ksr, int ksn) {
    final rof = ksr ? ksn : ksn >> 2;
    final eff = rate * 4 + rof;
    return eff > 63 ? 63 : eff;
  }

  /// Advances the envelope one native sample. When [keyOn] is false the
  /// envelope enters (or stays in) the release phase.
  void advance(bool keyOn) {
    if (!keyOn && _phase != _EgPhase.release && _phase != _EgPhase.done) {
      _phase = _EgPhase.release;
    }
    switch (_phase) {
      case _EgPhase.attack:
        // Attack: attenuation falls proportionally to what remains (the chip's
        // curved attack), reaching full volume faster the more it has to go.
        atten -= atten * _attackCoef;
        if (atten <= 0.5 || _attackCoef <= 0.0) {
          atten = 0.0;
          _phase = _EgPhase.decay;
        }
        break;
      case _EgPhase.decay:
        atten += _decayInc;
        if (atten >= _sustainAtten || _decayInc <= 0.0) {
          if (_decayInc > 0.0) atten = _sustainAtten;
          _phase = sustaining ? _EgPhase.sustain : _EgPhase.release;
        }
        break;
      case _EgPhase.sustain:
        break; // hold until key-off
      case _EgPhase.release:
        atten += _releaseInc;
        if (atten >= 511.0 || _releaseInc <= 0.0) {
          if (_releaseInc > 0.0) atten = 511.0;
          _phase = _EgPhase.done;
        }
        break;
      case _EgPhase.done:
        atten = 511.0;
        break;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Two-operator voice
// ─────────────────────────────────────────────────────────────────────────────

/// The fractional bits below the 10-bit phase index in the fixed-point phase
/// accumulator (accumulator = phase · 2^(10+_kPhaseFrac) cycles).
const int _kPhaseFrac = 16;
const int _kPhaseMask = (1 << (10 + _kPhaseFrac)) - 1;

/// FM modulation depth: a full-scale (±1) modulator output deviates the carrier
/// phase by this many CYCLES (·1024 phase-index units).
const double _kModDepthCycles = 1.0;

/// OPL frequency multiple per the 4-bit MULT field (11/13 alias 10/12; 14/15→15).
const List<double> _oplMult = <double>[
  0.5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 12, 12, 15, 15, //
];

/// A running YM3812/OPL2 two-operator voice for ONE note. Construct it with the
/// decoded operator fields and the note frequency, then pull native-rate samples
/// from [nextNative]. Holds only fixed scalar state — the sample loop allocates
/// nothing.
class Opl2Voice {
  /// Builds a voice for one note.
  ///
  /// Frequencies are derived from [frequencyHz] (× each operator's MULT); the
  /// f-number/block reconstructed from that frequency feed KSL and the
  /// key-scale rate. [feedback] is the modulator self-feedback (0..7);
  /// [additive] selects connection 1 (both operators summed) vs FM (0).
  Opl2Voice({
    required double frequencyHz,
    required this.nativeRate,
    // Modulator
    required int modMult,
    required int modWaveform,
    required int modTotalLevel,
    required int modKsl,
    required int modAttack,
    required int modDecay,
    required int modSustainLevel,
    required int modRelease,
    required bool modKsr,
    required bool modSustaining,
    required this.modTremolo,
    required this.modVibrato,
    // Carrier
    required int carMult,
    required int carWaveform,
    required int carTotalLevel,
    required int carKsl,
    required int carAttack,
    required int carDecay,
    required int carSustainLevel,
    required int carRelease,
    required bool carKsr,
    required bool carSustaining,
    required this.carTremolo,
    required this.carVibrato,
    // Channel
    required int feedback,
    required this.additive,
  })  : _modWave = modWaveform,
        _carWave = carWaveform,
        _feedbackFactor = feedback == 0 ? 0.0 : (feedback / 8.0) * 0.5 {
    // Reconstruct a canonical f-number / block from the frequency: pick the
    // block that keeps the 10-bit f-number in range.
    var fnumF = frequencyHz * (1 << 20) / nativeRate;
    var block = 0;
    while (fnumF >= 1024.0 && block < 7) {
      fnumF /= 2.0;
      block++;
    }
    final fnum = fnumF.round().clamp(0, 1023);
    final ksn = ((block << 1) | (fnum >> 9)) & 0x0F;

    _modAtten = modTotalLevel * 4 + oplKslAttenuation(block, fnum, modKsl);
    _carAtten = carTotalLevel * 4 + oplKslAttenuation(block, fnum, carKsl);

    // Phase increment per native sample, fixed-point (cycles · 2^(10+frac)).
    final scale = (1 << (10 + _kPhaseFrac)) / nativeRate;
    _modInc = (frequencyHz * _oplMult[modMult & 0x0F] * scale).round();
    _carInc = (frequencyHz * _oplMult[carMult & 0x0F] * scale).round();

    _modEg = OplEg(
      attack: modAttack,
      decay: modDecay,
      sustainLevel: modSustainLevel,
      release: modRelease,
      keyScaleRate: modKsr,
      sustaining: modSustaining,
      keyScaleNumber: ksn,
    );
    _carEg = OplEg(
      attack: carAttack,
      decay: carDecay,
      sustainLevel: carSustainLevel,
      release: carRelease,
      keyScaleRate: carKsr,
      sustaining: carSustaining,
      keyScaleNumber: ksn,
    );
  }

  final double nativeRate;
  final bool additive;
  final bool modTremolo;
  final bool modVibrato;
  final bool carTremolo;
  final bool carVibrato;

  final int _modWave;
  final int _carWave;
  final double _feedbackFactor;

  late final int _modInc;
  late final int _carInc;
  late final int _modAtten; // TL·4 + KSL, EG units (log domain, ·8 → 1/256 oct)
  late final int _carAtten;
  late final OplEg _modEg;
  late final OplEg _carEg;

  int _modPhase = 0;
  int _carPhase = 0;
  double _fbPrev1 = 0.0;
  double _fbPrev2 = 0.0;
  int _sampleIndex = 0;

  /// True once both operator envelopes have run out (safe to stop early).
  bool get done => _modEg.done && _carEg.done;

  // LFO: datasheet nominals (documented residual vs the exact chip staircase).
  static const double _vibHz = 6.4;
  static const double _amHz = 3.7;
  static const double _vibDepth = 0.0009; // ~14 cents peak fractional pitch
  static const double _amDepthEg = 5.5; // ~1 dB tremolo peak, EG units

  /// Renders the next native-rate sample. [keyOn] false releases the envelopes.
  double nextNative(bool keyOn) {
    final t = _sampleIndex / nativeRate;
    _sampleIndex++;

    _modEg.advance(keyOn);
    _carEg.advance(keyOn);

    // Shared LFOs.
    final vib = math.sin(2 * math.pi * _vibHz * t); // −1..1
    final amEg = (_amDepthEg * 0.5 * (1.0 - math.cos(2 * math.pi * _amHz * t)))
        .toInt(); // 0..~depth, added attenuation

    // Modulator (with self-feedback on its phase).
    final modLevel = (_modEg.atten + _modAtten + (modTremolo ? amEg : 0))
        .round()
        .clamp(0, 4095);
    final fbCycles = _feedbackFactor * 0.5 * (_fbPrev1 + _fbPrev2);
    final modIdx = (_modPhase >> _kPhaseFrac) + (fbCycles * 1024.0).round();
    final modOut = oplWaveSample(_modWave, modIdx, modLevel << 3);
    _fbPrev2 = _fbPrev1;
    _fbPrev1 = modOut;

    final double sample;
    if (additive) {
      final carLevel = (_carEg.atten + _carAtten + (carTremolo ? amEg : 0))
          .round()
          .clamp(0, 4095);
      final carOut =
          oplWaveSample(_carWave, _carPhase >> _kPhaseFrac, carLevel << 3);
      sample = (modOut + carOut).clamp(-1.0, 1.0);
    } else {
      final carLevel = (_carEg.atten + _carAtten + (carTremolo ? amEg : 0))
          .round()
          .clamp(0, 4095);
      final carIdx = (_carPhase >> _kPhaseFrac) +
          (_kModDepthCycles * modOut * 1024.0).round();
      sample = oplWaveSample(_carWave, carIdx, carLevel << 3);
    }

    // Advance the phase accumulators (with vibrato on the increment).
    final modStep =
        modVibrato ? (_modInc + (_modInc * _vibDepth * vib)).round() : _modInc;
    final carStep =
        carVibrato ? (_carInc + (_carInc * _vibDepth * vib)).round() : _carInc;
    _modPhase = (_modPhase + modStep) & _kPhaseMask;
    _carPhase = (_carPhase + carStep) & _kPhaseMask;

    return sample.isFinite ? sample : 0.0;
  }
}
