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

import 'package:comet_beat/core/audio/crisp_dsp/biquad.dart'
    show BiquadKind, biquadFx;
import 'package:comet_beat/core/audio/crisp_dsp/distortion.dart'
    show distortionFx;
import 'package:comet_beat/core/audio/crisp_dsp/dynamics.dart'
    show compressorFx, compressorFxStereo, gateFx, gateFxStereo;
import 'package:comet_beat/core/audio/crisp_dsp/modulated_delay.dart'
    show
        chorusFx,
        chorusFxStereo,
        delayFx,
        delayFxStereo,
        flangerFx,
        flangerFxStereo;
import 'package:comet_beat/core/audio/crisp_dsp/pitch_shift.dart'
    show granularPitchShift, granularPitchShiftStereo;
import 'package:comet_beat/core/audio/crisp_dsp/resample.dart'
    show resampleCubic;
import 'package:comet_beat/core/audio/crisp_dsp/reverb.dart'
    show reverbFx, reverbFxStereo;
import 'package:comet_beat/core/audio/crisp_dsp/ring_mod.dart' show ringModFx;
import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart'
    show timeStretch, timeStretchStereo;
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart'
    show VoiceEffect, applyVoiceEffect, voiceShapeFx, voiceShapeFxStereo;
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

/// A typed per-clip effect, matching CrispAudio's segment-effect-chain model:
/// each clip can carry an ordered list of same-length DSP transforms, each with
/// its own params and bypass state.
class DawClipEffect {
  const DawClipEffect({
    required this.type,
    this.enabled = true,
    this.params = const {},
    this.automation = const {},
  });

  final DawClipEffectType type;
  final bool enabled;
  final Map<String, double> params;
  final Map<String, List<DawAutomationPoint>> automation;

  DawClipEffect copyWith({
    DawClipEffectType? type,
    bool? enabled,
    Map<String, double>? params,
    Map<String, List<DawAutomationPoint>>? automation,
  }) =>
      DawClipEffect(
        type: type ?? this.type,
        enabled: enabled ?? this.enabled,
        params: params ?? this.params,
        automation: automation ?? this.automation,
      );

  Object get cacheKey => (
        type.name,
        enabled,
        Object.hashAll(
          [
            for (final e
                in params.entries.toList()
                  ..sort((a, b) => a.key.compareTo(b.key)))
              Object.hash(e.key, e.value),
          ],
        ),
        Object.hashAll(
          [
            for (final e
                in automation.entries.toList()
                  ..sort((a, b) => a.key.compareTo(b.key)))
              Object.hash(
                e.key,
                Object.hashAll([
                  for (final p in e.value) Object.hash(p.ms, p.value),
                ]),
              ),
          ],
        ),
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'enabled': enabled,
        'params': params,
        if (automation.isNotEmpty)
          'automation': {
            for (final entry in automation.entries)
              if (entry.value.isNotEmpty)
                entry.key: [for (final p in entry.value) p.toJson()],
          },
      };

  static DawClipEffect? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final typeName = raw['type'];
    if (typeName is! String) return null;
    final type =
        DawClipEffectType.values.where((t) => t.name == typeName).firstOrNull;
    if (type == null) return null;
    final p = <String, double>{};
    final params = raw['params'];
    if (params is Map) {
      for (final e in params.entries) {
        final k = e.key;
        final v = e.value;
        if (k is String && v is num) p[k] = v.toDouble();
      }
    }
    final automation = <String, List<DawAutomationPoint>>{};
    final rawAutomation = raw['automation'];
    if (rawAutomation is Map) {
      for (final e in rawAutomation.entries) {
        final key = e.key;
        final value = e.value;
        if (key is! String || value is! List) continue;
        final points = [
          for (final point in value)
            if (DawAutomationPoint.fromJson(point) case final parsed?) parsed,
        ]..sort((a, b) => a.ms.compareTo(b.ms));
        if (points.isNotEmpty) automation[key] = points;
      }
    }
    return DawClipEffect(
      type: type,
      enabled: raw['enabled'] != false,
      params: p,
      automation: automation,
    );
  }
}

enum DawClipEffectType {
  gain,
  pan,
  reverb,
  delay,
  chorus,
  flanger,
  ringMod,
  distortion,
  bitCrush,
  lowpass,
  highpass,
  compressor,
  gate,
  pitchShift,
  timeStretch,
  tremolo,
  vocoder,
  voiceShape,
  voiceChipmunk,
  voiceDeep,
  voiceRobot,
  voiceRadio,
}

