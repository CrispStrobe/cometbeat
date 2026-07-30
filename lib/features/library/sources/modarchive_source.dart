// The Mod Archive — tracker modules via the official XML API. **BYOK**: this
// source only works with the user's own API key (see modarchive_key_store.dart);
// no key ships. Its default modules are composer-copyrighted and the site's
// grant excludes app-bundling, so we **hard-filter to the CC0 / Public-Domain
// subset** via the same LicensePolicy gate as every other source — the module's
// XML carries `<license><title>`, which we classify per file.
//
// NB the docs' `view_by_license` is a *website* route, not a confirmed XML-tool
// request — so we `request=search` (or browse-by-letter) and filter client-side
// on the returned license, which the XML always includes. Endpoint + tag names
// verified against the archived docs + several open-source API clients.
// UNVERIFIED live (no key here) — the XML parse is fixture-tested; validate with
// a real key before relying on it.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/license_policy.dart';
import 'package:xml/xml.dart';

class ModArchiveSource implements ContentSource {
  final HttpGet _http;
  final String apiKey;
  final LicensePolicy _policy;

  ModArchiveSource(
    this._http,
    this.apiKey, {
    LicensePolicy policy = const LicensePolicy(),
  }) : _policy = policy;

  @override
  String get id => 'modarchive';
  @override
  String get name => 'The Mod Archive';
  @override
  String get homepage => 'https://modarchive.org';
  @override
  String get licenseSummary => 'CC0 / Public Domain only (your API key)';

  static const _base = 'https://api.modarchive.org/xml-tools.php';

  /// A search (or browse-by-first-letter when [query] is empty) request URL.
  Uri requestUrl(String query, {int page = 1}) {
    final q = query.trim();
    final params = q.isEmpty
        ? {'request': 'view_by_list', 'query': 'a'}
        : {
            'request': 'search',
            'type': 'filename_or_songtitle',
            'query': q,
          };
    return Uri.parse(_base).replace(
      queryParameters: {'key': apiKey, ...params, 'page': '$page'},
    );
  }

  /// Download link for a module id (also present verbatim in `<module><url>`).
  static Uri downloadUrl(String moduleId) => Uri.parse(
        'https://api.modarchive.org/downloads.php?moduleid=$moduleId',
      );

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
    final bytes = await _http(requestUrl(query));
    // Surface only the files the (default CC0/PD) gate accepts.
    return parseModules(utf8.decode(bytes))
        .where(_policy.isAllowed)
        .take(limit)
        .toList();
  }

  /// Parses a `<modarchive>` XML body into items. Pure — fixture-testable. The
  /// module id is read as a DIRECT child of `<module>` (there is a second `<id>`
  /// inside `<artist_info>` — scoping avoids mixing them).
  List<LibraryItem> parseModules(String xmlBody) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlBody);
    } on XmlException {
      return const [];
    }
    final out = <LibraryItem>[];
    for (final m in doc.findAllElements('module')) {
      final moduleId = _childText(m, 'id');
      if (moduleId == null) continue;
      final license = m.getElement('license');
      final licenseTitle = license == null ? '' : _childText(license, 'title');
      final artist = m
          .getElement('artist_info')
          ?.getElement('artist')
          ?.getElement('alias')
          ?.innerText
          .trim();
      final title = _childText(m, 'songtitle')?.trim();
      final filename = _childText(m, 'filename')?.trim();
      final url = _childText(m, 'url')?.trim();
      out.add(
        LibraryItem(
          sourceId: id,
          sourceName: name,
          id: 'ma_$moduleId',
          title: (title != null && title.isNotEmpty)
              ? title
              : (filename ?? 'Module $moduleId'),
          composer: artist ?? '',
          declaredLicense: (licenseTitle == null || licenseTitle.isEmpty)
              ? 'unknown'
              : licenseTitle,
          licenseUrl: license == null ? null : _childText(license, 'legalurl'),
          sourceUrl: 'https://modarchive.org/module.php?$moduleId',
          downloadUrl: (url != null && url.isNotEmpty)
              ? Uri.parse(url)
              : downloadUrl(moduleId),
          format: (_childText(m, 'format') ?? 'mod').toLowerCase(),
        ),
      );
    }
    return out;
  }

  /// Direct-child element text (not descendants) — key to the id-scoping gotcha.
  static String? _childText(XmlElement parent, String name) {
    final e = parent.getElement(name);
    return e?.innerText.trim();
  }

  @override
  Future<Uint8List> fetch(LibraryItem item) => _http(item.downloadUrl);
}
