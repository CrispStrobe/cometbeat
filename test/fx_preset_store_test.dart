// WS-W6 — saved effect chains.
//
// The store is deliberately the same shape as `ProjectStore`, so most of what is
// worth testing is the same too: newest first, a cap that drops the OLDEST, and
// a corrupt store that reads as empty rather than throwing at start-up.
//
// What is NEW here is the format. Presets are stored as chain STRINGS, which
// buys portability and readability and costs one thing: a chain string cannot
// carry per-param automation. That trade has to be visible, so it is asserted.

import 'package:comet_beat/core/audio/fx/fx_chain_codec.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/services/fx_preset_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<FxPresetStore> _store([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  return FxPresetStore(await SharedPreferences.getInstance());
}

List<FxSpec> _chain(String source) {
  final parsed = parseFxChain(source);
  expect(parsed.errors, isEmpty, reason: 'fixture "$source"');
  return parsed.chain;
}

void main() {
  test('a saved chain comes back as the same effects', () async {
    final store = await _store();
    await store.save('Warm', _chain('lowpass freq=800 | gain gainDb=-3'));

    final saved = store.find('Warm');
    expect(saved, isNotNull);
    expect(saved!.specs.map((f) => f.type), [FxType.lowpass, FxType.gain]);
    // Readable, which is half the reason for storing text.
    expect(saved.chain, contains('lowpass'));
  });

  test('presets come back newest first', () async {
    final store = await _store();
    await store.save('old', _chain('gain gainDb=-3'), nowMs: 1000);
    await store.save('new', _chain('reverb mix=20%'), nowMs: 2000);
    expect(store.list().map((p) => p.name), ['new', 'old']);
  });

  test('saving the same name replaces, it does not duplicate', () async {
    final store = await _store();
    await store.save('Warm', _chain('gain gainDb=-3'), nowMs: 1000);
    await store.save('Warm', _chain('reverb mix=20%'), nowMs: 2000);

    expect(store.list(), hasLength(1));
    expect(store.find('Warm')!.specs.single.type, FxType.reverb);
  });

  test('the cap drops the OLDEST, never the newest', () async {
    // The one that matters: a cap that drops what you just made is a cap that
    // eats your work.
    final store = await _store();
    for (var i = 0; i <= FxPresetStore.maxPresets; i++) {
      await store.save('p$i', _chain('gain gainDb=-$i'), nowMs: 1000 + i);
    }
    final names = store.list().map((p) => p.name).toList();
    expect(names, hasLength(FxPresetStore.maxPresets));
    expect(names.first, 'p${FxPresetStore.maxPresets}');
    expect(names, isNot(contains('p0')));
  });

  test('removing one leaves the rest', () async {
    final store = await _store();
    await store.save('a', _chain('gain gainDb=-3'), nowMs: 1000);
    await store.save('b', _chain('reverb mix=20%'), nowMs: 2000);
    await store.remove('a');
    expect(store.list().map((p) => p.name), ['b']);
  });

  group('what is refused', () {
    test('an empty name', () async {
      final store = await _store();
      await store.save('   ', _chain('gain gainDb=-3'));
      expect(store.list(), isEmpty);
    });

    test('an empty chain', () async {
      // "No effects" is what you get by not applying a preset; a list of empty
      // entries is a list you stop reading.
      final store = await _store();
      await store.save('Nothing', const []);
      expect(store.list(), isEmpty);
    });
  });

  group('a store that has gone bad reads as empty', () {
    // A throw at start-up is not recoverable; an empty list is.
    test('not even JSON', () async {
      final store = await _store({'fx_presets_v1': 'not json at all'});
      expect(store.list(), isEmpty);
    });

    test('JSON, but not a list', () async {
      final store = await _store({'fx_presets_v1': '{"a":1}'});
      expect(store.list(), isEmpty);
    });

    test('one bad row does not cost the good ones', () async {
      final store = await _store({
        'fx_presets_v1':
            '[{"name":"ok","chain":"gain gainDb=-3","savedAtMs":1},'
                '{"nope":true},"string",null]',
      });
      expect(store.list().map((p) => p.name), ['ok']);
    });

    test('a chain that no longer parses yields no effects, not a throw', () {
      // An older build, or a hand-edited value. The preset stays listed so the
      // user can see and delete it.
      const preset = SavedFxPreset(
        name: 'from the future',
        chain: 'quantumverb shimmer=11',
        savedAtMs: 1,
      );
      expect(preset.specs, isEmpty);
    });
  });

  group('⚠️ the cost of storing text: automation cannot travel', () {
    test('fxChainStringIsLossless is how a caller finds out BEFORE saving', () {
      final automated = [
        const FxSpec(
          type: FxType.gain,
          params: {'gainDb': -6},
          automation: {
            'gainDb': [
              FxAutomationPoint(ms: 0, value: -12),
              FxAutomationPoint(ms: 1000, value: 0),
            ],
          },
        ),
      ];
      expect(fxChainStringIsLossless(automated), isFalse);
      expect(fxChainStringIsLossless(_chain('gain gainDb=-6')), isTrue);
    });

    test('saving one anyway keeps the effect and loses only the automation',
        () async {
      // Stated rather than left to be discovered: the preset is still useful,
      // and what it dropped is exactly one thing.
      final store = await _store();
      await store.save('Swell', [
        const FxSpec(
          type: FxType.gain,
          params: {'gainDb': -6},
          automation: {
            'gainDb': [FxAutomationPoint(ms: 0, value: -12)],
          },
        ),
      ]);
      final saved = store.find('Swell')!.specs.single;
      expect(saved.type, FxType.gain);
      expect(saved.params['gainDb'], -6);
      expect(saved.automation, isEmpty);
    });
  });
}