enum DawClipEffectPreset {
  vocalPolish,
  lofiCrunch,
  wideSpace,
  robotVoice,
}

DawClipEffect defaultDawClipEffect(DawClipEffectType type) => switch (type) {
      DawClipEffectType.gain => const DawClipEffect(
          type: DawClipEffectType.gain,
          params: {'gainDb': 0, 'mix': 1},
        ),
      DawClipEffectType.pan => const DawClipEffect(
          type: DawClipEffectType.pan,
          params: {'pan': 0},
        ),
      DawClipEffectType.reverb => const DawClipEffect(
          type: DawClipEffectType.reverb,
          params: {
            'roomSize': 0.7,
            'damping': 0.4,
            'decay': 1.5,
            'mix': 0.35,
          },
        ),
      DawClipEffectType.delay => const DawClipEffect(
          type: DawClipEffectType.delay,
          params: {
            'delayMs': 300,
            'feedback': 0.35,
            'spread': 0.2,
            'mix': 0.35,
          },
        ),
      DawClipEffectType.chorus => const DawClipEffect(
          type: DawClipEffectType.chorus,
          params: {'rateHz': 1.5, 'depthMs': 6, 'mix': 0.45},
        ),
      DawClipEffectType.flanger => const DawClipEffect(
          type: DawClipEffectType.flanger,
          params: {'rateHz': 0.35, 'depthMs': 3, 'feedback': 0.5, 'mix': 0.5},
        ),
      DawClipEffectType.ringMod => const DawClipEffect(
          type: DawClipEffectType.ringMod,
          params: {'carrierHz': 180, 'mix': 0.5},
        ),
      DawClipEffectType.distortion => const DawClipEffect(
          type: DawClipEffectType.distortion,
          params: {'drive': 4, 'mix': 0.55},
        ),
      DawClipEffectType.bitCrush => const DawClipEffect(
          type: DawClipEffectType.bitCrush,
          params: {'bits': 8, 'mix': 0.55},
        ),
      DawClipEffectType.lowpass => const DawClipEffect(
          type: DawClipEffectType.lowpass,
          params: {'freq': 8000, 'q': 0.707, 'mix': 1},
        ),
      DawClipEffectType.highpass => const DawClipEffect(
          type: DawClipEffectType.highpass,
          params: {'freq': 180, 'q': 0.707, 'mix': 1},
        ),
      DawClipEffectType.compressor => const DawClipEffect(
          type: DawClipEffectType.compressor,
          params: {
            'thresholdDb': -18,
            'ratio': 4,
            'attackMs': 10,
            'releaseMs': 120,
            'kneeDb': 6,
            'makeupDb': 0,
            'mix': 1,
          },
        ),
      DawClipEffectType.gate => const DawClipEffect(
          type: DawClipEffectType.gate,
          params: {
            'thresholdDb': -40,
            'ratio': 4,
            'rangeDb': -60,
            'attackMs': 1,
            'releaseMs': 100,
            'mix': 1,
          },
        ),
      DawClipEffectType.pitchShift => const DawClipEffect(
          type: DawClipEffectType.pitchShift,
          params: {'semitones': 12, 'mix': 1},
        ),
      DawClipEffectType.timeStretch => const DawClipEffect(
          type: DawClipEffectType.timeStretch,
          params: {'speed': 0.75, 'mix': 1},
        ),
      DawClipEffectType.tremolo => const DawClipEffect(
          type: DawClipEffectType.tremolo,
          params: {'rateHz': 6, 'depth': 0.6, 'mix': 1},
        ),
      DawClipEffectType.vocoder => const DawClipEffect(
          type: DawClipEffectType.vocoder,
          params: {'carrierHz': 110, 'depth': 0.75, 'mix': 0.7},
        ),
      DawClipEffectType.voiceShape => const DawClipEffect(
          type: DawClipEffectType.voiceShape,
          params: {
            'formant': 0,
            'carrierHz': 80,
            'carrierMix': 0,
            'grit': 0,
            'radioLowHz': 300,
            'radioHighHz': 3200,
            'radioMix': 0,
            'mix': 1,
          },
        ),
      DawClipEffectType.voiceChipmunk => const DawClipEffect(
          type: DawClipEffectType.voiceChipmunk,
          params: {'mix': 1},
        ),
      DawClipEffectType.voiceDeep => const DawClipEffect(
          type: DawClipEffectType.voiceDeep,
          params: {'mix': 1},
        ),
      DawClipEffectType.voiceRobot => const DawClipEffect(
          type: DawClipEffectType.voiceRobot,
          params: {'mix': 1},
        ),
      DawClipEffectType.voiceRadio => const DawClipEffect(
          type: DawClipEffectType.voiceRadio,
          params: {'mix': 1},
        ),
    };

