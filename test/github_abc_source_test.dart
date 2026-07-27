// github_abc_source.dart — a GitHub-mirrored ABC tune source. The tree-JSON
// parse and path→item mapping are pure; browse/fetch take an injectable
// HttpGet, so the whole source is testable with a fake HTTP layer (no network).
import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/sources/github_abc_source.dart';
import 'package:flutter_test/flutter_test.dart';

const _treeJson = '''
{"tree":[
  {"path":"tunes/Reel_One.abc"},
  {"path":"README.md"},
  {"path":"tunes/aaa_First.ABC"},
  {"path":"tunes/sub/Jig_Two.abc"},
  {"path":"cover.png"}
]}''';

GithubAbcSource _source(HttpGet http) => GithubAbcSource(
      http,
      id: 'test_abc',
      name: 'Test Tunes',
      repo: 'Owner/Repo',
      declaredLicense: 'CC0 1.0',
      licenseUrl: 'https://example.org/cc0',
      branch: 'main',
    );

void main() {
  group('parseTreePaths', () {
    test('keeps only .abc paths (case-insensitive), sorted', () {
      expect(GithubAbcSource.parseTreePaths(_treeJson), [
        'tunes/Reel_One.abc',
        'tunes/aaa_First.ABC',
        'tunes/sub/Jig_Two.abc',
      ]);
    });

    test('a missing or empty tree yields no paths', () {
      expect(GithubAbcSource.parseTreePaths('{}'), isEmpty);
      expect(GithubAbcSource.parseTreePaths('{"tree":[]}'), isEmpty);
    });
  });

  group('itemForPath', () {
    test('maps a path to a titled, correctly-linked library item', () {
      final item =
          _source((_) async => Uint8List(0)).itemForPath('tunes/Reel_One.abc')!;
      expect(item.title, 'Reel One'); // stem, underscores → spaces
      expect(item.format, 'abc');
      expect(item.sourceId, 'test_abc');
      expect(item.declaredLicense, 'CC0 1.0');
      // raw.githubusercontent.com/<owner>/<repo>/<branch>/<path...>
      expect(
        item.downloadUrl.toString(),
        'https://raw.githubusercontent.com/Owner/Repo/main/tunes/Reel_One.abc',
      );
      expect(
        item.sourceUrl,
        'https://github.com/Owner/Repo/blob/main/tunes/Reel_One.abc',
      );
    });
  });

  group('browse (fake HTTP)', () {
    Future<Uint8List> fakeTree(Uri url) async => utf8.encode(_treeJson);

    test('lists every .abc tune as an item', () async {
      final items = await _source(fakeTree).browse();
      expect(items.map((i) => i.title), [
        'Reel One',
        'aaa First',
        'Jig Two',
      ]);
    });

    test('the query filters by title, case-insensitively', () async {
      final items = await _source(fakeTree).browse(query: 'jig');
      expect(items.map((i) => i.title), ['Jig Two']);
    });

    test('limit caps the result count', () async {
      final items = await _source(fakeTree).browse(limit: 1);
      expect(items, hasLength(1));
    });

    test('the tree is fetched once, then cached', () async {
      var calls = 0;
      final src = _source((url) async {
        calls++;
        return utf8.encode(_treeJson);
      });
      await src.browse();
      await src.browse();
      expect(calls, 1);
    });
  });

  test('fetch downloads the item bytes from its download URL', () async {
    Uri? asked;
    final src = _source((url) async {
      asked = url;
      return Uint8List.fromList([1, 2, 3]);
    });
    final item = src.itemForPath('tunes/Reel_One.abc')!;
    final bytes = await src.fetch(item);
    expect(bytes, [1, 2, 3]);
    expect(asked, item.downloadUrl);
  });

  test('the named factories carry the right repo, branch and licence', () {
    final gub = GithubAbcSource.gubbledenut((_) async => Uint8List(0));
    expect(gub.repo, 'Gubbledenut/ABC_TuneBooks');
    expect(gub.licenseSummary, 'CC0 1.0');
    expect(gub.homepage, 'https://github.com/Gubbledenut/ABC_TuneBooks');

    final econ = GithubAbcSource.econrad003((_) async => Uint8List(0));
    expect(econ.repo, 'econrad003/music-abc');
    expect(econ.licenseSummary, 'MIT');
  });
}
