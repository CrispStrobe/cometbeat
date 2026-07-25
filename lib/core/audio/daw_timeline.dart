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
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart'
    show VoiceEffect, applyVoiceEffect;
import 'package:comet_beat/core/audio/fx/fx_chain.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;

export 'package:comet_beat/core/audio/fx/fx_chain.dart';
export 'package:comet_beat/core/audio/fx/fx_spec.dart';

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

/// A persistent stereo sample source. Mono callers still receive the left
/// channel through [render], while the stereo timeline preserves both sides.
class StereoSampleSource extends SampleSource {
  StereoSampleSource(super.left, this.right, {super.key});

  final Float64List right;
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

// ---------------------------------------------------------------------------
// FX compatibility layer (A1).
//
// The effect model moved to `lib/core/audio/fx/` so all five modes can share it
// (see the "Cross-mode FX + interop consolidation" section of PLAN.md). The DAW
// names below are kept as aliases and re-exported, so every existing call site
// in `daw_service.dart` / `daw_screen.dart` / tests keeps compiling unchanged.
// New code should use the `Fx*` names directly.
// ---------------------------------------------------------------------------

/// The DAW's per-clip effect. Alias of the mode-neutral [FxSpec].
typedef DawClipEffect = FxSpec;

/// Alias of [FxType].
typedef DawClipEffectType = FxType;

/// Alias of [FxPreset].
typedef DawClipEffectPreset = FxPreset;

/// Alias of [FxAutomationPoint].
typedef DawAutomationPoint = FxAutomationPoint;

/// Alias of [FxFadeCurve].
typedef DawFadeCurve = FxFadeCurve;

/// Alias of [defaultFx].
const defaultDawClipEffect = defaultFx;

/// Alias of [fxPresetChain].
const dawClipEffectPresetChain = fxPresetChain;

/// Alias of [applyFxChain].
const applyClipEffectChain = applyFxChain;

/// Alias of [applyFxChainStereo].
const applyStereoClipEffectChain = applyFxChainStereo;

/// A placed clip: its [source], where it starts ([startMs]), a linear [gain],
/// whether it's [muted], and optional fade-in/out ramps ([fadeInMs]/
/// [fadeOutMs]) applied at render time.
class Clip {
  const Clip({
    required this.source,
    this.startMs = 0,
    this.gain = 1.0,
    this.pan = 0.0,
    this.width = 1.0,
    this.muted = false,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
    this.fadeInCurve = DawFadeCurve.linear,
    this.fadeOutCurve = DawFadeCurve.linear,
    this.trimStartMs = 0,
    this.trimEndMs = 0,
    this.effects = const [],
  });

  final ClipSource source;
  final double startMs;
  final double gain;

  /// Constant-power clip pan: -1 hard left, 0 centre, +1 hard right.
  final double pan;

  /// Stereo width in mid/side space: 0 mono, 1 unchanged, 2 widened.
  final double width;
  final bool muted;
  final double fadeInMs;
  final double fadeOutMs;
  final DawFadeCurve fadeInCurve;
  final DawFadeCurve fadeOutCurve;

  /// Non-destructive trim: play only the window `[trimStartMs, trimEndMs)` of
  /// the source's render. [trimStartMs] 0 = from the top; [trimEndMs] 0 = to
  /// the end. The source is untouched, so a trim is fully reversible.
  final double trimStartMs;
  final double trimEndMs;

  /// Ordered per-clip effect chain. Effects process the trimmed source audio
  /// before clip gain/fades and before the track insert.
  final List<DawClipEffect> effects;

