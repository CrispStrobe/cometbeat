// Restoration — the repair tools: hiss, hum, clicks, clipping, DC.
//
// These differ from the rest of the rack in what they are FOR. A filter or a
// compressor is a creative choice; these exist to take something out of a
// recording that nobody wanted there, and the measure of success is that you
// stop noticing the tool at all. So each one here errs toward doing too little:
// an over-aggressive de-hisser leaves a warbling artefact that is more
// distracting than the hiss was, and an over-eager de-clicker eats transients.
//
// Clean-room from published theory: spectral subtraction (estimate the noise
// magnitude per frequency bin, subtract it, keep the phase), a harmonic comb of
// notches for mains hum, median-deviation outlier detection with interpolation
// for clicks, and cubic reconstruction of flat-topped peaks for clipping.
//
// The FFT is the app's own radix-2 (`chroma_analysis.dart`), reused rather than
// re-written; the inverse comes from the standard conjugate identity, so there
// is only one transform to be right about.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart' show fft;
import 'package:comet_beat/core/audio/crisp_dsp/biquad.dart';

/// Add a constant [offset] to every sample.
///
/// The inverse of removing a DC offset, and useful for the same reason a
/// deliberate one is: some analysis and some hardware wants a bias. Alone it is
/// inaudible — a constant is 0 Hz — but it eats headroom, which is why the
/// result is not clamped: an honest number is more useful than a silent clip.
Float64List dcShiftFx(
  Float64List input, {
  double offset = 0,
  double mix = 1,
}) {
  final out = Float64List(input.length);
  final m = mix.clamp(0.0, 1.0);
  for (var i = 0; i < input.length; i++) {
    out[i] = input[i] + m * offset;
  }
  return out;
}

/// Notch out mains hum: [freq] and its harmonics.
///
/// Hum is never just its fundamental — a 50 Hz mains buzz carries 100, 150, 200
/// with it, and notching only the first leaves most of what you can hear. So
/// this is a COMB: one narrow notch per harmonic up to [harmonics], each sharp
/// enough ([q]) to leave the music between them alone.
Float64List humRemoveFx(
  Float64List input, {
  required double sampleRate,
  double freq = 50,
  int harmonics = 6,
  double q = 30,
  double mix = 1,
}) {
  final out = Float64List(input.length);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0 || input.isEmpty) {
    out.setAll(0, input);
    return out;
  }
  final sr = sampleRate <= 0 ? 44100.0 : sampleRate;
  final count = harmonics.clamp(1, 20);
  final filters = <Biquad>[];
  for (var h = 1; h <= count; h++) {
    final f = freq * h;
    if (f >= sr / 2 - 1) break;
    filters.add(
      Biquad(BiquadKind.notch, freq: f, sampleRate: sr, q: q.clamp(1, 100)),
    );
  }
  for (var i = 0; i < input.length; i++) {
    var v = input[i];
    for (final filter in filters) {
      v = filter.process(v);
    }
    out[i] = (1 - m) * input[i] + m * v;
  }
  return out;
}

/// The noise magnitude per FFT bin, estimated from [input] itself.
///
/// Learned from the QUIETEST frames rather than from a marked range: for each
/// bin, the level it sits at when nothing is playing is a low percentile of its
/// level over time. That makes a one-click de-hiss possible with no extra step
/// from the user, and it is why [noiseReduceFx] takes no profile parameter.
///
/// ⚠ **This cannot tell a sustained tone from noise, and nothing of this shape
/// can.** The estimator's whole premise is that noise is what is *always* there
/// and music is what comes and goes; a drone, an organ chord or a held string
/// note is always there too, so it lands in the profile and gets subtracted as
/// hiss. On material with note attacks and gaps — most music — the premise
/// holds and this works well. On a sustained pad it will eat the pad.
///
/// That is why a profile learned from a genuinely SILENT passage is the better
/// route whenever one exists, and why this function is public: a caller with a
/// marked quiet range can pass that slice here and hand the result to
/// [noiseReduceFx], which sidesteps the guess entirely.
Float64List noiseProfile(
  Float64List input, {
  int frameSize = 2048,
  double percentile = 0.2,
}) {
  final bins = frameSize ~/ 2 + 1;
  final profile = Float64List(bins);
  if (input.length < frameSize) return profile;
  final hop = frameSize ~/ 4;
  final window = _hann(frameSize);

  final perBin = List.generate(bins, (_) => <double>[]);
  for (var start = 0; start + frameSize <= input.length; start += hop) {
    final re = Float64List(frameSize);
    final im = Float64List(frameSize);
    for (var i = 0; i < frameSize; i++) {
      re[i] = input[start + i] * window[i];
    }
    fft(re, im);
    for (var b = 0; b < bins; b++) {
      perBin[b].add(math.sqrt(re[b] * re[b] + im[b] * im[b]));
    }
  }
  final p = percentile.clamp(0.01, 0.9);
  for (var b = 0; b < bins; b++) {
    final values = perBin[b]..sort();
    if (values.isEmpty) continue;
    profile[b] =
        values[(values.length * p).floor().clamp(0, values.length - 1)];
  }
  return profile;
}

