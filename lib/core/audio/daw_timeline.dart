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
import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart'
    show StretchQuality, timeStretch, timeStretchStereo;
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart'
    show VoiceEffect, applyVoiceEffect;
import 'package:comet_beat/core/audio/daw_tempo_map.dart' show TempoMap;
import 'package:comet_beat/core/audio/fx/fx_chain.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:comet_beat/core/licensing/license_obligations.dart'
    show LicensedWork;

export 'package:comet_beat/core/audio/fx/fx_chain.dart';
export 'package:comet_beat/core/audio/fx/fx_spec.dart';
// Re-exported so anything holding a Clip can read its provenance without a
// second import.
export 'package:comet_beat/core/licensing/license_obligations.dart'
    show LicensedWork;

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
    this.gainAutomation = const [],
    this.groupId,
    this.warp = false,
    this.nativeBpm,
    this.warpQuality = StretchQuality.balanced,
    this.takes = const [],
    this.takeIndex = 0,
    this.provenance,
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

  /// WS-A7 — follow the project tempo instead of playing at the rate it was
  /// recorded at.
  ///
  /// Off by default, and a clip with it off renders byte-for-byte as before:
  /// warping is a claim about what a clip MEANS musically (it is N beats of
  /// material, not N seconds of audio), and that claim is only true for
  /// material that was played in time.
  final bool warp;

  /// The tempo this clip's audio is in, in BPM — what [warp] stretches FROM.
  ///
  /// Null means "not stated", and a warped clip with no native tempo is left
  /// alone rather than guessed at: stretching by an invented factor would
  /// silently detune the arrangement's timing, and there is no way for the
  /// listener to tell that from a mistake they made.
  final double? nativeBpm;

  /// WS-A9 — which stretch setting [warp] uses.
  ///
  /// Per-CLIP rather than per-project because it is a property of the material:
  /// a bass line needs [StretchQuality.deep] to keep its pitch, and the drum
  /// loop on the next lane does not. Defaults to balanced, which is what warp
  /// did before this existed.
  final StretchQuality warpQuality;

  /// D5 — the alternative takes this clip can play, INCLUDING the active one.
  ///
  /// Empty means what it always meant: the clip has exactly one take, which is
  /// [source]. That is why nothing in the renderer changed for this feature —
  /// [source] is still the audio that plays, and these are the alternatives it
  /// can be swapped for.
  ///
  /// Comping falls out of this rather than needing its own machinery: split the
  /// clip at the phrase boundaries (which the timeline already does) and choose
  /// a take per segment. Each segment keeps the whole take list, so a choice
  /// made for one phrase can be revisited without re-recording anything.
  final List<ClipSource> takes;

  /// Which entry of [takes] is currently [source]. Meaningless when [takes] is
  /// empty.
  final int takeIndex;

  /// D2 — clips sharing a group id move together.
  ///
  /// Null means ungrouped, which is almost every clip. Grouping exists for the
  /// case where two clips ARE one musical event recorded twice — a DI and a mic
  /// on the same take, a kick and its sub — and sliding one without the other
  /// silently ruins the phase relationship that made them worth keeping
  /// together. It is a link, not a container: each clip keeps its own lane,
  /// gain, fades and envelope.
  final int? groupId;

  /// D3 — a gain envelope over THIS clip, in ms from the clip's own start.
  ///
  /// The lane already has [DawTrack.gainAutomation], and this is deliberately
  /// not the same thing: lane automation is anchored to the TIMELINE, so it
  /// stays put when a clip moves under it, which is what you want for a fade
  /// across a section. A clip envelope belongs to the take — move the clip and
  /// the shape goes with it — which is what you want for riding one phrase, and
  /// is why the alternative today is splitting the clip just to set a gain.
  ///
  /// Outside the authored points the multiplier is 1, so a partial envelope
  /// leaves the rest of the clip alone.
  final List<DawAutomationPoint> gainAutomation;

  /// Where this clip's audio came from and under what licence, when it came
  /// from the library. Null for the user's own recordings and generated
  /// material, which carry no obligation.
  ///
  /// This is what lets an export know what it owes: without provenance
  /// travelling WITH the clip, `obligationsFor` has nothing to be given at
  /// export time and share-alike material would leave the app silently. It is
  /// saved in the project for the same reason — an obligation that disappears
  /// on reload is worse than none, because it looks discharged.
  final LicensedWork? provenance;

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
    List<DawAutomationPoint>? gainAutomation,
    int? groupId,
    bool? warp,
    double? nativeBpm,
    StretchQuality? warpQuality,
    List<ClipSource>? takes,
    int? takeIndex,
    LicensedWork? provenance,
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
        gainAutomation: gainAutomation ?? this.gainAutomation,
        groupId: groupId ?? this.groupId,
        warp: warp ?? this.warp,
        nativeBpm: nativeBpm ?? this.nativeBpm,
        warpQuality: warpQuality ?? this.warpQuality,
        takes: takes ?? this.takes,
        takeIndex: takeIndex ?? this.takeIndex,
        provenance: provenance ?? this.provenance,
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
/// WS-A7 — how much to stretch a warped clip so it follows the project tempo.
///
/// Returns 1.0 (do nothing) whenever warping cannot be justified: the clip is
/// not warped, there is no tempo map, or the clip never said what tempo it is
/// in. Guessing a factor would silently shift the arrangement's timing, and a
/// listener cannot tell that from a mistake they made themselves.
///
/// **A clip that spans a tempo CHANGE gets one factor, not a piecewise
/// stretch.** The factor is derived from the real-time span the tempo map gives
/// the clip's musical length, so the tempo change is smeared across the clip's
/// interior but its END lands exactly where the map says it should — which
/// means nothing after it drifts. That is the invariant worth protecting; a
/// piecewise stretch would place the change exactly and cost a WSOLA seam at
/// every tempo edit.
double clipWarpFactor(
  Clip clip,
  TempoMap? tempoMap, {
  required double sourceDurationMs,
}) {
  if (!clip.warp || tempoMap == null) return 1;
  final native = clip.nativeBpm;
  if (native == null || native <= 0) return 1;
  if (sourceDurationMs <= 0) return 1;

  // How long the material is in MUSICAL time, at the tempo it was played.
  final beats = sourceDurationMs / (60000 / native);
  if (beats <= 0) return 1;

  // What the project says that many beats occupy, starting where the clip sits.
  final startBeat = tempoMap.beatAtMs(clip.startMs);
  final targetMs = tempoMap.msAtBeat(startBeat + beats) - clip.startMs;
  if (targetMs <= 0) return 1;

  return targetMs / sourceDurationMs;
}