List<DawClipEffect> dawClipEffectPresetChain(DawClipEffectPreset preset) =>
    switch (preset) {
      DawClipEffectPreset.vocalPolish => [
          defaultDawClipEffect(DawClipEffectType.highpass).copyWith(
            params: {'freq': 120, 'q': 0.707, 'mix': 1},
          ),
          defaultDawClipEffect(DawClipEffectType.compressor).copyWith(
            params: {
              'thresholdDb': -22,
              'ratio': 3,
              'attackMs': 8,
              'releaseMs': 160,
              'kneeDb': 6,
              'makeupDb': 3,
              'mix': 1,
            },
          ),
          defaultDawClipEffect(DawClipEffectType.reverb).copyWith(
            params: {'roomSize': 0.42, 'damping': 0.55, 'mix': 0.18},
          ),
        ],
      DawClipEffectPreset.lofiCrunch => [
          defaultDawClipEffect(DawClipEffectType.highpass).copyWith(
            params: {'freq': 180, 'q': 0.707, 'mix': 1},
          ),
          defaultDawClipEffect(DawClipEffectType.lowpass).copyWith(
            params: {'freq': 4200, 'q': 0.8, 'mix': 1},
          ),
          defaultDawClipEffect(DawClipEffectType.bitCrush).copyWith(
            params: {'bits': 7, 'mix': 0.38},
          ),
          defaultDawClipEffect(DawClipEffectType.distortion).copyWith(
            params: {'drive': 2.2, 'mix': 0.28},
          ),
        ],
      DawClipEffectPreset.wideSpace => [
          defaultDawClipEffect(DawClipEffectType.chorus).copyWith(
            params: {'rateHz': 0.8, 'depthMs': 9, 'mix': 0.35},
          ),
          defaultDawClipEffect(DawClipEffectType.delay).copyWith(
            params: {'delayMs': 260, 'feedback': 0.28, 'mix': 0.24},
          ),
          defaultDawClipEffect(DawClipEffectType.reverb).copyWith(
            params: {'roomSize': 0.78, 'damping': 0.38, 'mix': 0.32},
          ),
        ],
      DawClipEffectPreset.robotVoice => [
          defaultDawClipEffect(DawClipEffectType.voiceRobot),
          defaultDawClipEffect(DawClipEffectType.ringMod).copyWith(
            params: {'carrierHz': 92, 'mix': 0.34},
          ),
          defaultDawClipEffect(DawClipEffectType.highpass).copyWith(
            params: {'freq': 220, 'q': 0.707, 'mix': 1},
          ),
        ],
    };

/// Fade curve shapes for clip edges, matching CrispAudio's timeline segments.
enum DawFadeCurve { linear, exponential, sCurve }

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
      TrackEffect.voiceChipmunk =>
        defaultDawClipEffect(DawClipEffectType.voiceChipmunk),
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

/// A track-level gain automation breakpoint. Values are linear gain
/// multipliers; outside the authored point span the automation multiplier is 1.
class DawAutomationPoint {
  const DawAutomationPoint({
    required this.ms,
    required this.value,
    this.curve = DawFadeCurve.linear,
  });

  final double ms;
  final double value;
  final DawFadeCurve curve;

  DawAutomationPoint copyWith({
    double? ms,
    double? value,
    DawFadeCurve? curve,
  }) =>
      DawAutomationPoint(
        ms: ms ?? this.ms,
        value: value ?? this.value,
        curve: curve ?? this.curve,
      );

  Map<String, dynamic> toJson() => {
        'ms': ms,
        'value': value,
        if (curve != DawFadeCurve.linear) 'curve': curve.name,
      };

  static DawAutomationPoint? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final ms = raw['ms'];
    final value = raw['value'];
    if (ms is! num || value is! num) return null;
    final curveName = raw['curve'];
    final curve = curveName is String
        ? DawFadeCurve.values
            .where((curve) => curve.name == curveName)
            .firstOrNull
        : null;
    return DawAutomationPoint(
      ms: ms.toDouble(),
      value: value.toDouble(),
      curve: curve ?? DawFadeCurve.linear,
    );
  }
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

