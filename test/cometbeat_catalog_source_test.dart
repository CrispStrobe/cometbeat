// The curated CometBeat catalog source — reads the tiny index, then only the
// shards for the kinds it wants, maps items to LibraryItems with the right
// download URL (baseUrl + path), searches, and fetches. Fixture-driven: no
// network. Locks the shard-by-kind scaling design + the rights/provenance flow.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:comet_beat/core/audio/tts/tts_asset_cache.dart';
import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/sources/cometbeat_catalog_source.dart';
import 'package:flutter_test/flutter_test.dart';

const _index = '{"version":"t","baseUrl":"https://h/","count":2,"shards":['
    '{"kind":"soundfont","count":1,"url":"catalog/soundfont.json"},'
    '{"kind":"module","count":1,"url":"catalog/module.json"}'
    '],"full":"catalog.json"}';

// An index carrying every kind — used by the all-kinds browser test.
const _indexAll = '{"version":"t","baseUrl":"https://h/","count":4,"shards":['
    '{"kind":"soundfont","count":1,"url":"catalog/soundfont.json"},'
    '{"kind":"module","count":1,"url":"catalog/module.json"},'
    '{"kind":"sample","count":1,"url":"catalog/sample.json"},'
    '{"kind":"score","count":1,"url":"catalog/score.json"}'
    '],"full":"catalog.json"}';

const _sampleShard = '{"version":"t","baseUrl":"https://h/","kind":"sample",'
    '"items":[{"id":"s","name":"Ocean Drum","kind":"sample","format":"wav",'
    '"license":"CC0 1.0","attribution":"Versilian Studios (VCSL)",'
    '"path":"assets/instruments/vcsl/Membranophones/Ocean Drum/x.wav","bytes":9}]}';

const _soundfontShard =
    '{"version":"t","baseUrl":"https://h/","kind":"soundfont",'
    '"items":[{"id":"fluid","name":"FluidR3 GM","kind":"soundfont","format":"sf2",'
    '"license":"MIT License","attribution":"Frank Wen","sourceUrl":"http://src",'
    '"path":"assets/sf2/FluidR3_GM.sf2","bytes":3,"sha256":"z"}]}';

const _moduleShard = '{"version":"t","baseUrl":"https://h/","kind":"module",'
    '"items":[{"id":"m","name":"Chiptune","kind":"module","format":"xm",'
    '"license":"CC0 / Public Domain","path":"assets/mod/chip.xm","bytes":9}]}';
const _scoreShard = '{"version":"t","baseUrl":"https://h/","kind":"score",'
    '"items":[{"id":"sc","name":"Kyrie","kind":"score","format":"gabc",'
    '"license":"CC0 / Public Domain","path":"assets/scores/kyrie.gabc","bytes":9}]}';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

HttpGet _fakeHttp(Map<String, String> byUrl) => (Uri url) async {
      final body = byUrl[url.toString()];
      if (body == null) throw Exception('404 $url');
      return _b(body);
    };

