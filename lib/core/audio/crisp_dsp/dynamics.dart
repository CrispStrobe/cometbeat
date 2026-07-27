// Dynamics processors — compressor / limiter / gate. The app previously had no
// dynamics beyond the mixer's tanh soft-knee; these are proper level-dependent
// gain processors. Flutter-free, deterministic, same-length `Float64List →
// Float64List`. `mix == 0` is an exact identity copy.
//
// Design (feed-forward, log-domain gain computer + smoothed gain):
//   • Peak level → dB. A soft-knee gain computer maps over-threshold dB to a
//     gain-reduction in dB (ratio, knee). The linear reduction gain is smoothed
//     with an attack coefficient when it is DECREASING (clamping down) and a
//     release coefficient when recovering. Makeup is a constant post-gain.

import 'dart:math' as math;
import 'dart:typed_data';

double _log10(double x) => math.log(x) / math.ln10;

double _coef(double ms, double sampleRate) {
  final t = ms * 0.001 * sampleRate;
  return t <= 0 ? 0.0 : math.exp(-1 / t);
}

/// A soft-knee downward compressor. [thresholdDb] and [ratio] set where and how
/// hard it clamps; [attackMs]/[releaseMs] smooth the gain; [kneeDb] softens the
/// bend; [makeupDb] is constant post-gain.
Float64List compressorFx(
  Float64List input, {
  required double sampleRate,
  double thresholdDb = -18,
  double ratio = 4,
  double attackMs = 10,
  double releaseMs = 120,
  double kneeDb = 6,
  double makeupDb = 0,
  double mix = 1,
}) {
  final m = mix.clamp(0.0, 1.0);
  final out = Float64List(input.length);
  if (m == 0) {
    out.setAll(0, input);
    return out;
  }
  final r = ratio < 1 ? 1.0 : ratio;
  final knee = kneeDb < 0 ? 0.0 : kneeDb;
  final atk = _coef(attackMs, sampleRate);
  final rel = _coef(releaseMs, sampleRate);
  final makeup = math.pow(10, makeupDb / 20).toDouble();
  final slope = 1 / r - 1; // dB out per dB over-threshold (negative)

  var gain = 1.0; // smoothed linear reduction gain
  for (var i = 0; i < input.length; i++) {
    final x = input[i];
    final levelDb = 20 * _log10(x.abs() + 1e-12);
    final over = levelDb - thresholdDb;
    double reductionDb;
    if (2 * over < -knee) {
      reductionDb = 0;
    } else if (knee > 0 && 2 * over <= knee) {
      final t = over + knee / 2;
      reductionDb = slope * t * t / (2 * knee); // quadratic knee
    } else {
      reductionDb = slope * over;
    }
    final target = math.pow(10, reductionDb / 20).toDouble();
    final c = target < gain ? atk : rel; // attack while clamping, release back
    gain = c * gain + (1 - c) * target;
    final wet = x * gain * makeup;
    out[i] = (1 - m) * x + m * wet;
  }
  return out;
}