Float64List applyClipEffectChain(
  Float64List input,
  List<DawClipEffect> effects,
  int sampleRate,
) {
  var out = input;
  for (final fx in effects) {
    if (!fx.enabled) continue;
    out = _applyClipEffect(out, fx, sampleRate);
  }
  return out;
}

({Float64List left, Float64List right}) _applyStereoClipEffectChain(
  Float64List left,
  Float64List right,
  List<DawClipEffect> effects,
  int sampleRate,
) {
  var outLeft = left;
  var outRight = right;
  for (final fx in effects) {
    if (!fx.enabled) continue;
    if (fx.automation.isNotEmpty) {
      final automated = _applyAutomatedStereoClipEffect(
        outLeft,
        outRight,
        fx,
        sampleRate,
      );
      outLeft = automated.left;
      outRight = automated.right;
      continue;
    }
    double p(String key, double fallback) => fx.params[key] ?? fallback;
    final processed = switch (fx.type) {
      DawClipEffectType.pan => _panFxStereo(
          outLeft,
          outRight,
          pan: p('pan', 0),
        ),
      DawClipEffectType.delay => delayFxStereo(
          outLeft,
          outRight,
          delayMs: p('delayMs', 300),
          feedback: p('feedback', 0.35),
          spread: p('spread', 0),
          mix: p('mix', 0.35),
          sampleRate: sampleRate,
        ),
      DawClipEffectType.chorus => chorusFxStereo(
          outLeft,
          outRight,
          rateHz: p('rateHz', 1.5),
          depthMs: p('depthMs', 6),
          mix: p('mix', 0.45),
          sampleRate: sampleRate,
        ),
      DawClipEffectType.flanger => flangerFxStereo(
          outLeft,
          outRight,
          rateHz: p('rateHz', 0.35),
          depthMs: p('depthMs', 3),
          feedback: p('feedback', 0.5),
          mix: p('mix', 0.5),
          sampleRate: sampleRate,
        ),
      DawClipEffectType.reverb => reverbFxStereo(
          outLeft,
          outRight,
          roomSize: p('roomSize', 0.7),
          damping: p('damping', 0.4),
          decay: p('decay', 1.5),
          mix: p('mix', 0.35),
          sampleRate: sampleRate,
        ),
      DawClipEffectType.vocoder => _vocoderFxStereo(
          outLeft,
          outRight,
          sampleRate: sampleRate,
          carrierHz: p('carrierHz', 110),
          depth: p('depth', 0.75),
          mix: p('mix', 0.7),
        ),
      DawClipEffectType.voiceShape => voiceShapeFxStereo(
          outLeft,
          outRight,
          formant: p('formant', 0),
          carrierHz: p('carrierHz', 80),
          carrierMix: p('carrierMix', 0),
          grit: p('grit', 0),
          radioLowHz: p('radioLowHz', 300),
          radioHighHz: p('radioHighHz', 3200),
          radioMix: p('radioMix', 0),
          mix: p('mix', 1),
          sampleRate: sampleRate,
        ),
      DawClipEffectType.compressor => compressorFxStereo(
          outLeft,
          outRight,
          sampleRate: sampleRate.toDouble(),
          thresholdDb: p('thresholdDb', -18),
          ratio: p('ratio', 4),
          attackMs: p('attackMs', 10),
          releaseMs: p('releaseMs', 120),
          kneeDb: p('kneeDb', 6),
          makeupDb: p('makeupDb', 0),
          mix: p('mix', 1),
        ),
      DawClipEffectType.gate => gateFxStereo(
          outLeft,
          outRight,
          sampleRate: sampleRate.toDouble(),
          thresholdDb: p('thresholdDb', -40),
          ratio: p('ratio', 4),
          rangeDb: p('rangeDb', -60),
          attackMs: p('attackMs', 1),
          releaseMs: p('releaseMs', 100),
          mix: p('mix', 1),
        ),
      DawClipEffectType.pitchShift => _pitchShiftFxStereo(
          outLeft,
          outRight,
          semitones: p('semitones', 12),
          mix: p('mix', 1),
        ),
      DawClipEffectType.timeStretch => _timeStretchFxStereo(
          outLeft,
          outRight,
          speed: p('speed', 0.75),
          mix: p('mix', 1),
          sampleRate: sampleRate,
        ),
      _ => (
          left: _applyClipEffect(outLeft, fx, sampleRate),
          right: _applyClipEffect(outRight, fx, sampleRate),
        ),
    };
    outLeft = processed.left;
    outRight = processed.right;
  }
  return (left: outLeft, right: outRight);
}

