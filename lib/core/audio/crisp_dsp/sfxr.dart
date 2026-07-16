// lib/core/audio/crisp_dsp/sfxr.dart
//
// Focused pure-Dart port of the sfxr-style synth from CrispStrobe/crispaudio
// (MIT, ours — src/audio/engine/SynthEngine.ts, itself ported from CrispFXR).
// The "make an instrument" generator: a handful of parameters (waveform +
// envelope + frequency gesture + duty/arp/filters/distortion) synthesize the
// classic 8-bit blips, zaps and booms. Used by the Tracker as a chiptune
// instrument source (see docs/TRACKER_HANDOVER.md).
//
// Scope: this ports the LIVE synthesis path of generateSamples() — the params
// the sample loop actually reads. The delay-line effects (chorus/delay/flanger),
// FM/LFO/ring-mod and the phaser/second-order-ramp params that the upstream loop
// declares but never applies are intentionally omitted for v1; add them here if
// an instrument needs them. Distortion keeps the upstream bug-fix (a straight
// tanh saturator normalized by 1/tanh(drive), not divided by drive).
//
// Determinism: noise and the arpeggio use a seedable [Random], so a given
// (params, seed) always yields the same buffer — the Tracker's stem cache and
// the tests rely on it. Output is mono Float64 in [-1, 1] (unnormalized: the
// mixer sets levels).

import 'dart:math';
import 'dart:typed_data';

import 'package:klang_universum/core/audio/synth.dart' show kSampleRate;

/// Waveform selector for [SfxrParams.waveType].
class SfxrWave {
  static const square = 0;
  static const sawtooth = 1;
  static const sine = 2;
  static const noise = 3;
}

/// The synthesis parameters. Every field defaults to the upstream
/// createDefaultParams() value; a preset just overrides the few it cares about.
class SfxrParams {
  const SfxrParams({
    this.waveType = SfxrWave.square,
    this.noiseType = 0,
    this.attack = 0,
    this.sustain = 0.3,
    this.punch = 0,
    this.decay = 0.4,
    this.baseFreq = 0.3,
    this.freqRamp = 0,
    this.vibStrength = 0,
    this.vibSpeed = 0,
    this.arpMod = 0,
    this.arpSpeed = 0,
    this.duty = 0,
    this.dutyRamp = 0,
    this.repeatSpeed = 0,
    this.lpfFreq = 1,
    this.hpfFreq = 0,
    this.subBass = 0,
    this.distortion = 0,
    this.bitCrush = 0,
    this.soundVol = 0.5,
  });

  final int waveType;
  final int noiseType; // 0 white, 1 pink, 2 brown
  final double attack, sustain, punch, decay; // seconds-ish envelope
  final double baseFreq; // ×440 Hz
  final double freqRamp; // per-sample slide
  final double vibStrength, vibSpeed;
  final double arpMod, arpSpeed;
  final double duty, dutyRamp; // square pulse width
  final double repeatSpeed; // retrigger
  final double lpfFreq, hpfFreq; // 1-pole filters (1 = LPF open)
  final double subBass;
  final double distortion, bitCrush;
  final double soundVol;

  SfxrParams copyWith({double? baseFreq}) => SfxrParams(
        waveType: waveType,
        noiseType: noiseType,
        attack: attack,
        sustain: sustain,
        punch: punch,
        decay: decay,
        baseFreq: baseFreq ?? this.baseFreq,
        freqRamp: freqRamp,
        vibStrength: vibStrength,
        vibSpeed: vibSpeed,
        arpMod: arpMod,
        arpSpeed: arpSpeed,
        duty: duty,
        dutyRamp: dutyRamp,
        repeatSpeed: repeatSpeed,
        lpfFreq: lpfFreq,
        hpfFreq: hpfFreq,
        subBass: subBass,
        distortion: distortion,
        bitCrush: bitCrush,
        soundVol: soundVol,
      );
}

double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

double _tanh(double x) {
  final e = exp(2 * x);
  return (e - 1) / (e + 1);
}

Float64List _generateNoise(int type, int length, Random r) {
  final n = Float64List(length);
  var b0 = 0.0, b1 = 0.0, b2 = 0.0, b6 = 0.0;
  for (var i = 0; i < length; i++) {
    final white = r.nextDouble() * 2 - 1;
    switch (type) {
      case 1: // Pink (Paul Kellet)
        b0 = 0.99886 * b0 + white * 0.0555179;
        b1 = 0.99332 * b1 + white * 0.0750759;
        b2 = 0.96900 * b2 + white * 0.1538520;
        n[i] = b0 + b1 + b2 + white * 0.3104856;
      case 2: // Brown
        b6 = (b6 + white * 0.02) * 0.996;
        n[i] = b6 * 3.5;
      default: // White
        n[i] = white;
    }
  }
  return n;
}

