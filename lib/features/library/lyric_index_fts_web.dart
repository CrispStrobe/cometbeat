// FTS5 on the web, via sqlite3's WebAssembly build.
//
// Import ONLY through `lyric_index_wiring.dart` — this file pulls in
// `package:sqlite3/wasm.dart` and must not reach a native build.
//
// THREE DECISIONS WORTH KNOWING, because each is a trade rather than an
// obvious best answer:
//
// 1. THE WASM IS FETCHED, NOT BUNDLED. `sqlite3.wasm` is 748 KB. Committing it
//    would put a binary in the repo and add 748 KB to every web build whether or
//    not anyone searches lyrics. Instead it is hosted next to the catalog on the
//    same dataset the app already fetches from, and loaded ONLY when a lyric
//    search actually happens. Browsers cache it after that.
//
// 2. THE INDEX IS IN MEMORY, NOT PERSISTED. `sqlite3/wasm` offers OPFS and
//    IndexedDB virtual file systems, but both add real complexity (OPFS
//    availability varies; the async variant wants a worker) to persist something
//    that is DERIVED. The lyrics shard is already cached in IndexedDB by the
//    catalog layer, so rebuilding the index from it costs a couple of seconds
//    once per session and nothing over the wire.
//
// 3. IT IS STILL OPTIONAL. `package:sqlite3/wasm.dart` documents itself as
//    experimental, so every failure path here returns null and the caller falls
//    back to the linear scan. Web keeps working when this does not.
import 'dart:async';

import 'package:comet_beat/features/library/lyric_index.dart';
import 'package:sqlite3/wasm.dart';

/// Where the WebAssembly build is served from. Same dataset as the catalog, so
/// there is one host to keep alive rather than two.
const kSqliteWasmUrl =
    'https://huggingface.co/datasets/cstr/cometbeat-assets/resolve/main/wasm/sqlite3.wasm';

class Fts5WebLyricIndex implements LyricIndex {
  Fts5WebLyricIndex._(this._db);

  final CommonDatabase _db;

  @override
  String get backend => 'fts5-wasm';

  /// Loads the WASM build and indexes [texts], or returns null so the caller
  /// falls back to the linear scan.
  static Future<LyricIndex?> open(
    Map<String, String> texts, {
    String wasmUrl = kSqliteWasmUrl,
  }) async {
    try {
      final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse(wasmUrl));
      final db = sqlite.openInMemory();
      db.execute('CREATE VIRTUAL TABLE lyrics USING fts5(id UNINDEXED, txt);');
      final stmt = db.prepare('INSERT INTO lyrics(id, txt) VALUES (?, ?);');
      db.execute('BEGIN;');
      try {
        for (final e in texts.entries) {
          stmt.execute([e.key, e.value]);
        }
        db.execute('COMMIT;');
      } catch (_) {
        db.execute('ROLLBACK;');
        rethrow;
      } finally {
        stmt.close();
      }
      return Fts5WebLyricIndex._(db);
    } catch (_) {
      return null;
    }
  }

  /// Same expression builder as the native index: quote every term and
  /// prefix-match the last one. Quoting is not cosmetic — FTS5 reads a bare `-`,
  /// `"` or the word `NOT` as syntax, so an unquoted user query is a syntax
  /// error rather than a search.
  static String? matchExpr(String query) {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'[^\wÀ-ɏ]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return null;
    return [
      for (var i = 0; i < terms.length; i++)
        i == terms.length - 1 ? '"${terms[i]}"*' : '"${terms[i]}"',
    ].join(' AND ');
  }

  @override
  Future<Set<String>> search(String query) async {
    final expr = matchExpr(query);
    if (expr == null) return const {};
    try {
      final rows = _db.select(
        'SELECT id FROM lyrics WHERE lyrics MATCH ? LIMIT 5000;',
        [expr],
      );
      return {for (final r in rows) '${r['id']}'};
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<void> dispose() async {
    try {
      _db.close();
    } catch (_) {/* already gone */}
  }
}
