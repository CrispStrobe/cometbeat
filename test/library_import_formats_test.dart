// The library-import pipeline's format coverage — the formats our HF score
// corpus adds (kern, abc, gp) must decode to MusicXML that parses, so a browsed
// score becomes an importable song.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/features/library/library_import.dart';
import 'package:crisp_notation/crisp_notation.dart' show scoreFromMusicXml;
import 'package:flutter_test/flutter_test.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('kern (**kern) imports to parseable MusicXML', () {
    const kern = '**kern\n*M4/4\n4c\n4d\n4e\n4f\n=\n*-\n';
    final xml = bytesToMusicXml('krn', _b(kern));
    expect(xml, contains('<note'));
    expect(() => scoreFromMusicXml(xml), returnsNormally);
  });

  test('abc imports to parseable MusicXML', () {
    const abc = 'X:1\nT:Scale\nM:4/4\nL:1/4\nK:C\nCDEF|\n';
    final xml = bytesToMusicXml('abc', _b(abc));
    expect(xml, contains('<note'));
    expect(() => scoreFromMusicXml(xml), returnsNormally);
  });

  test('an unknown format still throws', () {
    expect(
      () => bytesToMusicXml('xyz', _b('nope')),
      throwsA(isA<FormatException>()),
    );
  });
}
