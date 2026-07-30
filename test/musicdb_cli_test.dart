// bin/musicdb.dart — the corpus query CLI.
//
// Spawns the real CLI (the established pattern for this repo's CLIs) over
// fixtures on disk, so the two artefact SHAPES are exercised for real. That
// distinction is the whole point of the tool: `db.json` and a catalog shard use
// different field names for the same facts (`title`/`name`,
// `licence`/`license`, `rights_status`/`tier`) and differ by ~7,500
// deliberately-held rows, so reading one while believing you read the other
// misreports what users can actually see.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// db.json shape: a bare LIST, en-GB `licence`, has `source`.
const _dbJson = '''
[
 {"id":"a1","title":"Kyrie","source":"CPDL","format":"mxl","kind":"score",
  "licence":"CC0 1.0","rights_status":"CC0","path":"cpdl/a.mxl","author":"Byrd"},
 {"id":"a2","title":"Gloria","source":"GregoBase","format":"gabc","kind":"score",
  "licence":"CC0 1.0","rights_status":"CC0","path":"greg/b.gabc"},
 {"id":"a3","title":"Held Song","source":"OpenEWLD","format":"mxl","kind":"score",
  "licence":"Public Domain","rights_status":"PD","path":"ew/c.mxl"},
 {"id":"i1","title":"FluidR3","source":"FluidR3","format":"sf2",
  "kind":"soundfont","licence":"MIT","path":"sf2/f.sf2"}
]
''';

/// catalog shard shape: a MAP with `items`, en-US `license`, `name`, `tier`,
/// and no `source` at all.
const _shard = '''
{"version":"2026-07-30","baseUrl":"https://h/","kind":"score","count":2,
 "items":[
  {"id":"a1","name":"Kyrie","format":"mxl","kind":"score","license":"CC0 1.0",
   "tier":"A","path":"cpdl/xx/a.mxl","attribution":"Byrd"},
  {"id":"a2","name":"Gloria","format":"gabc","kind":"score","license":"CC0 1.0",
   "tier":"A","path":"greg/yy/b.gabc"}
 ]}
''';

void main() {
  late Directory dir;
  late String db;
  late String shard;
  late String shardGz;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('musicdb');
    db = '${dir.path}/db.json';
    shard = '${dir.path}/score.json';
    shardGz = '${dir.path}/score.json.gz';
    File(db).writeAsStringSync(_dbJson);
    File(shard).writeAsStringSync(_shard);
    // the published shards are gzipped — the CLI must read them as-is
    File(shardGz).writeAsBytesSync(gzip.encode(utf8.encode(_shard)));
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  Future<ProcessResult> run(List<String> args) =>
      Process.run('dart', ['run', 'bin/musicdb.dart', ...args]);

  test('stats over db.json tallies kind/format/source', () async {
    final r = await run(['stats', '--db', db]);
    expect(r.exitCode, 0);
    final out = r.stdout as String;
    expect(out, contains('rows:   4'));
    expect(out, contains('master registry')); // says WHICH artefact it read
    expect(out, contains('score'));
    expect(out, contains('soundfont'));
    expect(out, contains('CPDL'));
  });

  test('stats over a catalog shard says SHIPPED and reads the version',
      () async {
    final r = await run(['stats', '--db', shard]);
    expect(r.exitCode, 0);
    final out = r.stdout as String;
    expect(out, contains('rows:   2'));
    expect(out, contains('SHIPPED'));
    expect(out, contains('2026-07-30'));
  });

  test('reads a gzipped shard identically to the plain one', () async {
    final a = await run(['stats', '--db', shard]);
    final b = await run(['stats', '--db', shardGz]);
    expect(b.exitCode, 0);
    expect(b.stdout, a.stdout);
  });

  test('filters combine, and are case-insensitive substrings', () async {
    final r = await run(['query', '--db', db, '--format', 'MXL', '--count']);
    expect((r.stdout as String).trim(), '2');

    final s = await run([
      'query',
      '--db',
      db,
      '--format',
      'mxl',
      '--source',
      'cpdl',
      '--count'
    ]);
    expect((s.stdout as String).trim(), '1');
  });

  test('--title and --text search different fields', () async {
    // --title matches the title only
    final t = await run(['query', '--db', db, '--title', 'kyrie', '--count']);
    expect((t.stdout as String).trim(), '1');
    // --text also reaches attribution/path/source, so an author name hits
    final x = await run(['query', '--db', db, '--text', 'byrd', '--count']);
    expect((x.stdout as String).trim(), '1');
    // ...and a title search for an author name does NOT
    final n = await run(['query', '--db', db, '--title', 'byrd', '--count']);
    expect((n.stdout as String).trim(), '0');
  });

  test('the en-GB/en-US licence split is normalised across both shapes',
      () async {
    final a = await run(['query', '--db', db, '--licence', 'CC0', '--count']);
    final b =
        await run(['query', '--db', shard, '--licence', 'CC0', '--count']);
    expect((a.stdout as String).trim(), '2');
    expect((b.stdout as String).trim(), '2');
  });

  test('--json emits the raw rows, --limit caps them', () async {
    final r = await run(['query', '--db', db, '--json', '--limit', '2']);
    final rows = jsonDecode(r.stdout as String) as List;
    expect(rows, hasLength(2));
    expect(rows.first, containsPair('id', 'a1'));
  });

  test('show prints one row and distinguishes a miss', () async {
    final hit = await run(['show', '--db', db, 'a2']);
    expect(hit.exitCode, 0);
    expect(jsonDecode(hit.stdout as String), containsPair('title', 'Gloria'));

    // a3 is in db.json but NOT in the shard — the exact "is it held?" question
    final inDb = await run(['show', '--db', db, 'a3']);
    expect(inDb.exitCode, 0);
    final inShard = await run(['show', '--db', shard, 'a3']);
    expect(inShard.exitCode, 1);
    expect(inShard.stderr as String, contains('SHIPPED'));
  });

  test('missing --db and unknown commands fail loudly, not silently', () async {
    expect((await run(['stats'])).exitCode, 2);
    expect((await run(['bogus', '--db', db])).exitCode, 2);
    expect((await run(['stats', '--db', '${dir.path}/nope.json'])).exitCode, 2);
    expect((await run([])).exitCode, 1); // bare invocation prints usage
  });
}
