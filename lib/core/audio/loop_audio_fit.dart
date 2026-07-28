// lib/core/audio/loop_audio_fit.dart
//
// WS-L10 — fitting a recorded loop to the groove's grid.
//
// Every other stem in the Loop Studio is SYNTHESISED to the loop's length, so
// it lands on the grid by construction. A recording does not: a take that was
// meant to be two bars is 2.03 bars, because a person started it and stopped
// it. That 30 ms is the whole problem, and it is not a rounding error — the
// engine renders ONE buffer and repeats it gaplessly, so a stem that is 30 ms
// long gets 30 ms of silence (or a truncated tail) every single time round, and
// the drift is audible on the second pass.
//
// THE INVARIANT THIS PROTECTS is the one the whole engine rests on: at 75, 100
// and 120 bpm an eighth-step is a whole number of milliseconds AND a whole
// number of samples, which is what keeps every stem sample-aligned and the
// gapless seam click-free. An audio stem therefore has to be EXACTLY the loop's
// sample count — not close to it.
//
// RESAMPLE, DO NOT TILE. Tiling a 2.03-bar take to fill 2 bars repeats its
// first 30 ms at the end, which is a stutter, and looping it past the boundary
// re-phases it every cycle, which is worse. Resampling changes the playback
// SPEED, exactly as a hardware looper does, and for the small corrections this
// is actually for (a percent or two) the pitch shift is inaudible. For large
// ones it is not, which is why [audioFitRatio] is reported rather than hidden:
// a caller that stretches a take by 2× should be able to say so.
//
// Pure Dart, no Flutter.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart'
    show ResampleQuality, resampleHq;

/// How far [sourceSamples] has to be stretched to fill [targetSamples].
///
/// 1 = already exact · 2 = the take is half the loop and plays at half speed ·
/// 0.5 = the take is twice the loop and plays twice as fast. Reported so a
/// caller can warn before a fit becomes a chipmunk.
double audioFitRatio(int sourceSamples, int targetSamples) {
  if (sourceSamples <= 0 || targetSamples <= 0) return 1;
  return targetSamples / sourceSamples;
}

/// Whether a fit of [ratio] is small enough to be inaudible as a pitch change.
///
/// A couple of percent is the "I stopped recording a moment late" case and
/// nobody hears it. Beyond that the take is a different length than the loop —
/// which usually means the LOOP should change, not the audio.
bool audioFitIsSubtle(double ratio) => (ratio - 1).abs() <= 0.06;

/// [pcm] resampled to occupy exactly [targetSamples].
///
/// Exactly, not approximately: the caller mixes this against stems that are
/// sample-aligned by construction, and "one sample short" is a click at the
/// seam once per loop. `resampleHq` floors its output length, so the result is
/// padded or trimmed to the target rather than trusted.
///
/// Band-limited rather than linear, because a downward fit is a downsample and
/// a naive one folds everything above the new Nyquist back into the audible
/// band as inharmonic grit — on a drum loop that reads as a lisp on every hat.
Float64List fitAudioToLoop(
  Float64List pcm,
  int targetSamples, {
  ResampleQuality quality = ResampleQuality.good,
}) {
  if (targetSamples <= 0) return Float64List(0);
  // Silence of the right length, so an empty take is a silent track rather
  // than a stem the mixer has to special-case.
  if (pcm.isEmpty) return Float64List(targetSamples);
  if (pcm.length == targetSamples) return pcm;

  final resampled = resampleHq(
    pcm,
    fromRate: pcm.length.toDouble(),
    toRate: targetSamples.toDouble(),
    quality: quality,
  );
  if (resampled.length == targetSamples) return resampled;

  final out = Float64List(targetSamples);
  final n = resampled.length < targetSamples ? resampled.length : targetSamples;
  out.setRange(0, n, resampled);
  // A short result is padded with silence rather than by repeating the head:
  // this can only ever be a sample or two of floor(), and a repeat would be a
  // tick at the seam — the exact thing this file exists to prevent.
  return out;
}
