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

  /// Auto-wah — a resonant low-pass whose cutoff is SWEPT by an LFO, the
  /// wah/filter-wobble the rack lacked (the static resonant low-pass is
  /// [lowpass]+`q`; [tremolo] sweeps amplitude, [phaser] sweeps all-pass notches,
  /// but nothing swept a resonant low-pass). Built on the tracker's shared
  /// `crisp_dsp/lfo.dart` shape and the biquad's click-free `setFreq`, so the
  /// sweep never clicks. Appended for the same `.cbdaw` name-stability reason as
  /// the O11 block above.
  autoWah,

  // A1 — the rest of the filter set. Appended, like every block before it,
  // because `.cbdaw` stores an effect by NAME and reordering would only risk
  // merges with parallel FX work for no gain.

  /// All-pass: full level at every frequency, PHASE rotated around [freq].
  /// Inaudible alone; the tool for time-aligning or deliberately de-phasing a
  /// signal against a copy of itself.
  allpass,

  /// One-pole (6 dB/oct) low-pass — a tone control, where [lowpass] is a
  /// 12 dB/oct filter that can resonate. The gentler shape is the commoner need.
  onePoleLowpass,

  /// One-pole (6 dB/oct) high-pass, the exact complement of [onePoleLowpass].
  onePoleHighpass,

  /// A biquad given directly as coefficients — the escape hatch for a response
  /// the named shapes do not cover. Unstable coefficients pass through unchanged
  /// rather than exploding into the mix.
  biquadRaw,

  /// Windowed-sinc FIR: STEEP and exactly linear-phase, where the biquads are
  /// gentle and phase-shifting. `shape` picks low-pass/high-pass/band-pass/
  /// band-reject and `taps` buys steepness with CPU.
  sincFilter,

  /// Hilbert transformer: every frequency shifted 90°, magnitudes untouched.
  /// The building block the stereo-field tools are made of.
  hilbert,

  // A3 — the dynamics the rack was missing. Appended, as always.

  /// A LOOK-AHEAD peak limiter — nothing leaves above the ceiling. Distinct
  /// from [compressor] at a high ratio, which computes its gain from a peak it
  /// has already passed and therefore lets that peak out.
  limiter,

  /// De-esser: compresses only the sibilant band, so the body of a voice does
  /// not pump every time an "s" arrives.
  deEsser,

  /// Three-band compressor with a detector per band, so the kick stops steering
  /// the vocal.
  multibandCompressor,

  // A4 — the channel/stereo-field ops. These need BOTH channels at once, so
  // unlike every other effect they cannot be run per-channel; the chain gives
  // each an explicit stereo case and passes a mono buffer through untouched.

  /// The general 2×2 channel matrix — the escape hatch of the channel ops.
  remix,

  /// Swap left and right.
  swapChannels,

  /// Mid/side width: 0 mono, 1 unchanged, 2 twice as wide.
  stereoWidth,

  /// Remove what both channels share — the "take the centre out" trick.
  centreCancel,

  /// Headphone crossfeed: a little of each channel into the opposite ear,
  /// delayed and dulled, the way a head does it.
  crossfeed,

  /// Sweep the image side to side with an LFO.
  autoPan,
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
      // A1. The all-pass default sits mid-spectrum with a gentle Q, where the
      // rotation is broad enough to hear when it is mixed against a dry copy.
      FxType.allpass => const FxSpec(
          type: FxType.allpass,
          params: {'freq': 1000, 'q': 0.707, 'mix': 1},
        ),
      // The one-poles have no q — that is the whole point of them — and default
      // to corners that read as "a bit darker" / "a bit thinner" rather than as
      // an effect.
      FxType.onePoleLowpass => const FxSpec(
          type: FxType.onePoleLowpass,
          params: {'freq': 4000, 'mix': 1},
        ),
      FxType.onePoleHighpass => const FxSpec(
          type: FxType.onePoleHighpass,
          params: {'freq': 200, 'mix': 1},
        ),
      // The identity filter: b0=1 and everything else 0 passes audio through
      // untouched, so an unedited raw biquad is a no-op rather than a surprise.
      FxType.biquadRaw => const FxSpec(
          type: FxType.biquadRaw,
          params: {'b0': 1, 'b1': 0, 'b2': 0, 'a1': 0, 'a2': 0, 'mix': 1},
        ),
      // 127 taps is a transition band of roughly 800 Hz at 44.1 kHz — steep
      // enough to be obviously not a biquad, cheap enough to stay interactive.
      // 'shape' is the FirShape index; 0 = low-pass, which is what the dispatch
      // falls back to, so a spec written without it renders identically.
      FxType.sincFilter => const FxSpec(
          type: FxType.sincFilter,
          params: {
            'shape': 0,
            'freq': 1000,
            'freqHigh': 8000,
            'taps': 127,
            'mix': 1,
          },
        ),
      FxType.hilbert => const FxSpec(
          type: FxType.hilbert,
          params: {'taps': 127, 'mix': 1},
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
      // A3. A limiter's ceiling sits just under full scale, and its look-ahead
      // is a few ms — long enough to catch a transient, short enough that the
      // latency is inaudible even if a caller ever plays it live.
      FxType.limiter => const FxSpec(
          type: FxType.limiter,
          params: {
            'ceilingDb': -0.3,
            'lookaheadMs': 5,
            'releaseMs': 100,
            'mix': 1,
          },
        ),
      // Sibilance lives around 5–8 kHz; the default threshold is low because a
      // de-esser should only catch the peaks that stick out.
      FxType.deEsser => const FxSpec(
          type: FxType.deEsser,
          params: {
            'freq': 6000,
            'thresholdDb': -28,
            'ratio': 6,
            'attackMs': 1,
            'releaseMs': 60,
            'mix': 1,
          },
        ),
      // Ratios default to 1 in every band — an untouched multiband compressor
      // returns its input EXACTLY (the splitter reconstructs), so adding one to
      // a chain does nothing until it is dialled in.
      FxType.multibandCompressor => const FxSpec(
          type: FxType.multibandCompressor,
          params: {
            'lowHz': 200,
            'highHz': 3000,
            'thresholdDb': -24,
            'lowRatio': 1,
            'midRatio': 1,
            'highRatio': 1,
            'attackMs': 10,
            'releaseMs': 120,
            'makeupDb': 0,
            'mix': 1,
          },
        ),
      // A4. The identity matrix: an unedited remix passes audio through
      // untouched, so adding one is never a surprise.
      FxType.remix => const FxSpec(
          type: FxType.remix,
          params: {
            'leftFromLeft': 1,
            'leftFromRight': 0,
            'rightFromLeft': 0,
            'rightFromRight': 1,
            'mix': 1,
          },
        ),
      FxType.swapChannels =>
        const FxSpec(type: FxType.swapChannels, params: {'mix': 1}),
      FxType.stereoWidth => const FxSpec(
          type: FxType.stereoWidth,
          params: {'width': 1.4, 'mix': 1},
        ),
      FxType.centreCancel => const FxSpec(
          type: FxType.centreCancel,
          params: {'amount': 1, 'mix': 1},
        ),
      // A modest default: enough to unclench a hard-panned mix on headphones,
      // not enough to read as an effect.
      FxType.crossfeed => const FxSpec(
          type: FxType.crossfeed,
          params: {
            'amount': 0.4,
            'delayMs': 0.3,
            'cutoffHz': 700,
            'mix': 1,
          },
        ),
      FxType.autoPan => const FxSpec(
          type: FxType.autoPan,
          params: {'rateHz': 0.5, 'depth': 0.8, 'waveform': 0, 'mix': 1},
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
      // A gentle vocal/guitar wah: a low base cutoff swept up ~2.5 octaves at
      // ~1.2 Hz with a resonant Q. `waveform` selects the LFO shape (0 sine /
      // 1 ramp / 2 square) via the shared tracker LFO.
      FxType.autoWah => const FxSpec(
          type: FxType.autoWah,
          params: {
            'baseFreq': 350,
            'octaves': 2.5,
            'rateHz': 1.2,
            'depth': 1,
            'q': 4,
            'waveform': 0,
            'mix': 1,
          },
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
