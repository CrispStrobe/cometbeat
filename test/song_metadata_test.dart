// Song Book: per-song composer / key / tempo.
//
// A book of twenty imports used to be twenty bare titles — `ImportedSong` kept
// only id/title/musicXml/attribution/sourceUrl. All three of these were already
// sitting in the stored MusicXML, so this is derive-and-cache, not new parsing:
// `musicXml` stays the source of truth and the fields are there so a list row
// does not have to parse a whole document to draw one subtitle.
//
// The two things worth pinning are the MIGRATION (songs saved before the fields
// existed must fill in, not show blanks) and the KEY LABEL, which deliberately
// refuses to claim a tonality the data does not carry.

import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/shared/key_signature_label.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal MusicXML document with the metadata we care about.
String _xml({
  String? composer,
  int fifths = 0,
  double? tempo,
}) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <work><work-title>Test Piece</work-title></work>
  <identification>
    ${composer == null ? '' : '<creator type="composer">$composer</creator>'}
  </identification>
  <part-list>
    <score-part id="P1"><part-name>Piano</part-name></score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>1</divisions>
        <key><fifths>$fifths</fifths></key>
        <time><beats>4</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line></clef>
      </attributes>
      ${tempo == null ? '' : _metronome(tempo)}
      <note>
        <pitch><step>C</step><octave>4</octave></pitch>
        <duration>4</duration><type>whole</type>
      </note>
    </measure>
  </part>
