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

import 'package:comet_beat/core/audio/crisp_dsp/modulated_delay.dart'
    show delayFx;
import 'package:comet_beat/core/audio/crisp_dsp/reverb.dart' show reverbFx;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;

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
    this.trimStartMs = 0,
    this.trimEndMs = 0,
  });

  final ClipSource source;
  final double startMs;
  final double gain;
  final bool muted;
  final double fadeInMs;
  final double fadeOutMs;

  /// Non-destructive trim: play only the window `[trimStartMs, trimEndMs)` of
  /// the source's render. [trimStartMs] 0 = from the top; [trimEndMs] 0 = to
  /// the end. The source is untouched, so a trim is fully reversible.
  final double trimStartMs;
  final double trimEndMs;

  Clip copyWith({
    double? startMs,
    double? gain,
    bool? muted,
    double? fadeInMs,
    double? fadeOutMs,
    double? trimStartMs,
    double? trimEndMs,
  }) =>
      Clip(
        source: source,
        startMs: startMs ?? this.startMs,
        gain: gain ?? this.gain,
        muted: muted ?? this.muted,
        fadeInMs: fadeInMs ?? this.fadeInMs,
        fadeOutMs: fadeOutMs ?? this.fadeOutMs,
        trimStartMs: trimStartMs ?? this.trimStartMs,
        trimEndMs: trimEndMs ?? this.trimEndMs,
      );
}

/// A per-track insert effect applied to the lane's summed audio at bake time.
enum TrackEffect { none, reverb, echo }

/// One DAW track — a lane of clips with its own [gain]/[muted]/[soloed]. An
/// optional [instrument] is the lane's default voice: engraved (score) clips
/// added to it adopt it, so the track behaves like an instrument lane. Baked
/// audio / drum / groove clips ignore it. An [effect] insert (reverb / echo) is
/// applied to the lane's whole mix. Neither is serialized (saved projects bake
/// each clip's sound in), so both are live-session conveniences.
class DawTrack {
  DawTrack({
    this.name = '',
    this.gain = 1.0,
    this.muted = false,
    this.soloed = false,
    this.instrument,
    this.effect = TrackEffect.none,
    List<Clip>? clips,
  }) : clips = clips ?? [];

  String name;
  double gain;
  bool muted;

  /// When ANY track is soloed, only soloed (and unmuted) tracks are heard.
  bool soloed;

  /// The lane's default instrument voice (null = default synth).
  TrackerInstrument? instrument;

  /// The lane's insert effect (applied to its summed audio at bake time).
  TrackEffect effect;
  final List<Clip> clips;
}

/// Apply a track's insert [effect] to its (full-length) summed [buf].
Float64List applyTrackEffect(
  TrackEffect effect,
  Float64List buf,
  int sampleRate,
) =>
    switch (effect) {
      TrackEffect.none => buf,
      TrackEffect.reverb =>
        reverbFx(buf, roomSize: 0.7, sampleRate: sampleRate),
      TrackEffect.echo => delayFx(buf, delayMs: 300, sampleRate: sampleRate),
    };

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

  // Resolve every audible clip to a placement, grouped by its track (so a
  // per-track insert effect can process that lane's whole mix). Tracks the
  // total length across all lanes.
  final perTrack = <(
    DawTrack,
    List<({int start, Float64List pcm, double gain, int fadeIn, int fadeOut})>
  )>[];
  var totalSamples = 0;
  // Solo is timeline-wide: if any track is soloed, non-soloed tracks fall
  // silent (a muted track stays silent regardless).
  final anySolo = timeline.tracks.any((t) => t.soloed);
  for (final track in timeline.tracks) {
    if (track.muted) continue;
    if (anySolo && !track.soloed) continue;
    final places = <({
      int start,
      Float64List pcm,
      double gain,
      int fadeIn,
      int fadeOut
    })>[];
    for (final clip in track.clips) {
      if (clip.muted) continue;
      final rendered = store.putIfAbsent(
        clip.source.cacheKey,
        () => clip.source.render(sampleRate),
      );
      if (rendered.isEmpty) continue;
      // Non-destructive trim: view the [trimStart, trimEnd) window of the
      // (cached) render. The cache still holds the full source, so a trim
      // change is free and reversible.
      final pcm = _trimView(rendered, clip, sampleRate);
      if (pcm.isEmpty) continue;
      final start = (clip.startMs * sampleRate / 1000).round();
      places.add(
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
    if (places.isNotEmpty) perTrack.add((track, places));
  }
  if (totalSamples == 0) return Float64List(0);

  // Sum each lane's clips (into the master directly when it has no effect, or
  // into a lane buffer that the effect processes over the FULL length — so a
  // reverb/echo tail rings out past the last clip — before adding to master).
  // With no effects this is bit-identical to a single flat sum (addition is
  // associative), so it doesn't change the existing bake.
  final master = Float64List(totalSamples);
  void mix(
    Float64List buf,
    List<({int start, Float64List pcm, double gain, int fadeIn, int fadeOut})>
        places,
  ) {
    for (final p in places) {
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
        buf[p.start + i] += p.pcm[i] * p.gain * env;
      }
    }
  }

  for (final (track, places) in perTrack) {
    if (track.effect == TrackEffect.none) {
      mix(master, places);
    } else {
      final lane = Float64List(totalSamples);
      mix(lane, places);
      final wet = applyTrackEffect(track.effect, lane, sampleRate);
      for (var i = 0; i < totalSamples; i++) {
        master[i] += wet[i];
      }
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

/// The `[trimStartMs, trimEndMs)` window of a clip's [rendered] audio as a
/// zero-copy view — the full buffer when the clip has no trim. What actually
/// plays / draws for a (possibly trimmed) clip.
Float64List trimmedPcm(
  Clip clip,
  Float64List rendered, {
  int sampleRate = kDawSampleRate,
}) =>
    _trimView(rendered, clip, sampleRate);

Float64List _trimView(Float64List rendered, Clip clip, int sampleRate) {
  if (clip.trimStartMs <= 0 && clip.trimEndMs <= 0) return rendered;
  final n = rendered.length;
  final from = (clip.trimStartMs * sampleRate / 1000).round().clamp(0, n);
  final to = clip.trimEndMs <= 0
      ? n
      : (clip.trimEndMs * sampleRate / 1000).round().clamp(0, n);
  if (to <= from) return Float64List(0);
  return Float64List.sublistView(rendered, from, to);
}

/// The audible length (ms) of [clip] after trim — its render length when
/// untrimmed. Used to draw a trimmed clip to scale.
double trimmedDurationMs(
  Clip clip,
  Float64List rendered, {
  int sampleRate = kDawSampleRate,
}) =>
    trimmedPcm(clip, rendered, sampleRate: sampleRate).length *
    1000 /
    sampleRate;
