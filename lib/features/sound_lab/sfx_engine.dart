// Sound Lab — the generate-your-own sound-effect engine. A self-contained,
// Flutter-free port of our MIT crispfxr-app synthesizer (an sfxr-lineage retro
// SFX generator): a per-sample render loop producing a `Float64List`, plus
// presets, randomize/mutate/morph, and a base64 share token. Kept separate from
// the tracker's `crisp_dsp/sfxr.dart` (its `SfxrInstrument`) so this richer
// engine can evolve without touching that shared file.
//
// Deterministic given a seed. Effects (distortion/bit-crush/one-pole LPF+HPF/
// sub-bass/ring-mod/chorus/delay/flanger) run in the synthesis loop, matching
// the crispfxr algorithms (the app already uses tanh soft-clip in synth.dart).

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

enum SfxWave { square, sawtooth, sine, noise }

enum NoiseColor { white, pink, brown }

/// The full parameter set of one sound. Immutable; edit via [copyWith].
class SfxParams {
  final SfxWave wave;
  final NoiseColor noiseColor;

  // Envelope (seconds; `punch` is a 0..1 gain boost during sustain).
  final double attack;
  final double sustain;
  final double punch;
  final double decay;

  // Pitch.
  final double baseFreq; // Hz
  final double freqRamp; // Hz per second (slide)
  final double vibStrength; // 0..1
  final double vibSpeed; // Hz
  final double arpMod; // pitch × factor after arpTime (1 = none)
  final double arpTime; // seconds

  // Timbre.
  final double duty; // 0..1 (square)
  final double dutyRamp; // per second
  final double retrigger; // Hz (0 = off)

  // Filters (one-pole).
  final double lpf; // 0..1 (1 = fully open)
  final double hpf; // 0..1 (0 = off)

  // Extras.
  final double fmFreq;
  final double fmDepth;
  final double subBass; // 0..1
  final double ringModFreq;
  final double ringModDepth; // 0..1
  final double distortion; // 0..1
  final double bitCrush; // 0..1
  final double chorus; // 0..1 depth
  final double delayTime; // seconds
  final double delayFeedback; // 0..1
  final double flanger; // 0..1 depth
  final double volume; // master 0..1

  const SfxParams({
    this.wave = SfxWave.square,
    this.noiseColor = NoiseColor.white,
    this.attack = 0.0,
    this.sustain = 0.1,
    this.punch = 0.0,
    this.decay = 0.2,
    this.baseFreq = 440,
    this.freqRamp = 0,
    this.vibStrength = 0,
    this.vibSpeed = 0,
    this.arpMod = 1,
    this.arpTime = 0,
    this.duty = 0.5,
    this.dutyRamp = 0,
    this.retrigger = 0,
    this.lpf = 1,
    this.hpf = 0,
    this.fmFreq = 0,
    this.fmDepth = 0,
    this.subBass = 0,
    this.ringModFreq = 0,
    this.ringModDepth = 0,
    this.distortion = 0,
    this.bitCrush = 0,
    this.chorus = 0,
    this.delayTime = 0,
    this.delayFeedback = 0,
    this.flanger = 0,
    this.volume = 0.6,
  });

  SfxParams copyWith(Map<String, dynamic> changes) =>
      SfxParams.fromJson({...toJson(), ...changes});

  Map<String, dynamic> toJson() => {
        'wave': wave.index,
        'noiseColor': noiseColor.index,
        'attack': attack,
        'sustain': sustain,
        'punch': punch,
        'decay': decay,
        'baseFreq': baseFreq,
        'freqRamp': freqRamp,
        'vibStrength': vibStrength,
        'vibSpeed': vibSpeed,
        'arpMod': arpMod,
        'arpTime': arpTime,
        'duty': duty,
        'dutyRamp': dutyRamp,
        'retrigger': retrigger,
        'lpf': lpf,
        'hpf': hpf,
        'fmFreq': fmFreq,
        'fmDepth': fmDepth,
        'subBass': subBass,
        'ringModFreq': ringModFreq,
        'ringModDepth': ringModDepth,
        'distortion': distortion,
        'bitCrush': bitCrush,
        'chorus': chorus,
        'delayTime': delayTime,
        'delayFeedback': delayFeedback,
        'flanger': flanger,
        'volume': volume,
      };