</score-partwise>
''';

/// A visible metronome mark. NOTE: `<sound tempo="…">` alone is NOT read by
/// crisp_notation's MusicXML reader (it only looks at `<metronome>`), so a file
/// carrying only the playback attribute imports with no tempo — see the
/// known-limitation test at the bottom.
String _metronome(double bpm) => '''
      <direction placement="above">
        <direction-type>
          <metronome>
            <beat-unit>quarter</beat-unit>
            <per-minute>${bpm.round()}</per-minute>
          </metronome>
        </direction-type>
      </direction>''';

ImportedSong _song(String xml) =>
    ImportedSong(id: 's1', title: 'Test Piece', musicXml: xml);

void main() {
  group('deriving metadata from the stored MusicXML', () {
    test('picks up the composer', () {
      final s = _song(_xml(composer: 'J. S. Bach')).withDerivedMetadata();
      expect(s.composer, 'J. S. Bach');
    });

    test('picks up the key signature as fifths', () {
      expect(_song(_xml(fifths: 2)).withDerivedMetadata().keyFifths, 2);
      expect(_song(_xml(fifths: -3)).withDerivedMetadata().keyFifths, -3);
    });

    test('picks up the tempo in quarter-notes per minute', () {
      final s = _song(_xml(tempo: 96)).withDerivedMetadata();
      expect(s.tempoBpm, closeTo(96, 0.001));
    });

    test('a source that names no composer leaves it null, not empty', () {
      // An empty string would render as a stray "· " separator in the list.
      final s = _song(_xml()).withDerivedMetadata();
      expect(s.composer, isNull);
    });

    test('it never overwrites metadata that is already set', () {
      // The XML is the source of truth, but an explicit value the user or an
      // importer supplied wins — this is a cache fill, not a re-sync.
      final s = ImportedSong(
        id: 's1',
        title: 'Test Piece',
        musicXml: _xml(composer: 'From XML', fifths: 2, tempo: 96),
        composer: 'Set explicitly',
        keyFifths: -1,
        tempoBpm: 60,
      ).withDerivedMetadata();
      expect(s.composer, 'Set explicitly');
      expect(s.keyFifths, -1);
      expect(s.tempoBpm, 60);
    });

    test('unparseable XML is left alone rather than throwing', () {
      // A song you cannot read is still a song you must be able to see and
      // delete, so deriving must never take the book down.
      final s = _song('not xml at all').withDerivedMetadata();
      expect(s.composer, isNull);
      expect(s.keyFifths, isNull);
      expect(s.title, 'Test Piece');
    });

    test('the other fields survive derivation untouched', () {
      final s = ImportedSong(
        id: 'keep-me',
        title: 'Test Piece',
        musicXml: _xml(composer: 'Anon', fifths: 1),
        attribution: 'Some library',
        sourceUrl: 'https://example.org/x',
      ).withDerivedMetadata();
      expect(s.id, 'keep-me');
      expect(s.attribution, 'Some library');
      expect(s.sourceUrl, 'https://example.org/x');
      expect(s.musicXml, contains('score-partwise'));
    });
  });

  group('persistence', () {
    test('the new fields round-trip through JSON', () {
      final s = _song(_xml(composer: 'Satie', fifths: -1, tempo: 72))
          .withDerivedMetadata();
      final back = ImportedSong.fromJson(s.toJson());
      expect(back.composer, 'Satie');
      expect(back.keyFifths, -1);
      expect(back.tempoBpm, closeTo(72, 0.001));
    });

    test('a record saved BEFORE these fields existed still loads', () {
      // The migration case: exactly the old on-disk shape, no new keys.
      final legacy = {
        'id': 's1',
        'title': 'Old Song',
        'xml': _xml(composer: 'Legacy', fifths: 3, tempo: 88),
      };
      final loaded = ImportedSong.fromJson(legacy);
      expect(loaded.composer, isNull, reason: 'nothing was stored yet');

      // …and deriving fills it in from the XML that was always there.
      final migrated = loaded.withDerivedMetadata();
      expect(migrated.composer, 'Legacy');
      expect(migrated.keyFifths, 3);
      expect(migrated.tempoBpm, closeTo(88, 0.001));
    });

    test('unknown metadata is omitted from JSON, not written as null', () {
      // So a song whose source names no composer looks the same on disk as one
      // saved before the field existed.
      final json = _song(_xml()).toJson();
      expect(json.containsKey('composer'), isFalse);
      expect(json.containsKey('tempoBpm'), isFalse);
    });
  });

  group('the key label refuses to invent a tonality', () {
    test('it names the relative PAIR, because fifths cannot distinguish them',
        () {
      // Two sharps is D major OR B minor and the file does not say which.
      expect(keySignatureLabel(2), 'D / Bm');
      expect(keySignatureLabel(0), 'C / Am');
      expect(keySignatureLabel(-1), 'F / Dm');
    });

    test('it covers the whole standard range', () {
      for (var f = kMinFifths; f <= kMaxFifths; f++) {
        final label = keySignatureLabel(f);
        expect(label, isNotNull, reason: 'fifths $f');
        expect(label, contains(' / '), reason: 'fifths $f');
      }
      expect(keySignatureLabel(kMinFifths), 'C♭ / A♭m');
      expect(keySignatureLabel(kMaxFifths), 'C♯ / A♯m');
    });

    test('an impossible signature returns null rather than a wrong key', () {
      expect(keySignatureLabel(8), isNull);
      expect(keySignatureLabel(-8), isNull);
      expect(majorKeyName(99), isNull);
    });

    test('every major/minor pair is a real relative pair', () {
      // A relative minor sits three semitones below its major, which shows up
      // in the circle of fifths as the SAME signature — so the two lists must
      // stay aligned. An off-by-one here would mislabel every key.
      expect(majorKeyName(0), 'C');
      expect(keySignatureLabel(0), startsWith('C '));
      expect(majorKeyName(1), 'G');
      expect(keySignatureLabel(1), 'G / Em');
      expect(majorKeyName(-2), 'B♭');
      expect(keySignatureLabel(-2), 'B♭ / Gm');
    });

    test('the tempo label rounds instead of showing false precision', () {
      // A MusicXML round-trip can leave 119.99999.
      expect(tempoLabel(119.99999), '♩=120');
      expect(tempoLabel(96), '♩=96');
    });
  });

  group('known limitation: <sound tempo> alone', () {
    test('a file with only <sound tempo> imports without a tempo', () {
      // crisp_notation's MusicXML reader takes its tempo from <metronome>, the
      // VISIBLE mark, and ignores the <sound tempo="..."> playback attribute.
      // Plenty of exporters write the latter with no visible mark, so those
      // files lose their tempo on import. This is a reader gap in the sibling
      // repo, not something this feature can fix — it is pinned here so the
      // behaviour is documented and this test flips to a failure (a good one)
      // the day the reader learns to read it.
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>P</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>1</divisions>
        <key><fifths>0</fifths></key>
        <clef><sign>G</sign><line>2</line></clef>
      </attributes>
      <direction><sound tempo="132"/></direction>
      <note><pitch><step>C</step><octave>4</octave></pitch>
        <duration>4</duration><type>whole</type></note>
    </measure>
  </part>
</score-partwise>
''';
      final s = _song(xml).withDerivedMetadata();
      expect(
        s.tempoBpm,
        isNull,
        reason: 'the reader now reads <sound tempo> — good! Update this test '
            'and the note on _metronome().',
      );
      // The rest of the metadata still comes through, so the song is fine.
      expect(s.keyFifths, 0);
    });
  });
}
