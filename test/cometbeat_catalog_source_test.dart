// The curated CometBeat catalog source — reads the tiny index, then only the
// shards for the kinds it wants, maps items to LibraryItems with the right
// download URL (baseUrl + path), searches, and fetches. Fixture-driven: no
// network. Locks the shard-by-kind scaling design + the rights/provenance flow.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/sources/cometbeat_catalog_source.dart';
import 'package:flutter_test/flutter_test.dart';

const _index = '{"version":"t","baseUrl":"https://h/","count":2,"shards":['
    '{"kind":"soundfont","count":1,"url":"catalog/soundfont.json"},'
    '{"kind":"module","count":1,"url":"catalog/module.json"}'
    '],"full":"catalog.json"}';

// An index carrying every kind — used by the all-kinds browser test.
const _indexAll = '{"version":"t","baseUrl":"https://h/","count":3,"shards":['
    '{"kind":"soundfont","count":1,"url":"catalog/soundfont.json"},'
    '{"kind":"module","count":1,"url":"catalog/module.json"},'
    '{"kind":"sample","count":1,"url":"catalog/sample.json"}'
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

  test('an all-kinds source fetches soundfont + module + sample shards',
      () async {
    final src = CometbeatCatalogSource(
      _fakeHttp({
        indexUrl: _indexAll,
        'https://h/catalog/soundfont.json': _soundfontShard,
        'https://h/catalog/module.json': _moduleShard,
        'https://h/catalog/sample.json': _sampleShard,
      }),
      kinds: const {'soundfont', 'instrument', 'sample', 'module'},
      indexUrl: indexUrl,
    );
    final items = await src.browse(limit: 100);
    final kinds = {for (final i in items) i.collection};
    expect(kinds, containsAll(<String>['soundfont', 'module', 'sample']));
    final sample = items.firstWhere((i) => i.collection == 'sample');
    expect(sample.title, 'Ocean Drum');
    expect(sample.format, 'wav'); // decodable → one-tap install
    expect(sample.declaredLicense, 'CC0 1.0');
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
}