/// Warp factors outside this range are refused. WSOLA degrades into obvious
/// artefacts well before 4× either way, and a factor that extreme almost always
/// means the stated native tempo is wrong (a 60 BPM loop declared at 240)
/// rather than that someone wants a 4× stretch — so the honest response is to
/// leave the audio alone rather than produce a mess and call it a feature.
const double kMaxWarpFactor = 4.0;

/// Whether [factor] is worth acting on: real, sane, and not a no-op.
bool warpFactorIsUsable(double factor) =>
    factor.isFinite &&
    factor > 1 / kMaxWarpFactor &&
    factor < kMaxWarpFactor &&
    (factor - 1).abs() > 1e-6;

/// Apply [clipWarpFactor] to a clip's trimmed window, if it is worth applying.
///
/// Shared by both render paths so they cannot disagree — they are pinned
/// byte-identical, and a warp implemented twice is exactly how that pin breaks.
({Float64List left, Float64List right}) _warpClip(
  Clip clip,
  Float64List pcm,
  Float64List rightPcm, {
  required bool isStereo,
  required int sampleRate,
  required TempoMap? tempoMap,
}) {
  final factor = clipWarpFactor(
    clip,
    tempoMap,
    sourceDurationMs: pcm.length * 1000 / sampleRate,
  );
  if (!warpFactorIsUsable(factor)) return (left: pcm, right: rightPcm);
  if (isStereo) {
    final out = timeStretchStereo(
      pcm,
      rightPcm,
      factor,
      sampleRate: sampleRate,
      quality: clip.warpQuality,
    );
    return (left: out.left, right: out.right);
  }
  final out = timeStretch(
    pcm,
    factor,
    sampleRate: sampleRate,
    quality: clip.warpQuality,
  );
  return (left: out, right: out);
}