/// Applies an ordered FX chain to stereo analysis buffers using the same path
/// as timeline rendering.
({Float64List left, Float64List right}) applyStereoClipEffectChain(
  Float64List left,
  Float64List right,
  List<DawClipEffect> effects,
  int sampleRate,
) =>
    _applyStereoClipEffectChain(left, right, effects, sampleRate);

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

Float64List _applyClipEffect(
  Float64List input,
  DawClipEffect fx,
  int sampleRate,
) {
  if (fx.automation.isNotEmpty) {
    return _applyAutomatedClipEffect(input, fx, sampleRate);
  }
  double p(String key, double fallback) => fx.params[key] ?? fallback;
  return switch (fx.type) {
    DawClipEffectType.gain => _gainFx(
        input,
        gainDb: p('gainDb', 0),
        mix: p('mix', 1),
      ),
    // The mono wrapper folds the stereo render after the full FX graph.
    DawClipEffectType.pan => Float64List.fromList(input),
    DawClipEffectType.reverb => reverbFx(
        input,
        roomSize: p('roomSize', 0.7),
        damping: p('damping', 0.4),
        decay: p('decay', 1.5),
        mix: p('mix', 0.35),
        sampleRate: sampleRate,
      ),
    DawClipEffectType.delay => delayFx(
        input,
        delayMs: p('delayMs', 300),
        feedback: p('feedback', 0.35),
        mix: p('mix', 0.35),
        sampleRate: sampleRate,
      ),
    DawClipEffectType.chorus => chorusFx(
        input,
        rateHz: p('rateHz', 1.5),
        depthMs: p('depthMs', 6),
        mix: p('mix', 0.45),
        sampleRate: sampleRate,
      ),
    DawClipEffectType.flanger => flangerFx(
        input,
        rateHz: p('rateHz', 0.35),
        depthMs: p('depthMs', 3),
        feedback: p('feedback', 0.5),
        mix: p('mix', 0.5),
        sampleRate: sampleRate,
      ),
    DawClipEffectType.ringMod => ringModFx(
        input,
        carrierHz: p('carrierHz', 180),
        mix: p('mix', 0.5),
        sampleRate: sampleRate,
      ),
    DawClipEffectType.distortion => distortionFx(
        input,
        drive: p('drive', 4),
        mix: p('mix', 0.55),
      ),
    DawClipEffectType.bitCrush => _bitCrushFx(
        input,
        bits: p('bits', 8),
        mix: p('mix', 0.55),
      ),
    DawClipEffectType.lowpass => biquadFx(
        input,
        sampleRate: sampleRate.toDouble(),
        freq: p('freq', 8000),
        q: p('q', 0.707),
        mix: p('mix', 1),
      ),
    DawClipEffectType.highpass => biquadFx(
        input,
        kind: BiquadKind.highpass,
        sampleRate: sampleRate.toDouble(),
        freq: p('freq', 180),
        q: p('q', 0.707),
        mix: p('mix', 1),
      ),
    DawClipEffectType.compressor => compressorFx(
        input,
        sampleRate: sampleRate.toDouble(),
        thresholdDb: p('thresholdDb', -18),
        ratio: p('ratio', 4),
        attackMs: p('attackMs', 10),
        releaseMs: p('releaseMs', 120),
        kneeDb: p('kneeDb', 6),
        makeupDb: p('makeupDb', 0),
        mix: p('mix', 1),
      ),
    DawClipEffectType.gate => gateFx(
        input,
        sampleRate: sampleRate.toDouble(),
        thresholdDb: p('thresholdDb', -40),
        ratio: p('ratio', 4),
        rangeDb: p('rangeDb', -60),
        attackMs: p('attackMs', 1),
        releaseMs: p('releaseMs', 100),
        mix: p('mix', 1),
      ),
    DawClipEffectType.pitchShift => _blendWetDry(
        input,
        _fitLength(
          granularPitchShift(input, p('semitones', 12)),
          input.length,
        ),
        p('mix', 1),
      ),
    DawClipEffectType.timeStretch => _blendWetDry(
        input,
        _fitLength(
          timeStretch(
            input,
            1 / p('speed', 0.75).clamp(0.1, 4.0),
            sampleRate: sampleRate,
          ),
          input.length,
        ),
        p('mix', 1),
      ),
    DawClipEffectType.tremolo => _tremoloFx(
        input,
        sampleRate: sampleRate,
        rateHz: p('rateHz', 6),
        depth: p('depth', 0.6),
        mix: p('mix', 1),
      ),
    DawClipEffectType.vocoder => _vocoderFx(
        input,
        sampleRate: sampleRate,
        carrierHz: p('carrierHz', 110),
        depth: p('depth', 0.75),
        mix: p('mix', 0.7),
      ),
    DawClipEffectType.voiceShape => voiceShapeFx(
        input,
        sampleRate: sampleRate,
        formant: p('formant', 0),
        carrierHz: p('carrierHz', 80),
        carrierMix: p('carrierMix', 0),
        grit: p('grit', 0),
        radioLowHz: p('radioLowHz', 300),
        radioHighHz: p('radioHighHz', 3200),
        radioMix: p('radioMix', 0),
        mix: p('mix', 1),
      ),
    DawClipEffectType.voiceChipmunk => _blendWetDry(
        input,
        applyVoiceEffect(input, VoiceEffect.chipmunk, sampleRate: sampleRate),
        p('mix', 1),
      ),
    DawClipEffectType.voiceDeep => _blendWetDry(
        input,
        applyVoiceEffect(input, VoiceEffect.deep, sampleRate: sampleRate),
        p('mix', 1),
      ),
    DawClipEffectType.voiceRobot => _blendWetDry(
        input,
        applyVoiceEffect(input, VoiceEffect.robot, sampleRate: sampleRate),
        p('mix', 1),
      ),
    DawClipEffectType.voiceRadio => _blendWetDry(
        input,
        applyVoiceEffect(input, VoiceEffect.radio, sampleRate: sampleRate),
        p('mix', 1),
      ),
  };
}

