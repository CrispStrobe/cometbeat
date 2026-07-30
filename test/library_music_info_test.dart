import 'package:comet_beat/features/library/content_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// `MusicInfo` is what lets the library browser answer "could we actually play
/// this?" before downloading anything. It is parsed straight out of the
/// catalog, so it has to survive rows that predate the field entirely.
MusicInfo info(Map<String, Object?> json) => MusicInfo.fromJson(json)!;

/// A row that only declares a range — the common shape in these checks.
MusicInfo range(int lo, int hi) => info(<String, Object?>{
      'ambitus': <int>[lo, hi],
    });

void main() {
  group('MusicInfo.fromJson', () {
    test('reads a full catalog music object', () {
      final m = info({
        'key': 'D major',
        'meter': '6/8',
        'bars': 20,
        'ambitus': [62, 74],
        'incipit': [62, 62, 66, 69, 74],
      });
      expect(m.key, 'D major');
      expect(m.meter, '6/8');
      expect(m.bars, 20);
      expect(m.lowestMidi, 62);
      expect(m.highestMidi, 74);
      expect(m.incipit, [62, 62, 66, 69, 74]);
    });

    test('older rows without the field yield null, not an empty badge', () {
      // The whole corpus predates `music`; a row missing it must render as
      // "no information", never as a row claiming an unknown key.
      expect(MusicInfo.fromJson(null), isNull);
      expect(MusicInfo.fromJson('not a map'), isNull);
      expect(MusicInfo.fromJson(const <String, Object?>{}), isNull);
    });

    test('a partial object still parses', () {
      final m = info({'meter': '4/4'});
      expect(m.meter, '4/4');
      expect(m.key, isNull);
      expect(m.ambitusLabel, isNull);
      expect(m.ambitusSemitones, isNull);
      expect(m.fitsOneOctave, isFalse);
    });

    test('a malformed ambitus does not throw', () {
      expect(info({'key': 'C major', 'ambitus': []}).lowestMidi, isNull);
      expect(
        info({'key': 'C major', 'ambitus': 'nonsense'}).highestMidi,
        isNull,
      );
      expect(
        info({
          'key': 'C major',
          'ambitus': <Object?>[null, null],
        }).lowestMidi,
        isNull,
      );
    });
  });

  group('range', () {
    test('labels the span with octave numbers', () {
      final m = range(62, 74);
      expect(m.ambitusLabel, 'D4–D5');
      expect(m.ambitusSemitones, 12);
      expect(m.fitsOneOctave, isTrue);
    });

    test('one octave is inclusive, a thirteenth is not', () {
      expect(range(60, 72).fitsOneOctave, isTrue);
      expect(range(60, 73).fitsOneOctave, isFalse);
    });

    test('a voice-plus-piano score is correctly NOT flagged as singable', () {
      // The Mozart KV 596 setting in the catalog spans 43-83 because it
      // includes the piano; the melody-only setting spans 62-74. Only the
      // latter should carry the badge.
      expect(range(43, 83).fitsOneOctave, isFalse);
      expect(range(62, 74).fitsOneOctave, isTrue);
    });

    test('names accidentals and octaves across the range', () {
      expect(range(60, 61).ambitusLabel, 'C4–C♯4');
      expect(range(21, 108).ambitusLabel, 'A0–C8');
    });
  });

  test('LibraryItem carries music through and defaults to null', () {
    final bare = LibraryItem(
      sourceId: 's',
      sourceName: 'S',
      id: 'i',
      title: 'T',
      composer: 'C',
      declaredLicense: 'CC0',
      downloadUrl: Uri.parse('https://example.invalid/a.abc'),
      format: 'abc',
    );
    expect(bare.music, isNull);

    final withMusic = LibraryItem(
      sourceId: 's',
      sourceName: 'S',
      id: 'i',
      title: 'T',
      composer: 'C',
      declaredLicense: 'CC0',
      downloadUrl: Uri.parse('https://example.invalid/a.abc'),
      format: 'abc',
      music: MusicInfo.fromJson({'key': 'G major', 'meter': '3/4'}),
    );
    expect(withMusic.music!.key, 'G major');
  });
}
