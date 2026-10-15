// lib/core/harmony/chart_render_cache.dart
//
// BB-T1 — the band rendered a few bars at a time, and only once.
//
// `renderBand` synthesises a whole performance before a note sounds; on a long
// chart that is seconds of silence after Play, and every edit pays it again.
// Here the cheap half (placing events on the clock — `planBand`) still runs over
// the whole piece, but the expensive half (synthesis) runs per WINDOW of bars,
// as STEMS, cached by what is actually in the window.
//
// Three properties, each load-bearing:
//
// 1. **Exact.** A window is a crop of the whole-piece render, not an
//    approximation of it: every comp/bass segment is rendered from its own start
//    (its waveform does not depend on where it sits), every drum hit lands on
//    the same absolute sample, and the additions happen in the same order. So
//    the windows laid end to end are sample-for-sample `renderBand`'s output —
//    seams are click-free by construction, and a test asserts it.
//
// 2. **Levels known up front.** `renderBand` unit-peaks each stem over the WHOLE
//    piece, which a window cannot see. The peaks are recovered cheaply instead:
//    comp and bass segments never overlap, so a stem's peak is the largest peak
//    of its distinct notes (a chart repeats the same few voicings — rendering
//    each once is a fraction of the piece), and the kit is only additions of
//    pre-rendered one-shots, cheap enough to sweep in full.
//
// 3. **Keyed by content.** A window's key is the events that sound in it,
//    relative to the window. An edit re-plans the piece (cheap) and re-renders
//    only windows whose events changed; a repeated chorus finds its windows
//    already rendered. Stems are cached unmixed, so a level or mute change is a
//    re-mix, never a re-render.
//
// Pure Dart: no isolate, timer or player. Everything a window needs is plain
// data ([PreparedBand]), so a caller can render it in an isolate.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/harmony/band_playback.dart';

/// One window: a run of whole bars, as a sample range of the piece.
typedef BandWindow = ({
  int firstBar,
  int endBar,
  int startSample,
  int endSample
});

/// One window's audio, per role, unmixed (un-normalised synth output).
class BandStems {
  const BandStems(this.comp, this.bass, this.drums);

  final Float64List comp;
  final Float64List bass;
  final Float64List drums;

  int get length => comp.length;
}

/// A [BandPlan] made ready for windowed rendering: windows, segment offsets and
/// the per-stem peaks the mix needs.
class PreparedBand {
  PreparedBand._({
    required this.plan,
    required this.sampleRate,
    required this.windows,
    required this.compPeak,
    required this.bassPeak,
    required this.drumPeak,
    required List<int> compOffsets,
    required List<int> bassOffsets,
    required List<int> drumStarts,
  })  : _compOffsets = compOffsets,
        _bassOffsets = bassOffsets,
        _drumStarts = drumStarts;

  final BandPlan plan;
  final int sampleRate;
  final List<BandWindow> windows;

  /// Whole-piece peaks, as `mixStemsFloat` would measure them. Zero = silent.
  final double compPeak;
  final double bassPeak;
  final double drumPeak;

  // Start sample of each segment / hit, as the whole-piece render places it.
  final List<int> _compOffsets;
  final List<int> _bassOffsets;
  final List<int> _drumStarts;

  int get totalSamples => plan.totalSamples(sampleRate);

  /// The window holding [sample], or the last one past the end.
  int windowAt(int sample) {
    for (var i = 0; i < windows.length; i++) {
      if (sample < windows[i].endSample) return i;
    }
    return windows.length - 1;
  }
}

