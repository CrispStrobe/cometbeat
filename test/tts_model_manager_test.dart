import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/tts_asset_cache.dart';
import 'package:comet_beat/core/audio/tts/tts_asset_catalog.dart';
import 'package:comet_beat/core/audio/tts/tts_model_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory cache for deterministic manager tests (no filesystem/network).
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
  group('catalog integrity', () {
    test('ids unique + cache-key aligned with PiperVoiceStore paths', () {
      final ids = kTtsAssetCatalog.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'ids must be unique');
      for (final a in kTtsAssetCatalog) {
        expect(
          a.id.startsWith('piper/'),
          isTrue,
          reason: 'id doubles as the models/-rooted cache key',
        );
        expect(a.url.startsWith('https://'), isTrue);
        expect(a.langs, isNotEmpty);
        expect(a.minBytes, greaterThan(0));
      }
    });

    test('every asset is ship-safe by licence (no NC / SA / espeak)', () {
      for (final a in kTtsAssetCatalog) {
        final l = a.license.toLowerCase();
        expect(l.contains('cc0'), isTrue, reason: 'voices are CC0');
        expect(l.contains('-nc'), isFalse);
        expect(l.contains('-sa') || l.contains('share'), isFalse);
        expect(l.contains('espeak'), isFalse);
      }
    });

    test('voice groups pair a model with its config', () {
      final groups = ttsVoiceGroups();
      expect(groups.map((g) => g.id).toSet(), {'piper-en', 'piper-de'});
      for (final g in groups) {
        final kinds = g.assets.map((a) => a.kind).toSet();
        expect(kinds, {TtsAssetKind.voiceModel, TtsAssetKind.voiceConfig});
        expect(g.approxBytes, greaterThan(0));
      }
    });
  });

  group('TtsModelManager', () {
    test('cache miss downloads, validates, and stores', () async {
      final cache = _MemCache();
      final fetched = <String>[];
      final mgr = TtsModelManager(
        cache: cache,
        fetch: (url, {onProgress}) async {
          fetched.add(url);
          onProgress?.call(2048, 2048);
          return Uint8List(2048);
        },
      );
      const id = 'piper/en_US-kathleen-low.onnx.json'; // 100-byte floor
      final bytes = await mgr.ensure(id);
      expect(bytes, isNotNull);
      expect(bytes!.length, 2048);
      expect(fetched.length, 1);
      expect(await cache.has(id), isTrue);
    });

    test('cache hit skips the network', () async {
      final cache = _MemCache();
      await cache.write('piper/en_US-kathleen-low.onnx.json', Uint8List(200));
      var fetches = 0;
      final mgr = TtsModelManager(
        cache: cache,
        fetch: (url, {onProgress}) async {
          fetches++;
          return Uint8List(200);
        },
      );
      final bytes = await mgr.ensure('piper/en_US-kathleen-low.onnx.json');
      expect(bytes, isNotNull);
      expect(fetches, 0, reason: 'served from cache');
    });

    test('a too-small download is rejected and not cached', () async {
      final cache = _MemCache();
      final mgr = TtsModelManager(
        cache: cache,
        // model minBytes is 1 MiB; return far less → treated as failure.
        fetch: (url, {onProgress}) async => Uint8List(10),
      );
      const id = 'piper/en_US-kathleen-low.onnx';
      expect(await mgr.ensure(id), isNull);
      expect(await cache.has(id), isFalse);
    });

    test('unknown id → null, no fetch', () async {
      var fetches = 0;
      final mgr = TtsModelManager(
        cache: _MemCache(),
        fetch: (url, {onProgress}) async {
          fetches++;
          return Uint8List(4096);
        },
      );
      expect(await mgr.ensure('nope/does-not-exist'), isNull);
      expect(fetches, 0);
    });

    test('progress is forwarded to the caller', () async {
      final seen = <int>[];
      final mgr = TtsModelManager(
        cache: _MemCache(),
        fetch: (url, {onProgress}) async {
          onProgress?.call(1024, 4096);
          onProgress?.call(4096, 4096);
          return Uint8List(4096);
        },
      );
      await mgr.ensure(
        'piper/en_US-kathleen-low.onnx.json',
        onProgress: (r, t) => seen.add(r),
      );
      expect(seen, [1024, 4096]);
    });

    test('ensureGroup / removeGroup / report cover both assets', () async {
      final cache = _MemCache();
      final mgr = TtsModelManager(
        cache: cache,
        fetch: (url, {onProgress}) async =>
            Uint8List(url.endsWith('.json') ? 200 : 2 * 1024 * 1024),
      );
      expect(await mgr.ensureGroup('piper-en'), isTrue);
      final rep = await mgr.report();
      final enCached =
          rep.where((s) => s.asset.group == 'piper-en').every((s) => s.cached);
      expect(enCached, isTrue);
      expect(await mgr.cachedBytes(), greaterThan(2 * 1024 * 1024));

      await mgr.removeGroup('piper-en');
      final rep2 = await mgr.report();
      final enGone = rep2
          .where((s) => s.asset.group == 'piper-en')
          .every((s) => !s.cached);
      expect(enGone, isTrue);
    });
  });

  group('file cache (io impl via facade, VM host)', () {
    test('write/read/has/delete/keys/totalBytes round-trip', () async {
      final dir = await _tempDir();
      final cache = createTtsAssetCache(dirOverride: dir);
      const key = 'piper/en_US-kathleen-low.onnx';
      expect(await cache.has(key), isFalse);
      final data = Uint8List.fromList(List.generate(5000, (i) => i % 256));
      await cache.write(key, data);
      expect(await cache.has(key), isTrue);
      expect(await cache.read(key), data);
      expect(await cache.keys(), contains(key));
      expect(await cache.totalBytes(), 5000);
      await cache.delete(key);
      expect(await cache.has(key), isFalse);
      expect(await cache.read(key), isNull);
    });
  });
}

Future<String> _tempDir() async {
  // dart:io only — this group runs on the VM host.
  final d = await Directory.systemTemp.createTemp('tts_cache_test_');
  addTearDown(() {
    if (d.existsSync()) d.deleteSync(recursive: true);
  });
  return d.path;
}
