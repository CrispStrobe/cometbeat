// The CometBeat curated catalog — OUR rights-verified sound library, published
// from the music-db pipeline as static JSON + assets on a Hugging Face dataset.
//
// Unlike the upstream sources (VCSL, FreePats, Commons), this is the catalog WE
// vet and ship: every item is CC0 / CC-BY / PD / MIT (the emit_catalog rights
// gate; CC-BY-SA and unclear material never reach it), with attribution carried
// per item. It is shard-ready: the app reads a tiny `index.json` first, then
// only the per-kind shard(s) it needs (soundfonts / instruments / samples), so
// it scales to a large registry without downloading everything or standing up a
// query server.
//
// ⚠️ CORRECTION (measured 2026-07-30): this header used to claim "HF's CDN serves
// each file gzipped on the wire". IT DOES NOT — requesting the score shard with
// and without `Accept-Encoding: gzip` returns the identical byte count. That
// wrong assumption is why the score shard was downloaded as 36.5 MB of raw JSON
// on EVERY cold start (the in-process cache does not survive a launch). So:
//   * the publisher now emits a `.json.gz` twin and advertises it as `urlGz`
//     (36.5 MB -> 3.71 MB, 8x), which we prefer and inflate here;
//   * shard bytes are persisted keyed by the catalog `version`, so a cold start
//     costs one ~1 KB index fetch instead of the whole shard.
// If you are tempted to trust a transport-level claim again, measure it first.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
// A generic key->bytes store that already solves files-on-native /
// IndexedDB-on-web. TTS-named for historical reasons — the API is just
// has/read/write/delete, nothing speech-specific.
import 'package:comet_beat/core/audio/tts/tts_asset_cache.dart';
import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/lyric_index_wiring.dart';

/// Thrown when the catalog index/shard comes back unreadable (a changed layout,
/// an error body) — loud, so an empty listing isn't mistaken for "nothing here".
class CometbeatCatalogUnavailable implements Exception {
  const CometbeatCatalogUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The published dataset's index (the one small file the app reads first).
const _kIndexUrl =
    'https://huggingface.co/datasets/cstr/cometbeat-assets/resolve/main/catalog/index.json';

/// Browses the curated CometBeat catalog for the given [kinds] (each maps to one
/// published shard). Defaults to the playable "sounds" — SoundFonts, SFZ
/// instruments, and samples — for the Sound Library; a module browser passes
/// `{'module'}` or `{'score'}`.
class CometbeatCatalogSource implements ContentSource {
  CometbeatCatalogSource(
    this._http, {
    this.kinds = const {'soundfont', 'instrument', 'sample'},
    String indexUrl = _kIndexUrl,
    TtsAssetCache? cache,
    String? lyricIndexDirectory,
  })  : _indexUrl = indexUrl,
        _cache = cache,
        _indexDir = lyricIndexDirectory;

  /// The playable sound library (SoundFonts + SFZ instruments + samples).
  factory CometbeatCatalogSource.sounds(HttpGet http) =>
      CometbeatCatalogSource(http);

  /// Tracker modules (whole songs), a separate browsing lane.
  factory CometbeatCatalogSource.modules(HttpGet http) =>
      CometbeatCatalogSource(http, kinds: const {'module'});

  /// Every catalog kind. The browser filters client-side by facet chip (kind /
  /// format / corpus source) — those chips exist as of 2026-07-30; this comment
  /// previously claimed them while `library_browser_screen.dart` had none.
  factory CometbeatCatalogSource.all(HttpGet http) => CometbeatCatalogSource(
        http,
        kinds: const {'soundfont', 'instrument', 'sample', 'module', 'score'},
      );

  /// Our curated symbolic SCORE corpus (GregoBase / NIFC / PDMX / Mutopia /
  /// Lieder / …) — browsed + imported by the Song Book's library browser, kept
  /// separate from the sound-library kinds so a sounds browse never fetches the
  /// (large) score shard.
  factory CometbeatCatalogSource.scores(HttpGet http) =>
      CometbeatCatalogSource(http, kinds: const {'score'});

  final HttpGet _http;

  /// Persists shard bytes across launches. Created lazily so a caller that never
  /// browses never touches the filesystem; injectable so tests can supply an
  /// in-memory store (or a throwing one, to prove cache failure is survivable).
  TtsAssetCache? _cache;
  final Set<String> kinds;
  final String _indexUrl;

  /// Fetched once per instance (the needed shards, flattened).
  List<LibraryItem>? _catalog;

  ({String base, String version, List<dynamic>? shards})? _index;

