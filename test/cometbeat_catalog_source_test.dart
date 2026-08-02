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

/// Byte-map HTTP stub that records what was requested — the recording is the
/// point for the laziness tests.
HttpGet httpWith(Map<String, Uint8List> raw, List<Uri> log) => (Uri url) async {
      log.add(url);
      final b = raw[url.toString()];
      if (b == null) throw Exception('404 $url');
      return b;
    };

HttpGet _fakeHttp(Map<String, String> byUrl) => (Uri url) async {
      final body = byUrl[url.toString()];
      if (body == null) throw Exception('404 $url');
      return _b(body);
    };

void main() {
  const indexUrl = 'https://h/catalog/index.json';

  group('payload cache', () {
    Future<CometbeatCatalogSource> srcWith(
      _MemCache cache,
      List<Uri> log, {
      String payload = 'SF2',
    }) async {
      return CometbeatCatalogSource(
        (Uri url) async {
          log.add(url);
          final body = {
            indexUrl: _index,
            'https://h/catalog/soundfont.json': _soundfontShard,
            'https://h/assets/sf2/FluidR3_GM.sf2': payload,
          }[url.toString()];
          if (body == null) throw Exception('404 $url');
          return _b(body);
        },
        indexUrl: indexUrl,
        cache: cache,
      );
    }

    test('a fetched payload is served from cache next time', () async {
      final cache = _MemCache();
      final log = <Uri>[];
      final a = await srcWith(cache, log);
      final item = (await a.browse()).single;
      expect(await a.fetch(item), _b('SF2'));
      final afterFirst = log.length;

      // A new instance = a new launch.
      final b = await srcWith(cache, log);
      final item2 = (await b.browse()).single;
      final before = log.length;
      expect(await b.fetch(item2), _b('SF2'));
      expect(log.length, before, reason: 'payload came from cache');
      expect(afterFirst, greaterThan(0));
    });

    test('the payload is available with the network GONE', () async {
      final cache = _MemCache();
      final log = <Uri>[];
      final online = await srcWith(cache, log);
      final item = (await online.browse()).single;
      await online.fetch(item);

      final offline = CometbeatCatalogSource(
        (Uri url) async => throw Exception('offline'),
        indexUrl: indexUrl,
        cache: cache,
      );
      final offlineItem = (await offline.browse()).single;
      expect(await offline.fetch(offlineItem), _b('SF2'));
    });

    test('a payload over the cap is NOT cached', () async {
      // ⚠️ The single most important behaviour here: this method serves both a
      // 20 KB score and a 140 MB SoundFont. Caching by default is right for the
      // first and ruinous for the second — someone auditioning instruments
      // would fill their disk without ever asking for an offline library.
      final cache = _MemCache();
      final log = <Uri>[];
      final big = 'x' * (CometbeatCatalogSource.kMaxCachedPayloadBytes + 1);
      final src = await srcWith(cache, log, payload: big);
      final item = (await src.browse()).single;
      await src.fetch(item);
      expect(
        cache.store.keys.where((k) => k.startsWith('payload/')),
        isEmpty,
      );
    });

    test('a different URL is a different entry, even for the same id',
        () async {
      // Keyed by download URL, not item id: a republish can repoint a stable id
      // at different bytes, and serving the old file would be a silent
      // wrong-content bug rather than a miss.
      final cache = _MemCache();
      final log = <Uri>[];
      final first = await srcWith(cache, log);
      await first.fetch((await first.browse()).single);
      final keysAfterFirst =
          cache.store.keys.where((k) => k.startsWith('payload/')).toSet();
      expect(keysAfterFirst, hasLength(1));

      final moved = _soundfontShard.replaceAll(
        'sf2/FluidR3_GM.sf2',
        'sf2/FluidR3_GM_v2.sf2',
      );
      final second = CometbeatCatalogSource(
        (Uri url) async {
          final body = {
            indexUrl: _index.replaceAll('"version":"t"', '"version":"t2"'),
            'https://h/catalog/soundfont.json': moved,
            'https://h/assets/sf2/FluidR3_GM_v2.sf2': 'NEW',
          }[url.toString()];
          if (body == null) throw Exception('404 $url');
          return _b(body);
        },
        indexUrl: indexUrl,
        cache: cache,
      );
      expect(await second.fetch((await second.browse()).single), _b('NEW'));
    });

    test('a broken cache still fetches', () async {
      final src = CometbeatCatalogSource(
        _fakeHttp({
          indexUrl: _index,
          'https://h/catalog/soundfont.json': _soundfontShard,
          'https://h/assets/sf2/FluidR3_GM.sf2': 'SF2',
        }),
        indexUrl: indexUrl,
        cache: _BrokenCache(),
      );
      expect(await src.fetch((await src.browse()).single), _b('SF2'));
    });
  });

  group('offline start', () {
    // ⚠️ The shard cache had been on disk for a while and was UNREACHABLE
    // offline, because `_load` fetched the index first with no recovery. One
    // failed request made every cached shard useless — a cache that only
    // worked when it was not needed.

    test('a second start works with the network gone', () async {
      final cache = _MemCache();
      final urls = {
        indexUrl: _index,
        'https://h/catalog/soundfont.json': _soundfontShard,
      };
      // First run: online, fills the cache.
      final online = CometbeatCatalogSource(
        _fakeHttp(urls),
        indexUrl: indexUrl,
        cache: cache,
      );
      expect(await online.browse(), hasLength(1));

      // Second run: the network is gone entirely.
      final offline = CometbeatCatalogSource(
        (Uri url) async => throw Exception('offline'),
        indexUrl: indexUrl,
        cache: cache,
      );
      final items = await offline.browse();
      expect(items, hasLength(1));
      expect(items.single.title, 'FluidR3 GM');
    });

    test('the network is still tried FIRST, so updates are picked up',
        () async {
      // The fallback must not become a stale-forever cache: a reachable
      // catalog is always authoritative.
      final cache = _MemCache();
      await CometbeatCatalogSource(
        _fakeHttp({
          indexUrl: _index,
          'https://h/catalog/soundfont.json': _soundfontShard,
        }),
        indexUrl: indexUrl,
        cache: cache,
      ).browse();

      final renamed = _soundfontShard.replaceAll('FluidR3 GM', 'Renamed GM');
      final fresh = CometbeatCatalogSource(
        _fakeHttp({
          // A NEW version, so the cached shard is not reused either.
          indexUrl: _index.replaceAll('"version":"t"', '"version":"t2"'),
          'https://h/catalog/soundfont.json': renamed,
        }),
        indexUrl: indexUrl,
        cache: cache,
      );
      expect((await fresh.browse()).single.title, 'Renamed GM');
    });

    test('with nothing cached it reports the NETWORK failure', () async {
      // A cache miss is not something the user can act on; "we could not reach
      // the catalog" is.
      final src = CometbeatCatalogSource(
        (Uri url) async => throw Exception('offline'),
        indexUrl: indexUrl,
        cache: _MemCache(),
      );
      await expectLater(src.browse(), throwsA(isA<Exception>()));
    });

    test('a broken cache still browses online', () async {
      final src = CometbeatCatalogSource(
        _fakeHttp({
          indexUrl: _index,
          'https://h/catalog/soundfont.json': _soundfontShard,
        }),
        indexUrl: indexUrl,
        cache: _BrokenCache(),
      );
      expect(await src.browse(), hasLength(1));
    });
  });

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
  group('filters + pagination', _pageMain);
}