void main() {
  const indexUrl = 'https://h/catalog/index.json';

  test('sounds source reads index → soundfont shard, maps download URL',
      () async {
    final src = CometbeatCatalogSource(
      _fakeHttp({
        indexUrl: _index,
        'https://h/catalog/soundfont.json': _soundfontShard,
      }),
      indexUrl: indexUrl,
    );
    final items = await src.browse();
    expect(items, hasLength(1)); // module shard not fetched for a sounds source
    final sf = items.single;
    expect(sf.title, 'FluidR3 GM');
    expect(sf.format, 'sf2');
    expect(sf.declaredLicense, 'MIT License');
    expect(sf.composer, 'Frank Wen'); // attribution carried
    // download URL = baseUrl + path
    expect(sf.downloadUrl.toString(), 'https://h/assets/sf2/FluidR3_GM.sf2');
  });

  test('fetch downloads the item bytes from its download URL', () async {
    final src = CometbeatCatalogSource(
      _fakeHttp({
        indexUrl: _index,
        'https://h/catalog/soundfont.json': _soundfontShard,
        'https://h/assets/sf2/FluidR3_GM.sf2': 'SF2',
      }),
      indexUrl: indexUrl,
    );
    final item = (await src.browse()).single;
    expect(utf8.decode(await src.fetch(item)), 'SF2');
  });

  test('encodes special characters in asset paths', () async {
    const shard = '{"version":"t","baseUrl":"https://h/",'
        '"items":[{"id":"s","name":"Glass #4",'
        '"kind":"sample","format":"wav",'
        '"license":"CC0","path":"assets/Wine Glasses/glass#4.wav"}]}';
    final src = CometbeatCatalogSource(
      _fakeHttp({
        indexUrl: '{"baseUrl":"https://h/","shards":[{"kind":"sample",'
            '"url":"catalog/sample.json"}]}',
        'https://h/catalog/sample.json': shard,
      }),
      kinds: const {'sample'},
      indexUrl: indexUrl,
    );

    final item = (await src.browse()).single;
    expect(
      item.downloadUrl.toString(),
      'https://h/assets/Wine%20Glasses/glass%234.wav',
    );
  });

  test('an all-kinds source fetches soundfont + module + sample + score shards',
      () async {
    final src = CometbeatCatalogSource(
      _fakeHttp({
        indexUrl: _indexAll,
        'https://h/catalog/soundfont.json': _soundfontShard,
        'https://h/catalog/module.json': _moduleShard,
        'https://h/catalog/sample.json': _sampleShard,
        'https://h/catalog/score.json': _scoreShard,
      }),
      kinds: const {'soundfont', 'instrument', 'sample', 'module', 'score'},
      indexUrl: indexUrl,
    );
    final items = await src.browse(limit: 100);
    final kinds = {for (final i in items) i.collection};
    expect(
      kinds,
      containsAll(<String>['soundfont', 'module', 'sample', 'score']),
    );
    final sample = items.firstWhere((i) => i.collection == 'sample');
    expect(sample.title, 'Ocean Drum');
    expect(sample.format, 'wav'); // decodable → one-tap install
    expect(sample.declaredLicense, 'CC0 1.0');
  });

  test('a scores source fetches ONLY the score shard (not the sound kinds)',
      () async {
    const indexWithScore =
        '{"version":"t","baseUrl":"https://h/","count":2,"shards":['
        '{"kind":"soundfont","count":1,"url":"catalog/soundfont.json"},'
        '{"kind":"score","count":1,"url":"catalog/score.json"}'
        '],"full":"catalog.json"}';
    const scoreShard = '{"version":"t","baseUrl":"https://h/","kind":"score",'
        '"items":[{"id":"g1","name":"Kyrie","kind":"score","format":"gabc",'
        '"license":"CC0 1.0","attribution":"GregoBase",'
        '"path":"gregobase/kyrie.gabc","bytes":42}]}';
    final scored = CometbeatCatalogSource(
      _fakeHttp({
        indexUrl: indexWithScore,
        'https://h/catalog/score.json': scoreShard,
      }),
      kinds: const {'score'}, // what scores() targets
      indexUrl: indexUrl,
    );
    final items = await scored.browse();
    expect(items, hasLength(1)); // the soundfont shard is NOT fetched
    expect(items.single.title, 'Kyrie');
    expect(items.single.format, 'gabc');
  });

  test('a modules source fetches only the module shard', () async {
    final src = CometbeatCatalogSource(
      _fakeHttp({
        indexUrl: _index,
        'https://h/catalog/module.json': _moduleShard,
      }),
      kinds: const {'module'},
      indexUrl: indexUrl,
    );
    final items = await src.browse();
    expect(items, hasLength(1)); // soundfont shard not fetched
    expect(items.single.title, 'Chiptune');
    expect(items.single.declaredLicense, 'CC0 / Public Domain');
  });

  test('search filters by title/attribution', () async {
    final src = CometbeatCatalogSource(
      _fakeHttp({
        indexUrl: _index,
        'https://h/catalog/soundfont.json': _soundfontShard,
      }),
      indexUrl: indexUrl,
    );
    expect(await src.browse(query: 'fluid'), hasLength(1));
    expect(await src.browse(query: 'frank'), hasLength(1)); // attribution
    expect(await src.browse(query: 'nope'), isEmpty);
  });

  test('an unreadable index throws (not a silent empty listing)', () async {
    final src = CometbeatCatalogSource(
      _fakeHttp({indexUrl: 'not json'}),
      indexUrl: indexUrl,
    );
    expect(src.browse, throwsA(isA<CometbeatCatalogUnavailable>()));
  });

  test('kind factories, metadata, exception message, cache clear', () {
    final http = _fakeHttp(const {});
    expect(CometbeatCatalogSource.sounds(http), isA<CometbeatCatalogSource>());
    expect(CometbeatCatalogSource.scores(http), isA<CometbeatCatalogSource>());
    expect(CometbeatCatalogSource.modules(http), isA<CometbeatCatalogSource>());
    expect(CometbeatCatalogSource.all(http), isA<CometbeatCatalogSource>());

    final src = CometbeatCatalogSource(http);
    expect(src.homepage, contains('huggingface.co'));
    expect(src.licenseSummary, isNotEmpty);

    expect(const CometbeatCatalogUnavailable('boom').toString(), 'boom');
    CometbeatCatalogSource.clearSharedCache(); // idempotent, no throw
  });

  group('gzip + cross-launch persistence', _gzMain);
}

// ── gzip + persistence (2026-07-30) ─────────────────────────────────────────
// The score shard was 36.5 MB of raw JSON downloaded on EVERY cold start,
// because the in-process cache does not survive a launch and HF applies no
// content-encoding of its own (measured: identical bytes with and without
// Accept-Encoding). Publisher now emits a `.json.gz` twin advertised as
// `urlGz`; these lock in that we prefer it, inflate it, persist by catalog
// version, and never let a cache fault break browsing.

/// An in-memory [TtsAssetCache] that records what it was asked to do.
class _MemCache implements TtsAssetCache {
  final Map<String, Uint8List> store = {};
  int reads = 0, writes = 0, deletes = 0;