  factory SfxParams.fromJson(Map<String, dynamic> j) {
    double d(String k, double dflt) => (j[k] as num?)?.toDouble() ?? dflt;
    int i(String k, int dflt) => (j[k] as num?)?.toInt() ?? dflt;
    return SfxParams(
      wave: SfxWave.values[i('wave', 0).clamp(0, SfxWave.values.length - 1)],
      noiseColor: NoiseColor
          .values[i('noiseColor', 0).clamp(0, NoiseColor.values.length - 1)],
      attack: d('attack', 0),
      sustain: d('sustain', 0.1),
      punch: d('punch', 0),
      decay: d('decay', 0.2),
      baseFreq: d('baseFreq', 440),
      freqRamp: d('freqRamp', 0),
      vibStrength: d('vibStrength', 0),
      vibSpeed: d('vibSpeed', 0),
      arpMod: d('arpMod', 1),
      arpTime: d('arpTime', 0),
      duty: d('duty', 0.5),
      dutyRamp: d('dutyRamp', 0),
      retrigger: d('retrigger', 0),
      lpf: d('lpf', 1),
      hpf: d('hpf', 0),
      fmFreq: d('fmFreq', 0),
      fmDepth: d('fmDepth', 0),
      subBass: d('subBass', 0),
      ringModFreq: d('ringModFreq', 0),
      ringModDepth: d('ringModDepth', 0),
      distortion: d('distortion', 0),
      bitCrush: d('bitCrush', 0),
      chorus: d('chorus', 0),
      delayTime: d('delayTime', 0),
      delayFeedback: d('delayFeedback', 0),
      flanger: d('flanger', 0),
      volume: d('volume', 0.6),
    );
  }

  /// A URL-safe base64 share token (base64 of the JSON) — same idea as
  /// crispfxr's `?sound=` links.
  String get shareToken => base64Url.encode(utf8.encode(jsonEncode(toJson())));