  Clip copyWith({
    double? startMs,
    double? gain,
    double? pan,
    double? width,
    bool? muted,
    double? fadeInMs,
    double? fadeOutMs,
    DawFadeCurve? fadeInCurve,
    DawFadeCurve? fadeOutCurve,
    double? trimStartMs,
    double? trimEndMs,
    List<DawClipEffect>? effects,
  }) =>
      Clip(
        source: source,
        startMs: startMs ?? this.startMs,
        gain: gain ?? this.gain,
        pan: pan ?? this.pan,
        width: width ?? this.width,
        muted: muted ?? this.muted,
        fadeInMs: fadeInMs ?? this.fadeInMs,
        fadeOutMs: fadeOutMs ?? this.fadeOutMs,
        fadeInCurve: fadeInCurve ?? this.fadeInCurve,
        fadeOutCurve: fadeOutCurve ?? this.fadeOutCurve,
        trimStartMs: trimStartMs ?? this.trimStartMs,
        trimEndMs: trimEndMs ?? this.trimEndMs,
        effects: effects ?? this.effects,
      );
}

/// A per-track insert effect applied to the lane's summed audio at bake time.
enum TrackEffect {
  none,
  reverb,
  echo,
  voiceChipmunk,
  voiceDeep,
  voiceRobot,
  voiceRadio,
}

DawClipEffect? clipEffectForTrackEffect(TrackEffect effect) => switch (effect) {
      TrackEffect.none => null,
      TrackEffect.reverb => defaultDawClipEffect(DawClipEffectType.reverb),
      TrackEffect.echo => defaultDawClipEffect(DawClipEffectType.delay),
      TrackEffect.voiceChipmunk => defaultDawClipEffect(
          DawClipEffectType.voiceChipmunk,
        ),
      TrackEffect.voiceDeep =>
        defaultDawClipEffect(DawClipEffectType.voiceDeep),
      TrackEffect.voiceRobot =>
        defaultDawClipEffect(DawClipEffectType.voiceRobot),
      TrackEffect.voiceRadio =>
        defaultDawClipEffect(DawClipEffectType.voiceRadio),
    };

List<DawClipEffect> trackEffectChainForLegacy(TrackEffect effect) {
  final fx = clipEffectForTrackEffect(effect);
  return fx == null ? const [] : [fx];
}

/// One DAW track — a lane of clips with its own [gain]/[muted]/[soloed]. An
/// optional [instrument] is the lane's default voice: engraved (score) clips
/// added to it adopt it, so the track behaves like an instrument lane. Baked
/// audio / drum / groove clips ignore it. The lane's ordered [effects] chain is
/// applied to the whole lane mix and survives saved-project reloads. The
/// [gainAutomation] points multiply the rendered lane over time, so a range can
/// swell or duck across clips without destructively changing the clips;
/// [instrument] is still a live-session default because saved projects bake each
/// clip's sound in. [effect] is the older single-insert field kept for backwards
/// compatibility with existing projects/API callers.
class DawTrack {
  DawTrack({
    this.name = '',
    this.gain = 1.0,
    this.pan = 0.0,
    this.muted = false,
    this.soloed = false,
    this.instrument,
    this.busIndex,
    Map<int, double>? busSends,
    this.effect = TrackEffect.none,
    List<DawClipEffect>? effects,
    List<DawAutomationPoint>? gainAutomation,
    List<Clip>? clips,
  })  : busSends = busSends ?? {},
        effects = effects ?? [],
        gainAutomation = gainAutomation ?? [],
        clips = clips ?? [];

  String name;
  double gain;

  /// Constant-power pan: -1 is left, 0 centre, +1 right.
  double pan;
  bool muted;

  /// When ANY track is soloed, only soloed (and unmuted) tracks are heard.
  bool soloed;

  /// The lane's default instrument voice (null = default synth).
  TrackerInstrument? instrument;

  /// Optional group bus route. Null means route straight to the master bus.
  int? busIndex;

  /// Parallel send gains into named buses, keyed by bus index.
  Map<int, double> busSends;

  /// The lane's insert effect (applied to its summed audio at bake time).
  TrackEffect effect;

  /// Ordered lane insert FX. Uses the same module model as clip/segment FX.
  List<DawClipEffect> effects;

  /// Track-level gain automation breakpoints.
  List<DawAutomationPoint> gainAutomation;

  final List<Clip> clips;
}

class DawBus {
  DawBus({this.name = '', List<DawClipEffect>? effects})
      : effects = effects ?? [];

  String name;

  /// Ordered group-bus FX applied after assigned tracks are summed.
  List<DawClipEffect> effects;
}

/// The two channels produced by [renderTimelineStereo].
class DawStereoMix {
  const DawStereoMix(this.left, this.right);

