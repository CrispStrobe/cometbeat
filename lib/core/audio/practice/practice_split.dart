// lib/core/audio/practice/practice_split.dart
//
// The memory-bounded core of "practise with your song": separate a whole song
// in overlapping WINDOWS rather than in one call, and the in-place helpers
// around it. Pure Dart (web-safe, unit-tested with a fake separator in
// test/practice/practice_split_test.dart); the CrispASR worker that drives it
// lives in practice_split_io.dart.
//
// Why windows: a separator handed a whole song holds the whole song several
// times over — its input, its internal spectrogram, one output per stem — and
// the Dart side copies each of those again. A 6-minute song peaked at 2.4 GB.
// In windows, only the four output stems are song-sized; everything else is
// window-sized.
//
// How the windows join: neighbours overlap by `2·margin + fade`. A window's
// outer [margin] on each side is discarded (the model saw no context there),
// and across the [fade] in the middle of the overlap one window fades out
// linearly while the next fades in, so the weights sum to exactly 1 at every
// frame — a separator that returned its input unchanged would come back
// bit-for-bit (up to float rounding).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/separated_stem.dart';

/// One stem as a separator returns it: interleaved stereo `L,R,…`.
typedef RawStem = ({String name, Float32List pcm});

/// Separates one interleaved stereo window into stems of the same length.
typedef StemSeparator = List<RawStem> Function(Float32List interleaved);

/// Default window: long enough that the model's own context is never the
/// limit, short enough that its buffers stay small (a 30 s window is ~10 MB of
/// stereo float in, ~40 MB of stems out).
const double kSeparationWindowSeconds = 30;

/// Discarded at each inner window edge, where the model lacked context.
const double kSeparationMarginSeconds = 1;

/// The crossfade between neighbouring windows.
const double kSeparationFadeSeconds = 1;

/// One window of a windowed separation: frames [start, end) of the song, with
/// a linear fade-in over [fadeInStart, fadeInEnd) (nothing kept before it) and
/// a fade-out over [fadeOutStart, fadeOutEnd) (nothing kept after it). The
/// first window has no fade-in and the last no fade-out.
class SeparationWindow {
  const SeparationWindow(
    this.start,
    this.end, {
    required this.fadeInStart,
    required this.fadeInEnd,
    required this.fadeOutStart,
    required this.fadeOutEnd,
  });

  final int start, end;
  final int fadeInStart, fadeInEnd, fadeOutStart, fadeOutEnd;

  int get length => end - start;

  /// The weight this window's output gets at song frame [t].
  double weight(int t) {
    if (t < fadeInStart || t >= fadeOutEnd) return 0;
    if (t < fadeInEnd) {
      return (t - fadeInStart + 0.5) / (fadeInEnd - fadeInStart);
    }
    if (t >= fadeOutStart) {
      return (fadeOutEnd - t - 0.5) / (fadeOutEnd - fadeOutStart);
    }
    return 1;
  }

  @override
  String toString() => 'SeparationWindow($start..$end, in $fadeInStart..'
      '$fadeInEnd, out $fadeOutStart..$fadeOutEnd)';
}

/// The windows that cover [frames] frames: at most [window] frames each,
/// neighbours overlapping by `2·margin + fade`, spaced evenly so the last one
/// is not a sliver. One window (no fades) when the song fits in one.
List<SeparationWindow> separationWindows(
  int frames, {
  required int window,
  required int margin,
  required int fade,
}) {
  if (frames <= 0) return const [];
  final overlap = 2 * margin + fade;
  if (frames <= window || window <= overlap) {
    return [
      SeparationWindow(
        0,
        frames,
        fadeInStart: 0,
        fadeInEnd: 0,
        fadeOutStart: frames,
        fadeOutEnd: frames,
      ),
    ];
  }
  final hop = window - overlap;
  final count = ((frames - overlap) / hop).ceil();
  final starts = [
    for (var k = 0; k < count; k++) ((frames - overlap) * k / count).round(),
  ];
  return [
    for (var k = 0; k < count; k++)
      () {
        final a = starts[k];
        final e = k == count - 1 ? frames : starts[k + 1] + overlap;
        final first = k == 0, last = k == count - 1;
        return SeparationWindow(
          a,
          e,
          fadeInStart: first ? a : a + margin,
          fadeInEnd: first ? a : a + margin + fade,
          fadeOutStart: last ? e : e - margin - fade,
          fadeOutEnd: last ? e : e - margin,
        );
      }(),
  ];
}

