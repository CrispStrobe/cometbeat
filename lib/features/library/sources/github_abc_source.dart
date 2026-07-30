import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/features/library/content_source.dart';

/// A cleanly-licensed (CC0/MIT) ABC tune collection browsed from its GitHub mirror.
class GithubAbcSource implements ContentSource {
  final HttpGet _http;

  @override
  final String id;
  @override
  final String name;

  /// `owner/repo` on GitHub.
  final String repo;
  final String branch;
  final String _declaredLicense;
  final String _licenseUrl;

  List<String>? _paths;

  GithubAbcSource(
    this._http, {
    required this.id,
    required this.name,
    required this.repo,
    required String declaredLicense,
    required String licenseUrl,
    this.branch = 'master',
  })  : _declaredLicense = declaredLicense,
        _licenseUrl = licenseUrl;

  /// Gubbledenut's 18th/19th century tunebook transcriptions (CC0).
  factory GithubAbcSource.gubbledenut(HttpGet http) => GithubAbcSource(
        http,
        id: 'gubbledenut_abc',
        name: 'Gubbledenut TuneBooks',
        repo: 'Gubbledenut/ABC_TuneBooks',
        declaredLicense: 'CC0 1.0',
        licenseUrl: 'https://creativecommons.org/publicdomain/zero/1.0/',
      );

  /// econrad003's historical transcriptions (MIT).
  factory GithubAbcSource.econrad003(HttpGet http) => GithubAbcSource(
        http,
        id: 'econrad003_abc',
        name: 'econrad003 Music ABC',
        repo: 'econrad003/music-abc',
        declaredLicense: 'MIT',
        licenseUrl: 'https://opensource.org/licenses/MIT',
        branch: 'main',
      );

  @override
  String get homepage => 'https://github.com/$repo';

  @override
  String get licenseSummary => _declaredLicense;

  Uri get _treeUrl => Uri.parse(
        'https://api.github.com/repos/$repo/git/trees/$branch?recursive=1',
      );

  Future<List<String>> _loadPaths() async {
    final cached = _paths;
    if (cached != null) return cached;
    final bytes = await _http(_treeUrl);
    final paths = parseTreePaths(utf8.decode(bytes));
    _paths = paths;
    return paths;
  }

  /// Extracts `.abc` paths from a GitHub git-tree JSON body.
  static List<String> parseTreePaths(String treeJson) {
    final root = json.decode(treeJson) as Map<String, dynamic>;
    final tree = root['tree'] as List? ?? [];
    final out = <String>[];
    for (final e in tree) {
      final path = (e as Map<String, dynamic>)['path'] as String?;
      if (path != null && path.toLowerCase().endsWith('.abc')) {
        out.add(path);
      }
    }
    out.sort();
    return out;
  }

  /// Builds a [LibraryItem] from an `.abc` file path.
  LibraryItem? itemForPath(String path) {
    final segs = path.split('/');
    final file = segs.last;
    final title = file.substring(0, file.length - 4).replaceAll('_', ' ');
    final scoreId = path.replaceAll('/', '_').replaceAll('.abc', '');

    return LibraryItem(
      sourceId: id,
      sourceName: name,
      id: scoreId,
      title: title,
      composer: 'Traditional / Various',
      collection: name,
      declaredLicense: _declaredLicense,
      licenseUrl: _licenseUrl,
      sourceUrl: 'https://github.com/$repo/blob/$branch/$path',
      downloadUrl: Uri(
        scheme: 'https',
        host: 'raw.githubusercontent.com',
        pathSegments: [...repo.split('/'), branch, ...segs],
      ),
      format: 'abc',
    );
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
    final paths = await _loadPaths();
    final q = query.toLowerCase().trim();
    final out = <LibraryItem>[];
    for (final p in paths) {
      final item = itemForPath(p);
      if (item == null) continue;
      if (q.isNotEmpty && !item.title.toLowerCase().contains(q)) {
        continue;
      }
      out.add(item);
      if (out.length >= limit) break;
    }
    return out;
  }

  @override
  Future<Uint8List> fetch(LibraryItem item) => _http(item.downloadUrl);
}
