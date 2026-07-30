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
  })  : _indexUrl = indexUrl,
        _cache = cache;

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

  Future<List<LibraryItem>> _load() async {
    if (_catalog != null) return _catalog!;
    if (_shareable) {
      final hit = _sharedCache[_cacheKey];
      if (hit != null) return _catalog = hit;
    }
    final index = _json(await _http(Uri.parse(_indexUrl)), 'catalog index');
    final baseUrl = (index['baseUrl'] as String?) ?? '';
    // The index is the ~1 KB file we always fetch; its `version` is what decides
    // whether a persisted shard is still current.
    final version = (index['version'] as String?) ?? 'unversioned';
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
    final matched = _match(await _load(), query, filter);
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

  List<LibraryItem> _match(
    List<LibraryItem> all,
    String query,
    LibraryFilter filter,
  ) {
    final q = query.trim().toLowerCase();
    return [
      for (final i in all)
        if ((q.isEmpty ||
                i.title.toLowerCase().contains(q) ||
                i.composer.toLowerCase().contains(q)) &&
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
  Future<Uint8List> fetch(LibraryItem item) => _http(item.downloadUrl);
}