// ── gzip + persistence (2026-07-30) ─────────────────────────────────────────
// The score shard was 36.5 MB of raw JSON downloaded on EVERY cold start,
// because the in-process cache does not survive a launch and HF applies no
// content-encoding of its own (measured: identical bytes with and without
// Accept-Encoding). Publisher now emits a `.json.gz` twin advertised as
// `urlGz`; these lock in that we prefer it, inflate it, persist by catalog
// version, and never let a cache fault break browsing.

/// The SHARD keys in a cache, ignoring the index copy.
///
/// The index is cached too (so a later start works offline), so a bare
/// `store.keys` no longer isolates shard behaviour.
List<String> _shardKeys(_MemCache c) =>
    c.store.keys.where((k) => k != 'catalog/index.json').toList();

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
    // ⚠️ Two writes now, not one: the index is cached too, so a later start
    // can proceed offline. What this test is ABOUT is the shard, so assert
    // that directly rather than a total that conflates the two.
    expect(_shardKeys(cache), hasLength(1));
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
    expect(
      _shardKeys(cache),
      hasLength(1),
      reason: 'shard was served from cache, not written again',
    );
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
    expect(_shardKeys(cache).single, 'catalog/soundfont-v1.json.gz');

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
    expect(_shardKeys(cache).single, 'catalog/soundfont-v2.json.gz');
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