/// Spectral noise reduction: subtract a noise floor, keep the music.
///
/// Every frame is transformed, the estimated noise magnitude for each bin is
/// subtracted from it (scaled by [reduction], where 1 subtracts the whole
/// estimate), and the frame is put back with its PHASE untouched — phase is what
/// makes a transient a transient, and re-estimating it is what makes bad noise
/// reduction sound underwater.
///
/// [floorAmount] is what stops it sounding worse than the hiss did. Subtracting
/// all the way to zero in a bin makes isolated surviving bins ring in and out
/// between frames — the classic "musical noise" warble — so each bin is held at
/// a fraction of its original level instead. A small residual hiss that sits
/// still is much less distracting than a quiet one that shimmers.
///
/// Pass [profile] to use a noise fingerprint learned elsewhere (a marked silent
/// range); omit it and one is estimated from [input] itself via [noiseProfile]
/// — which is convenient but cannot distinguish a SUSTAINED tone from noise.
/// See [noiseProfile] for why, and prefer a learned profile when there is a
/// quiet passage to learn from.
Float64List noiseReduceFx(
  Float64List input, {
  Float64List? profile,
  double reduction = 1,
  double floorAmount = 0.06,
  int frameSize = 2048,
  double mix = 1,
}) {
  final out = Float64List(input.length);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0 || input.length < frameSize) {
    out.setAll(0, input);
    return out;
  }
  // A power of two is required by the FFT; round down to the nearest one.
  var n = 1;
  while (n * 2 <= frameSize) {
    n *= 2;
  }
  final noise = profile ?? noiseProfile(input, frameSize: n);
  final hop = n ~/ 4;
  final window = _hann(n);
  final wet = Float64List(input.length);
  final weight = Float64List(input.length);
  final over = reduction.clamp(0.0, 4.0);
  final floor = floorAmount.clamp(0.0, 1.0);

  for (var start = 0; start + n <= input.length; start += hop) {
    final re = Float64List(n);
    final im = Float64List(n);
    for (var i = 0; i < n; i++) {
      re[i] = input[start + i] * window[i];
    }
    fft(re, im);

    final bins = n ~/ 2 + 1;
    for (var b = 0; b < bins; b++) {
      final magnitude = math.sqrt(re[b] * re[b] + im[b] * im[b]);
      if (magnitude <= 1e-20) continue;
      final estimate = b < noise.length ? noise[b] * over : 0.0;
      final reduced = math.max(magnitude - estimate, magnitude * floor);
      final scale = reduced / magnitude;
      re[b] *= scale;
      im[b] *= scale;
      // Keep the spectrum conjugate-symmetric so the inverse is real.
      if (b > 0 && b < n - b) {
        re[n - b] *= scale;
        im[n - b] *= scale;
      }
    }

    _ifft(re, im);
    for (var i = 0; i < n; i++) {
      wet[start + i] += re[i] * window[i];
      weight[start + i] += window[i] * window[i];
    }
  }

  for (var i = 0; i < input.length; i++) {
    final w = weight[i];
    final value = w > 1e-9 ? wet[i] / w : input[i];
    out[i] = (1 - m) * input[i] + m * value;
  }
  return out;
}

