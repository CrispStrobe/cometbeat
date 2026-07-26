// Windowed-sinc FIR filters — the STEEP end of the filter set, plus the Hilbert
// transformer the stereo tools need.
//
// The biquads are recursive: cheap, but 12 dB/octave and non-linear in phase, so
// a low-pass moves transients around a little and cannot be made brick-wall
// without stacking sections that then ring. An FIR designed by windowing the
// ideal impulse response is the opposite trade: expensive (every output sample
// touches every tap) but arbitrarily steep and EXACTLY linear-phase — every
// frequency delayed by the same (taps−1)/2 samples, so nothing is smeared
// relative to anything else. That is what you want for removing a band from
// music you are going to keep, and it is the only honest way to offer a
// "steepness" control.
//
// Clean-room from the standard windowed-sinc design: truncate the ideal impulse
// response (a sinc for a low-pass), multiply by a Blackman window to trade
// transition width against stopband ripple, and normalise to unity passband
// gain. High-pass and band-reject come from spectral inversion, band-pass from
// the difference of two low-passes — all textbook identities, not anyone's code.
//
// The Hilbert transformer is the same machinery with the other classic kernel:
// h[n] = 2/(πn) for odd n and 0 for even n, which shifts every frequency by 90°
// while leaving magnitudes alone.
//
// Pure Dart, deterministic. Cost is O(samples × taps), which is why [kMaxFirTaps]
// exists — this is an offline editor, but a 20-minute arrangement through a
// 4000-tap filter is still not a thing anyone wants to wait for.

import 'dart:math' as math;
import 'dart:typed_data';

/// The most taps a designed filter may use.
///
/// A cap rather than a preference: taps set BOTH the steepness and the cost, and
/// the cost is linear in them, so an unbounded control is a way to make the app
/// appear to hang. 511 taps at 44.1 kHz is a transition band of roughly 200 Hz —
/// steeper than any musical use needs.
const int kMaxFirTaps = 511;

/// What shape [designWindowedSinc] should produce.
enum FirShape { lowpass, highpass, bandpass, bandreject }

/// Design a linear-phase FIR by the windowed-sinc method.
///
/// [freq] is the corner for [FirShape.lowpass]/[FirShape.highpass] and the LOWER
/// edge for the band shapes, whose upper edge is [freqHigh]. [taps] is forced
/// odd (an even-length kernel has a half-sample delay, which would make the
/// linear-phase promise awkward to keep) and clamped to [kMaxFirTaps].
///
/// The returned kernel is normalised so the passband sits at unity gain.
///
/// ⚠ Taps set the TRANSITION WIDTH, and therefore the narrowest band that can
/// actually be built: a Blackman window needs roughly `6·fs/taps` Hz to get from
/// pass to stop, which at 44.1 kHz is about 520 Hz even at the [kMaxFirTaps]
/// ceiling. Ask for a 200 Hz-wide band-pass and the two transitions overlap, so
/// the "passband" never reaches unity and the "stopband" never reaches zero.
/// That is a property of windowed FIR design, not a bug — a narrow resonant band
/// is what the biquad [BiquadKind.bandpass] with a high Q is for.
Float64List designWindowedSinc({
  required FirShape shape,
  required double sampleRate,
  required double freq,
  double freqHigh = 8000,
  int taps = 127,
}) {
  final sr = sampleRate <= 0 ? 44100.0 : sampleRate;
  final nyquist = sr / 2;
  var n = taps.clamp(3, kMaxFirTaps);
  if (n.isEven) n += 1;
  final half = (n - 1) ~/ 2;

  // Normalised cut-offs in cycles/sample, kept strictly inside (0, 0.5).
  double cut(double hz) => (hz.clamp(1.0, nyquist - 1)) / sr;
  final lowCut = cut(math.min(freq, freqHigh));
  final highCut = cut(math.max(freq, freqHigh));

  // The ideal low-pass impulse response, windowed. `sinc(0)` is its limit, 2·fc.
  Float64List lowpassKernel(double fc) {
    final kernel = Float64List(n);
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      final k = i - half;
      final ideal =
          k == 0 ? 2 * fc : math.sin(2 * math.pi * fc * k) / (math.pi * k);
      // Blackman: a wider transition than Hamming, but ~−74 dB stopband, which
      // is what makes a "remove this band" edit inaudible rather than merely
      // quiet.
      final w = 0.42 -
          0.5 * math.cos(2 * math.pi * i / (n - 1)) +
          0.08 * math.cos(4 * math.pi * i / (n - 1));
      final v = ideal * w;
      kernel[i] = v;
      sum += v;
    }
    if (sum != 0) {
      for (var i = 0; i < n; i++) {
        kernel[i] /= sum;
      }
    }
    return kernel;
  }

  /// Spectral inversion: negate the kernel and add 1 at the centre, turning a
  /// low-pass into its complement.
  Float64List invert(Float64List kernel) {
    final out = Float64List(n);
    for (var i = 0; i < n; i++) {
      out[i] = -kernel[i];
    }
    out[half] += 1;
    return out;
  }

  switch (shape) {
    case FirShape.lowpass:
      return lowpassKernel(cut(freq));
    case FirShape.highpass:
      return invert(lowpassKernel(cut(freq)));
    case FirShape.bandpass:
      // Low-pass at the upper edge minus low-pass at the lower edge.
      final wide = lowpassKernel(highCut);
      final narrow = lowpassKernel(lowCut);
      final out = Float64List(n);
      for (var i = 0; i < n; i++) {
        out[i] = wide[i] - narrow[i];
      }
      return out;
    case FirShape.bandreject:
      final wide = lowpassKernel(highCut);
      final narrow = lowpassKernel(lowCut);
      final band = Float64List(n);
      for (var i = 0; i < n; i++) {
        band[i] = wide[i] - narrow[i];
      }
      return invert(band);
  }
}

