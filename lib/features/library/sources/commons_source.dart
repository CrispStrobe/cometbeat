// Wikimedia Commons — MIDI files via the open MediaWiki API (no key). Everything
// on Commons is freely licensed, but PER FILE (CC0 / CC BY / CC BY-SA / Public
// domain — and the occasional NC upload), so this is the first source where the
// LicensePolicy gate does real work: we surface only the files it permits. See
// docs/LIBRARIES_AND_TAB_SCOPING.md §1.2 ("Wikimedia Commons — SAFE").

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/license_policy.dart';

class CommonsSource implements ContentSource {
  final HttpGet _http;
  final LicensePolicy _policy;

  @override
  final String id;
  @override
  final String name;

  /// The MediaWiki `filemime:` this source searches (e.g. `audio/midi`,
  /// `audio/wav`).
  final String filemime;

  /// The [LibraryItem.format] to tag results with (`midi`, `wav`, …).
  final String format;

  CommonsSource(
    this._http, {
    LicensePolicy policy = const LicensePolicy(),
    this.id = 'wikimedia_commons',
    this.name = 'Wikimedia Commons',
    this.filemime = 'audio/midi',
    this.format = 'midi',
  }) : _policy = policy;

  /// CC0/PD (per default policy) **WAV audio samples** — a sound source the
  /// Tracker/instruments can consume. Key-free MediaWiki API.
  factory CommonsSource.audio(
    HttpGet http, {
    LicensePolicy policy = const LicensePolicy(),
  }) =>
      CommonsSource(
        http,
        policy: policy,
        id: 'wikimedia_commons_audio',
        name: 'Wikimedia Commons (sounds)',
        filemime: 'audio/wav',
        format: 'wav',
      );

  @override
  String get homepage => 'https://commons.wikimedia.org';
  @override
  String get licenseSummary => 'Free / public domain (per file)';

  Uri searchUrl(String query, int limit) {
    final search = 'filemime:$filemime ${query.trim()}'.trim();
    return Uri.parse(
      'https://commons.wikimedia.org/w/api.php'
      '?action=query&format=json&origin=*'
      '&generator=search&gsrnamespace=6&gsrlimit=$limit'
      '&gsrsearch=${Uri.encodeQueryComponent(search)}'
      '&prop=imageinfo&iiprop=url%7Cextmetadata'
      '&iiextmetadatafilter=LicenseShortName%7CArtist%7CLicenseUrl',
    );
  }

  @override
  Future<List<LibraryItem>> browse({String query = '', int limit = 60}) async {
    final bytes = await _http(searchUrl(query, limit));
    // Only surface files the permissive gate would accept.
    return parseSearch(utf8.decode(bytes)).where(_policy.isAllowed).toList();
  }

  /// Parses the MediaWiki `query` JSON into items. Static-ish + pure so it is
  /// unit-testable against a captured fixture (no license filtering here — that
  /// is [browse]'s job, so the parser stays honest about what Commons returned).
  List<LibraryItem> parseSearch(String body) {
    final root = json.decode(body) as Map<String, dynamic>;
    final query = root['query'];
    final pages = query is Map ? query['pages'] : null;
    if (pages is! Map) return [];
    final out = <LibraryItem>[];
    for (final entry in pages.values) {
      final page = entry as Map<String, dynamic>;
      final infos = page['imageinfo'];
      if (infos is! List || infos.isEmpty) continue;
      final info = infos.first as Map<String, dynamic>;
      final url = info['url'] as String?;
      if (url == null) continue;
      final em = info['extmetadata'];
      String meta(String key) {
        final v = em is Map ? em[key] : null;
        final value = v is Map ? v['value'] : null;
        return _stripHtml(value is String ? value : '');
      }

      final fullTitle = page['title'] as String? ?? '';
      final license = meta('LicenseShortName');
      final licenseUrl = meta('LicenseUrl');
      out.add(
        LibraryItem(
          sourceId: id,
          sourceName: name,
          id: 'commons_${page['pageid'] ?? fullTitle.hashCode}',
          title: _displayTitle(fullTitle),
          composer: meta('Artist'),
          declaredLicense: license.isEmpty ? 'unknown' : license,
          licenseUrl: licenseUrl.isEmpty ? null : licenseUrl,
          sourceUrl: 'https://commons.wikimedia.org/wiki/'
              '${Uri.encodeComponent(fullTitle)}',
          downloadUrl: Uri.parse(url),
          format: format,
        ),
      );
    }
    out.sort((a, b) => a.title.compareTo(b.title)); // deterministic order
    return out;
  }

  @override
  Future<Uint8List> fetch(LibraryItem item) => _http(item.downloadUrl);

  /// "File:Some Tune.mid" → "Some Tune" (strips `File:` + a known audio ext).
  static String _displayTitle(String title) {
    var t = title;
    if (t.startsWith('File:')) t = t.substring(5);
    t = t.replaceAll(
      RegExp(r'\.(midi?|wav|ogg|flac)$', caseSensitive: false),
      '',
    );
    return t.trim();
  }

  /// Strips HTML tags/entities Commons wraps some metadata fields in.
  static String _stripHtml(String s) => s
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
