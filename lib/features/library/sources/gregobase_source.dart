// The CC0 GregoBase Gregorian-chant corpus as a browsable library source.
//
// GregoBase (gregobase.selapa.net) publishes ~18.7k chants, "all transcriptions
// released under CC0". The chant list ships as a bundled compact index
// (`assets/library/gregobase_index.json`, generated from the CC0 SQL dump); each
// `.gabc` is fetched from GregoBase on import and decoded via crisp_notation's
// gabc reader (see `bytesToMusicXml`). Kept as its own source so Latin chant
// doesn't swamp the main (children's) repertoire.
import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/features/library/content_source.dart';
import 'package:flutter/services.dart' show rootBundle;

/// The GregoBase Gregorian-chant corpus (CC0), browsed from a bundled index.
class GregoBaseSource implements ContentSource {
  /// [http] fetches a chant's `.gabc`; [loadIndex] returns the bundled chant
  /// index JSON (injectable for tests; defaults to the bundled asset).
  GregoBaseSource(this._http, {Future<String> Function()? loadIndex})
      : _loadIndex = loadIndex ??
            (() =>
                rootBundle.loadString('assets/library/gregobase_index.json'));

  final HttpGet _http;
  final Future<String> Function() _loadIndex;
  List<dynamic>? _index;

  @override
  String get id => 'gregobase';

  @override
  String get name => 'Gregorian Chant';

  @override
  String get homepage => 'https://gregobase.selapa.net/';

  @override
  String get licenseSummary => 'CC0 — public domain';

  Future<List<dynamic>> _loaded() async =>
      _index ??= json.decode(await _loadIndex()) as List<dynamic>;

  @override
  Future<List<LibraryItem>> browse({String query = '', int limit = 60}) async {
    final rows = await _loaded();
    final q = query.toLowerCase().trim();
    final out = <LibraryItem>[];
    for (final r in rows) {
      final m = r as Map<String, dynamic>;
      final title = (m['t'] as String?) ?? '';
      final office = (m['o'] as String?) ?? '';
      if (q.isNotEmpty &&
          !title.toLowerCase().contains(q) &&
          !office.toLowerCase().contains(q)) {
        continue;
      }
      out.add(itemForRow(m));
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Builds a [LibraryItem] from an index row `{i,t,o,m}` (id/title/office/mode).
  LibraryItem itemForRow(Map<String, dynamic> r) {
    final cid = '${r['i']}';
    final office = (r['o'] as String?) ?? '';
    final mode = (r['m'] as String?) ?? '';
    final collection = [
      if (office.isNotEmpty) office,
      if (mode.isNotEmpty) 'mode $mode',
    ].join(' · ');
    final title = (r['t'] as String?)?.trim();
    return LibraryItem(
      sourceId: id,
      sourceName: name,
      id: cid,
      title: (title != null && title.isNotEmpty) ? title : 'Chant $cid',
      composer: 'Gregorian chant',
      collection: collection,
      declaredLicense: 'CC0',
      licenseUrl: 'https://creativecommons.org/publicdomain/zero/1.0/',
      sourceUrl: 'https://gregobase.selapa.net/chant.php?id=$cid',
      downloadUrl: Uri.parse(
        'https://gregobase.selapa.net/download.php?id=$cid&format=gabc&elem=1',
      ),
      format: 'gabc',
    );
  }

  @override
  Future<Uint8List> fetch(LibraryItem item) => _http(item.downloadUrl);
}
