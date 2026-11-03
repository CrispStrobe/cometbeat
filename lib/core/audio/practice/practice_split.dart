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
// outer margin on each side is discarded, and across the fade in the middle of
// the overlap one window fades out linearly while the next fades in, so the
// weights sum to exactly 1 at every frame.
//
// Where the windows go matters as much: CrispASR's separators themselves cut
// whatever they are handed into model chunks on a fixed grid, and each
// chunk's output depends on the whole chunk. Windows cut ON that grid
// ([SeparatorGrid], [alignedSeparationWindows]) reproduce a whole-song call
// exactly; windows cut anywhere else differ audibly in the bass (measured
// 2 dB SDR against the whole-song stems around a seam). Plain
// [separationWindows] is the fallback for a separator whose grid is unknown.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/separated_stem.dart';

/// One stem as a separator returns it: interleaved stereo `L,R,…`.
typedef RawStem = ({String name, Float32List pcm});

/// Separates one interleaved stereo window into stems of the same length.
typedef StemSeparator = List<RawStem> Function(Float32List interleaved);

/// Default window length. Per window the separator holds about fifteen
/// stereo-float copies of it (its input, accumulators and result copies, ours)
/// — ~200 MB at 40 s — against a compute overhead of one or two extra model
/// chunks per window (htdemucs at 40 s: +33 %, Mini-BS-RoFormer: +12 %).
const double kSeparationWindowSeconds = 40;

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

/// How a separator cuts its input internally: model chunks of [segment]
/// frames, one every [stride] frames from the start of whatever buffer it is
/// handed (every CrispASR separator does this — see crispasrSeparatorGrid).
///
/// Each chunk's output depends on the whole chunk, so where a window cuts the
/// song matters: a window that starts on this grid and spans a whole number
/// of strides reproduces the whole-song chunks exactly, and with them the
/// whole-song output — everywhere but its outer `segment − stride` frames,
/// whose chunks reach past the window. [alignedSeparationWindows] discards
/// exactly those frames.
class SeparatorGrid {
  const SeparatorGrid({required this.segment, required this.stride})
      : assert(stride > 0 && stride <= segment && 2 * stride >= segment);

  final int segment, stride;

  /// Discarded at each inner window edge.
  int get margin => segment - stride;

  /// Crossfaded between neighbours (0 when their kept spans just meet).
  int get fade => 2 * stride - segment;
}

/// Windows on [grid] covering [frames] frames, each about [window] frames
/// long (`segment + j·stride`, at least one stride past a segment): starts on
/// multiples of the stride, neighbours overlapping by one segment. Inside its
/// kept span every window sees the very chunks a whole-song call would.
List<SeparationWindow> alignedSeparationWindows(
  int frames,
  SeparatorGrid grid, {
  required int window,
}) {
  if (frames <= 0) return const [];
  final j = math.max(1, ((window - grid.segment) / grid.stride).round());
  final length = grid.segment + j * grid.stride;
  final hop = j * grid.stride;
  final out = <SeparationWindow>[];
  for (var a = 0;; a += hop) {
    final last = a + length >= frames;
    final e = last ? frames : a + length;
    final first = a == 0;
    out.add(
      SeparationWindow(
        a,
        e,
        fadeInStart: first ? a : a + grid.margin,
        fadeInEnd: first ? a : a + grid.margin + grid.fade,
        fadeOutStart: last ? e : e - grid.margin - grid.fade,
        fadeOutEnd: last ? e : e - grid.margin,
      ),
    );
    if (last) return out;
  }
}

/// Receives the finished frames `[start, start + left[k].length)` of every
/// stem, in song order, each frame exactly once. [names] is the same list on
/// every call. The block arrays are the sink's to keep or overwrite.
typedef StemBlockSink = void Function(
  int start,
  List<String> names,
  List<Float32List> left,
  List<Float32List> right,
);