  final Float64List left;
  final Float64List right;
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
      TrackEffect.voiceChipmunk => applyVoiceEffect(
          buf,
          VoiceEffect.chipmunk,
          sampleRate: sampleRate,
        ),
      TrackEffect.voiceDeep => applyVoiceEffect(
          buf,
          VoiceEffect.deep,
          sampleRate: sampleRate,
        ),
      TrackEffect.voiceRobot => applyVoiceEffect(
          buf,
          VoiceEffect.robot,
          sampleRate: sampleRate,
        ),
      TrackEffect.voiceRadio => applyVoiceEffect(
          buf,
          VoiceEffect.radio,
          sampleRate: sampleRate,
        ),
    };

({Float64List left, Float64List right}) _applyStereoWidth(
  ({Float64List left, Float64List right}) input,
  double width,
) {
  final w = width.clamp(0.0, 2.0).toDouble();
  if ((w - 1).abs() < 1e-12) return input;
  final frames = math.min(input.left.length, input.right.length);
  final left = Float64List(input.left.length);
  final right = Float64List(input.right.length);
  for (var i = 0; i < frames; i++) {
    final mid = (input.left[i] + input.right[i]) * 0.5;
    final side = (input.left[i] - input.right[i]) * 0.5 * w;
    left[i] = mid + side;
    right[i] = mid - side;
  }
  for (var i = frames; i < left.length; i++) {
    left[i] = input.left[i];
  }
  for (var i = frames; i < right.length; i++) {
    right[i] = input.right[i];
  }
  return (left: left, right: right);
}

/// A DAW arrangement: an ordered list of tracks.
/// A labelled point on the timeline — "verse 2", "fix this", the drop. Markers
/// are navigation only: they never affect the render, so an arrangement sounds
/// identical with or without them.
class DawMarker {
  const DawMarker({required this.ms, this.label = ''});

  /// Position on the timeline, in ms from the start.
  final double ms;
  final String label;

  DawMarker copyWith({double? ms, String? label}) =>
      DawMarker(ms: ms ?? this.ms, label: label ?? this.label);

  Map<String, dynamic> toJson() => {'ms': ms, if (label.isNotEmpty) 'l': label};

  static DawMarker? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final ms = raw['ms'];
    if (ms is! num || !ms.isFinite) return null;
    final label = raw['l'];
    return DawMarker(ms: ms.toDouble(), label: label is String ? label : '');
  }
}

class DawTimeline {
  DawTimeline({
    List<DawTrack>? tracks,
    List<DawBus>? buses,
    List<DawClipEffect>? effects,
    List<DawMarker>? markers,
  })  : tracks = tracks ?? [],
        buses = buses ?? [],
        effects = effects ?? [],
        markers = markers ?? [];
  final List<DawTrack> tracks;

  /// Named group buses. Tracks route here via [DawTrack.busIndex].
  final List<DawBus> buses;

  /// Ordered output-bus FX applied to the full mix before final limiting.
  List<DawClipEffect> effects;

  /// Labelled positions, kept sorted by [DawMarker.ms] (O13).
  final List<DawMarker> markers;
}

