// Covers #2 of the TTS follow-up queue: TtsService.prefetchNarration warms the
// pre-baked pack cache, and opening a tutorial prefetches all its step clips
// (so on web they later play instantly from IndexedDB). Uses an in-memory cache
// + a fake fetch — no network, no plugin.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/prebaked_narration.dart';
import 'package:comet_beat/core/audio/tts/tts_asset_cache.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/tts_service.dart';
import 'package:comet_beat/shared/tutorial/tutorial.dart';
import 'package:comet_beat/shared/tutorial/tutorial_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

class _MemCache implements TtsAssetCache {
  final Map<String, Uint8List> _m = {};
  @override
  Future<bool> has(String key) async => _m[key]?.isNotEmpty ?? false;
  @override
  Future<Uint8List?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, Uint8List bytes) async => _m[key] = bytes;
  @override
  Future<void> delete(String key) async => _m.remove(key);
  @override
  Future<List<String>> keys() async => _m.keys.toList();
  @override
  Future<int> totalBytes() async =>
      _m.values.fold<int>(0, (s, b) => s + b.length);
}

class _MuteBackend implements TtsBackend {
  @override
  Future<void> speak(String text, {required String langCode}) async {}
  @override
  Future<void> stop() async {}
}

/// A pack-mode pre-baked backend over [cache] whose manifest maps the two
/// tutorial step texts (en) to clip paths, fetched from a fake remote.
PrebakedNarrationBackend _packBackend(_MemCache cache) =>
    PrebakedNarrationBackend(
      play: (_) async {},
      cache: cache,
      remoteBase: 'https://cdn.example/narration',
      fetch: (url, {onProgress}) async => Uint8List(200),
      narration: PrebakedNarration(
        loadManifest: () async => jsonEncode({
          'en|First step text': 'narration/a.wav',
          'en|Second step text': 'narration/b.wav',
        }),
      ),
    );

final _tutorial = Tutorial(
  title: 'How to play',
  steps: const [
    TutorialStep(text: 'First step text'),
    TutorialStep(text: 'Second step text'),
  ],
);

void main() {
  test('prefetchNarration warms the pack cache; no-op in bundled mode',
      () async {
    final cache = _MemCache();
    final tts =
        TtsService(backend: _MuteBackend(), prebaked: _packBackend(cache));
    final n = await tts.prefetchNarration([
      ('First step text', 'en-US'),
      ('Second step text', 'en-US'),
    ]);
    expect(n, 2);
    expect(await cache.has('narration/a.wav'), isTrue);
    expect(await cache.has('narration/b.wav'), isTrue);

    // Bundled mode (no prebaked) → prefetch is a harmless no-op.
    final bundled = TtsService(backend: _MuteBackend());
    expect(await bundled.prefetchNarration([('x', 'en')]), 0);
  });

  testWidgets('opening a tutorial prefetches all its step clips into the cache',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cache = _MemCache();
    final tts =
        TtsService(backend: _MuteBackend(), prebaked: _packBackend(cache));
    await pumpGame(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showTutorial(context, _tutorial),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      extraProviders: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider<TtsService>.value(value: tts),
      ],
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Both steps' clips warmed on open — ready to play instantly later.
    expect(await cache.has('narration/a.wav'), isTrue);
    expect(await cache.has('narration/b.wav'), isTrue);
  });
}