  /// Built only when a lyric search actually happens. FTS5 where available,
  /// a linear scan otherwise — see `lyric_index.dart`.
  LyricIndex? _lyricIndex;

  /// Where a native FTS index may be persisted. Null = in-memory only.
  final String? _indexDir;

  /// Which backend answered the last lyric search ('fts5', 'fts5-wasm',
  /// 'linear'), or null if none has. Exposed because a silent fallback is
  /// otherwise invisible — the feature works either way, just slower.
  String? get lyricBackend => _lyricIndex?.backend;

  /// Process-wide cache so reopening the browser is instant instead of
  /// re-fetching the index + shards. Keyed by the kind-set; only used for the
  /// real published index, so test instances (custom [_indexUrl]) stay
  /// per-instance and never see each other's fixtures.
  static final Map<String, List<LibraryItem>> _sharedCache = {};

  bool get _shareable => _indexUrl == _kIndexUrl;
  String get _cacheKey => (kinds.toList()..sort()).join(',');

  /// Drops the process-wide cache (tests / a manual "refresh").
  static void clearSharedCache() => _sharedCache.clear();

  /// Resolve a catalog-relative path as URI path segments. Catalog assets may
  /// contain spaces, `#`, or other filename characters; concatenating the raw
  /// path lets `Uri.parse` treat `#` as a fragment and produces a broken URL.
  Uri _assetUrl(String baseUrl, String path) {
    final base = Uri.parse(baseUrl);
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    return base.resolve(encoded);
  }

  @override
  String get id => 'cometbeat-catalog';

  @override
  String get name => 'CometBeat Library';

  @override
  String get homepage =>
      'https://huggingface.co/datasets/cstr/cometbeat-assets';

  @override
  String get licenseSummary => 'CC0 / CC-BY / PD — curated, rights-verified';

