// OpenScore corpora — the connect-first sources. Volunteer-transcribed,
// released under **CC0** (public domain dedication). We pull from the GitHub
// mirrors, NOT musescore.com, so we never touch that site's ToS/paywall. See
// docs/LIBRARIES_AND_TAB_SCOPING.md §1.1.
//
// One config-driven adapter serves every OpenScore repo:
//   Lieder          scores/<Composer>/<Set or _>/<Title>/lc<id>.mxl
//   String Quartets scores/<Composer>/<Piece>/sq<id>.mscx
// Browse = read the git tree once, filter the score files, parse composer/title
// from the path (variable depth). Download = the raw.githubusercontent.com URL.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/features/library/content_source.dart';

/// A CC0 OpenScore corpus browsed from its GitHub mirror.
class OpenScoreSource implements ContentSource {
  final HttpGet _http;

  @override
  final String id;
  @override
  final String name;

  /// `owner/repo` on GitHub (e.g. `OpenScore/Lieder`).
  final String repo;
  final String branch;

  /// The score file extension in this repo (`mxl` or `mscx`).
  final String fileExt;

  /// The [LibraryItem.format] to tag downloads with (matches the pipeline's
  /// decoder — `mxl` or `mscx`).
  final String format;

  List<String>? _paths;

  OpenScoreSource(
    this._http, {
    required this.id,
    required this.name,
    required this.repo,
    required this.fileExt,
    required this.format,
    this.branch = 'main',
  });

  /// ~1,300 CC0 art songs (compressed MusicXML).
  factory OpenScoreSource.lieder(HttpGet http) => OpenScoreSource(
        http,
        id: 'openscore_lieder',
        name: 'OpenScore Lieder',
        repo: 'OpenScore/Lieder',
        fileExt: 'mxl',
        format: 'mxl',
      );

  /// CC0 string-quartet movements (MuseScore `.mscx`).
  factory OpenScoreSource.stringQuartets(HttpGet http) => OpenScoreSource(
        http,
        id: 'openscore_quartets',
        name: 'OpenScore String Quartets',
        repo: 'OpenScore/StringQuartets',
        fileExt: 'mscx',
        format: 'mscx',
      );

  @override
  String get homepage => 'https://github.com/$repo';

  @override
  String get licenseSummary => 'CC0 — public domain';

  Uri get _treeUrl => Uri.parse(
        'https://api.github.com/repos/$repo/git/trees/$branch?recursive=1',
      );

  static const declaredLicense = 'CC0';
  static const _licenseUrl =
      'https://creativecommons.org/publicdomain/zero/1.0/';

  Future<List<String>> _loadPaths() async {
    final cached = _paths;
    if (cached != null) return cached;
    final bytes = await _http(_treeUrl);
    final paths = parseTreePaths(utf8.decode(bytes), fileExt);
    _paths = paths;
    return paths;
  }

  /// Extracts the `scores/…` score paths (of extension [fileExt]) from a GitHub
  /// git-tree JSON body. Static + pure so it is unit-testable against a fixture.
  static List<String> parseTreePaths(String treeJson, String fileExt) {
    final root = json.decode(treeJson) as Map<String, dynamic>;
    final tree = root['tree'] as List? ?? [];
    final suffix = '.$fileExt';
    final out = <String>[];
    for (final e in tree) {
      final path = (e as Map<String, dynamic>)['path'] as String?;
      if (path != null && path.startsWith('scores/') && path.endsWith(suffix)) {
        out.add(path);
      }
    }
    out.sort();
    return out;
  }

  /// Builds a [LibraryItem] from a `scores/<composer>/…/<title>/<file>` path
  /// (variable depth). Returns null for a path that doesn't match.
  LibraryItem? itemForPath(String path) {
    final segs = path.split('/');
    if (segs.length < 4 || segs.first != 'scores') return null;
    final composer = _humanize(segs[1], flipName: true);
    final title = _humanize(segs[segs.length - 2]);
    // Anything between composer and title (a set/opus) → a collection label.
    final collection = segs
        .sublist(2, segs.length - 2)
        .where((s) => s != '_')
        .map(_humanize)
        .join(' · ');
    final file = segs.last;
    final scoreId = file.substring(0, file.length - fileExt.length - 1);
    return LibraryItem(
      sourceId: id,
      sourceName: name,
      id: scoreId,
      title: title,
      composer: composer,
      collection: collection,
      declaredLicense: declaredLicense,
      licenseUrl: _licenseUrl,
      sourceUrl: 'https://github.com/$repo/tree/$branch/'
          '${segs.sublist(0, segs.length - 1).join('/')}',
      downloadUrl: Uri(
        scheme: 'https',
        host: 'raw.githubusercontent.com',
        pathSegments: [...repo.split('/'), branch, ...segs],
      ),
      format: format,
    );
  }

  /// "Arne,_Thomas" → "Thomas Arne" (composer, [flipName]); "Rule,_Britannia!" →
  /// "Rule, Britannia!" (a title keeps its comma, no flip).
  static String _humanize(String seg, {bool flipName = false}) {
    final s = seg.replaceAll('_', ' ').trim();
    if (!flipName) return s;
    final comma = s.indexOf(', ');
    if (comma > 0 && !s.contains('!') && !s.contains('?')) {
      final surname = s.substring(0, comma);
      final given = s.substring(comma + 2);
      if (!given.contains(' ') || given.split(' ').length <= 3) {
        return '$given $surname';
      }
    }
    return s;
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
      if (q.isNotEmpty &&
          !item.title.toLowerCase().contains(q) &&
          !item.composer.toLowerCase().contains(q)) {
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