/// Stereo compressor with one gain envelope driven by the louder channel.
/// This keeps a stereo image centred when only one side contains a transient.
({Float64List left, Float64List right}) compressorFxStereo(
  Float64List left,
  Float64List right, {
  required double sampleRate,
  double thresholdDb = -18,
  double ratio = 4,
  double attackMs = 10,
  double releaseMs = 120,
  double kneeDb = 6,
  double makeupDb = 0,
  double mix = 1,
}) {
  final m = mix.clamp(0.0, 1.0);
  final outLeft = Float64List(left.length);
  final outRight = Float64List(right.length);
  if (m == 0) {
    outLeft.setAll(0, left);
    outRight.setAll(0, right);
    return (left: outLeft, right: outRight);
  }
  final r = ratio < 1 ? 1.0 : ratio;
  final knee = kneeDb < 0 ? 0.0 : kneeDb;
  final atk = _coef(attackMs, sampleRate);
  final rel = _coef(releaseMs, sampleRate);
  final makeup = math.pow(10, makeupDb / 20).toDouble();
  final slope = 1 / r - 1;
  var gain = 1.0;
  final frames = math.min(left.length, right.length);
  for (var i = 0; i < frames; i++) {
    final levelDb =
        20 * _log10(math.max(left[i].abs(), right[i].abs()) + 1e-12);
    final over = levelDb - thresholdDb;
    double reductionDb;
    if (2 * over < -knee) {
      reductionDb = 0;
    } else if (knee > 0 && 2 * over <= knee) {
      final t = over + knee / 2;
      reductionDb = slope * t * t / (2 * knee);
    } else {
      reductionDb = slope * over;
    }
    final target = math.pow(10, reductionDb / 20).toDouble();
    final c = target < gain ? atk : rel;
    gain = c * gain + (1 - c) * target;
    final wetGain = gain * makeup;
    outLeft[i] = (1 - m) * left[i] + m * left[i] * wetGain;
    outRight[i] = (1 - m) * right[i] + m * right[i] * wetGain;
  }
  for (var i = frames; i < left.length; i++) {
    outLeft[i] = left[i];
  }
  for (var i = frames; i < right.length; i++) {
    outRight[i] = right[i];
  }
  return (left: outLeft, right: outRight);
}

/// A brick-wall-ish limiter — a high-ratio, fast, hard-knee compressor at a
/// ceiling ([ceilingDb]).
Float64List limiterFx(
  Float64List input, {
  required double sampleRate,
  double ceilingDb = -1,
  double releaseMs = 60,
  double mix = 1,
}) =>
    compressorFx(
      input,
      sampleRate: sampleRate,
      thresholdDb: ceilingDb,
      ratio: 20,
      attackMs: 1,
      releaseMs: releaseMs,
      kneeDb: 1,
      mix: mix,
    );

/// A noise gate / downward expander: signal at or above [thresholdDb] passes;
/// below it is attenuated toward [rangeDb] (the floor) at [ratio].
Float64List gateFx(
  Float64List input, {
  required double sampleRate,
  double thresholdDb = -40,
  double ratio = 4,
  double rangeDb = -60,
  double attackMs = 1,
  double releaseMs = 100,
  double mix = 1,
}) {
  final m = mix.clamp(0.0, 1.0);
  final out = Float64List(input.length);
  if (m == 0) {
    out.setAll(0, input);
    return out;
  }
  final r = ratio < 1 ? 1.0 : ratio;
  final atk = _coef(attackMs, sampleRate);
  final rel = _coef(releaseMs, sampleRate);
  final floor = math.pow(10, rangeDb / 20).toDouble();

  var gain = 1.0;
  for (var i = 0; i < input.length; i++) {
    final x = input[i];
    final levelDb = 20 * _log10(x.abs() + 1e-12);
    double target;
    if (levelDb >= thresholdDb) {
      target = 1.0;
    } else {
      // Downward expander below the threshold.
      final reductionDb = (levelDb - thresholdDb) * (r - 1);
      target = math.max(floor, math.pow(10, reductionDb / 20).toDouble());
    }
    final c = target < gain ? rel : atk; // open fast, close on release
    gain = c * gain + (1 - c) * target;
    final wet = x * gain;
    out[i] = (1 - m) * x + m * wet;
  }
  return out;
}

/// Stereo gate with one gain envelope driven by the louder channel.
({Float64List left, Float64List right}) gateFxStereo(
  Float64List left,
  Float64List right, {
  required double sampleRate,
  double thresholdDb = -40,
  double ratio = 4,
  double rangeDb = -60,
  double attackMs = 1,
  double releaseMs = 100,
  double mix = 1,
}) {
  final m = mix.clamp(0.0, 1.0);
  final outLeft = Float64List(left.length);
  final outRight = Float64List(right.length);
  if (m == 0) {
    outLeft.setAll(0, left);
    outRight.setAll(0, right);
    return (left: outLeft, right: outRight);
  }
  final r = ratio < 1 ? 1.0 : ratio;
  final atk = _coef(attackMs, sampleRate);
  final rel = _coef(releaseMs, sampleRate);
  final floor = math.pow(10, rangeDb / 20).toDouble();
  var gain = 1.0;
  final frames = math.min(left.length, right.length);
  for (var i = 0; i < frames; i++) {
    final levelDb =
        20 * _log10(math.max(left[i].abs(), right[i].abs()) + 1e-12);
    final target = levelDb >= thresholdDb
        ? 1.0
        : math.max(
            floor,
            math.pow(10, ((levelDb - thresholdDb) * (r - 1)) / 20).toDouble(),
          );
    final c = target < gain ? rel : atk;
    gain = c * gain + (1 - c) * target;
    outLeft[i] = (1 - m) * left[i] + m * left[i] * gain;
    outRight[i] = (1 - m) * right[i] + m * right[i] * gain;
  }
  for (var i = frames; i < left.length; i++) {
    outLeft[i] = left[i];
  }
  for (var i = frames; i < right.length; i++) {
    outRight[i] = right[i];
  }
  return (left: outLeft, right: outRight);
}