/// Synthesizes [params] into a mono Float64 buffer of [durationSec] seconds
/// (in [-1, 1], unnormalized). [rng] seeds the noise/arpeggio for reproducible
/// output.
Float64List sfxrGenerate(
  SfxrParams params, {
  int sampleRate = kSampleRate,
  double durationSec = 0.3,
  Random? rng,
}) {
  final r = rng ?? Random(0);
  final dur = _clamp(durationSec, 0, 10);
  final length = (sampleRate * dur).floor();
  final data = Float64List(length);
  if (length == 0) return data;

  final noise = params.waveType == SfxrWave.noise
      ? _generateNoise(params.noiseType, length, r)
      : null;

  final attackSamples = (params.attack * sampleRate).floor();
  final sustainSamples = (params.sustain * sampleRate).floor();
  final decaySamples = (params.decay * sampleRate).floor();

  var phase = 0.0, subPhase = 0.0;
  var frequency = _clamp(params.baseFreq, 0.001, 2) * 440;
  var dutyCycle = _clamp(0.5 - params.duty * 0.5, 0.01, 0.99);
  var arpTime = 0.0, arpValue = 1.0;
  var lpfPrev = 0.0, hpfPrev = 0.0;

  for (var i = 0; i < length; i++) {
    final t = i / sampleRate;

    // Envelope: linear attack, punchy sustain, linear decay.
    double env;
    if (i < attackSamples) {
      env = attackSamples > 0 ? i / attackSamples : 1.0;
    } else if (i < attackSamples + sustainSamples) {
      final sp =
          sustainSamples > 0 ? (i - attackSamples) / sustainSamples : 0.0;
      env = 1 + (1 - sp) * 2 * params.punch;
    } else if (i < attackSamples + sustainSamples + decaySamples) {
      final dp = decaySamples > 0
          ? (i - attackSamples - sustainSamples) / decaySamples
          : 1.0;
      env = max(0.0, 1 - dp);
    } else {
      env = 0;
    }

    // Retrigger.
    if (params.repeatSpeed > 0) {
      final period = sampleRate / (params.repeatSpeed * 20);
      final rp = (i % period) / period;
      if (rp < 0.1) env *= rp / 0.1;
    }

    // Arpeggio.
    if (params.arpSpeed > 0) {
      arpTime += params.arpSpeed * 50 / sampleRate;
      if (arpTime >= 1) {
        arpTime = 0;
        arpValue = 1 + params.arpMod * (r.nextDouble() * 2 - 1);
      }
    }

    frequency = _clamp(frequency + params.freqRamp * 10, 20, 20000);
    var cur = frequency * _clamp(arpValue, 0.1, 10);

    if (params.vibStrength > 0 && params.vibSpeed > 0) {
      final v = sin(2 * pi * params.vibSpeed * 50 * t);
      cur += v * params.vibStrength * cur * 0.1;
    }

    if (params.dutyRamp != 0) {
      dutyCycle = _clamp(dutyCycle + params.dutyRamp * 0.0001, 0.01, 0.99);
    }

    cur = _clamp(cur, 20, 20000);
    phase += 2 * pi * cur / sampleRate;
    if (phase > 2 * pi) phase -= 2 * pi;

    double s;
    switch (params.waveType) {
      case SfxrWave.square:
        s = (phase / (2 * pi)) < dutyCycle ? 1 : -1;
      case SfxrWave.sawtooth:
        s = (phase / pi) - 1;
      case SfxrWave.sine:
        s = sin(phase);
      case SfxrWave.noise:
        s = noise![i];
      default:
        s = sin(phase);
    }
    s = _clamp(s, -1, 1);

    if (params.subBass > 0) {
      subPhase += pi * cur / sampleRate;
      if (subPhase > 2 * pi) subPhase -= 2 * pi;
      s += sin(subPhase) * params.subBass * 0.5;
    }

    // 1-pole low-pass / high-pass.
    if (params.lpfFreq < 1) {
      final c = _clamp(params.lpfFreq, 0, 1);
      lpfPrev = s * c + (1 - c) * lpfPrev;
      s = lpfPrev;
    }
    if (params.hpfFreq > 0) {
      final a = _clamp(params.hpfFreq, 0, 1);
      final o = s - hpfPrev;
      hpfPrev = s;
      s = o * (1 - a);
    }

    if (params.distortion > 0) {
      final drive = 1 + params.distortion * 10;
      s = _tanh(s * drive) / _tanh(drive);
    }
    if (params.bitCrush > 0) {
      final bits = (16 - params.bitCrush * 15).floor();
      final levels = pow(2, bits).toDouble();
      s = (s * levels).floor() / levels;
    }

    s = _clamp(s, -1, 1);
    env = _clamp(env, 0, 1);
    final fin = s * env * params.soundVol * 0.3;
    data[i] = fin.isNaN ? 0 : _clamp(fin, -1, 1);
  }
  return data;
}

