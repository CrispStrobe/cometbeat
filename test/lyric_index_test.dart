// Lyric search: FTS5 where available, linear scan otherwise.
//
// The contract that matters is AGREEMENT. SQLite is an accelerator here, so if
// the two backends answer differently the user's results change depending on
// which platform they are on — which is worse than being slow. These tests hold
// them to the same answers on the same data, and hold the fallback to actually
// being a fallback.
import 'dart:io';

import 'package:comet_beat/features/library/lyric_index.dart';
import 'package:comet_beat/features/library/lyric_index_fts.dart';
import 'package:flutter_test/flutter_test.dart';

const _texts = {
  'a': 'Drei Chinesen mit dem Kontrabass saßen auf der Straße',
  'b': "Stille Nacht, heilige Nacht, alles schläft, einsam wacht",
  'c': 'Winter, ade! Scheiden thut weh. Aber dein Scheiden macht',
  'd': 'Alleluia. Laudem Domini loquetur os meum',
  'e': "Rock-a-bye baby, on the tree top",
};

void main() {
  late Directory dir;

  setUpAll(() => dir = Directory.systemTemp.createTempSync('lyricidx'));
  tearDownAll(() => dir.deleteSync(recursive: true));

  Future<LyricIndex> fts({String? at, String version = 'v1'}) async {
    final i =
        await Fts5LyricIndex.open(_texts, version: version, directory: at);
    expect(i, isNotNull, reason: 'sqlite3 should be available on the test VM');
    return i!;
  }

  test('FTS5 finds a word in the middle of a lyric', () async {
    final i = await fts();
    expect(await i.search('kontrabass'), {'a'});
    expect(await i.search('einsam'), {'b'});
    await i.dispose();
  });

  test('prefix-matches the last term, so it works as you type', () async {
    final i = await fts();
    expect(await i.search('kontra'), {'a'});
    expect(await i.search('chin'), {'a'});
    await i.dispose();
  });

  test('multiple terms are ANDed', () async {
    final i = await fts();
    expect(await i.search('stille nacht'), {'b'});
    // both words exist, but not in the same row
    expect(await i.search('kontrabass alleluia'), isEmpty);
    await i.dispose();
  });

  test('punctuation in a query is a search, not a syntax error', () async {
    // FTS5 reads bare `-`, `"`, `(` and NOT/AND/OR as SYNTAX. Unquoted, each of
    // these raises instead of searching — a user typing an apostrophe must never
    // see a crash.
    final i = await fts();
    expect(await i.search('rock-a-bye'), {'e'});
    expect(await i.search('"'), isEmpty);
    expect(await i.search('NOT'), isEmpty);
    expect(await i.search('ade!'), {'c'});
    await i.dispose();
  });

  test('agrees with the linear scan on the same data', () async {
    final a = await fts();
    final b = LinearLyricIndex(_texts);
    for (final q in ['kontrabass', 'nacht', 'scheiden', 'domini', 'zzz']) {
      expect(await a.search(q), await b.search(q), reason: 'query "$q"');
    }
    await a.dispose();
  });

  test('persists to disk and reuses the file for the same version', () async {
    final one =
        await Fts5LyricIndex.open(_texts, version: 'v9', directory: dir.path)
            as Fts5LyricIndex;
    final path = one.file!.path;
    expect(File(path).existsSync(), isTrue);
    final built = File(path).lengthSync();
    await one.dispose();

    final two = await fts(at: dir.path, version: 'v9');
    expect(await two.search('kontrabass'), {'a'});
    expect(File(path).lengthSync(), built, reason: 'reused, not rebuilt');
    await two.dispose();
  });

  test('a new catalog version drops the old index file', () async {
    final old =
        await Fts5LyricIndex.open(_texts, version: 'old', directory: dir.path)
            as Fts5LyricIndex;
    final oldPath = old.file!.path;
    await old.dispose();
    expect(File(oldPath).existsSync(), isTrue);

    final fresh = await fts(at: dir.path, version: 'new');
    expect(File(oldPath).existsSync(), isFalse,
        reason: 'a derived index for a stale catalog is deleted, not migrated');
    await fresh.dispose();
  });

  test('a truncated database is rebuilt rather than trusted', () async {
    final d = Directory('${dir.path}/trunc')..createSync();
    final f = File('${d.path}/lyrics-fts-t.db')
      ..writeAsBytesSync([1, 2, 3]); // not a database at all
    final i =
        await Fts5LyricIndex.open(_texts, version: 't', directory: d.path);
    expect(i, isNotNull, reason: 'must recover, not fail');
    expect(await i!.search('kontrabass'), {'a'});
    expect(f.lengthSync(), greaterThan(3));
    await i.dispose();
  });

  test('an unusable directory falls back instead of throwing', () async {
    // A path that cannot be created — the accelerator must degrade quietly.
    final i = await Fts5LyricIndex.open(_texts,
        version: 'v1', directory: '/dev/null/nope');
    // Either it returned null (caller uses the linear index) or it recovered
    // in memory. What it must NOT do is throw.
    if (i != null) {
      expect(await i.search('kontrabass'), {'a'});
      await i.dispose();
    }
  });

  test('backend is reported, so a silent fallback is visible', () async {
    final i = await fts();
    expect(i.backend, 'fts5');
    expect(LinearLyricIndex(_texts).backend, 'linear');
    await i.dispose();
  });
}