/// Render [timeline] to one mono PCM buffer: every unmuted clip on an unmuted
/// track is rasterized (via [cache], one render per distinct `source.cacheKey`),
/// scaled by clip×track gain, and summed at its start offset. When [limit] is
/// true the summed mix is soft-limited (tanh) so overlapping clips can't hard-
/// clip. Pass a persistent [cache] across renders so an edit re-bakes only the
/// changed clips. Returns an empty buffer for a silent timeline.
DawStereoMix renderTimelineStereo(
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
    List<
        ({
          int start,
          Float64List pcmLeft,
          Float64List pcmRight,
          bool stereo,
          double gain,
          double pan,
          int fadeIn,
          int fadeOut,
          DawFadeCurve fadeInCurve,
          DawFadeCurve fadeOutCurve,
        })>,
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
      Float64List pcmLeft,
      Float64List pcmRight,
      bool stereo,
      double gain,
      double pan,
      int fadeIn,
      int fadeOut,
      DawFadeCurve fadeInCurve,
      DawFadeCurve fadeOutCurve,
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
      final sourceRight = clip.source is StereoSampleSource
          ? (clip.source as StereoSampleSource).right
          : rendered;
      final pcm = _trimView(rendered, clip, sampleRate);
      final rightPcm = _trimView(sourceRight, clip, sampleRate);
      if (pcm.isEmpty) continue;
      final isStereo = clip.source is StereoSampleSource;
      final effected = clip.effects.isEmpty
          ? (left: pcm, right: rightPcm)
          : isStereo
              ? applyFxChainStereo(pcm, rightPcm, clip.effects, sampleRate)
              : (
                  left: applyClipEffectChain(pcm, clip.effects, sampleRate),
                  right: rightPcm,
                );
      final stereoPositioned =
          isStereo ? _applyStereoWidth(effected, clip.width) : effected;
      final start = (clip.startMs * sampleRate / 1000).round();
      places.add(
        (
          start: start,
          pcmLeft: stereoPositioned.left,
          pcmRight: stereoPositioned.right,
          stereo: isStereo,
          gain: clip.gain * track.gain,
          pan: (track.pan + clip.pan).clamp(-1.0, 1.0),
          fadeIn: (clip.fadeInMs * sampleRate / 1000).round(),
          fadeOut: (clip.fadeOutMs * sampleRate / 1000).round(),
          fadeInCurve: clip.fadeInCurve,
          fadeOutCurve: clip.fadeOutCurve,
        ),
      );
      final end = start + stereoPositioned.left.length;
      if (end > totalSamples) totalSamples = end;
    }
    if (places.isNotEmpty) perTrack.add((track, places));
  }
  if (totalSamples == 0) {
    return DawStereoMix(Float64List(0), Float64List(0));
  }

  // Sum each lane's clips (into the master directly when it has no effect, or
  // into a lane buffer that the effect processes over the FULL length — so a
  // reverb/echo tail rings out past the last clip — before adding to master).
  // With no effects this is bit-identical to a single flat sum (addition is
  // associative), so it doesn't change the existing bake.
  void mix(
    Float64List left,
    Float64List right,
    List<
            ({
              int start,
              Float64List pcmLeft,
              Float64List pcmRight,
              bool stereo,
              double gain,
              double pan,
              int fadeIn,
              int fadeOut,
              DawFadeCurve fadeInCurve,
              DawFadeCurve fadeOutCurve,
            })>
        places,
  ) {
    for (final p in places) {
      final n = p.pcmLeft.length;
      for (var i = 0; i < n; i++) {
        // Fade envelope: ramp up over fadeIn, down over fadeOut; if they overlap
        // (a clip shorter than its fades), the smaller ramp wins.
        var env = 1.0;
        if (p.fadeIn > 0 && i < p.fadeIn) {
          env = fadeCurveValue(i / p.fadeIn, p.fadeInCurve);
        }
        if (p.fadeOut > 0 && i >= n - p.fadeOut) {
          final down = fadeCurveValue((n - i) / p.fadeOut, p.fadeOutCurve);
          if (down < env) env = down;
        }
        final gain = p.gain * env;
        if (p.stereo) {
          final leftGain = p.pan <= 0 ? 1.0 : math.cos(p.pan * math.pi / 2);
          final rightGain = p.pan >= 0 ? 1.0 : math.cos(p.pan * math.pi / 2);
          left[p.start + i] += p.pcmLeft[i] * gain * leftGain;
          right[p.start + i] += p.pcmRight[i] * gain * rightGain;
        } else {
          final sample = p.pcmLeft[i] * gain;
          final angle = (p.pan + 1) * math.pi / 4;
          left[p.start + i] += sample * math.cos(angle);
          right[p.start + i] += sample * math.sin(angle);
        }
      }
    }
  }

  void addBuffer(Float64List target, Float64List source) {
    for (var i = 0; i < target.length; i++) {
      target[i] += source[i];
    }
  }

  void addScaledBuffer(Float64List target, Float64List source, double gain) {
    if (gain <= 0) return;
    for (var i = 0; i < target.length; i++) {
      target[i] += source[i] * gain;
    }
  }

  final left = Float64List(totalSamples);
  final right = Float64List(totalSamples);
  final busBuffers = <int, ({Float64List left, Float64List right})>{};

  for (final (track, places) in perTrack) {
    final laneLeft = Float64List(totalSamples);
    final laneRight = Float64List(totalSamples);
    mix(laneLeft, laneRight, places);
    if (track.effects.isNotEmpty || track.effect != TrackEffect.none) {
      if (track.effects.isNotEmpty) {
        final processed = applyFxChainStereo(
          laneLeft,
          laneRight,
          track.effects,
          sampleRate,
        );
        laneLeft.setAll(0, processed.left);
        laneRight.setAll(0, processed.right);
      } else {
        laneLeft.setAll(
          0,
          applyTrackEffect(track.effect, laneLeft, sampleRate),
        );
        laneRight.setAll(
          0,
          applyTrackEffect(track.effect, laneRight, sampleRate),
        );
      }
    }
    if (track.gainAutomation.isNotEmpty) {
      _applyTrackGainAutomation(laneLeft, track.gainAutomation, sampleRate);
      _applyTrackGainAutomation(laneRight, track.gainAutomation, sampleRate);
    }
    for (final send in track.busSends.entries) {
      final sendBus = send.key;
      if (sendBus < 0 || sendBus >= timeline.buses.length) continue;
      final bus = busBuffers.putIfAbsent(
        sendBus,
        () =>
            (left: Float64List(totalSamples), right: Float64List(totalSamples)),
      );
      addScaledBuffer(bus.left, laneLeft, send.value);
      addScaledBuffer(bus.right, laneRight, send.value);
    }
    final busIndex = track.busIndex;
    if (busIndex != null && busIndex >= 0 && busIndex < timeline.buses.length) {
      final bus = busBuffers.putIfAbsent(
        busIndex,
        () =>
            (left: Float64List(totalSamples), right: Float64List(totalSamples)),
      );
      addBuffer(bus.left, laneLeft);
      addBuffer(bus.right, laneRight);
    } else {
      addBuffer(left, laneLeft);
      addBuffer(right, laneRight);
    }
  }

  for (final entry in busBuffers.entries) {
    final bus = timeline.buses[entry.key];
    final wet = bus.effects.isEmpty
        ? entry.value
        : applyFxChainStereo(
            entry.value.left,
            entry.value.right,
            bus.effects,
            sampleRate,
          );
    addBuffer(left, wet.left);
    addBuffer(right, wet.right);
  }

  final out = timeline.effects.isEmpty
      ? (left: left, right: right)
      : applyFxChainStereo(left, right, timeline.effects, sampleRate);
  final outLeft = out.left;
  final outRight = out.right;

  if (limit) {
    for (var i = 0; i < outLeft.length; i++) {
      final x = outLeft[i];
      // Soft-knee: transparent below ~0.6, tanh-limited toward the rails so
      // overlapping clips round off instead of hard-clipping.
      if (x.abs() > 0.6) {
        outLeft[i] = x.sign * (0.6 + _tanh((x.abs() - 0.6) / 0.4) * 0.4);
      }
      final r = outRight[i];
      if (r.abs() > 0.6) {
        outRight[i] = r.sign * (0.6 + _tanh((r.abs() - 0.6) / 0.4) * 0.4);
      }
    }
  }
  return DawStereoMix(outLeft, outRight);
}