  @override
  Future<bool> has(String key) async => store.containsKey(key);
  @override
  Future<Uint8List?> read(String key) async {
    reads++;
    return store[key];
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    writes++;
    store[key] = bytes;
  }

  @override
  Future<void> delete(String key) async {
    deletes++;
    store.remove(key);
  }

  @override
  Future<List<String>> keys() async => store.keys.toList();
  @override
  Future<int> totalBytes() async =>
      store.values.fold<int>(0, (a, b) => a + b.length);
}

/// A cache whose every operation throws — proves browsing survives it.
class _BrokenCache implements TtsAssetCache {
  @override
  Future<bool> has(String key) async => throw StateError('nope');
  @override
  Future<Uint8List?> read(String key) async => throw StateError('nope');
  @override
  Future<void> write(String key, Uint8List bytes) async =>
      throw StateError('nope');
  @override
  Future<void> delete(String key) async => throw StateError('nope');
  @override
  Future<List<String>> keys() async => throw StateError('nope');
  @override
  Future<int> totalBytes() async => throw StateError('nope');
}

const _indexGz = '{"version":"v1","baseUrl":"https://h/","count":1,"shards":['
    '{"kind":"soundfont","count":1,"url":"catalog/soundfont.json",'
    '"urlGz":"catalog/soundfont.json.gz"}],"full":"catalog.json"}';

void _gzMain() {
  const indexUrl = 'https://h/catalog/index.json';
  final gzBytes =
      Uint8List.fromList(const GZipEncoder().encode(_b(_soundfontShard)));

  HttpGet httpWith(Map<String, Uint8List> raw, List<Uri> log) =>
      (Uri url) async {
        log.add(url);
        final b = raw[url.toString()];
        if (b == null) throw Exception('404 $url');
        return b;
      };

  test('prefers urlGz and inflates it', () async {
    final log = <Uri>[];
    final src = CometbeatCatalogSource(
      httpWith(
        {
          indexUrl: _b(_indexGz),
          'https://h/catalog/soundfont.json.gz': gzBytes,
        },
        log,
      ),
      indexUrl: indexUrl,
      cache: _MemCache(),
    );
    expect((await src.browse()).single.title, 'FluidR3 GM');
    // the plain .json was never requested
    expect(log.map((u) => u.path), isNot(contains('/catalog/soundfont.json')));
  });

  test('second cold start hits the cache — no shard refetch', () async {
    final cache = _MemCache();
    final log = <Uri>[];
    final wire = {
      indexUrl: _b(_indexGz),
      'https://h/catalog/soundfont.json.gz': gzBytes,
    };
    await CometbeatCatalogSource(
      httpWith(wire, log),
      indexUrl: indexUrl,
      cache: cache,
    ).browse();
    expect(cache.writes, 1);
    final afterFirst = log.length;

    // a NEW instance = a new launch; the in-process cache is gone
    await CometbeatCatalogSource(
      httpWith(wire, log),
      indexUrl: indexUrl,
      cache: cache,
    ).browse();
    // only the ~1 KB index was fetched the second time
    expect(log.length - afterFirst, 1);
    expect(log.last.path, endsWith('/catalog/index.json'));
    expect(cache.writes, 1, reason: 'shard was served from cache');
  });

  test('a new catalog version evicts the old shard copy', () async {
    final cache = _MemCache();
    final log = <Uri>[];
    await CometbeatCatalogSource(
      httpWith(
        {
          indexUrl: _b(_indexGz),
          'https://h/catalog/soundfont.json.gz': gzBytes,
        },
        log,
      ),
      indexUrl: indexUrl,
      cache: cache,
    ).browse();
    expect(cache.store.keys.single, 'catalog/soundfont-v1.json.gz');

    await CometbeatCatalogSource(
      httpWith(
        {
          indexUrl: _b(_indexGz.replaceAll('"v1"', '"v2"')),
          'https://h/catalog/soundfont.json.gz': gzBytes,
        },
        log,
      ),
      indexUrl: indexUrl,
      cache: cache,
    ).browse();
    // one copy per shard, not one per publish
    expect(cache.store.keys.single, 'catalog/soundfont-v2.json.gz');
    expect(cache.deletes, 1);
  });

  test('a cache that throws does not break browsing', () async {
    final src = CometbeatCatalogSource(
      httpWith(
        {
          indexUrl: _b(_indexGz),
          'https://h/catalog/soundfont.json.gz': gzBytes,
        },
        <Uri>[],
      ),
      indexUrl: indexUrl,
      cache: _BrokenCache(),
    );
    expect((await src.browse()).single.title, 'FluidR3 GM');
  });

  test('an uncompressed shard still parses when urlGz is absent', () async {
    final src = CometbeatCatalogSource(
      httpWith(
        {
          indexUrl: _b(_index),
          'https://h/catalog/soundfont.json': _b(_soundfontShard),
        },
        <Uri>[],
      ),
      indexUrl: indexUrl,
      cache: _MemCache(),
    );
    expect((await src.browse()).single.title, 'FluidR3 GM');
  });
}
