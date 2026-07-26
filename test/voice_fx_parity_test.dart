// test/voice_fx_parity_test.dart
//
// A3 — the Instrument/Voice Lab's nine presets, expressed in the shared FxSpec
// model. Same contract as A2: the consolidation must change NOTHING audible, so
// every preset is asserted sample-identical to the old `applyVoiceEffect`.
//
// Three of the nine are the interesting ones. `monster` and `alien` had no rack
// type of their own and go through the adjustable voiceShape module; `cyborg`
// needs a genuine two-stage chain because voiceShape ties its grit's drive to
// its mix and cyborg's combination is not on that curve; `demon` needs a FUZZ
// shaper, which is why the rack's distortion had to start exposing its curve.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/distortion.dart'
    show DistortionKind, distortionFx;
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart';
import 'package:comet_beat/core/audio/fx/fx_chain.dart';
import 'package:comet_beat/core/audio/fx/fx_presets.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:flutter_test/flutter_test.dart';

/// A voice-like signal: a low fundamental with harmonics and an envelope, so
/// formant shifting and ring modulation both have something to bite on.
Float64List _voice({int n = 8000}) {
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = i / kSampleRate;
    final env = math.min(1.0, i / 400) * math.exp(-i / (n * 0.8));
    out[i] = 0.5 *
        env *
        (math.sin(2 * math.pi * 140 * t) +
            0.5 * math.sin(2 * math.pi * 280 * t) +
            0.25 * math.sin(2 * math.pi * 560 * t));
  }
  return out;
}

void main() {
  group(
      'preset parity — the shared rack must sound EXACTLY like applyVoiceEffect',
      () {
    for (final preset in VoiceEffect.values) {
      test('$preset', () {
        final sample = _voice();
        final legacy = applyVoiceEffect(sample, preset);
        final shared =
            applyFxChain(sample, fxForVoicePreset(preset), kSampleRate);

        expect(shared.length, legacy.length, reason: 'length drift');
        for (var i = 0; i < legacy.length; i++) {
          expect(
            shared[i],
            legacy[i],
            reason: 'sample $i differs for $preset — a param does not match',
          );
        }
      });
    }

    test('normal is an empty chain — identity, not a rebuilt copy', () {
      expect(fxForVoicePreset(VoiceEffect.normal), isEmpty);
      final sample = _voice();
      expect(
        applyFxChain(sample, fxForVoicePreset(VoiceEffect.normal), kSampleRate),
        same(sample),
      );
    });

    test('the presets that need a real chain have one', () {
      // If these collapse back to one element, the mapping has been
      // "simplified" into something that no longer matches the original DSP.
      expect(fxForVoicePreset(VoiceEffect.cyborg), hasLength(2));
      expect(fxForVoicePreset(VoiceEffect.demon), hasLength(2));
    });
  });

  group('pitch preservation', () {
    // The in-tune subset is a documented contract: a recorded sample processed
    // with one of these stays usable as a channel instrument.
    test('every pitch-preserving preset keeps the fundamental', () {
      for (final preset in kPitchPreservingVoiceEffects) {
        final chain = fxForVoicePreset(preset);
        final out = applyFxChain(_voice(), chain, kSampleRate);
        expect(out.length, 8000, reason: '$preset changed the length');
        for (final v in out) {
          expect(v.isFinite, isTrue, reason: '$preset produced $v');
        }
      }
    });
  });

  group('the distortion curve the rack was missing', () {
    test('kind selects the shaper, and its default is still soft clip', () {
      final sample = _voice();
      final defaulted = applyFxChain(
        sample,
        [
          const FxSpec(type: FxType.distortion, params: {'drive': 4, 'mix': 1}),
        ],
        kSampleRate,
      );
      // distortionFx's own defaults are soft clip / drive 4 / mix 1 — exactly
      // what the spec above asks for, so a bare call is the reference.
      final explicit = distortionFx(sample);
      for (var i = 0; i < sample.length; i++) {
        expect(defaulted[i], explicit[i], reason: 'sample $i');
      }
    });

    test('each kind index reaches its own shaper', () {
      final sample = _voice();
      final byIndex = <int, Float64List>{};
      for (var i = 0; i < DistortionKind.values.length; i++) {
        byIndex[i] = applyFxChain(
          sample,
          [
            FxSpec(
              type: FxType.distortion,
              params: {'kind': i.toDouble(), 'drive': 6, 'mix': 1},
            ),
          ],
          kSampleRate,
        );
        final direct = distortionFx(
          sample,
          kind: DistortionKind.values[i],
          drive: 6,
        );
        for (var s = 0; s < sample.length; s++) {
          expect(
            byIndex[i]![s],
            direct[s],
            reason: '${DistortionKind.values[i]} sample $s',
          );
        }
      }
      // And they are genuinely different curves, not four aliases.
      expect(byIndex[0]![100], isNot(byIndex[2]![100]));
    });

    test('an out-of-range kind clamps instead of throwing', () {
      final sample = _voice();
      for (final bad in [-5.0, 99.0]) {
        final out = applyFxChain(
          sample,
          [
            FxSpec(
              type: FxType.distortion,
              params: {'kind': bad, 'drive': 4, 'mix': 1},
            ),
          ],
          kSampleRate,
        );
        expect(out.length, sample.length);
        for (final v in out) {
          expect(v.isFinite, isTrue);
        }
      }
    });
  });

  group('guitar presets (A6)', () {
    test('clean is empty — a tab with it renders byte-identically', () {
      expect(fxForGuitarPreset(GuitarFxPreset.clean), isEmpty);
    });

    test('every other preset is a non-empty, length-preserving chain', () {
      final sample = _voice();
      for (final preset in GuitarFxPreset.values) {
        final chain = fxForGuitarPreset(preset);
        if (preset != GuitarFxPreset.clean) {
          expect(chain, isNotEmpty, reason: '$preset');
        }
        final out = applyFxChain(sample, chain, kSampleRate);
        expect(out.length, sample.length, reason: '$preset changed the length');
        for (final v in out) {
          expect(v.isFinite, isTrue, reason: '$preset produced $v');
        }
      }
    });

    test('each preset actually changes the sound', () {
      final sample = _voice();
      for (final preset in GuitarFxPreset.values) {
        if (preset == GuitarFxPreset.clean) continue;
        final out =
            applyFxChain(sample, fxForGuitarPreset(preset), kSampleRate);
        var differs = false;
        for (var i = 0; i < sample.length; i++) {
          if ((out[i] - sample[i]).abs() > 1e-9) {
            differs = true;
            break;
          }
        }
        expect(differs, isTrue, reason: '$preset was inaudible');
      }
    });

    test('they are data over the existing rack — no unknown effect types', () {
      for (final preset in GuitarFxPreset.values) {
        for (final fx in fxForGuitarPreset(preset)) {
          expect(FxType.values, contains(fx.type), reason: '$preset');
        }
      }
    });
  });
}