  static SfxParams? fromShareToken(String token) {
    try {
      final json = jsonDecode(utf8.decode(base64Url.decode(token)));
      return SfxParams.fromJson(json as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Linearly interpolates numeric params toward [other] by [t] (0..1); the
  /// discrete wave/noise pick snaps at the midpoint. Powers A/B morphing.
  SfxParams morph(SfxParams other, double t) {
    final u = t.clamp(0.0, 1.0);
    final a = toJson();
    final b = other.toJson();
    final out = <String, dynamic>{};
    for (final k in a.keys) {
      if (k == 'wave' || k == 'noiseColor') {
        out[k] = u < 0.5 ? a[k] : b[k];
      } else {
        out[k] = (a[k] as num) * (1 - u) + (b[k] as num) * u;
      }
    }
    return SfxParams.fromJson(out);
  }
}

/// The playful clamps a mutate/randomize stays within.
const _ranges = <String, (double, double)>{
  'attack': (0, 0.4),
  'sustain': (0.02, 0.6),
  'punch': (0, 1),
  'decay': (0.02, 0.8),
  'baseFreq': (60, 2000),
  'freqRamp': (-4000, 4000),
  'vibStrength': (0, 0.8),
  'vibSpeed': (0, 30),
  'arpMod': (0.5, 2),
  'arpTime': (0, 0.3),
  'duty': (0.05, 0.95),
  'dutyRamp': (-0.5, 0.5),
  'retrigger': (0, 40),
  'lpf': (0.1, 1),
  'hpf': (0, 0.5),
  'fmFreq': (0, 400),
  'fmDepth': (0, 0.8),
  'subBass': (0, 0.8),
  'ringModFreq': (0, 500),
  'ringModDepth': (0, 0.8),
  'distortion': (0, 0.8),
  'bitCrush': (0, 0.8),
  'chorus': (0, 0.6),
  'delayTime': (0, 0.4),
  'delayFeedback': (0, 0.7),
  'flanger': (0, 0.6),
  'volume': (0.3, 0.9),
};

/// Nudges each *unlocked* numeric param by ±[amount] of its range. Deterministic
/// for a given [seed].
SfxParams mutate(
  SfxParams p, {
  int seed = 0,
  double amount = 0.15,
  Set<String> locked = const {},
}) {
  final rng = math.Random(seed);
  final j = p.toJson();
  for (final entry in _ranges.entries) {
    final k = entry.key;
    if (locked.contains(k)) continue;
    final (lo, hi) = entry.value;
    final delta = (rng.nextDouble() * 2 - 1) * amount * (hi - lo);
    j[k] = ((j[k] as num) + delta).clamp(lo, hi);
  }
  return SfxParams.fromJson(j);
}

/// A fully random sound (respecting [locked] params). Deterministic per [seed].
SfxParams randomize(
  SfxParams base, {
  int seed = 0,
  Set<String> locked = const {},
}) {
  final rng = math.Random(seed);
  final j = base.toJson();
  if (!locked.contains('wave')) j['wave'] = rng.nextInt(SfxWave.values.length);
  for (final entry in _ranges.entries) {
    final k = entry.key;
    if (locked.contains(k)) continue;
    final (lo, hi) = entry.value;
    j[k] = lo + rng.nextDouble() * (hi - lo);
  }
  return SfxParams.fromJson(j);
}

/// Named starter presets (fixed, tuned recipes; use [mutate]/[randomize] for
/// variety). Keys drive the Sound Lab's preset chips.
const Map<String, SfxParams> kSfxPresets = {
  'coin': SfxParams(
    baseFreq: 900,
    sustain: 0.02,
    punch: 0.3,
    decay: 0.28,
    arpMod: 1.5,
    arpTime: 0.05,
    duty: 0.35,
  ),
  'laser': SfxParams(
    wave: SfxWave.sawtooth,
    baseFreq: 1200,
    freqRamp: -2600,
    sustain: 0.05,
    lpf: 0.9,
  ),
  'explosion': SfxParams(
    wave: SfxWave.noise,
    baseFreq: 300,
    freqRamp: -300,
    sustain: 0.15,
    punch: 0.6,
    decay: 0.5,
    lpf: 0.6,
    distortion: 0.3,
  ),
  'powerUp': SfxParams(
    baseFreq: 500,
    freqRamp: 1400,
    decay: 0.25,
    vibStrength: 0.2,
    vibSpeed: 12,
    duty: 0.4,
  ),
  'hit': SfxParams(
    wave: SfxWave.noise,
    baseFreq: 400,
    freqRamp: -600,
    sustain: 0.03,
    decay: 0.12,
    lpf: 0.7,
  ),
  'jump': SfxParams(
    baseFreq: 460,
    freqRamp: 900,
    sustain: 0.06,
    decay: 0.12,
  ),
  'blip': SfxParams(
    wave: SfxWave.sine,
    baseFreq: 900,
    sustain: 0.02,
    decay: 0.06,
  ),
  'zap': SfxParams(
    wave: SfxWave.sawtooth,
    baseFreq: 700,
    freqRamp: -1200,
    sustain: 0.04,
    decay: 0.14,
    ringModFreq: 120,
    ringModDepth: 0.4,
  ),
  'powerDown': SfxParams(
    baseFreq: 700,
    freqRamp: -900,
    sustain: 0.12,
    decay: 0.3,
    duty: 0.4,
  ),
  'click': SfxParams(
    baseFreq: 1200,
    sustain: 0.005,
    decay: 0.03,
  ),
};

double _log10(double x) => math.log(x) / math.ln10;

/// Renders [p] to mono PCM (`Float64List`, −1..1) at [sampleRate].
Float64List sfxRender(SfxParams p, {double sampleRate = 44100}) {
  final sr = sampleRate <= 0 ? 44100.0 : sampleRate;
  final envLen = math.max(0.001, p.attack + p.sustain + p.decay);
  final total = (envLen * sr).ceil();
  final out = Float64List(total);

  final attackN = (p.attack * sr).round();
  final sustainN = (p.sustain * sr).round();

  // Effect state.
  final chorusBuf = Float64List((0.03 * sr).ceil() + 2); // 30 ms
  var chorusW = 0;
  final delayBuf = Float64List((math.max(0.001, p.delayTime) * sr).ceil() + 2);
  var delayW = 0;
  final flangeBuf = Float64List((0.01 * sr).ceil() + 2); // 10 ms
  var flangeW = 0;
  var lpfPrev = 0.0, hpfPrev = 0.0, hpfInPrev = 0.0;
  var pink0 = 0.0, pink1 = 0.0, pink2 = 0.0, brown = 0.0;

  var phase = 0.0; // main oscillator phase (cycles)
  var subPhase = 0.0;
  var freq = p.baseFreq;
  var duty = p.duty;
  final rng = math.Random(1);

  for (var i = 0; i < total; i++) {
    final t = i / sr;

    // Envelope.
    double env;
    if (i < attackN) {
      env = attackN == 0 ? 1 : i / attackN;
    } else if (i < attackN + sustainN) {
      env = 1 + p.punch * (1 - (i - attackN) / math.max(1, sustainN));
    } else {
      final d = total - (attackN + sustainN);
      env = d <= 0 ? 0 : 1 - (i - attackN - sustainN) / d;
    }
    env = env.clamp(0.0, 2.0);

    // Pitch: slide + vibrato + FM + arpeggio.
    freq += p.freqRamp / sr;
    var f = freq;
    if (p.vibStrength > 0) {
      f *= 1 + p.vibStrength * 0.1 * math.sin(2 * math.pi * p.vibSpeed * t);
    }
    if (p.fmDepth > 0) {
      f += p.fmDepth * 100 * math.sin(2 * math.pi * p.fmFreq * t);
    }
    if (p.arpMod != 1 && p.arpTime > 0 && t >= p.arpTime) {
      f *= p.arpMod;
    }
    f = f.clamp(1.0, sr / 2);

    // Oscillator.
    phase += f / sr;
    phase -= phase.floor();
    duty = (duty + p.dutyRamp / sr).clamp(0.02, 0.98);
    double s;
    switch (p.wave) {
      case SfxWave.square:
        s = phase < duty ? 1 : -1;
      case SfxWave.sawtooth:
        s = 2 * phase - 1;
      case SfxWave.sine:
        s = math.sin(2 * math.pi * phase);
      case SfxWave.noise:
        final white = rng.nextDouble() * 2 - 1;
        switch (p.noiseColor) {
          case NoiseColor.white:
            s = white;
          case NoiseColor.pink:
            pink0 = 0.99765 * pink0 + white * 0.0990460;
            pink1 = 0.96300 * pink1 + white * 0.2965164;
            pink2 = 0.57000 * pink2 + white * 1.0526913;
            s = (pink0 + pink1 + pink2 + white * 0.1848) / 3.5;
          case NoiseColor.brown:
            brown = (brown + 0.02 * white).clamp(-1.0, 1.0);
            s = brown * 3.5;
        }
    }

    // Sub-bass (half-frequency sine).
    if (p.subBass > 0) {
      subPhase += 0.5 * f / sr;
      s += p.subBass * 0.5 * math.sin(2 * math.pi * subPhase);
    }
    // Ring mod.
    if (p.ringModDepth > 0) {
      s *= 1 -
          p.ringModDepth +
          p.ringModDepth * math.sin(2 * math.pi * p.ringModFreq * t);
    }

    // One-pole LPF then HPF.
    if (p.lpf < 1) {
      lpfPrev = s * p.lpf + (1 - p.lpf) * lpfPrev;
      s = lpfPrev;
    }
    if (p.hpf > 0) {
      final y = s - hpfInPrev + (1 - p.hpf) * hpfPrev;
      hpfInPrev = s;
      hpfPrev = y;
      s = y;
    }

    // Distortion (tanh soft-clip) + bit-crush.
    if (p.distortion > 0) {
      final k = 1 + p.distortion * 10;
      s = _tanh(s * k) / _tanh(k);
    }
    if (p.bitCrush > 0) {
      final bits = (16 - p.bitCrush * 15).floor().clamp(1, 16);
      final levels = math.pow(2, bits).toDouble();
      s = (s * levels).round() / levels;
    }

    // Chorus / flanger / delay (circular buffers).
    if (p.chorus > 0) {
      chorusBuf[chorusW] = s;
      final depth = p.chorus * 0.01 * sr;
      final read =
          chorusW - (depth * (1 + math.sin(2 * math.pi * 1.5 * t)) / 2).round();
      s += chorusBuf[read % chorusBuf.length] * p.chorus * 0.3;
      chorusW = (chorusW + 1) % chorusBuf.length;
    }
    if (p.flanger > 0) {
      flangeBuf[flangeW] = s;
      final depth = p.flanger * 0.005 * sr;
      final read =
          flangeW - (depth * (1 + math.sin(2 * math.pi * 0.5 * t)) / 2).round();
      s += flangeBuf[read % flangeBuf.length] * 0.5;
      flangeW = (flangeW + 1) % flangeBuf.length;
    }
    if (p.delayTime > 0 && p.delayFeedback > 0) {
      final delayed = delayBuf[delayW];
      s += delayed * p.delayFeedback * 0.5;
      delayBuf[delayW] = s;
      delayW = (delayW + 1) % delayBuf.length;
    }

    // Retrigger: hard re-attack at the retrigger rate.
    var e = env;
    if (p.retrigger > 0) {
      final period = sr / p.retrigger;
      e *= 1 - (i % period) / period;
    }

    out[i] = (s * e * p.volume).clamp(-1.0, 1.0);
  }
  return out;
}

double _tanh(double x) {
  final e2 = math.exp(2 * x);
  return (e2 - 1) / (e2 + 1);
}

/// Peak dBFS of a rendered buffer (for meters/tests).
double sfxPeakDb(Float64List pcm) {
  var peak = 0.0;
  for (final v in pcm) {
    peak = math.max(peak, v.abs());
  }
  return 20 * _log10(peak + 1e-12);
}