/// Backward-compatible mono view of the stereo timeline render.
Float64List renderTimeline(
  DawTimeline timeline, {
  int sampleRate = kDawSampleRate,
  Map<Object, Float64List>? cache,
  bool limit = true,
}) {
  final stereo = renderTimelineStereo(
    timeline,
    sampleRate: sampleRate,
    cache: cache,
    // The legacy mono API limited the folded mix, rather than each channel.
    limit: false,
  );
  // Preserve the former centre-mix amplitude for mono playback callers while
  // folding panned channels with constant-power energy preservation.
  final mono = Float64List(stereo.left.length);
  const invSqrt2 = 0.7071067811865476;
  for (var i = 0; i < mono.length; i++) {
    mono[i] = (stereo.left[i] + stereo.right[i]) * invSqrt2;
  }
  if (limit) _limitMonoBuffer(mono);
  return mono;
}

void _limitMonoBuffer(Float64List buffer) {
  for (var i = 0; i < buffer.length; i++) {
    final x = buffer[i];
    if (x.abs() > 0.6) {
      buffer[i] = x.sign * (0.6 + _tanh((x.abs() - 0.6) / 0.4) * 0.4);
    }
  }
}

void _applyTrackGainAutomation(
  Float64List lane,
  List<DawAutomationPoint> automation,
  int sampleRate,
) {
  final points = [
    for (final point in automation)
      if (point.ms.isFinite && point.value.isFinite)
        DawAutomationPoint(
          ms: point.ms < 0 ? 0 : point.ms,
          value: point.value < 0 ? 0 : point.value,
          curve: point.curve,
        ),
  ]..sort((a, b) => a.ms.compareTo(b.ms));
  if (points.isEmpty) return;
  for (var i = 0; i < lane.length; i++) {
    final ms = i * 1000 / sampleRate;
    lane[i] *= _trackAutomationValue(points, ms);
  }
}

double _trackAutomationValue(List<DawAutomationPoint> points, double ms) {
  if (points.length == 1) {
    return (ms - points.single.ms).abs() < 0.5 ? points.single.value : 1.0;
  }
  if (ms < points.first.ms || ms > points.last.ms) return 1.0;
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
    if (ms < a.ms || ms > b.ms) continue;
    if (b.ms <= a.ms) return b.value;
    final t = fadeCurveValue((ms - a.ms) / (b.ms - a.ms), a.curve);
    return a.value + (b.value - a.value) * t;
  }
  return points.last.value;
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