/// Separates the stereo song [left]/[right] (at [sampleRate]) with [separate]
/// one window at a time, and hands the crossfaded result to [sink] a block at
/// a time — nothing song-sized is built here, so the caller decides where
/// the stems live (in memory: [separateInWindows]; on disk: the practice
/// worker). With a [grid] the windows sit on the separator's own chunk grid
/// ([alignedSeparationWindows]); without one they are plain overlapping
/// windows of [windowFrames] with [marginFrames] and [fadeFrames]
/// ([separationWindows]). Returns the stem names (empty when the separator
/// returned nothing).
List<String> separateInWindowsTo(
  Float32List left,
  Float32List right,
  int sampleRate,
  StemSeparator separate,
  StemBlockSink sink, {
  SeparatorGrid? grid,
  int? windowFrames,
  int? marginFrames,
  int? fadeFrames,
}) {
  final n = math.min(left.length, right.length);
  final target =
      windowFrames ?? (kSeparationWindowSeconds * sampleRate).round();
  final windows = grid != null
      ? alignedSeparationWindows(n, grid, window: target)
      : separationWindows(
          n,
          window: target,
          margin:
              marginFrames ?? (kSeparationMarginSeconds * sampleRate).round(),
          fade: fadeFrames ?? (kSeparationFadeSeconds * sampleRate).round(),
        );
  final names = <String>[];
  // The previous window's weighted fade-out, waiting for this one's fade-in.
  var carryL = const <String, Float32List>{};
  var carryR = const <String, Float32List>{};
  for (final w in windows) {
    final inter = Float32List(w.length * 2);
    for (var i = 0, t = w.start; t < w.end; i += 2, t++) {
      inter[i] = left[t];
      inter[i + 1] = right[t];
    }
    final raw = {for (final s in separate(inter)) s.name: s.pcm};
    if (names.isEmpty) names.addAll(raw.keys);
    if (names.isEmpty) return names;
    // This window finishes [fadeInStart, fadeOutStart); its fade-in overlaps
    // the carry, its fade-out becomes the next carry.
    final from = w.fadeInStart, to = w.fadeOutStart;
    final nextL = <String, Float32List>{}, nextR = <String, Float32List>{};
    final bl = <Float32List>[], br = <Float32List>[];
    for (final name in names) {
      final pcm = raw[name] ?? Float32List(0);
      final avail = w.start + pcm.length ~/ 2;
      double at(int t, int c) =>
          t < avail ? pcm[2 * (t - w.start) + c] * w.weight(t) : 0.0;
      final l = Float32List(to - from), r = Float32List(to - from);
      final cl = carryL[name], cr = carryR[name];
      for (var t = from; t < to; t++) {
        final i = t - from;
        l[i] = at(t, 0);
        r[i] = at(t, 1);
        if (cl != null && i < cl.length) {
          l[i] += cl[i];
          r[i] += cr![i];
        }
      }
      final tl = Float32List(w.fadeOutEnd - to);
      final tr = Float32List(w.fadeOutEnd - to);
      for (var t = to; t < w.fadeOutEnd; t++) {
        tl[t - to] = at(t, 0);
        tr[t - to] = at(t, 1);
      }
      nextL[name] = tl;
      nextR[name] = tr;
      bl.add(l);
      br.add(r);
    }
    carryL = nextL;
    carryR = nextR;
    if (to > from) sink(from, names, bl, br);
  }
  return names;
}

/// [separateInWindowsTo] into song-length stems in memory.
List<SeparatedStem> separateInWindows(
  Float32List left,
  Float32List right,
  int sampleRate,
  StemSeparator separate, {
  SeparatorGrid? grid,
  int? windowFrames,
  int? marginFrames,
  int? fadeFrames,
}) {
  final n = math.min(left.length, right.length);
  final outL = <Float32List>[], outR = <Float32List>[];
  final names = separateInWindowsTo(
    left,
    right,
    sampleRate,
    separate,
    (start, names, l, r) {
      while (outL.length < names.length) {
        outL.add(Float32List(n));
        outR.add(Float32List(n));
      }
      for (var k = 0; k < names.length; k++) {
        outL[k].setAll(start, l[k]);
        outR[k].setAll(start, r[k]);
      }
    },
    grid: grid,
    windowFrames: windowFrames,
    marginFrames: marginFrames,
    fadeFrames: fadeFrames,
  );
  return [
    for (var k = 0; k < outL.length; k++)
      SeparatedStem(names[k], outL[k], outR[k], sampleRate),
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
