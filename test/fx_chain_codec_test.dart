// test/fx_chain_codec_test.dart
//
// F1 — the chain string is the shared surface between the CLI and the app, so
// what it must guarantee is: (a) it reads back what it printed, (b) it never
// throws on garbage, (c) it stays in step with the registry as effects are
// added. The last one is why the "every effect round-trips" test walks
// `FxType.values` instead of a hand-written list — a new effect that the codec
// cannot express fails here rather than in someone's terminal.

import 'package:comet_beat/core/audio/fx/fx_chain_codec.dart';
import 'package:comet_beat/core/audio/fx/fx_params.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parse', () {
    test('a chain of stages, in order', () {
      final parsed = parseFxChain(
        'highpass freq=120 | compressor ratio=4 thresholdDb=-22 | reverb',
      );
      expect(parsed.ok, isTrue, reason: parsed.errors.join('; '));
      expect(
        parsed.chain.map((f) => f.type),
        [FxType.highpass, FxType.compressor, FxType.reverb],
      );
      expect(parsed.chain[0].params['freq'], 120);
      expect(parsed.chain[1].params['ratio'], 4);
      expect(parsed.chain[1].params['thresholdDb'], -22);
    });

    test('unnamed params keep their defaults', () {
      final parsed = parseFxChain('reverb mix=0.5');
      final defaults = defaultFx(FxType.reverb).params;
      expect(parsed.chain.single.params['mix'], 0.5);
      expect(parsed.chain.single.params['roomSize'], defaults['roomSize']);
      expect(parsed.chain.single.params['damping'], defaults['damping']);
    });

    test('names match case- and punctuation-insensitively', () {
      for (final name in ['peakingEq', 'peaking-eq', 'PEAKING_EQ', 'Peaking EQ']
          .map((n) => n.replaceAll(' ', ''))) {
        expect(fxTypeFromName(name), FxType.peakingEq, reason: name);
      }
      expect(
        parseFxChain('Low-Pass FREQ=2000').chain.single.type,
        FxType.lowpass,
      );
      expect(
        parseFxChain('Low-Pass FREQ=2000').chain.single.params['freq'],
        2000,
      );
    });

    test('a percentage is read as a share of the range', () {
      expect(parseFxChain('reverb mix=20%').chain.single.params['mix'], 0.2);
      // pan spans -1..1, so 50% is the midpoint of that span, not 0.5.
      expect(parseFxChain('pan pan=50%').chain.single.params['pan'], 0);
    });

    test('a choice param takes its label as well as its index', () {
      expect(
        parseFxChain('distortion kind=fuzz').chain.single.params['kind'],
        2,
      );
      expect(
        parseFxChain('distortion kind="wave fold"'.replaceAll('"', ''))
            .chain
            .single
            .params['kind'],
        // `wave` alone is not a label; the quoted form splits on whitespace, so
        // the slug form is what a user types. Assert the slug form works.
        isNot(3),
      );
      expect(
        parseFxChain('distortion kind=wavefold').chain.single.params['kind'],
        3,
      );
    });

    test('a leading ! bypasses a stage but keeps it in the chain', () {
      final parsed = parseFxChain('!reverb mix=0.5 | delay');
      expect(parsed.chain.length, 2);
      expect(parsed.chain.first.enabled, isFalse);
      expect(parsed.chain.first.params['mix'], 0.5);
      expect(parsed.chain.last.enabled, isTrue);
    });

    test('newlines and semicolons separate stages too', () {
      final parsed = parseFxChain('reverb\ndelay; chorus');
      expect(
        parsed.chain.map((f) => f.type),
        [FxType.reverb, FxType.delay, FxType.chorus],
      );
    });

    test('an out-of-range value clamps and warns rather than failing', () {
      final parsed = parseFxChain('reverb mix=4');
      expect(parsed.ok, isTrue);
      expect(parsed.warnings, hasLength(1));
      expect(parsed.warnings.single, contains('mix'));
      expect(parsed.chain.single.params['mix'], 1);
    });

    test('an integer param snaps', () {
      expect(parseFxChain('bitCrush bits=7.6').chain.single.params['bits'], 8);
    });
  });

  group('errors — reported, never thrown', () {
    test('unknown effect, with a suggestion', () {
      final parsed = parseFxChain('revrb | reverb');
      expect(parsed.ok, isFalse);
      expect(parsed.errors.single, contains('revrb'));
      // The good stage still parsed — one typo does not lose the rest.
      expect(parsed.chain.single.type, FxType.reverb);
    });

    test('a near-miss name suggests the real one', () {
      // A prefix…
      expect(parseFxChain('comp').errors.single, contains('compressor'));
      // …and a typo, which is the commoner mistake.
      expect(parseFxChain('revrb').errors.single, contains('reverb'));
      expect(parseFxChain('chorsu').errors.single, contains('chorus'));
      expect(parseFxChain('compresor').errors.single, contains('compressor'));
      // But a genuinely unrelated word is not "corrected" into nonsense.
      expect(parseFxChain('banana').errors.single, isNot(contains('did you')));
    });

    test('unknown param names the valid ones', () {
      final parsed = parseFxChain('reverb wetness=0.5');
      expect(parsed.ok, isFalse);
      expect(parsed.errors.single, contains('wetness'));
      expect(parsed.errors.single, contains('roomSize'));
      // The effect survives with its defaults.
      expect(parsed.chain.single.type, FxType.reverb);
    });

    test('a malformed token is reported', () {
      final parsed = parseFxChain('reverb mix');
      expect(parsed.ok, isFalse);
      expect(parsed.errors.single, contains('key=value'));
    });

    test('a non-numeric value is reported', () {
      final parsed = parseFxChain('reverb mix=loud');
      expect(parsed.ok, isFalse);
      expect(parsed.errors.single, contains('not a number'));
    });

    test('garbage in, no exception out', () {
      for (final source in [
        '',
        '   ',
        '|||',
        '=',
        '= =',
        '!',
        '! |',
        'reverb mix=',
        'reverb =0.5',
        '💥 mix=1',
        'reverb | | delay',
      ]) {
        expect(() => parseFxChain(source), returnsNormally, reason: source);
      }
    });
  });

  group('format', () {
    test('prints only what differs from the default', () {
      final chain = [
        defaultFx(FxType.reverb).copyWith(
          params: {...defaultFx(FxType.reverb).params, 'mix': 0.5},
        ),
      ];
      expect(formatFxChain(chain), 'reverb mix=0.5');
      expect(formatFxChain(chain, verbose: true), contains('roomSize='));
    });

    test('an all-default effect prints as its bare name', () {
      expect(formatFxChain([defaultFx(FxType.delay)]), 'delay');
    });

    test('a bypassed effect keeps its !', () {
      final off = defaultFx(FxType.reverb).copyWith(enabled: false);
      expect(formatFxChain([off]), '!reverb');
      expect(parseFxChain(formatFxChain([off])).chain.single.enabled, isFalse);
    });

    test('automation cannot ride the string, and says so', () {
      final automated = defaultFx(FxType.gain).copyWith(
        automation: {
          'gainDb': const [FxAutomationPoint(ms: 0, value: -6)],
        },
      );
      expect(fxChainStringIsLossless([automated]), isFalse);
      expect(fxChainStringIsLossless([defaultFx(FxType.gain)]), isTrue);
    });
  });

  group('the registry drives it', () {
    test('every effect round-trips through the string form', () {
      for (final type in FxType.values) {
        final printed = formatFxChain([defaultFx(type)]);
        final parsed = parseFxChain(printed);
        expect(
          parsed.ok,
          isTrue,
          reason: '$type printed "$printed": ${parsed.errors}',
        );
        expect(parsed.chain, hasLength(1), reason: '$type → "$printed"');
        expect(parsed.chain.single.type, type, reason: printed);
        expect(
          parsed.chain.single.params,
          defaultFx(type).params,
          reason: '$type lost params through "$printed"',
        );
      }
    });

    test('every effect round-trips with every param moved off its default', () {
      for (final type in FxType.values) {
        final defaults = defaultFx(type);
        final tweaked = <String, double>{};
        for (final entry in defaults.params.entries) {
          final spec = fxParamSpec(type, entry.key);
          // A value inside the range that is not the default: step a quarter of
          // the way toward whichever bound is further away.
          final toMax = spec.max - entry.value;
          final toMin = entry.value - spec.min;
          final target = toMax >= toMin
              ? entry.value + toMax / 4
              : entry.value - toMin / 4;
          tweaked[entry.key] = spec.clamp(target);
        }
        final chain = [defaults.copyWith(params: tweaked)];
        final parsed = parseFxChain(formatFxChain(chain));
        expect(parsed.ok, isTrue, reason: '$type: ${parsed.errors}');
        expect(parsed.warnings, isEmpty, reason: '$type: ${parsed.warnings}');
        for (final key in tweaked.keys) {
          expect(
            parsed.chain.single.params[key],
            closeTo(tweaked[key]!, 1e-9),
            reason: '$type.$key',
          );
        }
      }
    });

    test('the catalog lists every effect', () {
      final text = fxCatalogText();
      for (final type in FxType.values) {
        expect(text, contains(type.name), reason: '${type.name} missing');
      }
      for (final category in FxCategory.values) {
        expect(text, contains(fxCategoryLabel(category).toUpperCase()));
      }
    });

    test('a single-effect listing shows every param with its range', () {
      final text = fxCatalogText(only: FxType.compressor);
      for (final key in defaultFx(FxType.compressor).params.keys) {
        expect(text, contains(key));
      }
      expect(text, contains('dB'));
      expect(text, contains('Compressor'));
    });
  });
}
