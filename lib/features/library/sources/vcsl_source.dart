// Versilian Community Sample Library (VCSL) — a CC0 instrument-sample library
// published by Versilian Studios as plain WAV files on GitHub.
//
// Why this source is a good citizen: the whole library is a single, blanket
// **CC0** dedication ("you can do whatever you want with these sounds, even
// make commercial software, no royalties, no credit, no special terms"), the
// files are uncompressed WAV (the one audio format the app decodes), and the
// catalog is one GitHub tree request — no API key, no scraping of a site that
// doesn't want it.
//
// Layout: `Family/Subfamily/Instrument[/Articulation…]/File.wav`, e.g.
//   Aerophones/Edge-blown Aerophones/Ball Whistle/Main_BallWhistle_Long-001.wav
//   Aerophones/…/Baroque Alto Recorder/Staccato/AltRecorder_Stac_A#3_rr1_Main.wav
// Note the `#` in note names — every path segment MUST be percent-encoded or
// the raw URL is truncated at the fragment.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/features/library/content_source.dart';

/// Thrown when the catalogue request comes back in a shape we can't read —
/// a rate-limit body, an error payload, or a changed repo layout. Loud on
/// purpose: an empty listing would look like "the library has nothing".
class VcslUnavailable implements Exception {
  const VcslUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}

const _kRepo = 'sgossner/VCSL';
const _kBranch = 'master';

/// Browses the CC0 VCSL instrument samples (WAV) from the GitHub mirror.
class VcslSource implements ContentSource {
  VcslSource(this._http);

  final HttpGet _http;

  /// The parsed catalog, fetched once per instance.
  List<LibraryItem>? _catalog;

  @override
  String get id => 'vcsl';

  @override
  String get name => 'Versilian Community Sample Library';

  @override
  String get homepage => 'https://github.com/$_kRepo';

  @override
  String get licenseSummary => 'CC0 — public domain';

  /// Percent-encodes each path segment (keeping the `/` separators) so spaces
  /// and `#` in note names survive into the raw URL.
  static Uri rawUrlFor(String path) {
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    return Uri.parse(
      'https://raw.githubusercontent.com/$_kRepo/$_kBranch/$encoded',
    );
  }

  /// Turns a repo path into a browsable item; null if it isn't a WAV sample.
  static LibraryItem? itemForPath(String path) {
    if (!path.toLowerCase().endsWith('.wav')) return null;
    final parts = path.split('/');
    if (parts.length < 2) return null;

    final file = parts.last;
    final base = file.substring(0, file.length - 4); // drop ".wav"
    final pretty = base.replaceAll('_', ' ').trim();
    // Family/Subfamily/Instrument/…/file.wav — the instrument is the 3rd
    // segment when present, else fall back to the deepest folder.
    final instrument = parts.length >= 4 ? parts[2] : parts[parts.length - 2];
    final family = parts.first;

    return LibraryItem(
      sourceId: 'vcsl',
      sourceName: 'Versilian Community Sample Library',
      id: path,
      title: '$instrument · $pretty',
      composer: '',
      collection: family,
      declaredLicense: 'CC0',
      licenseUrl: 'https://creativecommons.org/publicdomain/zero/1.0/',
      sourceUrl: 'https://github.com/$_kRepo',
      downloadUrl: rawUrlFor(path),
      format: 'wav',
    );
  }

  /// Parses a GitHub `git/trees?recursive=1` payload into sample items.
  static List<LibraryItem> parseTree(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return const []; // a truncated/HTML error body must not crash browsing
    }
    if (decoded is! Map) return const [];
    final tree = decoded['tree'];
    if (tree is! List) return const [];
    final out = <LibraryItem>[];
    for (final entry in tree) {
      if (entry is! Map) continue;
      if (entry['type'] != 'blob') continue;
      final path = entry['path'];
      if (path is! String) continue;
      final item = itemForPath(path);
      if (item != null) out.add(item);
    }
    return out;
  }

  Future<List<LibraryItem>> _loadCatalog() async {
    final cached = _catalog;
    if (cached != null) return cached;
    final bytes = await _http(
      Uri.parse(
        'https://api.github.com/repos/$_kRepo/git/trees/$_kBranch?recursive=1',
      ),
    );
    final parsed = parseTree(utf8.decode(bytes));
    // A blanket-CC0 repo of thousands of WAVs never legitimately yields zero.
    // Empty here means the API answered with something we didn't expect — a
    // rate-limit body, an error payload, or a changed layout — and reporting
    // "no results" would misrepresent that as "the library is empty".
    if (parsed.isEmpty) {
      throw VcslUnavailable(
        'GitHub returned no VCSL sample entries (${bytes.length} bytes) — the '
        'API may be rate-limiting or the repository layout changed',
      );
    }
    _catalog = parsed;
    return parsed;
  }

  @override
  Future<LibraryPage> browsePage({
    String query = '',
    LibraryFilter filter = const LibraryFilter(),
    int limit = 60,
    int offset = 0,
  }) =>
      browsePageByFiltering(
        this,
        query: query,
        filter: filter,
        limit: limit,
        offset: offset,
      );

  @override
  Future<List<LibraryItem>> browse({String query = '', int limit = 60}) async {
    final all = await _loadCatalog();
    final q = query.trim().toLowerCase();
    final matches = q.isEmpty
        ? all
        : all.where(
            (i) =>
                i.title.toLowerCase().contains(q) ||
                i.collection.toLowerCase().contains(q),
          );
    return matches.take(limit).toList();
  }

  @override
  Future<Uint8List> fetch(LibraryItem item) => _http(item.downloadUrl);
}