Float64List _gainFx(
  Float64List input, {
  required double gainDb,
  required double mix,
}) {
  final gain = math.pow(10, gainDb.clamp(-80.0, 48.0) / 20).toDouble();
  final wet = mix.clamp(0.0, 1.0);
  final dry = 1 - wet;
  final out = Float64List(input.length);
  for (var i = 0; i < input.length; i++) {
    out[i] = input[i] * (dry + gain * wet);
  }
  return out;
}

({Float64List left, Float64List right}) _pitchShiftFxStereo(
  Float64List left,
  Float64List right, {
  required double semitones,
  required double mix,
}) {
  final shifted = granularPitchShiftStereo(left, right, semitones);
  return (
    left: _blendWetDry(left, _fitLength(shifted.left, left.length), mix),
    right: _blendWetDry(right, _fitLength(shifted.right, right.length), mix),
  );
}

({Float64List left, Float64List right}) _timeStretchFxStereo(
  Float64List left,
  Float64List right, {
  required double speed,
  required double mix,
  required int sampleRate,
}) {
  final stretched = timeStretchStereo(
    left,
    right,
    1 / speed.clamp(0.1, 4.0),
    sampleRate: sampleRate,
  );
  return (
    left: _blendWetDry(left, _fitLength(stretched.left, left.length), mix),
    right: _blendWetDry(right, _fitLength(stretched.right, right.length), mix),
  );
}

Float64List _applyAutomatedClipEffect(
  Float64List input,
  DawClipEffect fx,
  int sampleRate,
) {
  if (input.isEmpty) return input;
  final automation = <String, List<DawAutomationPoint>>{};
  for (final entry in fx.automation.entries) {
    final points = [
      for (final point in entry.value)
        if (point.ms.isFinite && point.value.isFinite)
          DawAutomationPoint(
            ms: point.ms < 0 ? 0 : point.ms,
            value: point.value,
          ),
    ]..sort((a, b) => a.ms.compareTo(b.ms));
    if (points.isNotEmpty) automation[entry.key] = points;
  }
  if (automation.isEmpty) {
    return _applyClipEffect(
      input,
      fx.copyWith(automation: const {}),
      sampleRate,
    );
  }
  final block = math.max(64, (sampleRate / 50).round());
  final out = Float64List(input.length);
  for (var start = 0; start < input.length; start += block) {
    final end = math.min(input.length, start + block);
    final ms = start * 1000 / sampleRate;
    final params = {...fx.params};
    for (final entry in automation.entries) {
      params[entry.key] = _paramAutomationValue(
        entry.value,
        ms,
        fx.params[entry.key] ?? 0,
      );
    }
    final processed = _fitLength(
      _applyClipEffect(
        Float64List.sublistView(input, start, end),
        fx.copyWith(params: params, automation: const {}),
        sampleRate,
      ),
      end - start,
    );
    out.setRange(start, end, processed);
  }
  return out;
}