/// Repair clicks and crackle: find samples that jump further than their
/// neighbourhood plausibly can, and interpolate across them.
///
/// A click is a discontinuity, so it shows up in the DIFFERENCE between
/// consecutive samples rather than in their level — which is what lets a quiet
/// click on a loud passage be found at all. A sample whose step exceeds
/// [sensitivity] times the local median step is treated as damaged and replaced
/// by a line across the gap.
///
/// The median is what keeps it from eating music: a mean step would be dragged
/// up by the very click being looked for, so every loud transient would look
/// normal beside it and every quiet passage would look damaged.
Float64List declickFx(
  Float64List input, {
  double sensitivity = 8,
  int window = 64,
  double mix = 1,
}) {
  final out = Float64List(input.length)..setAll(0, input);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0 || input.length < 4) return out;
  final threshold = sensitivity.clamp(2.0, 50.0);
  final half = window.clamp(8, 512) ~/ 2;

  final steps = Float64List(input.length);
  for (var i = 1; i < input.length; i++) {
    steps[i] = (input[i] - input[i - 1]).abs();
  }

  for (var i = 2; i < input.length - 2; i++) {
    final from = math.max(1, i - half);
    final to = math.min(input.length - 1, i + half);
    final local = <double>[];
    for (var j = from; j < to; j++) {
      local.add(steps[j]);
    }
    if (local.isEmpty) continue;
    local.sort();
    final median = local[local.length ~/ 2];
    if (median <= 1e-12) continue;
    if (steps[i] > median * threshold) {
      // Bridge the damaged sample from its neighbours.
      final repaired = (out[i - 1] + input[i + 1]) / 2;
      out[i] = (1 - m) * input[i] + m * repaired;
    }
  }
  return out;
}

/// Rebuild the tops of clipped peaks.
///
/// A clipped peak is a run of samples pinned at (or just under) full scale where
/// a curve used to be. This finds those runs and replaces each with an arc that
/// leaves and rejoins the waveform at the slope it had going in — so the peak
/// gets its shape back instead of its corner.
///
/// It cannot know how tall the peak really was; the arc's height is inferred
/// from how long the flat run is, which is the only evidence there is. That
/// makes this a plausible reconstruction, not a recovery, and the doc says so
/// because the difference matters when someone is deciding whether to re-record.
Float64List declipFx(
  Float64List input, {
  double threshold = 0.95,
  double strength = 1,
  double mix = 1,
}) {
  final out = Float64List(input.length)..setAll(0, input);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0 || input.length < 3) return out;
  final limit = threshold.clamp(0.1, 1.0);
  final amount = strength.clamp(0.0, 2.0);

  var i = 0;
  while (i < input.length) {
    if (input[i].abs() < limit) {
      i++;
      continue;
    }
    // A run of pinned samples, all on the same side.
    final sign = input[i] >= 0 ? 1.0 : -1.0;
    var end = i;
    while (end < input.length &&
        input[end].abs() >= limit &&
        (input[end] >= 0 ? 1.0 : -1.0) == sign) {
      end++;
    }
    final runLength = end - i;
    // A single sample at the ceiling is a peak that just touched, not a clip.
    if (runLength >= 2) {
      // The longer the flat, the more of the peak went missing.
      final height = limit * (1 + 0.15 * amount * math.min(runLength, 16) / 4);
      for (var j = i; j < end; j++) {
        // A half-cycle arc across the run: 0 at the edges, tallest in the
        // middle, so it rejoins the surviving waveform smoothly.
        final t = (j - i + 0.5) / runLength;
        final arc = math.sin(t * math.pi);
        final rebuilt = sign * (limit + (height - limit) * arc);
        out[j] = (1 - m) * input[j] + m * rebuilt;
      }
    }
    i = end;
  }
  return out;
}

/// A periodic Hann window of [n] samples.
Float64List _hann(int n) {
  final w = Float64List(n);
  for (var i = 0; i < n; i++) {
    w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / n);
  }
  return w;
}

/// The inverse of [fft], by the conjugate identity: conjugate, forward,
/// conjugate, scale. One transform to be right about instead of two.
void _ifft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 0; i < n; i++) {
    im[i] = -im[i];
  }
  fft(re, im);
  for (var i = 0; i < n; i++) {
    re[i] /= n;
    im[i] = -im[i] / n;
  }
}
