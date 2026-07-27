import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/prebaked_narration.dart';
import 'package:comet_beat/core/audio/tts/tts_asset_cache.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory asset cache for pack-mode tests (no IndexedDB/filesystem).
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

void main() {
  test('narrationKey normalizes whitespace + is lang-prefixed', () {
    expect(narrationKey('  Hello   world ', 'en-US'), 'en|Hello world');
    expect(narrationKey('Guten Morgen', 'de_DE'), 'de|Guten Morgen');
    // Same normalized text + lang → same key regardless of formatting.
    final a = narrationKey('Hello\nworld', 'en');
    final b = narrationKey('Hello world', 'en');
    expect(a, b);
  });

  test('assetFor resolves baked keys, null for unbaked', () async {
    final manifest = jsonEncode({
      'en|Hello world': 'narration/en/abc.wav',
      'de|Guten Morgen': 'narration/de/def.wav',
    });
    final pn = PrebakedNarration(loadManifest: () async => manifest);
    final en = await pn.assetFor('  Hello world  ', 'en-US');
    expect(en, 'narration/en/abc.wav');
    expect(await pn.assetFor('Guten Morgen', 'de'), 'narration/de/def.wav');
    expect(await pn.assetFor('not baked', 'en'), isNull);
  });

  test('missing/broken manifest → nothing prebaked (no crash)', () async {
    final pn = PrebakedNarration(loadManifest: () async => throw 'no asset');
    expect(await pn.assetFor('anything', 'en'), isNull);
  });

  test('backend plays the baked asset; no-ops (falls back) when unbaked',
      () async {
    final played = <Uint8List>[];
    final wav = Uint8List.fromList([1, 2, 3, 4]);
    final backend = PrebakedNarrationBackend(
      play: (w) async => played.add(w),
      narration: PrebakedNarration(
        loadManifest: () async =>
            jsonEncode({'en|Hi there': 'narration/en/x.wav'}),
      ),
      loadAsset: (path) async {
        expect(path, 'narration/en/x.wav');
        return wav;
      },
    );

    expect(await backend.has('Hi there', 'en-US'), isTrue);
    expect(await backend.has('nope', 'en'), isFalse);

    await backend.speak('Hi there', langCode: 'en-US');
    expect(played, [wav]); // played the baked asset

    // 'not baked' → no-op, so the caller falls back to the platform voice.
    await backend.speak('not baked', langCode: 'en');
    expect(played, [wav]); // unchanged
  });

  test(
      'pack mode: has() is false until prefetch caches from remote, then '
      'speak plays the cached bytes', () async {
    final played = <Uint8List>[];
    final cache = _MemCache();
    final fetched = <String>[];
    final wav = Uint8List.fromList(List.filled(100, 7)); // > 44-byte WAV header
    final backend = PrebakedNarrationBackend(
      play: (w) async => played.add(w),
      cache: cache,
      remoteBase: 'https://cdn.example/narration',
      fetch: (url, {onProgress}) async {
        fetched.add(url);
        return wav;
      },
      narration: PrebakedNarration(
        loadManifest: () async =>
            jsonEncode({'en|Hi there': 'narration/en/x.wav'}),
      ),
      loadAsset: (_) async =>
          throw StateError('pack mode must not bundle-load'),
    );

    // Not cached yet → has() false → caller uses the platform voice.
    expect(await backend.has('Hi there', 'en-US'), isFalse);

    // Warm the cache from the remote pack.
    final n = await backend.prefetch([('Hi there', 'en-US')]);
    expect(n, 1);
    expect(fetched, ['https://cdn.example/narration/narration/en/x.wav']);

    // Now it serves from the cache (IndexedDB in the browser).
    expect(await backend.has('Hi there', 'en-US'), isTrue);
    await backend.speak('Hi there', langCode: 'en-US');
    expect(played, [wav]);

    // Prefetch again → already cached → no second fetch.
    expect(await backend.prefetch([('Hi there', 'en-US')]), 0);
    expect(fetched.length, 1);
  });

  test(
      'pack mode: a failed remote fetch caches nothing (stays silent → '
      'caller falls back)', () async {
    final cache = _MemCache();
    final backend = PrebakedNarrationBackend(
      play: (_) async {},
      cache: cache,
      remoteBase: 'https://cdn.example/narration',
      fetch: (url, {onProgress}) async => null, // offline / CORS / 404
      narration: PrebakedNarration(
        loadManifest: () async =>
            jsonEncode({'en|Hi there': 'narration/en/x.wav'}),
      ),
    );
    expect(await backend.prefetch([('Hi there', 'en-US')]), 0);
    expect(await backend.has('Hi there', 'en-US'), isFalse);
  });
}