({Float64List left, Float64List right}) _applyAutomatedStereoClipEffect(
  Float64List left,
  Float64List right,
  DawClipEffect fx,
  int sampleRate,
) {
  if (left.isEmpty && right.isEmpty) return (left: left, right: right);
  final block = math.max(64, (sampleRate / 50).round());
  final outLeft = Float64List(left.length);
  final outRight = Float64List(right.length);
  for (var start = 0; start < left.length; start += block) {
    final end = math.min(left.length, start + block);
    final ms = start * 1000 / sampleRate;
    final params = {...fx.params};
    for (final entry in fx.automation.entries) {
      params[entry.key] = _paramAutomationValue(
        entry.value,
        ms,
        fx.params[entry.key] ?? 0,
      );
    }
    final processed = _applyStereoClipEffectChain(
      Float64List.sublistView(left, start, end),
      Float64List.sublistView(right, start, end),
      [fx.copyWith(params: params, automation: const {})],
      sampleRate,
    );
    outLeft.setRange(start, end, processed.left);
    outRight.setRange(start, end, processed.right);
  }
  return (left: outLeft, right: outRight);
}

double _paramAutomationValue(
  List<DawAutomationPoint> points,
  double ms,
  double fallback,
) {
  if (points.length == 1) {
    return (ms - points.single.ms).abs() < 0.5 ? points.single.value : fallback;
  }
  if (ms < points.first.ms || ms > points.last.ms) return fallback;
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
    if (ms < a.ms || ms > b.ms) continue;
    if (b.ms <= a.ms) return b.value;
    final t = _fadeCurveValue((ms - a.ms) / (b.ms - a.ms), a.curve);
    return a.value + (b.value - a.value) * t;
  }
  return points.last.value;
}

Float64List _blendWetDry(Float64List dry, Float64List wet, double mix) {
  final m = mix.clamp(0.0, 1.0);
  if (m == 0) {
    final out = Float64List(dry.length);
    out.setAll(0, dry);
    return out;
  }
  if (m == 1 && wet.length == dry.length) return wet;
  final n = dry.length > wet.length ? dry.length : wet.length;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final d = i < dry.length ? dry[i] : 0.0;
    final w = i < wet.length ? wet[i] : 0.0;
    out[i] = (1 - m) * d + m * w;
  }
  return out;
}

({Float64List left, Float64List right}) _panFxStereo(
  Float64List left,
  Float64List right, {
  required double pan,
}) {
  final p = pan.clamp(-1.0, 1.0).toDouble();
  final leftGain = p <= 0 ? 1.0 : math.cos(p * math.pi / 2);
  final rightGain = p >= 0 ? 1.0 : math.cos(p * math.pi / 2);
  final outLeft = Float64List(left.length);
  final outRight = Float64List(right.length);
  for (var i = 0; i < left.length; i++) {
    outLeft[i] = left[i] * leftGain;
  }
  for (var i = 0; i < right.length; i++) {
    outRight[i] = right[i] * rightGain;
  }
  return (left: outLeft, right: outRight);
}

Float64List _tremoloFx(
  Float64List input, {
  required int sampleRate,
  double rateHz = 6,
  double depth = 0.6,
  double mix = 1,
}) {
  final d = depth.clamp(0.0, 1.0);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0 || input.isEmpty) return Float64List.fromList(input);
  final hz = rateHz.clamp(0.05, sampleRate / 2).toDouble();
  final out = Float64List(input.length);
  for (var i = 0; i < input.length; i++) {
    final lfo = (1 + math.sin(2 * math.pi * hz * i / sampleRate)) * 0.5;
    final amp = 1 - d + d * lfo;
    final wet = input[i] * amp;
    out[i] = input[i] * (1 - m) + wet * m;
  }
  return out;
}

Float64List _vocoderFx(
  Float64List input, {
  required int sampleRate,
  double carrierHz = 110,
  double depth = 0.75,
  double mix = 0.7,
}) {
  final d = depth.clamp(0.0, 1.0);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0 || input.isEmpty) return Float64List.fromList(input);
  final hz = carrierHz.clamp(20.0, sampleRate / 2).toDouble();
  final out = Float64List(input.length);
  var envelope = 0.0;
  const attack = 0.18;
  const release = 0.018;
  for (var i = 0; i < input.length; i++) {
    final level = input[i].abs();
    envelope += (level - envelope) * (level > envelope ? attack : release);
    final carrier = math.sin(2 * math.pi * hz * i / sampleRate);
    final wet = input[i] * (1 - d) + carrier * envelope * d;
    out[i] = input[i] * (1 - m) + wet * m;
  }
  return out;
}