/// Separates the stereo song [left]/[right] (at [sampleRate]) with [separate]
/// one window at a time, crossfading the windows into song-length stereo
/// stems. Only the returned stems are song-sized. Window, margin and fade
/// default to [kSeparationWindowSeconds], [kSeparationMarginSeconds] and
/// [kSeparationFadeSeconds].
List<SeparatedStem> separateInWindows(
  Float32List left,
  Float32List right,
  int sampleRate,
  StemSeparator separate, {
  int? windowFrames,
  int? marginFrames,
  int? fadeFrames,
}) {
  final n = math.min(left.length, right.length);
  final windows = separationWindows(
    n,
    window: windowFrames ?? (kSeparationWindowSeconds * sampleRate).round(),
    margin: marginFrames ?? (kSeparationMarginSeconds * sampleRate).round(),
    fade: fadeFrames ?? (kSeparationFadeSeconds * sampleRate).round(),
  );
  final names = <String>[];
  final outL = <String, Float32List>{}, outR = <String, Float32List>{};
  for (final w in windows) {
    final inter = Float32List(w.length * 2);
    for (var i = 0, t = w.start; t < w.end; i += 2, t++) {
      inter[i] = left[t];
      inter[i + 1] = right[t];
    }
    for (final s in separate(inter)) {
      final l = outL.putIfAbsent(s.name, () {
        names.add(s.name);
        return Float32List(n);
      });
      final r = outR.putIfAbsent(s.name, () => Float32List(n));
      final end = math.min(w.end, w.start + s.pcm.length ~/ 2);
      final pcm = s.pcm;
      // Fully kept span: copy. Fades: weight.
      final keepFrom = math.max(w.fadeInEnd, w.start);
      final keepTo = math.min(w.fadeOutStart, end);
      for (var t = w.fadeInStart; t < math.min(keepFrom, end); t++) {
        final g = w.weight(t), i = 2 * (t - w.start);
        l[t] += g * pcm[i];
        r[t] += g * pcm[i + 1];
      }
      for (var t = keepFrom; t < keepTo; t++) {
        final i = 2 * (t - w.start);
        l[t] = pcm[i];
        r[t] = pcm[i + 1];
      }
      for (var t = math.max(keepTo, w.fadeOutStart);
          t < math.min(w.fadeOutEnd, end);
          t++) {
        final g = w.weight(t), i = 2 * (t - w.start);
        l[t] += g * pcm[i];
        r[t] += g * pcm[i + 1];
      }
    }
  }
  return [
    for (final name in names)
      SeparatedStem(name, outL[name]!, outR[name]!, sampleRate),
  ];
}

/// [mixtureConsistent] without the copies: rewrites [stems] in place so they
/// sum to [left]/[right] over their common span. Same projection — the
/// residual `mix − Σ stems` shared equally.
void mixtureConsistentInPlace(
  List<SeparatedStem> stems,
  Float32List left,
  Float32List right,
) {
  if (stems.isEmpty) return;
  final n = stems.map((s) => s.frames).fold(
        math.min(left.length, right.length),
        math.min,
      );
  final share = 1 / stems.length;
  for (var i = 0; i < n; i++) {
    var sl = 0.0, sr = 0.0;
    for (final s in stems) {
      sl += s.left[i];
      sr += s.right[i];
    }
    final rl = (left[i] - sl) * share, rr = (right[i] - sr) * share;
    for (final s in stems) {
      s.left[i] += rl;
      s.right[i] += rr;
    }
  }
}

/// [x] from [from] Hz to [to] Hz by linear interpolation, in float32 — the
/// same arithmetic as `resampleLinear(x, from / to)` without its two
/// whole-song float64 copies. [x] itself when the rates match.
Float32List resampleLinear32(Float32List x, int from, int to) {
  if (from == to || x.isEmpty) return x;
  final ratio = from / to;
  final out = Float32List((x.length / ratio).floor());
  final last = x.length - 1;
  for (var i = 0; i < out.length; i++) {
    final p = i * ratio;
    final f = p.floor();
    final c = f + 1 < last ? f + 1 : last;
    final frac = p - f;
    out[i] = x[f] * (1 - frac) + x[c] * frac;
  }
  return out;
}

/// The mono mix `(left + right) / 2` at [to] Hz, built without a song-length
/// intermediate at [from] Hz.
Float32List monoAtRate(Float32List left, Float32List right, int from, int to) {
  final n = math.min(left.length, right.length);
  if (n == 0) return Float32List(0);
  final ratio = from / to;
  final out = Float32List((n / ratio).floor());
  final last = n - 1;
  for (var i = 0; i < out.length; i++) {
    final p = i * ratio;
    final f = p.floor();
    final c = f + 1 < last ? f + 1 : last;
    final frac = p - f;
    final a = (left[f] + right[f]) / 2, b = (left[c] + right[c]) / 2;
    out[i] = a * (1 - frac) + b * frac;
  }
  return out;
}