DawStereoMix renderTimelineStereo(
  DawTimeline timeline, {
  int sampleRate = kDawSampleRate,
  Map<Object, Float64List>? cache,
  bool limit = true,
  // WS-A7 — needed only to warp clips that ask to follow it. Null means no
  // clip warps, which is what every caller predating this got.
  TempoMap? tempoMap,
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
          List<DawAutomationPoint> envelope,
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
      List<DawAutomationPoint> envelope,
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
      var pcm = _trimView(rendered, clip, sampleRate);
      var rightPcm = _trimView(sourceRight, clip, sampleRate);
      if (pcm.isEmpty) continue;
      final isStereo = clip.source is StereoSampleSource;
      // WS-A7 — warp the TRIMMED window (that is the audio actually used), and
      // before the effects, so an effect's delay time stays in real time.
      final warped = _warpClip(
        clip,
        pcm,
        rightPcm,
        isStereo: isStereo,
        sampleRate: sampleRate,
        tempoMap: tempoMap,
      );
      pcm = warped.left;
      rightPcm = warped.right;
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
          envelope: clip.gainAutomation,
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
              List<DawAutomationPoint> envelope,
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
        // D3 — the clip's own envelope, indexed from ITS start so the shape
        // travels with the take.
        final shaped = p.envelope.isEmpty
            ? env
            : env * clipEnvelopeAt(p.envelope, i * 1000 / sampleRate);
        final gain = p.gain * shaped;
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

  if (limit) _limitStereoBuffers(outLeft, outRight);
  return DawStereoMix(outLeft, outRight);
}

/// The master soft-knee limiter: transparent below ~0.6, tanh-limited toward
/// the rails so overlapping clips round off instead of hard-clipping.
///
/// Per-sample and stateless, which is why a windowed render can apply it to a
/// window and still match the full render exactly — shared by both paths so
/// they can't drift apart.
void _limitStereoBuffers(Float64List left, Float64List right) {
  for (var i = 0; i < left.length; i++) {
    final x = left[i];
    if (x.abs() > 0.6) {
      left[i] = x.sign * (0.6 + _tanh((x.abs() - 0.6) / 0.4) * 0.4);
    }
    final r = right[i];
    if (r.abs() > 0.6) {
      right[i] = r.sign * (0.6 + _tanh((r.abs() - 0.6) / 0.4) * 0.4);
    }
  }
}

/// Backward-compatible mono view of the stereo timeline render.
/// Whether a WINDOWED render ([renderTimelineWindowStereo]) can skip material
/// outside the window and still be byte-identical to slicing the full render.
///
/// It can when nothing processes a lane as a whole. Clip effects are safe at any
/// window — a clip's audio is bounded and its chain is applied to that clip's
/// own buffer, so it doesn't depend on where the window falls. What is NOT safe
/// is anything that reads a lane's entire timeline:
///
///   * a track insert chain / [TrackEffect] — a reverb tail or delay repeat
///     started before the window still belongs inside it;
///   * track gain AUTOMATION — its value at a sample depends on the points
///     around it, which may sit outside the window;
///   * bus sends / bus routing and master effects, for the same reason.
///
/// Those lanes are still rendered CORRECTLY by the windowed path (it falls back
/// to rendering that lane in full and slicing); this predicate only reports
/// whether the memory win applies. Mirrors the Tracker's
/// `songCanStreamFlowVariable` in spirit: name exactly which constructs couple
/// across the window, and route only those to the whole-length path.
bool timelineWindowIsBounded(DawTimeline timeline) {
  if (timeline.effects.isNotEmpty) return false;
  if (timeline.buses.isNotEmpty) return false;
  for (final track in timeline.tracks) {
    if (track.effects.isNotEmpty) return false;
    if (track.effect != TrackEffect.none) return false;
    if (track.gainAutomation.isNotEmpty) return false;
    if (track.busIndex != null) return false;
    if (track.busSends.isNotEmpty) return false;
  }
  return true;
}

/// Render only `[fromSample, toSample)` of [timeline].
///
/// This is the piece the DAW was missing: [renderTimelineStereo] allocates a
/// full-length buffer per lane plus the master, so memory grows with
/// `tracks × arrangement length` and playback has to bake the whole thing before
/// a single sample is heard. A windowed render touches only the clips that
/// overlap the window, so a two-second preview of a twenty-minute arrangement
/// costs two seconds of memory.
///
/// **Byte-identical** to the matching slice of [renderTimelineStereo] — there is
/// a test pinning exactly that. When [timelineWindowIsBounded] is false the
/// lane-coupled tracks are rendered in full and sliced, which keeps the audio
/// right at the cost of the saving; the fast path still applies to every other
/// lane.
DawStereoMix renderTimelineWindowStereo(
  DawTimeline timeline, {
  required int fromSample,
  required int toSample,
  // WS-A7 — must match the full render's, or the two stop being byte-identical
  // for any warped clip.
  TempoMap? tempoMap,
  int sampleRate = kDawSampleRate,
  Map<Object, Float64List>? cache,
  bool limit = true,
}) {
  final from = fromSample < 0 ? 0 : fromSample;
  final to = toSample < from ? from : toSample;
  final n = to - from;
  if (n == 0) return DawStereoMix(Float64List(0), Float64List(0));

  // Anything lane-coupled: render the whole mix once and slice. Correct, and no
  // worse than today.
  if (!timelineWindowIsBounded(timeline)) {
    final full = renderTimelineStereo(
      timeline,
      sampleRate: sampleRate,
      cache: cache,
      limit: limit,
    );
    return DawStereoMix(
      _sliceOrPad(full.left, from, to),
      _sliceOrPad(full.right, from, to),
    );
  }

  final store = cache ?? <Object, Float64List>{};
  final left = Float64List(n);
  final right = Float64List(n);
  final anySolo = timeline.tracks.any((t) => t.soloed);

  for (final track in timeline.tracks) {
    if (track.muted) continue;
    if (anySolo && !track.soloed) continue;
    for (final clip in track.clips) {
      if (clip.muted) continue;
      final start = (clip.startMs * sampleRate / 1000).round();
      final rendered = store.putIfAbsent(
        clip.source.cacheKey,
        () => clip.source.render(sampleRate),
      );
      if (rendered.isEmpty) continue;
      final isStereo = clip.source is StereoSampleSource;
      final sourceRight =
          isStereo ? (clip.source as StereoSampleSource).right : rendered;
      final trimmedLeft = _trimView(rendered, clip, sampleRate);
      final trimmedRight = _trimView(sourceRight, clip, sampleRate);
      if (trimmedLeft.isEmpty) continue;
      // WS-A7 — warp BEFORE the window test: a warped clip's length is not its
      // trimmed length, so testing first would drop a clip that does reach the
      // window (or keep one that no longer does).
      final warped = _warpClip(
        clip,
        trimmedLeft,
        trimmedRight,
        isStereo: isStereo,
        sampleRate: sampleRate,
        tempoMap: tempoMap,
      );
      final pcm = warped.left;
      final rightPcm = warped.right;
      // Skip clips that don't reach the window at all — the whole point.
      if (start + pcm.length <= from || start >= to) continue;

      final effected = clip.effects.isEmpty
          ? (left: pcm, right: rightPcm)
          : isStereo
              ? applyFxChainStereo(pcm, rightPcm, clip.effects, sampleRate)
              : (
                  left: applyClipEffectChain(pcm, clip.effects, sampleRate),
                  right: rightPcm,
                );
      final positioned =
          isStereo ? _applyStereoWidth(effected, clip.width) : effected;

      final total = positioned.left.length;
      final gainBase = clip.gain * track.gain;
      final pan = (track.pan + clip.pan).clamp(-1.0, 1.0);
      final fadeIn = (clip.fadeInMs * sampleRate / 1000).round();
      final fadeOut = (clip.fadeOutMs * sampleRate / 1000).round();

      // Only the overlapping span, but the fade envelope is still indexed from
      // the CLIP's own start so a window mid-fade gets the right level.
      final iStart = from - start < 0 ? 0 : from - start;
      final iEnd = to - start < total ? to - start : total;
      for (var i = iStart; i < iEnd; i++) {
        var env = 1.0;
        if (fadeIn > 0 && i < fadeIn) {
          env = fadeCurveValue(i / fadeIn, clip.fadeInCurve);
        }
        if (fadeOut > 0 && i >= total - fadeOut) {
          final down = fadeCurveValue((total - i) / fadeOut, clip.fadeOutCurve);
          if (down < env) env = down;
        }
        final shaped = clip.gainAutomation.isEmpty
            ? env
            : env * clipEnvelopeAt(clip.gainAutomation, i * 1000 / sampleRate);
        final gain = gainBase * shaped;
        final at = start + i - from;
        if (isStereo) {
          final lg = pan <= 0 ? 1.0 : math.cos(pan * math.pi / 2);
          final rg = pan >= 0 ? 1.0 : math.cos(pan * math.pi / 2);
          left[at] += positioned.left[i] * gain * lg;
          right[at] += positioned.right[i] * gain * rg;
        } else {
          final sample = positioned.left[i] * gain;
          final angle = (pan + 1) * math.pi / 4;
          left[at] += sample * math.cos(angle);
          right[at] += sample * math.sin(angle);
        }
      }
    }
  }

  if (limit) {
    _limitStereoBuffers(left, right);
  }
  return DawStereoMix(left, right);
}

/// `[from, to)` of [buffer], zero-padded where the window runs past the end.
Float64List _sliceOrPad(Float64List buffer, int from, int to) {
  final out = Float64List(to - from);
  for (var i = from; i < to && i < buffer.length; i++) {
    out[i - from] = buffer[i];
  }
  return out;
}

/// The frame count [renderTimelineStereo] would produce, computed WITHOUT
/// allocating the whole-song mix — only the clip renders (cached in [cache]) and
/// their placements. Clip effects preserve length (the FX-chain invariant), so a
/// clip's contribution ends at `start + trimmedLength`. Share [cache] with a
/// following [streamTimelineWav] so each clip renders once.
int dawTimelineLengthSamples(
  DawTimeline timeline, {
  int sampleRate = kDawSampleRate,
  Map<Object, Float64List>? cache,
  // WS-A7 — a warped clip's contribution is its WARPED length. Without this the
  // render would be truncated for any clip that warps longer.
  TempoMap? tempoMap,
}) {
  final store = cache ?? <Object, Float64List>{};
  var total = 0;
  final anySolo = timeline.tracks.any((t) => t.soloed);
  for (final track in timeline.tracks) {
    if (track.muted) continue;
    if (anySolo && !track.soloed) continue;
    for (final clip in track.clips) {
      if (clip.muted) continue;
      final rendered = store.putIfAbsent(
        clip.source.cacheKey,
        () => clip.source.render(sampleRate),
      );
      if (rendered.isEmpty) continue;
      final pcm = _trimView(rendered, clip, sampleRate);
      if (pcm.isEmpty) continue;
      final start = (clip.startMs * sampleRate / 1000).round();
      // Computed rather than stretched — the length is all that is wanted here,
      // and WSOLA on every clip just to measure it would be absurd.
      final factor = clipWarpFactor(
        clip,
        tempoMap,
        sourceDurationMs: pcm.length * 1000 / sampleRate,
      );
      final length = warpFactorIsUsable(factor)
          ? (pcm.length * factor).round()
          : pcm.length;
      final end = start + length;
      if (end > total) total = end;
    }
  }
  return total;
}

/// Streams the timeline mix as a 16-bit little-endian **stereo** WAV in bounded
/// memory: the mix is rendered in [blockSamples]-frame windows — each touching
/// only the clips overlapping it, via [renderTimelineWindowStereo] — and each
/// chunk of bytes (the 44-byte header first) is handed to [onBytes]. The
/// whole-song mix is never allocated; peak memory is one window plus the
/// (input-bounded) clip cache, so a twenty-minute arrangement exports in the
/// memory of one window.
///
/// **Byte-identical** to
/// `pcmFloatToWav(renderTimelineStereo(t).left, right: ….right, sampleRate: sr)`
/// at the same [sampleRate] and 16-bit depth — the window render is a
/// byte-identical slice of the full render (its own pinned invariant), and the
/// header/sample encoding mirror `pcmFloatToWav`. Renders at the timeline's own
/// rate (no export-time resample), so the caller must export at [sampleRate].
///
/// A typical file writer: `final s = File(path).openWrite();
/// streamTimelineWav(t, onBytes: s.add); await s.close();`.
void streamTimelineWav(
  DawTimeline timeline, {
  required void Function(List<int> bytes) onBytes,
  int blockSamples = 1 << 15,
  int sampleRate = kDawSampleRate,
  Map<Object, Float64List>? cache,
}) {
  final store = cache ?? <Object, Float64List>{};
  final frames =
      dawTimelineLengthSamples(timeline, sampleRate: sampleRate, cache: store);
  const channels = 2;
  const blockAlign = channels * 2; // 16-bit
  final dataSize = frames * blockAlign;

  final header = Uint8List(44);
  final hb = ByteData.sublistView(header);
  void ascii(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      header[o + i] = s.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  hb.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  hb.setUint32(16, 16, Endian.little);
  hb.setUint16(20, 1, Endian.little); // PCM
  hb.setUint16(22, channels, Endian.little);
  hb.setUint32(24, sampleRate, Endian.little);
  hb.setUint32(28, sampleRate * blockAlign, Endian.little);
  hb.setUint16(32, blockAlign, Endian.little);
  hb.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  hb.setUint32(40, dataSize, Endian.little);
  onBytes(header);
  if (frames == 0) return;

  final block = blockSamples < 1 ? 1 : blockSamples;
  for (var from = 0; from < frames; from += block) {
    final to = from + block > frames ? frames : from + block;
    final mix = renderTimelineWindowStereo(
      timeline,
      fromSample: from,
      toSample: to,
      sampleRate: sampleRate,
      cache: store,
    );
    final n = to - from;
    final bytes = Uint8List(n * blockAlign);
    final bb = ByteData.sublistView(bytes);
    var off = 0;
    for (var i = 0; i < n; i++) {
      final l = i < mix.left.length ? mix.left[i] : 0.0;
      bb.setInt16(off, (l.clamp(-1.0, 1.0) * 32767).round(), Endian.little);
      off += 2;
      final r = i < mix.right.length ? mix.right[i] : 0.0;
      bb.setInt16(off, (r.clamp(-1.0, 1.0) * 32767).round(), Endian.little);
      off += 2;
    }
    onBytes(bytes);
  }
}

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

/// The clip envelope's multiplier at [msIntoClip] — 1 outside the authored
/// points, so a partial envelope leaves the rest of the clip alone.
///
/// Indexed from the CLIP's start rather than the timeline's, which is the whole
/// difference from lane automation: the shape travels with the take.
double clipEnvelopeAt(List<DawAutomationPoint> points, double msIntoClip) {
  if (points.isEmpty) return 1;
  return _trackAutomationValue(points, msIntoClip);
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