/// Splits [plan] into windows of [barsPerWindow] bars and measures its peaks.
///
/// [segmentCache] (keyed by [segmentKey]) is filled with every distinct note
/// rendered for the peaks; pass the same map to [renderWindowStems] and those
/// notes are not synthesised twice.
PreparedBand prepareBand(
  BandPlan plan, {
  int barsPerWindow = 4,
  int sampleRate = kSampleRate,
  Map<String, Float64List>? segmentCache,
}) {
  final cache = segmentCache ?? <String, Float64List>{};
  final total = plan.totalSamples(sampleRate);
  final per = max(1, barsPerWindow);
  final windows = <BandWindow>[];
  for (var b = 0; b < plan.bars.length; b += per) {
    final end = min(b + per, plan.bars.length);
    windows.add(
      (
        firstBar: b,
        endBar: end,
        startSample: _msToSample(plan.bars[b].startMs, sampleRate),
        endSample: end == plan.bars.length
            ? total
            : _msToSample(plan.bars[end].startMs, sampleRate),
      ),
    );
  }

  final drumStarts = [
    for (final (atMs, _) in plan.drumHits) _msToSample(atMs, sampleRate),
  ];
  final prepared = PreparedBand._(
    plan: plan,
    sampleRate: sampleRate,
    windows: windows,
    compPeak: _segmentPeak(plan.comp, sampleRate, cache),
    bassPeak: _segmentPeak(plan.bass, sampleRate, cache),
    drumPeak: 0,
    compOffsets: _offsets(plan.comp, sampleRate),
    bassOffsets: _offsets(plan.bass, sampleRate),
    drumStarts: drumStarts,
  );

  // The kit's peak needs the overlaps, so sweep it window by window (cheap: no
  // synthesis, only additions of the cached one-shots).
  var drumPeak = 0.0;
  if (plan.drumHits.isNotEmpty) {
    final shots = <Drum, Float64List>{};
    for (final w in windows) {
      final d = _drumWindow(prepared, w, shots);
      for (final v in d) {
        if (v.abs() > drumPeak) drumPeak = v.abs();
      }
    }
  }
  return PreparedBand._(
    plan: plan,
    sampleRate: sampleRate,
    windows: windows,
    compPeak: prepared.compPeak,
    bassPeak: prepared.bassPeak,
    drumPeak: drumPeak,
    compOffsets: prepared._compOffsets,
    bassOffsets: prepared._bassOffsets,
    drumStarts: drumStarts,
  );
}

/// The cache key of one segment's audio (its window position aside).
String segmentKey(Segment s) => '${s.ms}:${s.freqs.join(',')}';

// A note cache may outlive one sample rate; its keys must not.
String _cacheKey(Segment s, int sampleRate) => '$sampleRate@${segmentKey(s)}';

/// Which events a window render includes.
///
/// [all] is the plain crop. The other two exist for a change of plan mid-
/// performance (BB-U3, a new style from the next window): the window at the
/// switch is the OLD plan's [carryIn] — whatever started earlier and is still
/// sounding, so nothing is cut off — plus the NEW plan's [ownStarts] — only
/// what begins inside the window, so nothing that never started rings in.
enum WindowPart { all, carryIn, ownStarts }

/// Synthesises window [index] of [band] as stems.
BandStems renderWindowStems(
  PreparedBand band,
  int index, {
  Map<String, Float64List>? segmentCache,
  WindowPart part = WindowPart.all,
}) {
  final cache = segmentCache ?? <String, Float64List>{};
  final w = band.windows[index];
  return BandStems(
    _segmentWindow(band.plan.comp, band._compOffsets, w, band, cache, part),
    _segmentWindow(band.plan.bass, band._bassOffsets, w, band, cache, part),
    _drumWindow(band, w, <Drum, Float64List>{}, part),
  );
}

/// [a] + [b], sample by sample (for the switch window: carry-in + own starts).
BandStems addStems(BandStems a, BandStems b) {
  Float64List sum(Float64List x, Float64List y) {
    final out = Float64List(x.length);
    for (var i = 0; i < x.length; i++) {
      out[i] = x[i] + y[i];
    }
    return out;
  }

  return BandStems(
    sum(a.comp, b.comp),
    sum(a.bass, b.bass),
    sum(a.drums, b.drums),
  );
}

/// Each role's samples at its place in the mix: stem ÷ whole-piece peak × the
/// role's gain — exactly the terms [mixWindow] sums before clamping. Played as
/// three voices, the audio engine's own float sum is that mix, and a role's
/// voice volume is a mute or level change that touches nothing rendered.
///
/// Order: comp, bass, drums.
List<Float32List> scaleStems(
  PreparedBand band,
  BandStems stems, {
  BandMix mix = const BandMix(),
}) {
  Float32List scale(Float64List s, double peak, double gain) {
    final out = Float32List(s.length);
    if (peak == 0 || gain == 0) return out;
    final k = gain / peak;
    for (var i = 0; i < s.length; i++) {
      out[i] = s[i] * k;
    }
    return out;
  }

  return [
    scale(stems.comp, band.compPeak, mix.comp),
    scale(stems.bass, band.bassPeak, mix.bass),
    scale(stems.drums, band.drumPeak, mix.drums),
  ];
}