// ---------------------------------------------------------------------------
// Presets — deterministic when given a seeded [Random]. Ported from
// crispaudio's sfxPresets.ts (which randomizes each field); the Tracker freezes
// one per instrument so its timbre is stable, while a future "mutate/randomize"
// UI can re-roll by passing a fresh Random.
// ---------------------------------------------------------------------------

typedef SfxrPreset = SfxrParams Function(Random r);

SfxrParams sfxrCoin(Random r) {
  final arp = r.nextDouble() > 0.5;
  return SfxrParams(
    waveType: SfxrWave.sawtooth,
    baseFreq: 0.4 + r.nextDouble() * 0.5,
    sustain: r.nextDouble() * 0.1,
    decay: 0.1 + r.nextDouble() * 0.4,
    punch: 0.3 + r.nextDouble() * 0.3,
    arpSpeed: arp ? 0.5 + r.nextDouble() * 0.2 : 0,
    arpMod: arp ? 0.2 + r.nextDouble() * 0.4 : 0,
  );
}

SfxrParams sfxrLaser(Random r) => SfxrParams(
      waveType: (r.nextDouble() * 3).floor(),
      baseFreq: 0.3 + r.nextDouble() * 0.6,
      freqRamp: -0.35 - r.nextDouble() * 0.3,
      sustain: 0.1 + r.nextDouble() * 0.2,
      decay: r.nextDouble() * 0.4,
      hpfFreq: r.nextDouble() * 0.3,
      distortion: r.nextDouble() * 0.3,
    );

SfxrParams sfxrExplosion(Random r) => SfxrParams(
      waveType: SfxrWave.noise,
      baseFreq: pow(0.1 + r.nextDouble() * 0.4, 2).toDouble(),
      freqRamp: -0.1 + r.nextDouble() * 0.4,
      sustain: 0.1 + r.nextDouble() * 0.3,
      decay: r.nextDouble() * 0.5,
      punch: 0.2 + r.nextDouble() * 0.6,
      distortion: 0.2 + r.nextDouble() * 0.5,
    );

SfxrParams sfxrPowerUp(Random r) => SfxrParams(
      waveType: r.nextDouble() > 0.5 ? SfxrWave.sawtooth : SfxrWave.square,
      baseFreq: 0.2 + r.nextDouble() * 0.3,
      freqRamp: 0.1 + r.nextDouble() * 0.4,
      sustain: r.nextDouble() * 0.4,
      decay: 0.1 + r.nextDouble() * 0.4,
    );

SfxrParams sfxrHit(Random r) {
  var wave = (r.nextDouble() * 3).floor();
  if (wave == SfxrWave.sine) wave = SfxrWave.noise;
  return SfxrParams(
    waveType: wave,
    baseFreq: 0.2 + r.nextDouble() * 0.6,
    freqRamp: -0.3 - r.nextDouble() * 0.4,
    sustain: r.nextDouble() * 0.1,
    decay: 0.1 + r.nextDouble() * 0.2,
    distortion: r.nextDouble() * 0.4,
  );
}

SfxrParams sfxrJump(Random r) => SfxrParams(
      duty: r.nextDouble() * 0.6,
      baseFreq: 0.3 + r.nextDouble() * 0.3,
      freqRamp: 0.1 + r.nextDouble() * 0.2,
      sustain: 0.1 + r.nextDouble() * 0.3,
      decay: 0.1 + r.nextDouble() * 0.2,
    );

SfxrParams sfxrBlip(Random r) => SfxrParams(
      waveType: SfxrWave.sine,
      baseFreq: 0.5 + r.nextDouble() * 0.3,
      sustain: 0.01 + r.nextDouble() * 0.05,
      decay: 0.1 + r.nextDouble() * 0.2,
      freqRamp: 0.1 + r.nextDouble() * 0.3,
    );

SfxrParams sfxrZap(Random r) => SfxrParams(
      baseFreq: 0.6 + r.nextDouble() * 0.4,
      freqRamp: -0.5 - r.nextDouble() * 0.3,
      sustain: 0.05 + r.nextDouble() * 0.1,
      decay: 0.1 + r.nextDouble() * 0.2,
      duty: -0.2 + r.nextDouble() * 0.4,
      distortion: 0.1 + r.nextDouble() * 0.3,
    );

SfxrParams sfxrClick(Random r) => SfxrParams(
      baseFreq: 0.8 + r.nextDouble() * 0.2,
      sustain: 0.01,
      decay: 0.02 + r.nextDouble() * 0.03,
      duty: 0.1 + r.nextDouble() * 0.2,
      hpfFreq: 0.2 + r.nextDouble() * 0.3,
    );

/// The named preset palette (for instrument pickers / tests).
const Map<String, SfxrPreset> kSfxrPresets = {
  'coin': sfxrCoin,
  'laser': sfxrLaser,
  'explosion': sfxrExplosion,
  'powerup': sfxrPowerUp,
  'hit': sfxrHit,
  'jump': sfxrJump,
  'blip': sfxrBlip,
  'zap': sfxrZap,
  'click': sfxrClick,
};
