import 'dart:typed_data';

import 'package:comet_beat/features/games/songs/import/chordpro.dart';
import 'package:comet_beat/features/games/songs/import/midi_import.dart';
import 'package:comet_beat/features/games/songs/song_book.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show NoteElement, scoreFromAbc, scoreFromMusicXml, scoreToMusicXml;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChordPro', () {
    test('parses title, chords and lyrics segments', () {
      const source = '''
{title: Alle meine Entchen}
{comment: just a test}

[C]Alle meine [G]Entchen
schwimmen auf dem [C]See
''';
      final sheet = parseChordPro(source);
      expect(sheet.title, 'Alle meine Entchen');
      expect(sheet.chords, ['C', 'G']);
      expect(sheet.lines.first.first.chord, 'C');
      expect(sheet.lines.first.first.text, 'Alle meine ');
      // The second line's chord sits mid-line.
      final lastLine = sheet.lines.last;
      expect(lastLine.last.chord, 'C');
      expect(lastLine.last.text, 'See');
    });

    test('rejects empty input, maps chord symbols to triads', () {
      expect(() => parseChordPro('{title: x}\n\n'), throwsFormatException);
      expect(chordMidis('C'), [60, 64, 67]);
      expect(chordMidis('Am'), [69, 72, 76]);
      expect(chordMidis('F7'), [65, 69, 72]); // reduced to the F triad
      expect(chordMidis('Bb'), [70, 74, 77]);
      expect(chordMidis('??'), isNull);
    });
  });

  group('ABC import', () {
    test('parses a simple tune and round-trips through the stored MusicXML',
        () {
      const abc = '''
X:1
T:Test Tune
M:4/4
L:1/4
K:C
C D E F | G A B c |
''';
      final score = scoreFromAbc(abc);
      expect(score.measures.length, greaterThanOrEqualTo(2));

      // The Song Book stores imports as MusicXML; re-parsing must still work.
      final xml = scoreToMusicXml(score, partName: 'Test Tune');
      expect(scoreFromMusicXml(xml).measures, isNotEmpty);
    });
  });

  group('MIDI import', () {
    /// Builds a minimal format-0 SMF: division 480, C4 quarter, D4 quarter,
    /// E4 half.
    Uint8List buildMidi() {
      final track = <int>[
        // delta, note-on C4; delta 480, note-off; ...
        0x00, 0x90, 60, 100, 0x83, 0x60, 0x80, 60, 0, // C4, 480 ticks
        0x00, 0x90, 62, 100, 0x83, 0x60, 0x80, 62, 0, // D4, 480 ticks
        0x00, 0x90, 64, 100, 0x87, 0x40, 0x80, 64, 0, // E4, 960 ticks
        0x00, 0xff, 0x2f, 0x00, // end of track
      ];
      final header = [
        ...'MThd'.codeUnits,
        0,
        0,
        0,
        6,
        0,
        0,
        0,
        1,
        0x01,
        0xe0,
        ...'MTrk'.codeUnits,
        (track.length >> 24) & 0xff,
        (track.length >> 16) & 0xff,
        (track.length >> 8) & 0xff,
        track.length & 0xff,
        ...track,
      ];
      return Uint8List.fromList(header);
    }

    test('parses and quantizes a simple melody', () {
      final score = scoreFromMidi(buildMidi());
      final notes = [
        for (final m in score.measures)
          for (final e in m.elements)
            if (e is NoteElement) e,
      ];
      expect(notes.length, 3);
      expect(notes[0].pitches.first.midiNumber, 60);
      expect(notes[1].pitches.first.midiNumber, 62);
      expect(notes[2].pitches.first.midiNumber, 64);
      // Quarter, quarter, half.
      expect(notes[0].duration.fraction, (1, 4));
      expect(notes[2].duration.fraction, (1, 2));
    });

    test('rejects junk', () {
      expect(
        () => scoreFromMidi(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });
  });

  group('MusicXML round trip', () {
    test('built-in song survives export -> import, playback preserved', () {
      final original = kSongs.first.score;
      final xml = scoreToMusicXml(original);
      final reimported = scoreFromMusicXml(xml);

      final a = playbackOf(original);
      final b = playbackOf(reimported);
      expect(b.length, a.length);
      for (var i = 0; i < a.length; i++) {
        expect(b[i].$2, a[i].$2, reason: 'midi of note $i');
        expect(b[i].$3, a[i].$3, reason: 'duration of note $i');
      }
    });
  });
}