/// What sounds in window [index], relative to its start — equal keys mean
/// sample-identical stems.
String windowKey(PreparedBand band, int index) {
  final w = band.windows[index];
  final out = StringBuffer('${band.sampleRate}|${w.endSample - w.startSample}');
  void segments(String tag, List<Segment> segs, List<int> offsets) {
    out.write('|$tag');
    for (var k = 0; k < segs.length; k++) {
      final start = offsets[k];
      final end = offsets[k + 1];
      if (end <= w.startSample || start >= w.endSample) continue;
      if (segs[k].freqs.isEmpty) continue; // a rest renders silence
      out.write(';${start - w.startSample}:${segmentKey(segs[k])}');
    }
  }

  segments('c', band.plan.comp, band._compOffsets);
  segments('b', band.plan.bass, band._bassOffsets);
  out.write('|d');
  final hits = band.plan.drumHits;
  for (var h = 0; h < hits.length; h++) {
    final start = band._drumStarts[h];
    if (start >= w.endSample ||
        start + _maxShotSamples(band) <= w.startSample) {
      continue;
    }
    out.write(
      ';${start - w.startSample}:${hits[h].$2.index}:'
      '${band.plan.drumGains[h]}',
    );
  }
  return out.toString();
}

/// Mixes window stems to PCM16 exactly as `renderBand` mixes the whole piece:
/// each stem over its whole-piece peak × its gain, summed, clamped.
///
/// A role's gain of 0 drops it — that is mute, and it costs no render.
Int16List mixWindow(
  PreparedBand band,
  BandStems stems, {
  BandMix mix = const BandMix(),
}) {
  final n = stems.length;
  final sum = Float64List(n);
  void add(Float64List s, double peak, double gain) {
    if (peak == 0 || gain == 0) return;
    final scale = gain / peak;
    for (var i = 0; i < n; i++) {
      sum[i] += s[i] * scale;
    }
  }

  // Same order as renderBand's stem list: comp, bass, drums.
  if (band.plan.comp.isNotEmpty) add(stems.comp, band.compPeak, mix.comp);
  if (band.plan.bass.isNotEmpty) add(stems.bass, band.bassPeak, mix.bass);
  if (band.plan.drumHits.isNotEmpty) {
    add(stems.drums, band.drumPeak, mix.drums);
  }
  final pcm = Int16List(n);
  for (var i = 0; i < n; i++) {
    pcm[i] = (sum[i].clamp(-1.0, 1.0) * 32767).round();
  }
  return pcm;
}

/// Window stems cached by [windowKey], least recently used dropped first.
///
/// [renders] and [hits] count what happened, so a test can assert that an edit
/// re-rendered only what it touched.
class ChartRenderCache {
  ChartRenderCache({this.maxWindows = 64, this.sampleRate = kSampleRate});

  final int maxWindows;
  final int sampleRate;
  // A map literal keeps insertion order, which is the LRU order here.
  final _windows = <String, BandStems>{};

  /// Distinct notes already synthesised, shared by every plan.
  final segments = <String, Float64List>{};

  int renders = 0;
  int hits = 0;

  /// [prepareBand] using this cache's notes.
  PreparedBand prepare(BandPlan plan, {int barsPerWindow = 4}) => prepareBand(
        plan,
        barsPerWindow: barsPerWindow,
        sampleRate: sampleRate,
        segmentCache: segments,
      );

  /// Window [index]'s stems — from the cache when its content was rendered
  /// before (for this plan or any other).
  BandStems stems(PreparedBand band, int index) =>
      lookup(band, index) ??
      store(
        band,
        index,
        renderWindowStems(band, index, segmentCache: segments),
      );

  /// The cached stems for window [index], counted as a hit; null if absent.
  BandStems? lookup(PreparedBand band, int index) {
    final key = windowKey(band, index);
    final cached = _windows.remove(key);
    if (cached == null) return null;
    hits++;
    _windows[key] = cached; // most recently used
    return cached;
  }

  /// Keeps [stems] — rendered elsewhere, an isolate say — as window [index],
  /// counted as a render. Returns them.
  BandStems store(PreparedBand band, int index, BandStems stems) {
    renders++;
    _windows[windowKey(band, index)] = stems;
    while (_windows.length > maxWindows) {
      _windows.remove(_windows.keys.first);
    }
    return stems;
  }

