// test/fx_spec_test.dart
//
// A1 — the mode-neutral FX model. These lock the contract that every mode now
// depends on: the type list is stable (persisted by NAME, so a rename or a
// reorder silently corrupts saved projects and share tokens), defaults are
// complete, JSON round-trips, and the cache key tracks every field.

import 'package:comet_beat/core/audio/daw_timeline.dart'
    show
        DawClipEffect,
        DawClipEffectPreset,
        DawClipEffectType,
        dawClipEffectPresetChain,
        defaultDawClipEffect;
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FxType', () {
    test('every type has a default with at least a mix or its own params', () {
      for (final type in FxType.values) {
        final fx = defaultFx(type);
        expect(fx.type, type);
        expect(fx.enabled, isTrue);
        expect(
          fx.params,
          isNotEmpty,
          reason: '$type has no default params — the FX rack has nothing to '
              'show and the DSP would fall back to hardcoded literals',
        );
      }
    });

    test('names are stable — they are the on-disk representation', () {
      // `.cbdaw` / `.cbtrk` / share tokens store an effect by `type.name`, so
      // this list is a FILE FORMAT. Add at the end; never rename or reorder.
      expect(FxType.values.map((t) => t.name).toList(), [
        'gain',
        'pan',
        'reverb',
        'delay',
        'chorus',
        'flanger',
        'ringMod',
        'distortion',
        'bitCrush',
        'lowpass',
        'highpass',
        'compressor',
        'gate',
        'pitchShift',
        'timeStretch',
        'tremolo',
        'vocoder',
        'voiceShape',
        'voiceChipmunk',
        'voiceDeep',
        'voiceRobot',
        'voiceRadio',
        'bandpass',
        'notch',
        'peakingEq',
        'lowShelf',
        'highShelf',
        'phaser',
        // Appended, never inserted: these names ARE the on-disk form, so
        // reordering silently repoints saved projects at the wrong effect.
        'convolutionReverb',
        'autoWah',
      ]);
    });
  });

  group('FxSpec JSON', () {
    test('round-trips every default', () {
      for (final type in FxType.values) {
        final fx = defaultFx(type);
        final back = FxSpec.fromJson(fx.toJson());
        expect(back, isNotNull, reason: '$type failed to parse back');
        expect(back!.type, fx.type);
        expect(back.enabled, fx.enabled);
        expect(back.params, fx.params);
      }
    });

    test('round-trips automation points and their curves', () {
      final fx = defaultFx(FxType.reverb).copyWith(
        enabled: false,
        automation: {
          'mix': const [
            FxAutomationPoint(ms: 0, value: 0),
            FxAutomationPoint(ms: 500, value: 1, curve: FxFadeCurve.sCurve),
            FxAutomationPoint(
              ms: 1000,
              value: 0.25,
              curve: FxFadeCurve.exponential,
            ),
          ],
        },
      );
      final back = FxSpec.fromJson(fx.toJson())!;
      expect(back.enabled, isFalse);
      expect(back.automation['mix'], hasLength(3));
      expect(back.automation['mix']![1].curve, FxFadeCurve.sCurve);
      expect(back.automation['mix']![2].value, 0.25);
    });

    test('a malformed or future entry degrades to null, never throws', () {
      expect(FxSpec.fromJson(null), isNull);
      expect(FxSpec.fromJson('reverb'), isNull);
      expect(FxSpec.fromJson(<String, Object?>{}), isNull);
      expect(FxSpec.fromJson({'type': 42}), isNull);
      // A type added by a NEWER build must not crash an older one.
      expect(FxSpec.fromJson({'type': 'quantumFlux'}), isNull);
    });
  });

  group('FxSpec.cacheKey', () {
    test('equal specs share a key, any change breaks it', () {
      final a = defaultFx(FxType.delay);
      expect(a.cacheKey, defaultFx(FxType.delay).cacheKey);
      expect(a.cacheKey, isNot(a.copyWith(enabled: false).cacheKey));
      expect(
        a.cacheKey,
        isNot(a.copyWith(params: {...a.params, 'mix': 0.9}).cacheKey),
      );
      expect(
        a.cacheKey,
        isNot(
          a.copyWith(
            automation: {
              'mix': const [FxAutomationPoint(ms: 0, value: 1)],
            },
          ).cacheKey,
        ),
      );
    });

    test('param order does not affect the key', () {
      const a = FxSpec(
        type: FxType.reverb,
        params: {'roomSize': 0.7, 'mix': 0.4},
      );
      const b = FxSpec(
        type: FxType.reverb,
        params: {'mix': 0.4, 'roomSize': 0.7},
      );
      expect(a.cacheKey, b.cacheKey);
    });
  });

  group('FxPreset', () {
    test('every preset resolves to a non-empty chain of known types', () {
      for (final preset in FxPreset.values) {
        final chain = fxPresetChain(preset);
        expect(chain, isNotEmpty, reason: '$preset is empty');
        for (final fx in chain) {
          expect(FxType.values, contains(fx.type));
        }
      }
    });
  });

  group('daw_timeline compatibility aliases (A1)', () {
    test('the legacy DAW names still resolve to the shared model', () {
      // The DAW's persisted projects and every existing call site use these.
      expect(DawClipEffectType.reverb, FxType.reverb);
      expect(DawClipEffectPreset.values.length, FxPreset.values.length);
      expect(defaultDawClipEffect(DawClipEffectType.reverb), isA<FxSpec>());
      expect(
        defaultDawClipEffect(DawClipEffectType.delay).params,
        defaultFx(FxType.delay).params,
      );
      expect(
        dawClipEffectPresetChain(DawClipEffectPreset.vocalPolish).length,
        fxPresetChain(FxPreset.vocalPolish).length,
      );
      const legacy = DawClipEffect(type: DawClipEffectType.gain);
      expect(legacy, isA<FxSpec>());
      expect(DawClipEffect.fromJson(legacy.toJson()), isNotNull);
    });
  });
}
