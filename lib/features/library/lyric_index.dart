// Lyric search over the catalog's `lyrics` shard.
//
// TWO IMPLEMENTATIONS BEHIND ONE SEAM, and the seam is the point.
//
// The linear index is what shipped first: a `Map<id, text>` and a substring
// scan. On 27,650 rows / 13.6 MB that is perfectly usable but it holds the whole
// corpus of text resident (~30–40 MB) and every keystroke walks all of it.
//
// The FTS5 index builds a SQLite full-text table from the SAME already-fetched
// shard — so it costs ZERO extra download — and then answers from an index
// instead of a scan. Building it is a one-off; it is persisted next to the app's
// other data and rebuilt only when the catalog version changes.
//
// ⚠️ SQLite is an ACCELERATOR HERE, NOT A REQUIREMENT. `sqflite` has no web
// support at all, and even the `sqlite3` WASM route depends on an asset plus
// OPFS availability that varies by browser. So every entry point degrades to the
// linear path: a platform where SQLite will not open still searches lyrics, just
// more slowly. Anything that makes a failure to open FATAL is a bug.
import 'dart:async';

/// Matches ids whose sung text contains a query.
abstract class LyricIndex {
  /// Ids whose text matches [query]. Empty for an empty query.
  Future<Set<String>> search(String query);

  /// Frees anything held (a database handle, the resident text).
  Future<void> dispose() async {}

  /// How the search is actually being answered — surfaced so a diagnostic can
  /// tell "SQLite is working" from "we silently fell back", which is otherwise
  /// invisible precisely because the fallback works.
  String get backend;
}

/// Substring scan over resident text. Always available, no dependencies.
class LinearLyricIndex implements LyricIndex {
  LinearLyricIndex(Map<String, String> texts)
      : _texts = {
          for (final e in texts.entries) e.key: e.value.toLowerCase(),
        };

  final Map<String, String> _texts;

  @override
  String get backend => 'linear';

  @override
  Future<Set<String>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const {};
    return {
      for (final e in _texts.entries)
        if (e.value.contains(q)) e.key,
    };
  }

  @override
  Future<void> dispose() async => _texts.clear();
}

/// Builds the best available index for [texts].
///
/// [version] keys the persisted database so a catalog publish invalidates it.
/// [directory] is where a native database may live; null means "no durable
/// storage available", which forces the in-memory path.
typedef LyricIndexBuilder = FutureOr<LyricIndex> Function(
  Map<String, String> texts, {
  required String version,
  String? directory,
});

/// Swapped in tests. Defaults to [defaultLyricIndexBuilder], which the platform
/// wiring sets to the best available implementation; if nothing sets it, the
/// dependency-free linear index is used and the feature still works.
LyricIndexBuilder lyricIndexBuilder = (
  Map<String, String> texts, {
  required String version,
  String? directory,
}) =>
    defaultLyricIndexBuilder(texts, version: version, directory: directory);

/// Set by `lyric_index_wiring.dart` at first use. Kept as a mutable hook rather
/// than a direct import so `lyric_index.dart` stays free of `dart:io` and of the
/// sqlite dependency — the seam is what lets web and native differ without the
/// callers knowing.
LyricIndexBuilder defaultLyricIndexBuilder = (
  Map<String, String> texts, {
  required String version,
  String? directory,
}) =>
    LinearLyricIndex(texts);