// ── filters + pagination (2026-07-30) ───────────────────────────────────────
// browse() was a substring match over title+composer with a hard limit of 60 and
// no paging, so a query matching thousands looked like a query matching sixty.
// browsePage adds facet filters, an EXACT total where the source can count, and
// "is there more" — the last of which is knowable even when a total is not.

const _bigShard = '{"version":"t","baseUrl":"https://h/","kind":"score",'
    '"items":[';

String _mkShard(int n) {
  final b = StringBuffer(_bigShard);
  for (var i = 0; i < n; i++) {
    if (i > 0) b.write(',');
    b.write('{"id":"s$i","name":"Song $i","kind":"score",'
        '"format":"${i.isEven ? 'mxl' : 'abc'}",'
        '"license":"${i % 3 == 0 ? 'CC0 1.0' : 'CC BY 4.0'}",'
        '"path":"p/$i.x"}');
  }
  b.write(']}');
  return b.toString();
}

void _pageMain() {
  const indexUrl = 'https://h/catalog/index.json';
  const idx = '{"version":"t","baseUrl":"https://h/","count":150,"shards":['
      '{"kind":"score","count":150,"url":"catalog/score.json"}'
      '],"full":"catalog.json"}';

  final wire = {indexUrl: idx, 'https://h/catalog/score.json': _mkShard(150)};
  CometbeatCatalogSource make() => CometbeatCatalogSource(
        _fakeHttp(wire),
        kinds: const {'score'},
        indexUrl: indexUrl,
        cache: _MemCache(),
      );

  test('reports an EXACT total and pages through it', () async {
    final src = make();
    final p1 = await src.browsePage();
    expect(p1.items, hasLength(60));
    // this source holds everything, so it can count exactly
    expect(p1.total, 150);
    expect(p1.hasMore, isTrue);

    final p3 = await src.browsePage(offset: 120);
    expect(p3.items, hasLength(30));
    expect(p3.hasMore, isFalse, reason: 'last page');
  });

  test('a format filter narrows the total, not just the page', () async {
    final page = await make().browsePage(
      filter: const LibraryFilter(formats: {'abc'}),
      limit: 10,
    );
    expect(page.total, 75); // the odd-indexed half
    expect(page.items.every((i) => i.format == 'abc'), isTrue);
  });

  test('a licence filter matches by substring, not exact string', () async {
    // real licence strings are prose: "CC0 1.0", "CC BY 4.0"
    final page = await make().browsePage(
      filter: const LibraryFilter(licences: {'cc0'}),
      limit: 5,
    );
    expect(page.total, 50); // every third
    expect(page.items.every((i) => i.declaredLicense.contains('CC0')), isTrue);
  });

  test('filters compose with the text query', () async {
    final page = await make().browsePage(
      query: 'Song 1',
      filter: const LibraryFilter(formats: {'mxl'}),
      limit: 100,
    );
    // "Song 1", "Song 1x", "Song 1xx" … all contain the query; only even ones
    // are mxl, and the intersection must be non-empty and consistent.
    expect(page.total, greaterThan(0));
    expect(
      page.items.every((i) => i.title.contains('Song 1') && i.format == 'mxl'),
      isTrue,
    );
  });

  test('facets offer only values that are present', () async {
    final f = await make().facets();
    expect(f['format'], containsAll(<String>['mxl', 'abc']));
    expect(f['kind'], contains('score'));
  });

  test('the source facet uses the CORPUS source, not the connector name',
      () async {
    // sourceName is "CometBeat Library" for every row, so filtering on it
    // narrows nothing; provenance has to come from the catalog's `source`.
    const idx2 = '{"version":"t","baseUrl":"https://h/","count":2,"shards":['
        '{"kind":"score","count":2,"url":"catalog/score.json"}]}';
    const shard2 = '{"version":"t","baseUrl":"https://h/","kind":"score",'
        '"items":['
        '{"id":"g","name":"Kyrie","kind":"score","format":"gabc",'
        '"license":"CC0 1.0","source":"GregoBase","path":"a.gabc"},'
        '{"id":"c","name":"Motet","kind":"score","format":"mxl",'
        '"license":"CC0 1.0","source":"CPDL","path":"b.mxl"}]}';
    final src = CometbeatCatalogSource(
      _fakeHttp({indexUrl: idx2, 'https://h/catalog/score.json': shard2}),
      kinds: const {'score'},
      indexUrl: indexUrl,
      cache: _MemCache(),
    );
    final facets = await src.facets();
    expect(facets['source'], containsAll(<String>['GregoBase', 'CPDL']));
    final only = await src.browsePage(
      filter: const LibraryFilter(sources: {'CPDL'}),
    );
    expect(only.total, 1);
    expect(only.items.single.title, 'Motet');
  });

  test('lyric search is lazy: the shard is fetched only when asked for',
      () async {
    const idx = '{"version":"t","baseUrl":"https://h/","count":2,"shards":['
        '{"kind":"score","count":2,"url":"catalog/score.json"},'
        '{"kind":"lyrics","count":1,"url":"catalog/lyrics.json"}]}';
    const shard = '{"version":"t","baseUrl":"https://h/","kind":"score",'
        '"items":['
        '{"id":"a","name":"Opus 1","kind":"score","format":"mxl",'
        '"license":"CC0 1.0","path":"a.mxl"},'
        '{"id":"b","name":"Opus 2","kind":"score","format":"mxl",'
        '"license":"CC0 1.0","path":"b.mxl"}]}';
    const lyrics = '{"version":"t","kind":"lyrics","count":1,'
        '"items":{"b":"drei chinesen mit dem kontrabass"}}';
    final log = <Uri>[];
    final src = CometbeatCatalogSource(
      httpWith(
        {
          indexUrl: _b(idx),
          'https://h/catalog/score.json': _b(shard),
          'https://h/catalog/lyrics.json': _b(lyrics),
        },
        log,
      ),
      kinds: const {'score'},
      indexUrl: indexUrl,
      cache: _MemCache(),
    );

    // a plain search never touches the lyrics shard...
    final plain = await src.browsePage(query: 'chinesen');
    expect(plain.total, 0, reason: 'no title contains it');
    expect(
      log.map((u) => u.path).where((p) => p.contains('lyrics')),
      isEmpty,
      reason: 'lyrics cost 3.6 MB — never fetch them unasked',
    );

    // ...and opting in finds the row by its words
    final sung = await src.browsePage(
      query: 'chinesen',
      filter: const LibraryFilter(searchLyrics: true),
    );
    expect(sung.total, 1);
    expect(sung.items.single.title, 'Opus 2');
    expect(
      log.map((u) => u.path).where((p) => p.contains('lyrics')),
      hasLength(1),
    );
  });

  test('the inline incipit answers the common case without the shard',
      () async {
    const idx = '{"version":"t","baseUrl":"https://h/","count":1,"shards":['
        '{"kind":"score","count":1,"url":"catalog/score.json"}]}';
    const shard = '{"version":"t","baseUrl":"https://h/","kind":"score",'
        '"items":[{"id":"a","name":"Untitled","kind":"score","format":"mxl",'
        '"license":"CC0 1.0","path":"a.mxl",'
        '"textIncipit":"Winter, ade! Scheiden thut weh…"}]}';
    final src = CometbeatCatalogSource(
      httpWith(
        {
          indexUrl: _b(idx),
          'https://h/catalog/score.json': _b(shard),
        },
        <Uri>[],
      ),
      kinds: const {'score'},
      indexUrl: indexUrl,
      cache: _MemCache(),
    );
    final page = await src.browsePage(query: 'scheiden');
    expect(page.total, 1, reason: 'matched on the incipit, no shard needed');
  });

  test('a source that cannot count leaves total null but still pages',
      () async {
    // The default browsePage over a plain browse(): no total, but hasMore works.
    final src = _CountlessSource(150);
    final p1 = await src.browsePage();
    expect(p1.items, hasLength(60));
    expect(p1.total, isNull, reason: 'never invent a total');
    expect(p1.hasMore, isTrue);
    final p3 = await src.browsePage(offset: 120);
    expect(p3.items, hasLength(30));
    expect(p3.hasMore, isFalse);
  });
}

/// A source with no idea how many rows it has — exercises the shared default.
class _CountlessSource implements ContentSource {
  _CountlessSource(this.n);
  final int n;

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
  Future<List<LibraryItem>> browse({String query = '', int limit = 60}) async =>
      [
        for (var i = 0; i < n && i < limit; i++)
          LibraryItem(
            sourceId: 'x',
            sourceName: 'X',
            id: '$i',
            title: 'T$i',
            composer: '',
            declaredLicense: 'CC0',
            downloadUrl: Uri.parse('https://h/$i'),
            format: 'abc',
          ),
      ];

  @override
  Future<Uint8List> fetch(LibraryItem item) async => Uint8List(0);
  @override
  String get id => 'x';
  @override
  String get name => 'X';
  @override
  String get homepage => 'https://h';
  @override
  String get licenseSummary => 'CC0';
}
