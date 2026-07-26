// lib/core/audio/fx/fx_presets.dart
//
// The named FX chains, in one place — the mode-neutral home for "what a preset
// actually is".
//
// Each mode grew its own preset vocabulary as a closed enum with the params
// baked into a switch: the Tracker's seven channel effects, the Instrument
// mode's nine voices, and (from A6) the Tab's guitar rig. Those enums stay —
// they are the user-facing names, and they are what saved files store — but the
// PARAMS behind them now live here as [FxSpec] chains, so a preset authored in
// one mode is playable, editable, and automatable in every other.
//
// The contract for every entry below: it must reproduce its mode's original
// hardcoded DSP call EXACTLY. `voice_fx_parity_test.dart` and
// `channel_fx_parity_test.dart` assert that sample-for-sample, which is what
// makes the consolidation safe to ship — a preset that drifts is a preset that
// changed how somebody's saved song sounds.

import 'package:comet_beat/core/audio/crisp_dsp/distortion.dart'
    show DistortionKind;
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart' show VoiceEffect;
import 'package:comet_beat/core/audio/fx/fx_spec.dart';

/// The [DistortionKind] index an [FxSpec] uses for its `kind` param.
double _kind(DistortionKind kind) =>
    DistortionKind.values.indexOf(kind).toDouble();

// ─── A3 — Instrument / Voice Lab presets ────────────────────────────────────

/// The nine voice presets as [FxSpec] chains.
///
/// Most map to a single rack effect, but three genuinely need a chain, and that
/// is the point: the old `applyVoiceEffect` switch could nest DSP calls freely
/// while a mode holding one enum value could not. As chains they are editable —
/// a user can keep "cyborg" and turn its grit down.
///
/// [VoiceEffect.normal] is an EMPTY chain, matching `applyFxChain`'s identity.
List<FxSpec> fxForVoicePreset(VoiceEffect preset) => switch (preset) {
      VoiceEffect.normal => const [],

      // Straight formant shifts. chipmunk/deep have their own rack types;
      // monster does not, so it goes through the adjustable voiceShape module
      // with only its formant stage engaged.
      VoiceEffect.chipmunk => const [
          FxSpec(type: FxType.voiceChipmunk, params: {'mix': 1}),
        ],
      VoiceEffect.deep => const [
          FxSpec(type: FxType.voiceDeep, params: {'mix': 1}),
        ],
      VoiceEffect.monster => const [
          FxSpec(
            type: FxType.voiceShape,
            params: {'formant': -0.5, 'mix': 1},
          ),
        ],
      VoiceEffect.robot => const [
          FxSpec(type: FxType.voiceRobot, params: {'mix': 1}),
        ],
      VoiceEffect.radio => const [
          FxSpec(type: FxType.voiceRadio, params: {'mix': 1}),
        ],

      // Formant up into a mid ring-mod carrier. voiceShape runs its stages
      // formant -> radio -> ring-mod -> grit, which is exactly this order.
      VoiceEffect.alien => const [
          FxSpec(
            type: FxType.voiceShape,
            params: {
              'formant': 0.4,
              'carrierHz': 150,
              'carrierMix': 0.6,
              'mix': 1,
            },
          ),
        ],

      // A real two-stage chain: voiceShape ties its grit's drive to its mix
      // (drive = 1 + grit*11), and cyborg needs drive 3 at mix 0.6 — which that
      // formula cannot produce. So the ring-mod and the distortion are separate
      // rack entries, which also makes them independently tweakable.
      VoiceEffect.cyborg => const [
          FxSpec(
            type: FxType.ringMod,
            params: {'carrierHz': 80, 'mix': 0.5},
          ),
          FxSpec(
            type: FxType.distortion,
            params: {'drive': 3, 'mix': 0.6},
          ),
        ],

      // Formant down into a FUZZ shaper — the reason the rack's distortion had
      // to start exposing its curve (see `_distortionKind` in fx_chain.dart).
      VoiceEffect.demon => [
          const FxSpec(
            type: FxType.voiceShape,
            params: {'formant': -0.5, 'mix': 1},
          ),
          FxSpec(
            type: FxType.distortion,
            params: {
              'kind': _kind(DistortionKind.fuzz),
              'drive': 2,
              'mix': 0.5,
            },
          ),
        ],
    };

// ─── A6 — Tab / guitar rig presets ──────────────────────────────────────────

/// A guitar amp/pedal voicing for the Tab mode, which had no FX at all before
/// A6. These are DATA, not new DSP — every one is a chain of rack effects that
/// already existed.
enum GuitarFxPreset {
  /// No processing. An empty chain, so a tab renders byte-identically.
  clean,

  /// A touch of grit and body — a driven clean amp.
  crunch,

  /// Heavier saturation with the mud filtered out first.
  overdrive,

  /// Fuzz-face territory: hard shaping, rolled-off top.
  fuzz,

  /// Wide, slow modulation.
  chorus,

  /// A short bright ambience — a spring tank.
  springReverb,

  /// Clean, plus a rhythmic slapback.
  slapback,
}

/// The [FxSpec] chain for a guitar preset.
List<FxSpec> fxForGuitarPreset(GuitarFxPreset preset) => switch (preset) {
      GuitarFxPreset.clean => const [],
      GuitarFxPreset.crunch => const [
          FxSpec(
            type: FxType.distortion,
            params: {'drive': 3, 'mix': 0.5},
          ),
          FxSpec(
            type: FxType.peakingEq,
            params: {'freq': 900, 'q': 0.9, 'gainDb': 3, 'mix': 1},
          ),
        ],
      GuitarFxPreset.overdrive => [
          // Roll off the low end BEFORE the shaper — distorting mud makes mud.
          const FxSpec(
            type: FxType.highpass,
            params: {'freq': 120, 'q': 0.707, 'mix': 1},
          ),
          const FxSpec(
            type: FxType.distortion,
            params: {'drive': 8, 'mix': 0.8},
          ),
          const FxSpec(
            type: FxType.lowShelf,
            params: {'freq': 300, 'gainDb': 2, 'q': 0.707, 'mix': 1},
          ),
        ],
      GuitarFxPreset.fuzz => [
          FxSpec(
            type: FxType.distortion,
            params: {
              'kind': _kind(DistortionKind.fuzz),
              'drive': 6,
              'mix': 0.9,
            },
          ),
          const FxSpec(
            type: FxType.lowpass,
            params: {'freq': 3500, 'q': 0.707, 'mix': 1},
          ),
        ],
      GuitarFxPreset.chorus => const [
          FxSpec(
            type: FxType.chorus,
            params: {'rateHz': 0.8, 'depthMs': 8, 'mix': 0.45},
          ),
        ],
      GuitarFxPreset.springReverb => const [
          FxSpec(
            type: FxType.highpass,
            params: {'freq': 250, 'q': 0.707, 'mix': 1},
          ),
          FxSpec(
            type: FxType.reverb,
            // No 'decay' — roomSize is the control here (see fx_chain.dart).
            params: {'roomSize': 0.45, 'damping': 0.55, 'mix': 0.28},
          ),
        ],
      GuitarFxPreset.slapback => const [
          FxSpec(
            type: FxType.delay,
            params: {'delayMs': 120, 'feedback': 0.18, 'mix': 0.3},
          ),
        ],
    };
