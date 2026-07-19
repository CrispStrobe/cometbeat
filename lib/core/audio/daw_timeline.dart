// lib/core/audio/daw_timeline.dart
//
// The DAW timeline core — the "vector, not bitmap" model. A clip references a
// SOURCE (any module that renders offline to PCM — a groove, a score, a tracker
// song, a drum pattern, a raw sample), placed on a track at a start time. The
// mix is RASTERIZED ON DEMAND and cached per source, so editing a source model
// updates its clip without re-rendering the rest (like a vector object in a
// bitmap editor).
//
// This is an OFFLINE render-then-play DAW (the app has no realtime audio graph):
// `renderTimeline` bakes the whole arrangement to one PCM buffer, but the cache
// means only changed clips re-render, so re-baking after an edit stays cheap.
// Pure Dart, headless-testable; a DAW surface + per-module `ClipSource` adapters
// (GrooveSource, ScoreSource, TrackerSource, DrumSource, SampleSource) drive it.

import 'dart:math' as math;
import 'dart:typed_data';

/// The default render rate (matches `synth.kSampleRate`), kept inline so this
/// core stays dependency-light.
const int kDawSampleRate = 44100;

/// A source of audio for a [Clip]. Any module that renders offline to mono PCM
/// implements this — the editable "vector". [cacheKey] MUST be equal iff
/// [render] would produce identical audio, so the timeline caches by it and
/// re-renders a clip only when its source actually changes.
abstract class ClipSource {
  /// Render this source to mono PCM at [sampleRate]. Pure + deterministic.
  Float64List render(int sampleRate);

  /// Cache identity — equal keys ⇒ identical audio.
  Object get cacheKey;
}

/// A raw PCM sample source (already "rasterized" — e.g. a recorded clip or a
/// module's baked output). [key] identifies it for caching; two SampleSources
/// over the same buffer share a cache entry.
class SampleSource implements ClipSource {
  SampleSource(this.pcm, {Object? key}) : cacheKey = key ?? _Ref(pcm);

  /// The mono PCM (assumed already at the timeline's sample rate).
  final Float64List pcm;

  @override
  final Object cacheKey;

  @override
  Float64List render(int sampleRate) => pcm;
}

/// Identity wrapper so an un-keyed [SampleSource] caches by buffer identity.
class _Ref {
  _Ref(this.target);
  final Object target;
  @override
  bool operator ==(Object other) =>
      other is _Ref && identical(other.target, target);
  @override
  int get hashCode => identityHashCode(target);
}

/// A placed clip: its [source], where it starts ([startMs]), a linear [gain],
/// whether it's [muted], and optional fade-in/out ramps ([fadeInMs]/
/// [fadeOutMs]) applied at render time.
class Clip {
  const Clip({
    required this.source,
    this.startMs = 0,
    this.gain = 1.0,
    this.muted = false,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
  });

  final ClipSource source;
  final double startMs;
  final double gain;
  final bool muted;
  final double fadeInMs;
  final double fadeOutMs;

  Clip copyWith({
    double? startMs,
    double? gain,
    bool? muted,
    double? fadeInMs,
    double? fadeOutMs,
  }) =>
      Clip(
        source: source,
        startMs: startMs ?? this.startMs,
        gain: gain ?? this.gain,
        muted: muted ?? this.muted,
        fadeInMs: fadeInMs ?? this.fadeInMs,
        fadeOutMs: fadeOutMs ?? this.fadeOutMs,
      );
}

/// One DAW track — a lane of clips with its own [gain]/[muted].
class DawTrack {
  DawTrack({
    this.name = '',
    this.gain = 1.0,
    this.muted = false,
    List<Clip>? clips,
  }) : clips = clips ?? [];

  String name;
  double gain;
  bool muted;
  final List<Clip> clips;
}

/// A DAW arrangement: an ordered list of tracks.
class DawTimeline {
  DawTimeline({List<DawTrack>? tracks}) : tracks = tracks ?? [];
  final List<DawTrack> tracks;
}

/// Render [timeline] to one mono PCM buffer: every unmuted clip on an unmuted
/// track is rasterized (via [cache], one render per distinct `source.cacheKey`),
/// scaled by clip×track gain, and summed at its start offset. When [limit] is
/// true the summed mix is soft-limited (tanh) so overlapping clips can't hard-
/// clip. Pass a persistent [cache] across renders so an edit re-bakes only the
/// changed clips. Returns an empty buffer for a silent timeline.
Float64List renderTimeline(
  DawTimeline timeline, {
  int sampleRate = kDawSampleRate,
  Map<Object, Float64List>? cache,
  bool limit = true,
}) {
  final store = cache ?? <Object, Float64List>{};

  // Resolve every audible clip to a placement, tracking the length.
  final placed =
      <({int start, Float64List pcm, double gain, int fadeIn, int fadeOut})>[];
  var totalSamples = 0;
  for (final track in timeline.tracks) {
    if (track.muted) continue;
    for (final clip in track.clips) {
      if (clip.muted) continue;
      final pcm = store.putIfAbsent(
        clip.source.cacheKey,
        () => clip.source.render(sampleRate),
      );
      if (pcm.isEmpty) continue;
      final start = (clip.startMs * sampleRate / 1000).round();
      placed.add(
        (
          start: start,
          pcm: pcm,
          gain: clip.gain * track.gain,
          fadeIn: (clip.fadeInMs * sampleRate / 1000).round(),
          fadeOut: (clip.fadeOutMs * sampleRate / 1000).round(),
        ),
      );
      final end = start + pcm.length;
      if (end > totalSamples) totalSamples = end;
    }
  }
  if (totalSamples == 0) return Float64List(0);

  final master = Float64List(totalSamples);
  for (final p in placed) {
    final n = p.pcm.length;
    for (var i = 0; i < n; i++) {
      // Fade envelope: ramp up over fadeIn, down over fadeOut; if they overlap
      // (a clip shorter than its fades), the smaller ramp wins.
      var env = 1.0;
      if (p.fadeIn > 0 && i < p.fadeIn) env = i / p.fadeIn;
      if (p.fadeOut > 0 && i >= n - p.fadeOut) {
        final down = (n - i) / p.fadeOut;
        if (down < env) env = down;
      }
      master[p.start + i] += p.pcm[i] * p.gain * env;
    }
  }

  if (limit) {
    for (var i = 0; i < master.length; i++) {
      final x = master[i];
      // Soft-knee: transparent below ~0.6, tanh-limited toward the rails so
      // overlapping clips round off instead of hard-clipping.
      if (x.abs() > 0.6) {
        master[i] = x.sign * (0.6 + _tanh((x.abs() - 0.6) / 0.4) * 0.4);
      }
    }
  }
  return master;
}

double _tanh(double x) {
  final e2 = math.exp(2 * x);
  return (e2 - 1) / (e2 + 1);
}
