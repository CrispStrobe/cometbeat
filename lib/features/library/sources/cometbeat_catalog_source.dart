// The CometBeat curated catalog — OUR rights-verified sound library, published
// from the music-db pipeline as static JSON + assets on a Hugging Face dataset.
//
// Unlike the upstream sources (VCSL, FreePats, Commons), this is the catalog WE
// vet and ship: every item is CC0 / CC-BY / PD / MIT (the emit_catalog rights
// gate; CC-BY-SA and unclear material never reach it), with attribution carried
// per item. It is shard-ready: the app reads a tiny `index.json` first, then
// only the per-kind shard(s) it needs (soundfonts / instruments / samples), so
// it scales to a large registry without downloading everything or standing up a
// query server. HF's CDN serves each file gzipped on the wire.

import 'dart:convert';
import 'dart:typed_data';

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
/// `{'module'}`.
class CometbeatCatalogSource implements ContentSource {
  CometbeatCatalogSource(
    this._http, {
    this.kinds = const {'soundfont', 'instrument', 'sample'},
    String indexUrl = _kIndexUrl,
  }) : _indexUrl = indexUrl;

  /// The playable sound library (SoundFonts + SFZ instruments + samples).
  factory CometbeatCatalogSource.sounds(HttpGet http) =>
      CometbeatCatalogSource(http);

  /// Tracker modules (whole songs), a separate browsing lane.
  factory CometbeatCatalogSource.modules(HttpGet http) =>
      CometbeatCatalogSource(http, kinds: const {'module'});

  /// Every playable-asset kind — the capable browser filters client-side by
  /// kind chip. (Not scores — those are their own library-browser lane.)
  factory CometbeatCatalogSource.all(HttpGet http) => CometbeatCatalogSource(
        http,
        kinds: const {'soundfont', 'instrument', 'sample', 'module'},
      );

  /// Our curated symbolic SCORE corpus (GregoBase / NIFC / PDMX / Mutopia /
  /// Lieder / …) — browsed + imported by the Song Book's library browser, kept
  /// separate from the sound-library kinds so a sounds browse never fetches the
  /// (large) score shard.
  factory CometbeatCatalogSource.scores(HttpGet http) =>
      CometbeatCatalogSource(http, kinds: const {'score'});

  final HttpGet _http;
  final Set<String> kinds;
  final String _indexUrl;

  /// Fetched once per instance (the needed shards, flattened).
  List<LibraryItem>? _catalog;

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
      final v = jsonDecode(utf8.decode(bytes));
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    throw CometbeatCatalogUnavailable('unreadable $what');
  }

  Future<List<LibraryItem>> _load() async {
    if (_catalog != null) return _catalog!;
    final index = _json(await _http(Uri.parse(_indexUrl)), 'catalog index');
    final baseUrl = (index['baseUrl'] as String?) ?? '';
    final shards = (index['shards'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((s) => kinds.contains(s['kind']));
    final items = <LibraryItem>[];
    for (final shard in shards) {
      final data = _json(
        await _http(Uri.parse(baseUrl + (shard['url'] as String))),
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
            downloadUrl: Uri.parse(baseUrl + path),
            format: (raw['format'] as String?) ?? '',
          ),
        );
      }
    }
    return _catalog = items;
  }

  @override
  Future<List<LibraryItem>> browse({String query = '', int limit = 60}) async {
    final all = await _load();
    final q = query.trim().toLowerCase();
    final matched = q.isEmpty
        ? all
        : [
            for (final i in all)
              if (i.title.toLowerCase().contains(q) ||
                  i.composer.toLowerCase().contains(q))
                i,
          ];
    return matched.take(limit).toList();
  }

  @override
  Future<Uint8List> fetch(LibraryItem item) => _http(item.downloadUrl);
}
