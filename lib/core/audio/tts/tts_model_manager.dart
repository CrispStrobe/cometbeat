// tts_model_manager.dart — the ONE place that downloads, caches, reports, and
// removes TTS model/voice assets, on BOTH native and web. Web-safe: it fetches
// with `package:http` (BrowserClient/fetch on web, dart:io client on native)
// and caches through the `tts_asset_cache` facade (files native, IndexedDB web).
//
//   final mgr = TtsModelManager();
//   final bytes = await mgr.ensure('piper/en_US-kathleen-low.onnx',
//       onProgress: (r, t) => ...);   // cached → instant; else download+cache
//
// `ensure` never throws: on offline / CORS-blocked / 404 / too-small it returns
// null and the caller falls back (platform voice, or a bundled pre-baked WAV).
//
// On native the cache is rooted at the SAME `~/.cache/comet_beat/models` dir
// PiperVoiceStore reads, and catalog ids are `piper/<base>.onnx` — so a download
// here transparently populates the files native synthesis loads. One cache, one
// downloader. (Kokoro stays on CrispASR's own registry; it is not in the catalog.)

import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/tts_asset_cache.dart';
import 'package:comet_beat/core/audio/tts/tts_asset_catalog.dart';
import 'package:http/http.dart' as http;

/// Fetches [url] to bytes, reporting progress (`received`, `total` — total is
/// null when the server sends no Content-Length). Returns null on any failure.
typedef ByteFetcher = Future<Uint8List?> Function(
  String url, {
  void Function(int received, int? total)? onProgress,
});

/// Cached / not-cached status for one catalog asset.
class TtsAssetStatus {
  const TtsAssetStatus(this.asset, this.cached);
  final TtsAsset asset;
  final bool cached;
}

class TtsModelManager {
  TtsModelManager({
    TtsAssetCache? cache,
    List<TtsAsset>? catalog,
    ByteFetcher? fetch,
  })  : _cache = cache ?? createTtsAssetCache(),
        catalog = catalog ?? kTtsAssetCatalog,
        _fetch = fetch ?? httpByteFetch;

  final TtsAssetCache _cache;
  final List<TtsAsset> catalog;
  final ByteFetcher _fetch;

  TtsAsset? assetById(String id) {
    for (final a in catalog) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Whether [id]'s bytes are already cached (no download needed).
  Future<bool> isCached(String id) => _cache.has(id);

  /// Cached bytes if present; otherwise download → validate (>= minBytes) →
  /// cache → return. Returns null for an unknown id or any download failure;
  /// never throws.
  Future<Uint8List?> ensure(
    String id, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final asset = assetById(id);
    if (asset == null) return null;
    final cached = await _cache.read(id);
    if (cached != null && cached.length >= asset.minBytes) return cached;
    final bytes = await _fetch(asset.url, onProgress: onProgress);
    if (bytes == null || bytes.length < asset.minBytes) return null;
    await _cache.write(id, bytes);
    return bytes;
  }

  /// Ensure every asset in a voice group; true iff all succeeded.
  Future<bool> ensureGroup(
    String groupId, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final assets = catalog.where((a) => a.group == groupId).toList();
    if (assets.isEmpty) return false;
    for (final a in assets) {
      if (await ensure(a.id, onProgress: onProgress) == null) return false;
    }
    return true;
  }

  /// Remove one asset's cached bytes.
  Future<void> remove(String id) => _cache.delete(id);

  /// Remove every asset in a voice group.
  Future<void> removeGroup(String groupId) async {
    for (final a in catalog.where((a) => a.group == groupId)) {
      await _cache.delete(a.id);
    }
  }

  /// Total bytes currently cached (whole cache, for a settings readout).
  Future<int> cachedBytes() => _cache.totalBytes();

  /// Per-asset cached status across the catalog.
  Future<List<TtsAssetStatus>> report() async => [
        for (final a in catalog) TtsAssetStatus(a, await _cache.has(a.id)),
      ];
}

/// Default cross-platform fetcher (streams so progress is live). Public so
/// tests can compose it and callers can reuse it.
Future<Uint8List?> httpByteFetch(
  String url, {
  void Function(int received, int? total)? onProgress,
}) async {
  final client = http.Client();
  try {
    final resp = await client.send(http.Request('GET', Uri.parse(url)));
    if (resp.statusCode != 200) return null;
    final total = resp.contentLength;
    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in resp.stream) {
      builder.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    return builder.takeBytes();
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}
