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
    show compressorFx, gateFx;
import 'package:comet_beat/core/audio/crisp_dsp/modulated_delay.dart'
    show chorusFx, delayFx, flangerFx;
import 'package:comet_beat/core/audio/crisp_dsp/pitch_shift.dart'
    show granularPitchShift;
import 'package:comet_beat/core/audio/crisp_dsp/resample.dart'
    show resampleCubic;
import 'package:comet_beat/core/audio/crisp_dsp/reverb.dart' show reverbFx;
import 'package:comet_beat/core/audio/crisp_dsp/ring_mod.dart' show ringModFx;
import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart'
    show timeStretch;
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart'
    show VoiceEffect, applyVoiceEffect, voiceShapeFx;
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
      DawClipEffectType.reverb => const DawClipEffect(
          type: DawClipEffectType.reverb,
          params: {'roomSize': 0.7, 'damping': 0.4, 'mix': 0.35},
        ),
      DawClipEffectType.delay => const DawClipEffect(
          type: DawClipEffectType.delay,
          params: {'delayMs': 300, 'feedback': 0.35, 'mix': 0.35},
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
          params: {'thresholdDb': -40, 'ratio': 4, 'rangeDb': -60, 'mix': 1},
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
  const DawAutomationPoint({required this.ms, required this.value});

  final double ms;
  final double value;

  DawAutomationPoint copyWith({double? ms, double? value}) =>
      DawAutomationPoint(ms: ms ?? this.ms, value: value ?? this.value);

  Map<String, dynamic> toJson() => {'ms': ms, 'value': value};

  static DawAutomationPoint? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final ms = raw['ms'];
    final value = raw['value'];
    if (ms is! num || value is! num) return null;
    return DawAutomationPoint(
      ms: ms.toDouble(),
      value: value.toDouble(),
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
    DawClipEffectType.reverb => reverbFx(
        input,
        roomSize: p('roomSize', 0.7),
        damping: p('damping', 0.4),
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
    final t = ((ms - a.ms) / (b.ms - a.ms)).clamp(0.0, 1.0);
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
    List<
        ({
          int start,
          Float64List pcm,
          double gain,
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
      Float64List pcm,
      double gain,
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
      final pcm = _trimView(rendered, clip, sampleRate);
      if (pcm.isEmpty) continue;
      final effected = clip.effects.isEmpty
          ? pcm
          : applyClipEffectChain(pcm, clip.effects, sampleRate);
      final start = (clip.startMs * sampleRate / 1000).round();
      places.add(
        (
          start: start,
          pcm: effected,
          gain: clip.gain * track.gain,
          fadeIn: (clip.fadeInMs * sampleRate / 1000).round(),
          fadeOut: (clip.fadeOutMs * sampleRate / 1000).round(),
          fadeInCurve: clip.fadeInCurve,
          fadeOutCurve: clip.fadeOutCurve,
        ),
      );
      final end = start + effected.length;
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
    List<
            ({
              int start,
              Float64List pcm,
              double gain,
              int fadeIn,
              int fadeOut,
              DawFadeCurve fadeInCurve,
              DawFadeCurve fadeOutCurve,
            })>
        places,
  ) {
    for (final p in places) {
      final n = p.pcm.length;
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
        buf[p.start + i] += p.pcm[i] * p.gain * env;
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

  final busBuffers = <int, Float64List>{};

  for (final (track, places) in perTrack) {
    final lane = Float64List(totalSamples);
    if (track.effects.isEmpty && track.effect == TrackEffect.none) {
      mix(lane, places);
    } else {
      mix(lane, places);
      final wet = track.effects.isNotEmpty
          ? applyClipEffectChain(lane, track.effects, sampleRate)
          : applyTrackEffect(track.effect, lane, sampleRate);
      lane.setAll(0, wet);
    }
    if (track.gainAutomation.isNotEmpty) {
      _applyTrackGainAutomation(lane, track.gainAutomation, sampleRate);
    }
    for (final send in track.busSends.entries) {
      final sendBus = send.key;
      if (sendBus < 0 || sendBus >= timeline.buses.length) continue;
      addScaledBuffer(
        busBuffers.putIfAbsent(sendBus, () => Float64List(totalSamples)),
        lane,
        send.value,
      );
    }
    final busIndex = track.busIndex;
    if (busIndex != null && busIndex >= 0 && busIndex < timeline.buses.length) {
      addBuffer(
        busBuffers.putIfAbsent(busIndex, () => Float64List(totalSamples)),
        lane,
      );
    } else {
      addBuffer(master, lane);
    }
  }

  for (final entry in busBuffers.entries) {
    final bus = timeline.buses[entry.key];
    final wet = bus.effects.isEmpty
        ? entry.value
        : applyClipEffectChain(entry.value, bus.effects, sampleRate);
    addBuffer(master, wet);
  }

  final out = timeline.effects.isEmpty
      ? master
      : applyClipEffectChain(master, timeline.effects, sampleRate);

  if (limit) {
    for (var i = 0; i < out.length; i++) {
      final x = out[i];
      // Soft-knee: transparent below ~0.6, tanh-limited toward the rails so
      // overlapping clips round off instead of hard-clipping.
      if (x.abs() > 0.6) {
        out[i] = x.sign * (0.6 + _tanh((x.abs() - 0.6) / 0.4) * 0.4);
      }
    }
  }
  return out;
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
    final t = ((ms - a.ms) / (b.ms - a.ms)).clamp(0.0, 1.0);
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
