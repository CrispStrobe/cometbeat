// GregoBaseSource — browse over an injected (fake) chant index, item shape,
// query filtering, and the gabc → MusicXML decode. No network / no bundled asset.
import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/features/library/library_import.dart'
    show bytesToMusicXml;
import 'package:comet_beat/features/library/sources/gregobase_source.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _noHttp(Uri _) async => Uint8List(0);

void main() {
  final src = GregoBaseSource(
    _noHttp,
    loadIndex: () async => json.encode([
      {'i': '1', 't': 'Laudem Domini', 'o': 'al', 'm': '1'},
      {'i': '900', 't': 'Diffusa est gratia', 'o': 'of', 'm': '5'},
    ]),
  );

  test('browse yields CC0 chant items with a GregoBase download URL', () async {
    final items = await src.browse();
    expect(items.length, 2);
    final it = items.first;
    expect(it.title, 'Laudem Domini');
    expect(it.format, 'gabc');
    expect(it.declaredLicense, 'CC0');
    expect(it.composer, 'Gregorian chant');
    expect(it.collection, contains('al'));
    expect(it.sourceId, 'gregobase');
    final url = it.downloadUrl.toString();
    expect(url, contains('gregobase.selapa.net'));
    expect(url, contains('id=1'));
    expect(url, contains('format=gabc'));
  });

  test('browse filters by title or office', () async {
    expect((await src.browse(query: 'diffusa')).single.id, '900');
    expect((await src.browse(query: 'al')).single.id, '1'); // office match
  });

  test('a fetched .gabc decodes to MusicXML with notes + lyrics', () {
    const gabc = 'name:Test;\n%%\n(c4) Al(f)le(g)lú(h)ia(g.)';
    final xml = bytesToMusicXml('gabc', Uint8List.fromList(utf8.encode(gabc)));
    expect(xml, contains('<note'));
    expect(xml, contains('<lyric'));
  });
}
