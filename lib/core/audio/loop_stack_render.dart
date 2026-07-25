// Live-looper S0 — the pure summing renderer for an overdub layer stack.
//
// Each recorded loop layer is one loop cycle of mono-float PCM (a `Float64List`,
// its length = its own bar-count × samples-per-bar). [renderLoopStack] sums the
// active layers into ONE seamless loop: a shorter layer is tiled (repeated) to
// fill the loop, so a 1-bar layer rides cleanly under a 2-bar one. The sum is
// soft-limited so stacking many layers never clips.
//
// Pure + Flutter-free (like the DAW's `renderTimeline`), so it's the testable
// enabler under the Perform surface. Feed it `LoopStack<Float64List>.activeLayers`.

import 'dart:math';
import 'dart:typed_data';

/// Makes a finite loop buffer continuous at its wrap point.
///
/// The source and destination windows are paired across the boundary and
/// equalized with a short linear crossfade. This only changes the final few
/// milliseconds, but removes the single-sample discontinuity that becomes an
/// audible click when a platform audio element repeats the buffer.
Float64List crossfadeLoopSeam(
  Float64List pcm, {
  int fadeSamples = 128,
}) {
  if (pcm.length < 2 ||
      fadeSamples < 1 ||
      pcm.length < fadeSamples * 2 ||
      (pcm.first - pcm.last).abs() < 0.01) {
    return pcm;
  }
  final fade = fadeSamples;
  final out = Float64List.fromList(pcm);
  final seam = Float64List(fade);
  for (var i = 0; i < fade; i++) {
    final t = (i + 1) / fade;
    // The head fades from its original start toward the tail. Mirror that
    // ramp into the tail so the final sample equals the first sample.
    seam[i] = pcm[pcm.length - fade + i] * t + pcm[i] * (1 - t);
    out[i] = seam[i];
  }
  for (var i = 0; i < fade; i++) {
    out[pcm.length - fade + i] = seam[fade - 1 - i];
  }
  return out;
}

/// Int16 counterpart used by the Loop Mixer WAV renderer.
Int16List crossfadePcm16Seam(Int16List pcm, {int fadeSamples = 128}) {
  if (pcm.length < 2 ||
      fadeSamples < 1 ||
      pcm.length < fadeSamples * 2 ||
      (pcm.first - pcm.last).abs() < 256) {
    return pcm;
  }
  final fade = fadeSamples;
  final out = Int16List.fromList(pcm);
  final seam = Int32List(fade);
  for (var i = 0; i < fade; i++) {
    final t = (i + 1) / fade;
    seam[i] = (pcm[pcm.length - fade + i] * t + pcm[i] * (1 - t)).round();
    out[i] = seam[i].clamp(-32768, 32767);
  }
  for (var i = 0; i < fade; i++) {
    out[pcm.length - fade + i] = seam[fade - 1 - i].clamp(-32768, 32767);
  }
  return out;
}

/// tanh soft-knee — compresses hot sums without a hard clip.
double _tanh(double x) {
  if (x > 20) return 1.0;
  if (x < -20) return -1.0;
  final e = exp(2 * x);
  return (e - 1) / (e + 1);
}

/// Sums [layers] (each one loop cycle of mono-float PCM) into a single seamless
/// loop. The result length is [loopSamples] if given, else the LONGEST layer;
/// every layer is tiled to fill that length. Empty layers are ignored. With
/// [limit] (default true) the sum is tanh soft-limited so many stacked layers
/// stay clean; pass false to get the raw sum (e.g. for further processing).
///
/// Layers are meant to be whole-bar loops (see `quantizeLoopBars`), so the
/// longest is an exact multiple of each and the tiling is phase-clean.
Float64List renderLoopStack(
  List<Float64List> layers, {
  int? loopSamples,
  bool limit = true,
}) {
  final active = [
    for (final l in layers)
      if (l.isNotEmpty) l,
  ];
  final n = loopSamples ??
      (active.isEmpty ? 0 : active.map((l) => l.length).reduce(max));
  final out = Float64List(n);
  if (n == 0) return out;

  for (final layer in active) {
    final len = layer.length;
    for (var i = 0; i < n; i++) {
      out[i] += layer[i % len];
    }
  }
  if (limit) {
    for (var i = 0; i < n; i++) {
      out[i] = _tanh(out[i]);
    }
  }
  return crossfadeLoopSeam(out);
}