  Map<String, dynamic> _json(Uint8List bytes, String what) {
    try {
      // Sniff the gzip magic rather than trusting the URL: the publisher may
      // serve either, and a `.gz` that arrived already-inflated by some proxy
      // must still parse.
      final raw = (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b)
          ? Uint8List.fromList(const GZipDecoder().decodeBytes(bytes))
          : bytes;
      final v = jsonDecode(utf8.decode(raw));
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    throw CometbeatCatalogUnavailable('unreadable $what');
  }

  /// Shard bytes for [shard], from the on-disk cache when the cached copy was
  /// written for this catalog [version], else fetched and then cached.
  ///
  /// Cache failure is never fatal — a browse that cannot persist is still a
  /// working browse, so every cache call degrades to the network path.
  Future<Uint8List> _shardBytes(
    Map<String, dynamic> shard,
    String baseUrl,
    String version,
  ) async {
    final kind = shard['kind'] as String? ?? 'shard';
    final gz = shard['urlGz'] as String?;
    final url = gz ?? shard['url'] as String;
    final key = 'catalog/$kind-$version${gz != null ? '.json.gz' : '.json'}';

    final cache = _cache ??= createTtsAssetCache();
    try {
      final hit = await cache.read(key);
      if (hit != null && hit.isNotEmpty) return hit;
    } catch (_) {/* unreadable cache — fall through to the network */}

    final bytes = await _http(Uri.parse(baseUrl + url));
    try {
      // Drop other versions of THIS kind first, so the cache holds one copy per
      // shard rather than growing by a few MB on every catalog publish.
      for (final k in await cache.keys()) {
        if (k.startsWith('catalog/$kind-') && k != key) await cache.delete(k);
      }
      await cache.write(key, bytes);
    } catch (_) {/* cache is a nicety, not a requirement */}
    return bytes;
  }

  /// Where the last good index is kept, so a later start can proceed offline.
  ///
  /// NOT versioned like the shards are: the index is what CARRIES the version,
  /// so there is nothing to key it by. One slot, overwritten on every
  /// successful fetch.
  static const _kIndexCacheKey = 'catalog/index.json';

  /// The catalog index — from the network, falling back to the last good copy.
  ///
  /// ⚠️ This fallback is what makes the shard cache USABLE. Shards have been
  /// cached on disk for a while, but `_load` fetched the index first with no
  /// recovery, so one failed request made every cached shard unreachable and
  /// the library read as empty offline — a cache that only worked when it was
  /// not needed.
  ///
  /// The network is still tried FIRST, and a fresh index is still what decides
  /// whether cached shards are current. Only an actual failure reaches for the
  /// copy, so a published catalog update is picked up exactly as before.
  Future<Uint8List> _indexBytes() async {
    final cache = _cache ??= createTtsAssetCache();
    try {
      final fresh = await _http(Uri.parse(_indexUrl));
      try {
        await cache.write(_kIndexCacheKey, fresh);
      } catch (_) {/* cache is a nicety, not a requirement */}
      return fresh;
    } catch (_) {
      try {
        final hit = await cache.read(_kIndexCacheKey);
        if (hit != null && hit.isNotEmpty) return hit;
      } catch (_) {/* unreadable cache — report the ORIGINAL failure */}
      // Nothing cached: the real problem is the network, and saying so is more
      // useful than reporting a cache miss the user cannot act on.
      rethrow;
    }
  }

  Future<List<LibraryItem>> _load() async {
    if (_catalog != null) return _catalog!;
    if (_shareable) {
      final hit = _sharedCache[_cacheKey];
      if (hit != null) return _catalog = hit;
    }
    final index = _json(await _indexBytes(), 'catalog index');
    final baseUrl = (index['baseUrl'] as String?) ?? '';
    // The index is the ~1 KB file we always fetch; its `version` is what decides
    // whether a persisted shard is still current.
    final version = (index['version'] as String?) ?? 'unversioned';
    // Remembered so the lyrics shard can be fetched LATER, only if asked for.
    _index =
        (base: baseUrl, version: version, shards: index['shards'] as List?);
    final shards = (index['shards'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((s) => kinds.contains(s['kind']));
    final items = <LibraryItem>[];
    for (final shard in shards) {
      final data = _json(
        await _shardBytes(shard, baseUrl, version),
        'catalog shard ${shard['kind']}',
      );
      for (final raw in (data['items'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final path = raw['path'] as String?;
        if (path == null) continue;
        items.add(
          LibraryItem(
            sourceId: id,
            sourceName: name,
            id: (raw['id'] as String?) ?? path,
            title: (raw['name'] as String?) ?? path.split('/').last,
            composer: (raw['attribution'] as String?) ?? '',
            collection: (raw['kind'] as String?) ?? '',
            declaredLicense: (raw['license'] as String?) ?? '',
            sourceUrl: raw['sourceUrl'] as String?,
            downloadUrl: _assetUrl(baseUrl, path),
            format: (raw['format'] as String?) ?? '',
            music: MusicInfo.fromJson(raw['music']),
            corpusSource: raw['source'] as String?,
            textIncipit: raw['textIncipit'] as String?,
          ),
        );
      }
    }
    if (_shareable) _sharedCache[_cacheKey] = items;
    return _catalog = items;
  }

  @override

  /// Exact filtering and an exact total — this source already holds every item
  /// for the requested kinds in memory, so counting costs nothing and the UI can
  /// honestly say "448 matches" instead of "60 shown, who knows".
  @override
  Future<LibraryPage> browsePage({
    String query = '',
    LibraryFilter filter = const LibraryFilter(),
    int limit = 60,
    int offset = 0,
  }) async {
    final all = await _load();
    final lyricHits = filter.searchLyrics
        ? await _lyricMatches(query.trim())
        : const <String>{};
    final matched = _match(all, query, filter, lyricHits);
    return LibraryPage(
      items: matched.skip(offset).take(limit).toList(),
      total: matched.length,
      hasMore: matched.length > offset + limit,
    );
  }

  /// The facet values actually present, for building filter chips that can never
  /// offer a choice yielding zero results.
  Future<Map<String, List<String>>> facets() async {
    final all = await _load();
    Map<String, int> tally(String Function(LibraryItem) f) {
      final c = <String, int>{};
      for (final i in all) {
        final k = f(i);
        if (k.isNotEmpty) c[k] = (c[k] ?? 0) + 1;
      }
      return c;
    }

    List<String> ranked(Map<String, int> c, int top) =>
        (c.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(top)
            .map((e) => e.key)
            .toList();

    return {
      'kind': ranked(tally((i) => i.collection), 8),
      'format': ranked(tally((i) => i.format), 12),
      'source': ranked(tally((i) => i.corpusSource ?? ''), 20),
    };
  }

  /// Ids whose sung text contains [q], fetching the lyrics shard on first use.
  ///
  /// Deliberately lazy: the shard is 3.6 MB gzipped against the browse path's
  /// 2.6 MB, so paying for it up front would undo the work that got the catalog
  /// small. Cached by catalog version like every other shard, so the cost is
  /// once per publish, not once per launch.
  Future<Set<String>> _lyricMatches(String q) async {
    final idx = _index;
    if (idx == null || q.isEmpty) return const {};
    if (_lyricIndex == null) {
      installLyricIndexBackend();
      final shard = (idx.shards ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((s) => s['kind'] == 'lyrics')
          .firstOrNull;
      if (shard == null) return const {};
      final data = _json(
        await _shardBytes(shard, idx.base, idx.version),
        'catalog shard lyrics',
      );
      final texts = {
        for (final e in (data['items'] as Map? ?? const {}).entries)
          '${e.key}': '${e.value}',
      };
      _lyricIndex = await lyricIndexBuilder(
        texts,
        version: idx.version,
        directory: _indexDir,
      );
    }
    return _lyricIndex!.search(q);
  }

  List<LibraryItem> _match(
    List<LibraryItem> all,
    String query,
    LibraryFilter filter, [
    Set<String> lyricHits = const {},
  ]) {
    final q = query.trim().toLowerCase();
    return [
      for (final i in all)
        if ((q.isEmpty ||
                i.title.toLowerCase().contains(q) ||
                i.composer.toLowerCase().contains(q) ||
                // the inline incipit makes the common case work without the
                // lyrics shard at all
                (i.textIncipit?.toLowerCase().contains(q) ?? false) ||
                lyricHits.contains(i.id)) &&
            (filter.isEmpty || filter.matches(i)))
          i,
    ];
  }

  @override
  Future<List<LibraryItem>> browse({String query = '', int limit = 60}) async {
    // One matcher for both entry points, so a filter can never disagree with a
    // plain search about what "matches".
    return _match(await _load(), query, const LibraryFilter())
        .take(limit)
        .toList();
  }

  @override
  Future<Uint8List> fetch(LibraryItem item) async {
    final key = _payloadKey(item);
    final cache = _cache ??= createTtsAssetCache();
    if (key != null) {
      try {
        final hit = await cache.read(key);
        if (hit != null && hit.isNotEmpty) return hit;
      } catch (_) {/* unreadable cache — fall through to the network */}
    }

    final bytes = await _http(item.downloadUrl);
    if (key != null && bytes.length <= kMaxCachedPayloadBytes) {
      try {
        await _prunePayloads(cache, incoming: bytes.length);
        await cache.write(key, bytes);
      } catch (_) {/* cache is a nicety, not a requirement */}
    }
    return bytes;
  }

  /// Where [item]'s bytes are kept, or null when it must not be cached.
  ///
  /// ⚠️ Keyed by the DOWNLOAD URL, not the item id. Catalog ids are stable but
  /// a republish can repoint one at different bytes, and serving the old file
  /// for a new URL is a silent wrong-content bug rather than a miss.
  String? _payloadKey(LibraryItem item) {
    final url = item.downloadUrl.toString();
    if (url.isEmpty) return null;
    // A filesystem-safe, collision-resistant name. `hashCode` alone is 32-bit
    // and would collide across ~38k items sooner than is comfortable, so the
    // length goes in too.
    return 'payload/${url.hashCode.toRadixString(16)}-${url.length}';
  }

  /// The biggest payload worth keeping.
  ///
  /// ⚠️ This method serves BOTH a 20 KB score and a 140 MB SoundFont. Caching
  /// by default is right for the first and ruinous for the second — a user who
  /// auditions a few instruments would fill their disk without ever asking for
  /// an offline library. 4 MB comfortably covers every score and tracker module
  /// in the catalog while excluding the sample and soundfont payloads, which
  /// have their own deliberate download flow.
  static const int kMaxCachedPayloadBytes = 4 * 1024 * 1024;

  /// How much catalog cache to keep on disk in total.
  ///
  /// ⚠️ Measured against the WHOLE cache, not just payloads — the shards live
  /// there too (the score shard alone is ~2.7 MB gzipped) and pretending
  /// otherwise would let the real footprint drift past whatever number this
  /// claims. Only payloads are evicted, because the shards are what make the
  /// library work offline at all and are cheap by comparison.
  static const int kCatalogCacheBudgetBytes = 64 * 1024 * 1024;

  /// Drops cached payloads until [incoming] fits inside the budget.
  ///
  /// Eviction order is arbitrary (the cache exposes no timestamps), which is
  /// honest rather than pretending to be an LRU: every entry is re-fetchable,
  /// so the cost of evicting the wrong one is one download, not a loss.
  Future<void> _prunePayloads(
    TtsAssetCache cache, {
    required int incoming,
  }) async {
    final keys = (await cache.keys()).where((k) => k.startsWith('payload/'));
    var total = await cache.totalBytes();
    if (total + incoming <= kCatalogCacheBudgetBytes) return;
    for (final k in keys) {
      if (total + incoming <= kCatalogCacheBudgetBytes) return;
      try {
        final bytes = await cache.read(k);
        await cache.delete(k);
        total -= bytes?.length ?? 0;
      } catch (_) {/* skip what will not budge */}
    }
  }
}
