// test/fx_params_test.dart
//
// A4 — the param descriptor table. Its job is to let one widget edit all 28
// effects, so the tests are about COMPLETENESS and CONSISTENCY: every param of
// every effect must be describable, every default must sit inside its own
// range, and adding a new FxType without extending the table must fail here
// rather than silently ship a slider that goes 0..1 for a frequency.

import 'package:comet_beat/core/audio/fx/fx_params.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('completeness', () {
    test('every FxType has a label', () {
      for (final type in FxType.values) {
        expect(fxTypeLabel(type), isNotEmpty, reason: '$type');
      }
    });

    test('every FxType has at least one editable param', () {
      for (final type in FxType.values) {
        expect(
          fxParamSpecs(type),
          isNotEmpty,
          reason: '$type would render as an empty rack row',
        );
      }
    });

    test('every param of every effect has a REAL descriptor', () {
      // The fallback in fxParamSpec is a safety net so a new effect is still
      // editable — not a licence to skip the table. This is the test that
      // catches a new FxType landing without its ranges.
      final missing = <String>[];
      for (final type in FxType.values) {
        for (final key in defaultFx(type).params.keys) {
          if (!hasFxParamSpec(type, key)) missing.add('$type.$key');
        }
      }
      expect(
        missing,
        isEmpty,
        reason: 'no descriptor for: ${missing.join(", ")}',
      );
    });

    test('every param has a label that is not just its key', () {
      // The raw biquad's coefficients are the exception, and deliberately so:
      // b0/b1/b2/a1/a2 ARE their names. Anyone reaching for a filter typed as
      // coefficients knows the difference equation, and inventing prose for
      // them ("first feed-forward tap") would be less clear, not more.
      const namedByConvention = {'b0', 'b1', 'b2', 'a1', 'a2'};
      final raw = <String>[];
      for (final type in FxType.values) {
        for (final key in defaultFx(type).params.keys) {
          if (namedByConvention.contains(key)) continue;
          if (fxParamLabel(key) == key) raw.add('$type.$key');
        }
      }
      expect(raw, isEmpty, reason: 'unlabelled: ${raw.join(", ")}');
    });

    test('every FxType has a category, and every category is reachable', () {
      final seen = <FxCategory>{};
      for (final type in FxType.values) {
        seen.add(fxCategory(type));
      }
      expect(seen, hasLength(FxCategory.values.length));
      for (final category in FxCategory.values) {
        expect(fxCategoryLabel(category), isNotEmpty, reason: '$category');
      }
    });
  });

  group('consistency with defaultFx', () {
    test('every default sits inside its own range', () {
      for (final type in FxType.values) {
        final params = defaultFx(type).params;
        for (final spec in fxParamSpecs(type)) {
          final value = params[spec.key]!;
          expect(
            value,
            inInclusiveRange(spec.min, spec.max),
            reason: '$type.${spec.key} default $value is outside '
                '${spec.min}..${spec.max}',
          );
        }
      }
    });

    test('the spec order follows the signal path, not the alphabet', () {
      // fxParamSpecs reads defaultFx's declaration order, so the rack reads the
      // way the effect is applied. Checking one representative is enough to
      // catch an accidental sort.
      expect(
        fxParamSpecs(FxType.compressor).map((s) => s.key).toList(),
        defaultFx(FxType.compressor).params.keys.toList(),
      );
    });

    test('an integer param has an integral default', () {
      for (final type in FxType.values) {
        for (final spec in fxParamSpecs(type)) {
          if (!spec.integer) continue;
          final value = defaultFx(type).params[spec.key]!;
          expect(
            value,
            value.roundToDouble(),
            reason: '$type.${spec.key} is integral but defaults to $value',
          );
        }
      }
    });

    test('ranges are non-degenerate', () {
      for (final type in FxType.values) {
        for (final spec in fxParamSpecs(type)) {
          expect(spec.min, lessThan(spec.max), reason: '$type.${spec.key}');
        }
      }
    });
  });

  group('value mapping', () {
    test('clamp keeps a value in range', () {
      const spec = FxParamSpec(key: 'mix', min: 0, max: 1);
      expect(spec.clamp(-3), 0);
      expect(spec.clamp(9), 1);
      expect(spec.clamp(0.4), 0.4);
    });

    test('an integer param snaps', () {
      const spec = FxParamSpec(key: 'bits', min: 1, max: 16, integer: true);
      expect(spec.clamp(7.4), 7);
      expect(spec.clamp(7.6), 8);
      // Midway across 1..16 is 8.5, which snaps up.
      expect(spec.denormalize(0.5), 9);
      expect(spec.denormalize(0), 1);
      expect(spec.denormalize(1), 16);
    });

    test('normalize and denormalize round-trip', () {
      for (final type in FxType.values) {
        for (final spec in fxParamSpecs(type)) {
          if (spec.integer) continue;
          for (final t in [0.0, 0.25, 0.5, 1.0]) {
            final value = spec.denormalize(t);
            expect(
              spec.normalize(value),
              closeTo(t, 1e-9),
              reason: '$type.${spec.key} at $t',
            );
          }
        }
      }
    });

    test('normalize handles a value outside the range', () {
      const spec = FxParamSpec(key: 'freq', min: 20, max: 18000);
      expect(spec.normalize(-100), 0);
      expect(spec.normalize(99999), 1);
    });
  });

  group('choice params', () {
    test('the distortion curve is a picker, not a slider', () {
      final spec = fxParamSpec(FxType.distortion, 'kind');
      expect(spec.isChoice, isTrue);
      expect(spec.choices, hasLength(4));
      expect(spec.integer, isTrue);
    });

    test('a choice range exactly covers its options', () {
      for (final type in FxType.values) {
        for (final spec in fxParamSpecs(type)) {
          if (!spec.isChoice) continue;
          expect(spec.min, 0, reason: '$type.${spec.key}');
          expect(
            spec.max,
            spec.choices!.length - 1,
            reason: '$type.${spec.key} range does not match its option count',
          );
        }
      }
    });

    test('nothing else claims to be a choice', () {
      final choices = <String>[];
      for (final type in FxType.values) {
        for (final spec in fxParamSpecs(type)) {
          if (spec.isChoice) choices.add('$type.${spec.key}');
        }
      }
      expect(choices, [
        'FxType.distortion.kind',
        'FxType.autoWah.waveform',
        'FxType.sincFilter.shape',
        // A4 — auto-pan reuses the shared tracker LFO shapes, so it inherits
        // `waveform`'s choice descriptor rather than inventing a second one.
        'FxType.autoPan.waveform',
        // A2 — the de-emphasis curve is one of two constants, not a free
        // number, so it is a choice like the others.
        'FxType.deEmphasis.curve',
      ]);
    });
  });

  group('per-effect overrides', () {
    test('a highpass sweeps a useful band, not the whole spectrum', () {
      // Sweeping a highpass to 18 kHz just mutes the track.
      expect(fxParamSpec(FxType.highpass, 'freq').max, lessThan(4000));
      expect(fxParamSpec(FxType.lowpass, 'freq').max, greaterThan(10000));
    });

    test('an override only affects its own effect', () {
      expect(fxParamSpec(FxType.tremolo, 'rateHz').max, 20);
      expect(fxParamSpec(FxType.chorus, 'rateHz').max, 12);
    });
  });
}