  /// Whether window [index] would come from the cache.
  bool has(PreparedBand band, int index) =>
      _windows.containsKey(windowKey(band, index));

  void clear() {
    _windows.clear();
    segments.clear();
    renders = 0;
    hits = 0;
  }
}

// ---------------------------------------------------------------------------

int _msToSample(int ms, int sampleRate) => (ms * sampleRate) ~/ 1000;

/// Start sample of every segment, plus the end of the last one — the same
/// per-segment flooring `renderSegmentsRaw` does.
List<int> _offsets(List<Segment> segments, int sampleRate) {
  final out = List<int>.filled(segments.length + 1, 0);
  for (var k = 0; k < segments.length; k++) {
    out[k + 1] = out[k] + (segments[k].ms * sampleRate) ~/ 1000;
  }
  return out;
}

Float64List _renderSegment(
  Segment s,
  int sampleRate,
  Map<String, Float64List> cache,
) =>
    cache[_cacheKey(s, sampleRate)] ??=
        renderSegmentsRaw([s], sampleRate: sampleRate);

/// The peak of a back-to-back segment stem: segments never overlap, so it is
/// the largest single-segment peak.
double _segmentPeak(
  List<Segment> segments,
  int sampleRate,
  Map<String, Float64List> cache,
) {
  var peak = 0.0;
  final seen = <String>{};
  for (final s in segments) {
    if (s.freqs.isEmpty || !seen.add(segmentKey(s))) continue;
    for (final v in _renderSegment(s, sampleRate, cache)) {
      if (v.abs() > peak) peak = v.abs();
    }
  }
  return peak;
}

Float64List _segmentWindow(
  List<Segment> segments,
  List<int> offsets,
  BandWindow w,
  PreparedBand band,
  Map<String, Float64List> cache,
  WindowPart part,
) {
  final out = Float64List(w.endSample - w.startSample);
  for (var k = 0; k < segments.length; k++) {
    final start = offsets[k];
    final end = offsets[k + 1];
    if (end <= w.startSample) continue;
    if (start >= w.endSample) break;
    if (segments[k].freqs.isEmpty) continue;
    if (!_included(start, w, part)) continue;
    final audio = _renderSegment(segments[k], band.sampleRate, cache);
    final from = max(start, w.startSample);
    final to = min(end, w.endSample);
    for (var i = from; i < to; i++) {
      out[i - w.startSample] = audio[i - start];
    }
  }
  return out;
}

/// Whether an event starting at [start] belongs to [part] of window [w].
bool _included(int start, BandWindow w, WindowPart part) => switch (part) {
      WindowPart.all => true,
      WindowPart.carryIn => start < w.startSample,
      WindowPart.ownStarts => start >= w.startSample,
    };

/// The longest one-shot, in samples — how far back a hit can still ring into
/// a window.
int _maxShotSamples(PreparedBand band) =>
    _shotLength[band.sampleRate] ??= Drum.values
        .map((d) => renderDrum(d, sampleRate: band.sampleRate).length)
        .reduce(max);
final _shotLength = <int, int>{};

Float64List _drumWindow(
  PreparedBand band,
  BandWindow w,
  Map<Drum, Float64List> shots, [
  WindowPart part = WindowPart.all,
]) {
  final out = Float64List(w.endSample - w.startSample);
  final hits = band.plan.drumHits;
  final gains = band.plan.drumGains;
  final total = band.totalSamples;
  final reach = _maxShotSamples(band);
  for (var h = 0; h < hits.length; h++) {
    final start = band._drumStarts[h];
    if (start >= w.endSample) continue;
    if (start + reach <= w.startSample) continue;
    if (!_included(start, w, part)) continue;
    final shot = shots[hits[h].$2] ??=
        renderDrum(hits[h].$2, sampleRate: band.sampleRate);
    final g = gains[h];
    // Exactly renderDrumPattern's bounds: a tail stops at the piece's end.
    final last = min(start + shot.length, total);
    final from = max(start, w.startSample);
    final to = min(last, w.endSample);
    for (var i = from; i < to; i++) {
      out[i - w.startSample] += shot[i - start] * g;
    }
  }
  return out;
}