({Float64List left, Float64List right}) _vocoderFxStereo(
  Float64List left,
  Float64List right, {
  required int sampleRate,
  double carrierHz = 110,
  double depth = 0.75,
  double mix = 0.7,
}) {
  final d = depth.clamp(0.0, 1.0);
  final m = mix.clamp(0.0, 1.0);
  final outLeft = Float64List(left.length);
  final outRight = Float64List(right.length);
  if (m == 0) {
    outLeft.setAll(0, left);
    outRight.setAll(0, right);
    return (left: outLeft, right: outRight);
  }
  final hz = carrierHz.clamp(20.0, sampleRate / 2).toDouble();
  const attack = 0.18;
  const release = 0.018;
  var envelopeLeft = 0.0;
  var envelopeRight = 0.0;
  final frames = math.min(left.length, right.length);
  for (var i = 0; i < frames; i++) {
    final levelLeft = left[i].abs();
    final levelRight = right[i].abs();
    envelopeLeft += (levelLeft - envelopeLeft) *
        (levelLeft > envelopeLeft ? attack : release);
    envelopeRight += (levelRight - envelopeRight) *
        (levelRight > envelopeRight ? attack : release);
    final phase = 2 * math.pi * hz * i / sampleRate;
    final wetLeft = left[i] * (1 - d) + math.sin(phase) * envelopeLeft * d;
    final wetRight =
        right[i] * (1 - d) + math.sin(phase + math.pi / 2) * envelopeRight * d;
    outLeft[i] = left[i] * (1 - m) + wetLeft * m;
    outRight[i] = right[i] * (1 - m) + wetRight * m;
  }
  for (var i = frames; i < left.length; i++) {
    outLeft[i] = left[i];
  }
  for (var i = frames; i < right.length; i++) {
    outRight[i] = right[i];
  }
  return (left: outLeft, right: outRight);
}

Float64List _fitLength(Float64List input, int length) {
  if (input.length == length) return input;
  if (length <= 0) return Float64List(0);
  if (input.isEmpty) return Float64List(length);
  final resized = resampleCubic(input, input.length / length);
  if (resized.length == length) return resized;
  final out = Float64List(length);
  out.setRange(0, math.min(length, resized.length), resized);
  return out;
}

Float64List _bitCrushFx(
  Float64List input, {
  double bits = 8,
  double mix = 0.55,
}) {
  final m = mix.clamp(0.0, 1.0);
  final out = Float64List(input.length);
  if (m == 0) {
    out.setAll(0, input);
    return out;
  }
  final b = bits.round().clamp(1, 16);
  final levels = math.pow(2, b - 1).toDouble();
  for (var i = 0; i < input.length; i++) {
    final dry = input[i];
    final wet = (dry * levels).floorToDouble() / levels;
    out[i] = (1 - m) * dry + m * wet;
  }
  return out;
}

/// A DAW arrangement: an ordered list of tracks.
class DawTimeline {
  DawTimeline({
    List<DawTrack>? tracks,
    List<DawBus>? buses,
    List<DawClipEffect>? effects,
  })  : tracks = tracks ?? [],
        buses = buses ?? [],
        effects = effects ?? [];
  final List<DawTrack> tracks;

  /// Named group buses. Tracks route here via [DawTrack.busIndex].
  final List<DawBus> buses;

  /// Ordered output-bus FX applied to the full mix before final limiting.
  List<DawClipEffect> effects;
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
        })>
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
              ? _applyStereoClipEffectChain(
                  pcm,
                  rightPcm,
                  clip.effects,
                  sampleRate,
                )
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
          env = _fadeCurveValue(i / p.fadeIn, p.fadeInCurve);
        }
        if (p.fadeOut > 0 && i >= n - p.fadeOut) {
          final down = _fadeCurveValue((n - i) / p.fadeOut, p.fadeOutCurve);
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
        final processed = _applyStereoClipEffectChain(
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
        : _applyStereoClipEffectChain(
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
      : _applyStereoClipEffectChain(
          left,
          right,
          timeline.effects,
          sampleRate,
        );
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

double _fadeCurveValue(double value, DawFadeCurve curve) {
  final t = value.clamp(0.0, 1.0).toDouble();
  return switch (curve) {
    DawFadeCurve.linear => t,
    DawFadeCurve.exponential => t * t,
    DawFadeCurve.sCurve => t * t * (3 - 2 * t),
  };
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
    final t = _fadeCurveValue((ms - a.ms) / (b.ms - a.ms), a.curve);
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
