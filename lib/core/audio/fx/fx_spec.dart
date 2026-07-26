// lib/core/audio/fx/fx_spec.dart
//
// The mode-neutral FX model — one effect vocabulary for all five authoring
// modes (Audio, Tracker, Loop, Instrument, Tab) over the shared `crisp_dsp/`
// primitives. Before this file each mode carried its own effect enum
// (`DawClipEffectType` 27 typed+automatable, `TrackerChannelEffect` 7 with
// hardcoded params, `VoiceEffect` 9 hardcoded, Tab none), so an effect authored
// in one mode could not travel to another.
//
// [FxSpec] is the superset: a type, a bypass flag, a free param map, and
// optional per-param automation. It is pure data — serialisable, comparable,
// and Flutter-free. The DSP dispatch lives next door in `fx_chain.dart`.
//
// The legacy per-mode enums survive as PRESET lookups that resolve to an
// [FxSpec] chain, so no persisted project or share token breaks.
//
// Renamed from the DAW-only originals in `daw_timeline.dart` (which now aliases
// the old names): DawClipEffect->FxSpec, DawClipEffectType->FxType,
// DawClipEffectPreset->FxPreset, DawAutomationPoint->FxAutomationPoint,
// DawFadeCurve->FxFadeCurve, defaultDawClipEffect->defaultFx,
// dawClipEffectPresetChain->fxPresetChain.

/// each clip can carry an ordered list of same-length DSP transforms, each with
/// its own params and bypass state.
class FxSpec {
  const FxSpec({
    required this.type,
    this.enabled = true,
    this.params = const {},
    this.automation = const {},
  });

  final FxType type;
  final bool enabled;
  final Map<String, double> params;
  final Map<String, List<FxAutomationPoint>> automation;

  FxSpec copyWith({
    FxType? type,
    bool? enabled,
    Map<String, double>? params,
    Map<String, List<FxAutomationPoint>>? automation,
  }) =>
      FxSpec(
        type: type ?? this.type,
        enabled: enabled ?? this.enabled,
        params: params ?? this.params,
        automation: automation ?? this.automation,
      );

  Object get cacheKey => (
        type.name,
        enabled,
        Object.hashAll([
          for (final e
              in params.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key)))
            Object.hash(e.key, e.value),
        ]),
        Object.hashAll([
          for (final e
              in automation.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key)))
            Object.hash(
              e.key,
              Object.hashAll([
                for (final p in e.value) Object.hash(p.ms, p.value),
              ]),
            ),
        ]),
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

  static FxSpec? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final typeName = raw['type'];
    if (typeName is! String) return null;
    final type = FxType.values.where((t) => t.name == typeName).firstOrNull;
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
    final automation = <String, List<FxAutomationPoint>>{};
    final rawAutomation = raw['automation'];
    if (rawAutomation is Map) {
      for (final e in rawAutomation.entries) {
        final key = e.key;
        final value = e.value;
        if (key is! String || value is! List) continue;
        final points = [
          for (final point in value)
            if (FxAutomationPoint.fromJson(point) case final parsed?) parsed,
        ]..sort((a, b) => a.ms.compareTo(b.ms));
        if (points.isNotEmpty) automation[key] = points;
      }
    }
    return FxSpec(
      type: type,
      enabled: raw['enabled'] != false,
      params: p,
      automation: automation,
    );
  }
}

enum FxType {
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
  // O11 — the rest of the biquad set plus a phaser. APPENDED deliberately:
  // `.cbdaw` stores an effect by `name`, but keeping the existing order also
  // keeps merges with the FX work happening in parallel clean.
  bandpass,
  notch,
  peakingEq,
  lowShelf,
  highShelf,
  phaser,

  /// Convolution reverb — a REAL-SPACE tail (convolve with a synthesized
  /// impulse response), where [reverb] is algorithmic Freeverb. The DSP was
  /// already written and tested but only reachable from the Voice Lab.
  convolutionReverb,
}

enum FxPreset { vocalPolish, lofiCrunch, wideSpace, robotVoice }

