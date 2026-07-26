// One-pole (6 dB/octave) filters — the gentle end of the filter set.
//
// The rack already has the two-pole biquads, which are 12 dB/octave and can
// resonate. That is the wrong tool for the commonest job of all: "a bit less
// top", "a bit less mud". A two-pole low-pass audibly *removes* a band and, at
// any Q above 0.707, rings at the corner; a one-pole just tilts, which is what
// a tone control does and what gets reached for far more often.
//
// It is also the only correct shape for smoothing a control signal (an envelope
// follower, a sweep), where resonance would be a defect rather than a flavour.
//
// Clean-room from the standard bilinear one-pole design: a single feedback
// coefficient `a = exp(-2π·f/fs)`, giving `y[n] = (1-a)·x[n] + a·y[n-1]` for the
// low-pass, and input-minus-low-pass for the high-pass. Flutter-free and
// deterministic like the rest of crisp_dsp.

import 'dart:math' as math;
import 'dart:typed_data';

/// The feedback coefficient for a one-pole at [freq] on [sampleRate].
///
/// Shared by both shapes so they cannot drift apart, and clamped to a corner
/// strictly inside (0, Nyquist) so the exponential stays finite.
double onePoleCoefficient(double freq, double sampleRate) {
  final sr = sampleRate <= 0 ? 44100.0 : sampleRate;
  final f = freq.clamp(0.1, sr / 2 - 1);
  return math.exp(-2 * math.pi * f / sr);
}

/// A one-pole (6 dB/octave) LOW-pass: −3 dB at [freq], gently darker above.
/// Same length as [input]; `mix == 0` is an exact copy.
Float64List onePoleLowpassFx(
  Float64List input, {
  required double sampleRate,
  double freq = 4000,
  double mix = 1,
}) {
  final out = Float64List(input.length);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0) {
    out.setAll(0, input);
    return out;
  }
  final a = onePoleCoefficient(freq, sampleRate);
  final gain = 1 - a;
  var y = 0.0;
  for (var i = 0; i < input.length; i++) {
    y = gain * input[i] + a * y;
    out[i] = (1 - m) * input[i] + m * y;
  }
  return out;
}

/// A one-pole (6 dB/octave) HIGH-pass, cornered at [freq]: gently thinner below.
///
/// Taken as input minus the matching low-pass, so the two shapes are EXACT
/// complements: run both at one corner, sum them, and the input comes back
/// sample for sample.
///
/// That guarantee is worth a small inaccuracy elsewhere and the trade is
/// deliberate. A textbook one-pole high-pass is −3.0 dB at its corner; this one
/// measures about −3.6 dB, because the discrete low-pass it is subtracted from
/// is not exactly −3 dB there. Perfect reconstruction is the more useful
/// property — it is what lets a band-splitter (a multiband compressor, a
/// crossover) take a signal apart and put it back together without a phase or
/// level notch at the split.
Float64List onePoleHighpassFx(
  Float64List input, {
  required double sampleRate,
  double freq = 200,
  double mix = 1,
}) {
  final out = Float64List(input.length);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0) {
    out.setAll(0, input);
    return out;
  }
  final a = onePoleCoefficient(freq, sampleRate);
  final gain = 1 - a;
  var low = 0.0;
  for (var i = 0; i < input.length; i++) {
    low = gain * input[i] + a * low;
    out[i] = (1 - m) * input[i] + m * (input[i] - low);
  }
  return out;
}