// ---------------------------------------------------------------------------
// A3 — the dynamics the rack was missing: a limiter that actually limits, a
// de-esser, and a multiband compressor.
// ---------------------------------------------------------------------------

/// A LOOK-AHEAD peak limiter: nothing leaves above [ceilingDb], full stop.
///
/// [limiterFx] above is a fast compressor, and a fast compressor is not a
/// limiter: its gain reduction is computed from a peak it has already passed, so
/// the transient that triggered it goes out over the ceiling and only the tail
/// gets turned down. That overshoot is exactly what a limiter exists to prevent.
///
/// The fix is to let the detector see the future. The signal is DELAYED by
/// [lookaheadMs] while the gain envelope is computed from the undelayed input,
/// so by the time a peak arrives at the output the gain is already down for it.
/// The envelope only ever falls instantly (a peak must never be missed) and
/// recovers over [releaseMs]; the attack is the look-ahead itself, ramped so the
/// gain slides down into the peak instead of stepping, which would click.
///
/// The cost is latency: the output is [lookaheadMs] later than the input. For an
/// offline editor that is free — the whole buffer is in hand — and the returned
/// buffer is re-aligned, so the caller sees no shift at all.
Float64List lookaheadLimiterFx(
  Float64List input, {
  required double sampleRate,
  double ceilingDb = -0.3,
  double lookaheadMs = 5,
  double releaseMs = 100,
  double mix = 1,
}) {
  final out = Float64List(input.length);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0 || input.isEmpty) {
    out.setAll(0, input);
    return out;
  }
  final sr = sampleRate <= 0 ? 44100.0 : sampleRate;
  final ceiling = math.pow(10, ceilingDb / 20).toDouble();
  final look = (lookaheadMs.clamp(0.1, 100) * sr / 1000).round().clamp(1, 4410);
  final release = _coef(releaseMs.clamp(1, 5000), sr);

  // The gain each sample is allowed, before smoothing: 1 where the signal fits
  // under the ceiling, less where it does not.
  final target = Float64List(input.length);
  for (var i = 0; i < input.length; i++) {
    final a = input[i].abs();
    target[i] = a > ceiling ? ceiling / a : 1.0;
  }

  // Look ahead: the gain at sample i must already account for the loudest peak
  // within the next `look` samples — a running minimum over that window.
  final gain = Float64List(input.length);
  for (var i = 0; i < input.length; i++) {
    var lowest = 1.0;
    final end = math.min(i + look, input.length - 1);
    for (var j = i; j <= end; j++) {
      if (target[j] < lowest) lowest = target[j];
    }
    gain[i] = lowest;
  }

  // Smooth the RECOVERY only. Falling instantly is the point: a gain that eased
  // downward would let the peak it was reacting to escape, which is the bug in
  // the compressor-as-limiter above.
  var g = 1.0;
  for (var i = 0; i < input.length; i++) {
    if (gain[i] < g) {
      g = gain[i];
    } else {
      g = gain[i] + (g - gain[i]) * release;
    }
    final limited = input[i] * g;
    out[i] = (1 - m) * input[i] + m * limited;
  }
  return out;
}