FxSpec defaultFx(FxType type) => switch (type) {
      FxType.gain => const FxSpec(
          type: FxType.gain,
          params: {'gainDb': 0, 'mix': 1},
        ),
      FxType.pan => const FxSpec(type: FxType.pan, params: {'pan': 0}),
      FxType.reverb => const FxSpec(
          type: FxType.reverb,
          params: {'roomSize': 0.7, 'damping': 0.4, 'decay': 1.5, 'mix': 0.35},
        ),
      FxType.delay => const FxSpec(
          type: FxType.delay,
          params: {
            'delayMs': 300,
            'feedback': 0.35,
            'spread': 0.2,
            'mix': 0.35,
          },
        ),
      FxType.chorus => const FxSpec(
          type: FxType.chorus,
          params: {'rateHz': 1.5, 'depthMs': 6, 'mix': 0.45},
        ),
      FxType.flanger => const FxSpec(
          type: FxType.flanger,
          params: {'rateHz': 0.35, 'depthMs': 3, 'feedback': 0.5, 'mix': 0.5},
        ),
      FxType.ringMod => const FxSpec(
          type: FxType.ringMod,
          params: {'carrierHz': 180, 'mix': 0.5},
        ),
      FxType.distortion => const FxSpec(
          type: FxType.distortion,
          // 'kind' is the DistortionKind index; 1 = soft clip, which is what the
          // dispatch falls back to, so a saved spec written before A3 (with no
          // 'kind' key at all) renders identically.
          params: {'kind': 1, 'drive': 4, 'mix': 0.55},
        ),
      FxType.bitCrush => const FxSpec(
          type: FxType.bitCrush,
          params: {'bits': 8, 'mix': 0.55},
        ),
      FxType.lowpass => const FxSpec(
          type: FxType.lowpass,
          params: {'freq': 8000, 'q': 0.707, 'mix': 1},
        ),
      FxType.highpass => const FxSpec(
          type: FxType.highpass,
          params: {'freq': 180, 'q': 0.707, 'mix': 1},
        ),
      // O11. Band-pass/notch want a tighter Q than the shelves; the bell and
      // the shelves carry a gainDb because they boost/cut rather than remove.
      FxType.bandpass => const FxSpec(
          type: FxType.bandpass,
          params: {'freq': 1000, 'q': 2, 'mix': 1},
        ),
      FxType.notch => const FxSpec(
          type: FxType.notch,
          params: {'freq': 1000, 'q': 4, 'mix': 1},
        ),
      FxType.peakingEq => const FxSpec(
          type: FxType.peakingEq,
          params: {'freq': 1000, 'q': 1, 'gainDb': 6, 'mix': 1},
        ),
      FxType.lowShelf => const FxSpec(
          type: FxType.lowShelf,
          params: {'freq': 200, 'q': 0.707, 'gainDb': 6, 'mix': 1},
        ),
      FxType.highShelf => const FxSpec(
          type: FxType.highShelf,
          params: {'freq': 4000, 'q': 0.707, 'gainDb': 6, 'mix': 1},
        ),
      FxType.phaser => const FxSpec(
          type: FxType.phaser,
          params: {
            'rateHz': 0.5,
            'depth': 0.7,
            'feedback': 0.3,
            'minFreq': 200,
            'maxFreq': 2000,
            'stages': 4,
          },
        ),
      // A shortish, fairly damped room by default — long enough to hear the
      // difference from the algorithmic reverb, short enough that the
      // convolution cost stays modest on a phone.
      FxType.convolutionReverb => const FxSpec(
          type: FxType.convolutionReverb,
          params: {
            'seconds': 1.5,
            'decay': 0.5,
            'predelayMs': 0,
            'mix': 0.35,
          },
        ),
      FxType.compressor => const FxSpec(
          type: FxType.compressor,
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
      FxType.gate => const FxSpec(
          type: FxType.gate,
          params: {
            'thresholdDb': -40,
            'ratio': 4,
            'rangeDb': -60,
            'attackMs': 1,
            'releaseMs': 100,
            'mix': 1,
          },
        ),
      FxType.pitchShift => const FxSpec(
          type: FxType.pitchShift,
          params: {'semitones': 12, 'mix': 1},
        ),
      FxType.timeStretch => const FxSpec(
          type: FxType.timeStretch,
          params: {'speed': 0.75, 'mix': 1},
        ),
      FxType.tremolo => const FxSpec(
          type: FxType.tremolo,
          params: {'rateHz': 6, 'depth': 0.6, 'mix': 1},
        ),
      FxType.vocoder => const FxSpec(
          type: FxType.vocoder,
          params: {'carrierHz': 110, 'depth': 0.75, 'mix': 0.7},
        ),
      FxType.voiceShape => const FxSpec(
          type: FxType.voiceShape,
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
      FxType.voiceChipmunk => const FxSpec(
          type: FxType.voiceChipmunk,
          params: {'mix': 1},
        ),
      FxType.voiceDeep =>
        const FxSpec(type: FxType.voiceDeep, params: {'mix': 1}),
      FxType.voiceRobot => const FxSpec(
          type: FxType.voiceRobot,
          params: {'mix': 1},
        ),
      FxType.voiceRadio => const FxSpec(
          type: FxType.voiceRadio,
          params: {'mix': 1},
        ),
    };

List<FxSpec> fxPresetChain(FxPreset preset) => switch (preset) {
      FxPreset.vocalPolish => [
          defaultFx(
            FxType.highpass,
          ).copyWith(params: {'freq': 120, 'q': 0.707, 'mix': 1}),
          defaultFx(FxType.compressor).copyWith(
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
          defaultFx(
            FxType.reverb,
          ).copyWith(params: {'roomSize': 0.42, 'damping': 0.55, 'mix': 0.18}),
        ],
      FxPreset.lofiCrunch => [
          defaultFx(
            FxType.highpass,
          ).copyWith(params: {'freq': 180, 'q': 0.707, 'mix': 1}),
          defaultFx(
            FxType.lowpass,
          ).copyWith(params: {'freq': 4200, 'q': 0.8, 'mix': 1}),
          defaultFx(FxType.bitCrush).copyWith(params: {'bits': 7, 'mix': 0.38}),
          defaultFx(FxType.distortion)
              .copyWith(params: {'drive': 2.2, 'mix': 0.28}),
        ],
      FxPreset.wideSpace => [
          defaultFx(
            FxType.chorus,
          ).copyWith(params: {'rateHz': 0.8, 'depthMs': 9, 'mix': 0.35}),
          defaultFx(
            FxType.delay,
          ).copyWith(params: {'delayMs': 260, 'feedback': 0.28, 'mix': 0.24}),
          defaultFx(
            FxType.reverb,
          ).copyWith(params: {'roomSize': 0.78, 'damping': 0.38, 'mix': 0.32}),
        ],
      FxPreset.robotVoice => [
          defaultFx(FxType.voiceRobot),
          defaultFx(FxType.ringMod)
              .copyWith(params: {'carrierHz': 92, 'mix': 0.34}),
          defaultFx(
            FxType.highpass,
          ).copyWith(params: {'freq': 220, 'q': 0.707, 'mix': 1}),
        ],
    };

/// Fade curve shapes for clip edges, matching CrispAudio's timeline segments.
enum FxFadeCurve { linear, exponential, sCurve }

/// A track-level gain automation breakpoint. Values are linear gain
/// multipliers; outside the authored point span the automation multiplier is 1.
class FxAutomationPoint {
  const FxAutomationPoint({
    required this.ms,
    required this.value,
    this.curve = FxFadeCurve.linear,
  });

  final double ms;
  final double value;
  final FxFadeCurve curve;

  FxAutomationPoint copyWith({double? ms, double? value, FxFadeCurve? curve}) =>
      FxAutomationPoint(
        ms: ms ?? this.ms,
        value: value ?? this.value,
        curve: curve ?? this.curve,
      );

  Map<String, dynamic> toJson() => {
        'ms': ms,
        'value': value,
        if (curve != FxFadeCurve.linear) 'curve': curve.name,
      };

  static FxAutomationPoint? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final ms = raw['ms'];
    final value = raw['value'];
    if (ms is! num || value is! num) return null;
    final curveName = raw['curve'];
    final curve = curveName is String
        ? FxFadeCurve.values
            .where((curve) => curve.name == curveName)
            .firstOrNull
        : null;
    return FxAutomationPoint(
      ms: ms.toDouble(),
      value: value.toDouble(),
      curve: curve ?? FxFadeCurve.linear,
    );
  }
}

double fadeCurveValue(double value, FxFadeCurve curve) {
  final t = value.clamp(0.0, 1.0).toDouble();
  return switch (curve) {
    FxFadeCurve.linear => t,
    FxFadeCurve.exponential => t * t,
    FxFadeCurve.sCurve => t * t * (3 - 2 * t),
  };
}
