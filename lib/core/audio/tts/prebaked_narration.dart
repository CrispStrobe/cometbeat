// prebaked_narration.dart — play pre-rendered neural-voice narration from
// bundled WAV assets (built offline by tool/bake_narration.dart with the
// pure-Dart Piper core + CC0 voices). Instant on web, ZERO client inference —
// the practical way to get the neural voice into a browser (runtime synthesis
// there would freeze the single-threaded main isolate; see bin/tts_render.dart).
//
// LICENSE: MIT (this project). The baked audio is generated from CC0 Piper
// voices; the manifest/lookup here carries no third-party data.
//
// Web-safe: only `rootBundle` asset loading — no dart:io/ffi. The manifest KEY
// is the normalized text string (NOT a numeric hash), because a VM-side hash
// wouldn't match on the web (53-bit ints); only the asset FILENAME is hashed,
// and that is read from the manifest, never recomputed at lookup.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/narration_key.dart';
import 'package:comet_beat/core/audio/tts/tts_asset_cache.dart';
import 'package:comet_beat/core/audio/tts/tts_model_manager.dart'
    show ByteFetcher, httpByteFetch;
import 'package:comet_beat/core/services/tts_service.dart' show TtsBackend;
import 'package:flutter/services.dart' show rootBundle;

export 'package:comet_beat/core/audio/tts/narration_key.dart'
    show narrationKey, normalizeNarration;

/// Resolves narration strings to bundled WAV assets via `manifest.json`.
class PrebakedNarration {
  PrebakedNarration({Future<String> Function()? loadManifest})
      : _loadManifest = loadManifest ??
            (() => rootBundle.loadString('assets/narration/manifest.json'));

  final Future<String> Function() _loadManifest;
  Map<String, String>? _cache;

  Future<Map<String, String>> _manifest() async {
    if (_cache != null) return _cache!;
    try {
      final decoded = jsonDecode(await _loadManifest()) as Map<String, dynamic>;
      _cache = {for (final e in decoded.entries) e.key: e.value as String};
    } catch (_) {
      _cache = const {}; // no manifest bundled yet → nothing is prebaked
    }
    return _cache!;
  }

  /// The bundled asset path for [text]/[langCode], or null if not pre-baked.
  Future<String?> assetFor(String text, String langCode) async =>
      (await _manifest())[narrationKey(text, langCode)];
}

/// A [TtsBackend] that plays a pre-baked narration asset when one exists. When
/// the text isn't baked, [speak] no-ops (and [has] is false) so the caller
/// falls back to the platform/neural voice.
class PrebakedNarrationBackend implements TtsBackend {
  PrebakedNarrationBackend({
    required this.play,
    PrebakedNarration? narration,
    Future<Uint8List> Function(String assetPath)? loadAsset,
    this.stopPlayback,
    TtsAssetCache? cache,
    String? remoteBase,
    ByteFetcher? fetch,
  })  : narration = narration ?? PrebakedNarration(),
        _loadAsset = loadAsset ??
            ((p) async =>
                (await rootBundle.load('assets/$p')).buffer.asUint8List()),
        _cache = cache,
        _remoteBase = remoteBase,
        _fetch = fetch ?? httpByteFetch;

  /// Plays a finished WAV (e.g. AudioService.playWavBytes).
  final Future<void> Function(Uint8List wav) play;
  final PrebakedNarration narration;
  final Future<Uint8List> Function(String assetPath) _loadAsset;
  final Future<void> Function()? stopPlayback;

  /// PACK MODE (opt-in): when a [cache] is supplied, narration WAVs live in the
  /// asset cache (IndexedDB on web, files native) instead of being bundled — so
  /// a web build can ship WITHOUT the ~40 MB of baked audio and fetch/cache
  /// clips on demand from [remoteBase]. With no cache this is BUNDLED MODE and
  /// behaves exactly as before (WAVs read from `rootBundle`). The manifest value
  /// (e.g. `narration/<hash>.wav`) doubles as the cache key and the remote path.
  final TtsAssetCache? _cache;
  final String? _remoteBase;
  final ByteFetcher _fetch;

  /// Whether [text]/[langCode] can be served RIGHT NOW without a network round
  /// trip: bundled mode ⇒ the manifest has it (bundled); pack mode ⇒ it's cached
  /// (else the caller safely falls back to the platform voice — [prefetch] warms
  /// the cache for next time).
  Future<bool> has(String text, String langCode) async {
    final asset = await narration.assetFor(text, langCode);
    if (asset == null) return false;
    final cache = _cache;
    if (cache == null) return true; // bundled
    return cache.has(asset);
  }

  @override
  Future<void> speak(String text, {required String langCode}) async {
    final asset = await narration.assetFor(text, langCode);
    if (asset == null) return; // not prebaked → caller falls back
    final cache = _cache;
    if (cache == null) {
      await play(await _loadAsset(asset)); // bundled
      return;
    }
    final wav = await cache.read(asset);
    if (wav != null) await play(wav); // pack mode: cached only (has() gated it)
  }

  /// PACK MODE only: fetch + cache any not-yet-cached clips for [items] (each a
  /// `(text, langCode)`), so a later [has]/[speak] serves them from IndexedDB.
  /// No-op in bundled mode or without a [remoteBase]. Returns the count newly
  /// cached. Best-effort — a failed fetch is skipped, never thrown.
  Future<int> prefetch(Iterable<(String, String)> items) async {
    final cache = _cache;
    final base = _remoteBase;
    if (cache == null || base == null) return 0;
    var cached = 0;
    for (final (text, langCode) in items) {
      final asset = await narration.assetFor(text, langCode);
      if (asset == null || await cache.has(asset)) continue;
      final bytes = await _fetch('$base/$asset');
      if (bytes != null && bytes.length > 44) {
        await cache.write(asset, bytes);
        cached++;
      }
    }
    return cached;
  }

  @override
  Future<void> stop() async => stopPlayback?.call();
}
