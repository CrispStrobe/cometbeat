// The FTS5 lyric index. Import ONLY through `lyric_index_wiring.dart`, never
// directly — this file touches `dart:io` and must not reach a web build.
//
// It indexes the lyrics shard the app has already downloaded, so it costs no
// extra bytes over the wire: the win is answering from an index instead of
// walking 13.6 MB of text per keystroke, and not holding that text resident.
//
// Persisted next to the app's data and keyed by catalog VERSION, so building is
// a one-off per publish rather than per launch. A stale database for a previous
// version is deleted rather than migrated — it is a derived artefact and the
// source of truth is one gzip fetch away.
import 'dart:async';
import 'dart:io';

import 'package:comet_beat/features/library/lyric_index.dart';
import 'package:sqlite3/sqlite3.dart';

class Fts5LyricIndex implements LyricIndex {
  Fts5LyricIndex._(this._db, this._file);

  final Database _db;
  final File? _file;

  @override
  String get backend => 'fts5';

  /// Opens (or builds) the index for [texts].
  ///
  /// Returns null when SQLite cannot be used at all, so the caller falls back to
  /// the linear scan. Everything here is best-effort by design: an accelerator
  /// that takes the feature down when it fails is worse than no accelerator.
  static Future<LyricIndex?> open(
    Map<String, String> texts, {
    required String version,
    String? directory,
  }) async {
    try {
      File? file;
      Database db;
      if (directory != null) {
        final dir = Directory(directory);
        if (!dir.existsSync()) dir.createSync(recursive: true);
        // Version in the FILENAME, so a publish invalidates by construction
        // rather than by remembering to check a stored value.
        for (final f in dir.listSync()) {
          if (f is File &&
              f.path.contains('lyrics-fts-') &&
              !f.path.endsWith('lyrics-fts-$version.db')) {
            try {
              f.deleteSync();
            } catch (_) {/* a stale file we cannot remove is harmless */}
          }
        }
        file = File('${dir.path}/lyrics-fts-$version.db');
        final fresh = !file.existsSync();
        db = sqlite3.open(file.path);
        if (fresh) {
          _build(db, texts);
        } else if (!_usable(db)) {
          // An existing file could be a truncated half-write from a killed
          // process; a cheap probe beats trusting its presence.
          db.close();
          file.deleteSync();
          db = sqlite3.open(file.path);
          _build(db, texts);
        }
      } else {
        db = sqlite3.openInMemory();
        _build(db, texts);
      }
      return Fts5LyricIndex._(db, file);
    } catch (_) {
      return null; // caller falls back to the linear index
    }
  }

  static bool _usable(Database db) {
    try {
      return db.select('SELECT count(*) AS n FROM lyrics;').first['n'] as int >
          0;
    } catch (_) {
      return false;
    }
  }

  static void _build(Database db, Map<String, String> texts) {
    db.execute('DROP TABLE IF EXISTS lyrics;');
    // `id UNINDEXED` keeps the id out of the term index — matching an id as if
    // it were a word would return nonsense hits.
    db.execute('CREATE VIRTUAL TABLE lyrics USING fts5(id UNINDEXED, txt);');
    final stmt = db.prepare('INSERT INTO lyrics(id, txt) VALUES (?, ?);');
    // One transaction: 27k individual commits would take orders of magnitude
    // longer than the whole build should.
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
  }

  /// Turns a user's words into an FTS5 MATCH expression.
  ///
  /// Everything is quoted and the last term gets a `*`, which gives
  /// prefix-matching as you type ("chin" finds "chinesen"). Quoting matters:
  /// FTS5 treats bare `-`, `"`, `(`, `*` and the words AND/OR/NOT as syntax, so
  /// an unquoted query like `rock-a-bye` or `not` is a syntax ERROR rather than
  /// a search — a user typing an apostrophe should never see a crash.
  static String? _matchExpr(String query) {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'[^\wÀ-ɏ]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return null;
    final quoted = [
      for (var i = 0; i < terms.length; i++)
        i == terms.length - 1 ? '"${terms[i]}"*' : '"${terms[i]}"',
    ];
    return quoted.join(' AND ');
  }

  @override
  Future<Set<String>> search(String query) async {
    final expr = _matchExpr(query);
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

  /// The backing file, for tests and diagnostics.
  File? get file => _file;
}
