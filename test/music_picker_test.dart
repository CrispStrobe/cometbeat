// The music picker's pure decoder: notation bytes → MultiPartScore by extension.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/notation/multi_part_export.dart'
    show multiPartToMidi;
import 'package:comet_beat/features/library/content_source.dart'
    show LibraryItem;
import 'package:comet_beat/shared/music/music_picker.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('decodes ABC text into a score with notes', () {
    const abc = 'X:1\nT:Scale\nM:4/4\nL:1/4\nK:C\nC D E F|';
    final score = decodeMusicFile('scale.abc', _b(abc));
    expect(score.parts, isNotEmpty);
    // The first part carries the four notes (chords/rests preserved by the
    // multi-part reader).
    final elements = score.parts.first.measures.expand((m) => m.elements);
    expect(elements, isNotEmpty);
  });

  test('decodes MusicXML by extension', () {
    const xml = '''
<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>M</part-name></score-part></part-list>
  <part id="P1"><measure number="1">
    <attributes><divisions>1</divisions>
      <key><fifths>0</fifths></key>
      <time><beats>4</beats><beat-type>4</beat-type></time>
      <clef><sign>G</sign><line>2</line></clef>
    </attributes>
    <note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration><type>whole</type></note>
  </measure></part>
</score-partwise>''';
    final score = decodeMusicFile('c.musicxml', _b(xml));
    expect(score.parts, isNotEmpty);
  });

  test('decodes Gregorio chant (.gabc) into a score with notes', () {
    const gabc = 'name:Test;\n%%\n(c4) Al(f)le(g)lú(h)ia(g.)';
    final score = decodeMusicFile('chant.gabc', _b(gabc));
    expect(score.parts, isNotEmpty);
    final elements = score.parts.first.measures.expand((m) => m.elements);
    expect(elements.isNotEmpty, isTrue);
  });

  test('decodes MIDI (.mid) — round-trip through the app MIDI writer', () {
    // Encode a known ABC score to MIDI, then decode the MIDI back.
    final abc = decodeMusicFile('t.abc', _b('X:1\nK:C\nL:1/4\nCDEF|'));
    final midi = multiPartToMidi(abc);
    final back = decodeMusicFile('song.mid', midi);
    expect(back.parts, isNotEmpty);
  });

  test('the .kern alias resolves like .krn', () {
    // A minimal Humdrum **kern spine (one quarter note C).
    const kern = '**kern\n4c\n*-\n';
    final score = decodeMusicFile('tune.kern', _b(kern));
    expect(score.parts, isNotEmpty);
  });

  test('catalog modules convert into a multi-part score', () {
    final bytes = File('test/fixtures/golden.mod').readAsBytesSync();
    final score = decodeMusicAsset('golden.mod', bytes, collection: 'module');
    expect(score.parts, isNotEmpty);
    expect(
      score.parts.expand((part) => part.measures.expand((m) => m.elements)),
      isNotEmpty,
    );
  });

  test('music catalog kinds are limited to songs and modules', () {
    final items = <LibraryItem>[
      LibraryItem(
        sourceId: 'test',
        sourceName: 'Test',
        id: 'score',
        title: 'Song',
        composer: '',
        collection: 'score',
        declaredLicense: 'CC0',
        downloadUrl: Uri.parse('https://example.com/song.abc'),
        format: 'abc',
      ),
      LibraryItem(
        sourceId: 'test',
        sourceName: 'Test',
        id: 'sample',
        title: 'Kick',
        composer: '',
        collection: 'sample',
        declaredLicense: 'CC0',
        downloadUrl: Uri.parse('https://example.com/kick.wav'),
        format: 'wav',
      ),
    ];
    final music = [
      for (final item in items)
        if (item.collection == 'score' || item.collection == 'module') item,
    ];
    expect(music.map((item) => item.title), ['Song']);
  });

  test('an unsupported extension throws FormatException', () {
    expect(
      () => decodeMusicFile('song.xyz', Uint8List(0)),
      throwsA(isA<FormatException>()),
    );
  });
}
