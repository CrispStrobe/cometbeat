// lib/core/audio/crisp_dsp/modulated_delay.dart
//
// The modulated-delay effect family — delay, chorus, flanger — for the Tracker's
// per-channel effect chain (and the Loop Mixer / SFX sends). All three share a
// fractional delay line; all are pure, deterministic, SAME-LENGTH transforms
// (`Float64List → Float64List`) so an effected channel stem still lines up for
// `mixStems`. Pure Dart, Flutter-free (tested like sample_dsp_test.dart). Drawn
// from crispaudio's effects chain (MIT). See docs/FX_HANDOVER.md #1.
//
// Conventions shared by all three:
//   • Output length == input length. Tails/echoes past the end are truncated.
//   • `mix` is the wet/dry blend in [0,1]: out = (1-mix)*dry + mix*wet. mix == 0
//     MUST return an exact copy of the dry input (identity), mix == 1 = fully wet.
//   • Deterministic: no RNG, no wall-clock. Same input+params → same output.
//   • Guard params (clamp mix to [0,1], feedback to [0, 0.95] to stay stable,
//     delay ≥ 0). Never emit NaN/Inf; keep |out| bounded.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:klang_universum/core/audio/synth.dart' show kSampleRate;

/// Linear-interpolated read of [history] at fractional index [pos]. Samples
/// before the start (pos < 0) or past the end read as 0.
double _interp(Float64List history, double pos) {
  if (pos <= 0) {
    // pos == 0 → history[0]; negative → before the buffer → 0.
    if (pos < 0) return 0;
    return history[0];
  }
  final i0 = pos.floor();
  if (i0 >= history.length) return 0;
  final frac = pos - i0;
  final a = history[i0];
  final b = (i0 + 1 < history.length) ? history[i0 + 1] : 0.0;
  return a + (b - a) * frac;
}

/// A feedback **delay** (echo) line of [delayMs], echoes decaying by [feedback].
///
/// Contract: let `D = round(delayMs * sampleRate / 1000)`. With a working line
/// `line[i] = input[i] + feedback * line[i-D]` (line[i-D] = 0 for i < D) the wet
/// signal at tap `i` is `line[i-D]`, and `out[i] = (1-mix)*input[i] + mix*line[i-D]`.
/// So an impulse at 0 yields wet peaks `mix`, `mix*feedback`, `mix*feedback²`… at
/// D, 2D, 3D. Clamp feedback to [0, 0.95].
Float64List delayFx(
  Float64List input, {
  double delayMs = 250,
  double feedback = 0.35,
  double mix = 0.35,
  int sampleRate = kSampleRate,
}) {
  final n = input.length;
  final out = Float64List(n);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0) {
    out.setAll(0, input);
    return out;
  }
  final fb = feedback.clamp(0.0, 0.95);
  final safeDelayMs = math.max(0.0, delayMs);
  final d = (safeDelayMs * sampleRate / 1000).round();
  final line = Float64List(n);
  for (var i = 0; i < n; i++) {
    final tap = (i >= d) ? line[i - d] : 0.0;
    line[i] = input[i] + fb * tap;
    out[i] = (1 - m) * input[i] + m * tap;
  }
  return out;
}

/// A **chorus**: several detuned voices via an LFO-swept short delay (~[depthMs]
/// centre, ±[depthMs] sweep at [rateHz]) read with fractional (linear) interp,
/// blended with the dry signal. Thickens a sample without a strong pitch artifact.
/// No feedback. mix == 0 → identity.
Float64List chorusFx(
  Float64List input, {
  double rateHz = 1.5,
  double depthMs = 6,
  double mix = 0.5,
  int sampleRate = kSampleRate,
}) {
  final n = input.length;
  final out = Float64List(n);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0) {
    out.setAll(0, input);
    return out;
  }
  final depth = math.max(0.0, depthMs);
  final rate = math.max(0.0, rateHz);
  final centreSamp = depth * sampleRate / 1000;
  final w = 2 * math.pi * rate / sampleRate;
  for (var i = 0; i < n; i++) {
    final delaySamples = centreSamp * (1 + math.sin(w * i));
    final wet = _interp(input, i - delaySamples);
    out[i] = (1 - m) * input[i] + m * wet;
  }
  return out;
}

/// A **flanger**: like [chorusFx] but a shorter swept delay (~[depthMs], a few ms)
/// WITH [feedback] for the classic metallic "jet" comb sweep. Fractional read,
/// LFO at [rateHz]. Clamp feedback to [0, 0.95]. mix == 0 → identity.
Float64List flangerFx(
  Float64List input, {
  double rateHz = 0.3,
  double depthMs = 3,
  double feedback = 0.5,
  double mix = 0.5,
  int sampleRate = kSampleRate,
}) {
  final n = input.length;
  final out = Float64List(n);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0) {
    out.setAll(0, input);
    return out;
  }
  final fb = feedback.clamp(0.0, 0.95);
  final depth = math.max(0.0, depthMs);
  final rate = math.max(0.0, rateHz);
  final centreSamp = depth * sampleRate / 1000;
  final w = 2 * math.pi * rate / sampleRate;
  // history holds the wet-fed signal so feedback recirculates the swept comb.
  final history = Float64List(n);
  for (var i = 0; i < n; i++) {
    final delaySamples = centreSamp * (1 + math.sin(w * i));
    final delayed = _interp(history, i - delaySamples);
    history[i] = input[i] + fb * delayed;
    out[i] = (1 - m) * input[i] + m * delayed;
  }
  return out;
}