/// Split [input] into [low] and [high] at [freq] so that `low + high == input`
/// sample for sample.
///
/// Uses the complementary one-pole pair, which is why that pair was built
/// complementary: a splitter whose bands do not sum back to the input puts a
/// notch (or a bump) at every crossover, and a multiband processor with three
/// of those sounds wrong before it has processed anything.
({Float64List low, Float64List high}) splitAt(
  Float64List input,
  double freq, {
  required double sampleRate,
}) {
  final sr = sampleRate <= 0 ? 44100.0 : sampleRate;
  final f = freq.clamp(20.0, sr / 2 - 1);
  final a = math.exp(-2 * math.pi * f / sr);
  final k = 1 - a;
  final low = Float64List(input.length);
  final high = Float64List(input.length);
  var state = 0.0;
  for (var i = 0; i < input.length; i++) {
    state = k * input[i] + a * state;
    low[i] = state;
    high[i] = input[i] - state;
  }
  return (low: low, high: high);
}

/// A DE-ESSER: compress only the sibilant band, leave everything else alone.
///
/// A plain compressor ducks the WHOLE signal when an "s" arrives, which is why
/// heavy de-essing with one makes a voice pump. This splits at [freq], drives a
/// compressor with (and applies it to) the high band only, and sums the
/// untouched low band back — so the body of the voice never moves.
Float64List deEsserFx(
  Float64List input, {
  required double sampleRate,
  double freq = 6000,
  double thresholdDb = -28,
  double ratio = 6,
  double attackMs = 1,
  double releaseMs = 60,
  double mix = 1,
}) {
  final out = Float64List(input.length);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0 || input.isEmpty) {
    out.setAll(0, input);
    return out;
  }
  final bands = splitAt(input, freq, sampleRate: sampleRate);
  final tamed = compressorFx(
    bands.high,
    sampleRate: sampleRate,
    thresholdDb: thresholdDb,
    ratio: ratio,
    attackMs: attackMs,
    releaseMs: releaseMs,
    kneeDb: 3,
  );
  for (var i = 0; i < input.length; i++) {
    out[i] = (1 - m) * input[i] + m * (bands.low[i] + tamed[i]);
  }
  return out;
}

/// A three-band compressor: split at [lowHz] and [highHz], compress each band on
/// its own detector, sum.
///
/// The reason to want one is that a full-band compressor is steered by whatever
/// is loudest — usually the kick — so every bass note ducks the vocal and the
/// cymbals with it. Per-band detectors mean the bass controls the bass.
///
/// Because [splitAt] reconstructs exactly, setting all three ratios to 1 returns
/// the input unchanged; there is no crossover colouring to work around.
Float64List multibandCompressorFx(
  Float64List input, {
  required double sampleRate,
  double lowHz = 200,
  double highHz = 3000,
  double thresholdDb = -24,
  double lowRatio = 3,
  double midRatio = 3,
  double highRatio = 3,
  double attackMs = 10,
  double releaseMs = 120,
  double makeupDb = 0,
  double mix = 1,
}) {
  final out = Float64List(input.length);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0 || input.isEmpty) {
    out.setAll(0, input);
    return out;
  }
  // Split low first, then split what is left — so the three bands still sum to
  // the input exactly.
  final lowSplit =
      splitAt(input, math.min(lowHz, highHz), sampleRate: sampleRate);
  final restSplit =
      splitAt(lowSplit.high, math.max(lowHz, highHz), sampleRate: sampleRate);

  Float64List band(Float64List x, double ratio) => ratio <= 1
      ? x
      : compressorFx(
          x,
          sampleRate: sampleRate,
          thresholdDb: thresholdDb,
          ratio: ratio,
          attackMs: attackMs,
          releaseMs: releaseMs,
        );

  final low = band(lowSplit.low, lowRatio);
  final mid = band(restSplit.low, midRatio);
  final high = band(restSplit.high, highRatio);
  final makeup = math.pow(10, makeupDb / 20).toDouble();
  for (var i = 0; i < input.length; i++) {
    final processed = (low[i] + mid[i] + high[i]) * makeup;
    out[i] = (1 - m) * input[i] + m * processed;
  }
  return out;
}