/// Convolve [input] with [kernel], compensating the filter's own delay so the
/// output lines up with the input sample for sample.
///
/// Same length as [input]. The delay compensation is what makes the result
/// mixable with the dry signal (and comparable to the biquads) rather than
/// arriving (taps−1)/2 samples late.
Float64List convolveFir(Float64List input, Float64List kernel) {
  final out = Float64List(input.length);
  if (kernel.isEmpty) {
    out.setAll(0, input);
    return out;
  }
  final half = (kernel.length - 1) ~/ 2;
  for (var i = 0; i < input.length; i++) {
    var acc = 0.0;
    for (var k = 0; k < kernel.length; k++) {
      final j = i + half - k;
      if (j >= 0 && j < input.length) acc += kernel[k] * input[j];
    }
    out[i] = acc;
  }
  return out;
}

/// A steep, linear-phase filter over [input]. `mix == 0` is an exact copy.
Float64List sincFilterFx(
  Float64List input, {
  required double sampleRate,
  FirShape shape = FirShape.lowpass,
  double freq = 1000,
  double freqHigh = 8000,
  int taps = 127,
  double mix = 1,
}) {
  final out = Float64List(input.length);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0 || input.isEmpty) {
    out.setAll(0, input);
    return out;
  }
  final kernel = designWindowedSinc(
    shape: shape,
    sampleRate: sampleRate,
    freq: freq,
    freqHigh: freqHigh,
    taps: taps,
  );
  final wet = convolveFir(input, kernel);
  for (var i = 0; i < input.length; i++) {
    out[i] = (1 - m) * input[i] + m * wet[i];
  }
  return out;
}

/// An FIR Hilbert transformer kernel of [taps] (forced odd, clamped to
/// [kMaxFirTaps]): zero on even offsets, `2/(πk)` on odd ones, Blackman-windowed.
Float64List designHilbert({int taps = 127}) {
  var n = taps.clamp(3, kMaxFirTaps);
  if (n.isEven) n += 1;
  final half = (n - 1) ~/ 2;
  final kernel = Float64List(n);
  for (var i = 0; i < n; i++) {
    final k = i - half;
    if (k == 0 || k.isEven) continue;
    final w = 0.42 -
        0.5 * math.cos(2 * math.pi * i / (n - 1)) +
        0.08 * math.cos(4 * math.pi * i / (n - 1));
    kernel[i] = 2 / (math.pi * k) * w;
  }
  return kernel;
}

/// Shift every frequency in [input] by 90° without touching its magnitudes.
///
/// Alone this is close to inaudible on most material — phase is not what the ear
/// hears in isolation — and that is exactly why it matters: it is the piece that
/// lets a signal be combined with a phase-rotated copy of itself, which is how
/// stereo widening, single-sideband shifting and out-of-phase extraction work.
///
/// [mix] blends against the DELAY-MATCHED dry signal, not the raw input, so a
/// half-and-half blend is a real 45° rotation rather than a comb filter.
Float64List hilbertFx(
  Float64List input, {
  int taps = 127,
  double mix = 1,
}) {
  final out = Float64List(input.length);
  final m = mix.clamp(0.0, 1.0);
  if (input.isEmpty) return out;
  if (m == 0) {
    out.setAll(0, input);
    return out;
  }
  // `convolveFir` already compensates the kernel's own (taps−1)/2 delay, so the
  // wet signal is aligned with the input and the dry term needs no extra delay
  // line — the two sides of the blend are the same moment in time.
  final wet = convolveFir(input, designHilbert(taps: taps));
  for (var i = 0; i < input.length; i++) {
    out[i] = (1 - m) * input[i] + m * wet[i];
  }
  return out;
}
