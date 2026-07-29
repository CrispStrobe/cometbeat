// Unit tests for importScore — the Workshop's unified, extension-dispatched file
// import. Pure (bytes in, Score out), so it exercises the format routing without
// a file picker.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/notation/multi_part_export.dart'
    show multiPartToMidi;
import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('round-trips MusicXML by its extension', () {
    final xml = scoreToMusicXml(Score.simple(notes: 'c4:q d4 e4 f4'));
    final score = importScore('tune.musicxml', _bytes(xml));
    expect(score.measures, isNotEmpty);
  });

  test('reads ABC by its extension', () {
    final score = importScore('tune.abc', _bytes('X:1\nK:C\nCDEF|'));
    expect(score.measures, isNotEmpty);
  });

  test('round-trips MEI by its extension', () {
    final mei = scoreToMei(Score.simple(notes: 'c4:q d4 e4 f4'));
    final score = importScore('tune.mei', _bytes(mei));
    expect(score.measures, isNotEmpty);
  });

  test('is case-insensitive on the extension', () {
    final xml = scoreToMusicXml(Score.simple(notes: 'c4:q d4'));
    expect(importScore('TUNE.MusicXML', _bytes(xml)).measures, isNotEmpty);
  });

  test('rejects an unknown extension with a FormatException', () {
    expect(
      () => importScore('mystery.foo', Uint8List(0)),
      throwsA(isA<FormatException>()),
    );
  });

  // ---- importMultiPart (G6): all instrument parts, not just the first ------

  test('importMultiPart keeps both parts of a two-part MusicXML', () {
    const q = NoteDuration(DurationBase.quarter);
    final doc = ScoreDocument()
      ..insertNote(const Pitch(Step.g), q)
      ..insertNote(const Pitch(Step.c, octave: 3), q);
    final xml = grandStaffToMusicXml(doc.buildGrandStaff());
    final mps = importMultiPart('score.musicxml', _bytes(xml));
    expect(mps.parts.length, 2);
  });

  test('importMultiPart keeps both staves of a multi-staff .ly', () {
    const ly = r'''
\score {
  \new StaffGroup <<
    \new Staff { \clef treble c'4 d' e' f' }
    \new Staff { \clef bass c4 d e f }
  >>
}
''';
    final mps = importMultiPart('duet.ly', _bytes(ly));
    expect(mps.parts, hasLength(2));
    expect(mps.parts[0].clef, Clef.treble);
    expect(mps.parts[1].clef, Clef.bass);
  });

  test('importMultiPart wraps a single-part file as one part', () {
    final xml = scoreToMusicXml(Score.simple(notes: 'c4:q d4'));
    final mps = importMultiPart('tune.musicxml', _bytes(xml));
    expect(mps.parts, hasLength(1));
    expect(mps.parts.first.measures, isNotEmpty);
  });

  test('importMultiPart keeps both tracks of a multi-track MIDI', () {
    final midi = multiPartToMidi(
      MultiPartScore([
        Score.simple(notes: 'c4:q d4 e4 f4'),
        Score.simple(notes: 'g3:q e3 c3 g2'),
      ]),
    );
    final mps = importMultiPart('band.mid', midi);
    expect(mps.parts.length, 2, reason: 'one part per MIDI track');
  });

  test('importMultiPart falls back through importScore for unknown types', () {
    expect(
      () => importMultiPart('mystery.foo', Uint8List(0)),
      throwsA(isA<FormatException>()),
    );
  });

  // ---- importBekern (paste OMR tokens → playable score) -------------------

  test('importBekern parses single-spine tokens into one part', () {
    final mps = importBekern('**kern <b> 4 c <b> 4 d <b> *-');
    expect(mps.parts, hasLength(1));
    expect(mps.parts.first.measures, isNotEmpty);
    final notes = mps.parts.first.measures
        .expand((m) => m.elements)
        .whereType<NoteElement>();
    expect(notes, isNotEmpty);
  });

  test('importBekern parses a two-spine system into two parts', () {
    const bekern = '**kern <t> **kern <b> '
        '*clefF4 <t> *clefG2 <b> '
        '*M4/4 <t> *M4/4 <b> '
        '4 C <t> 4 c <b> '
        '4 D <t> 4 d <b> '
        '*- <t> *-';
    final mps = importBekern(bekern);
    expect(mps.parts.length, 2, reason: 'one part per **kern spine');
  });

  test('importBekern trims surrounding whitespace', () {
    final mps = importBekern('\n  **kern <b> 4 c <b> *-  \n');
    expect(mps.parts, hasLength(1));
  });

  test('a Guitar Pro file keeps its barre and string choices END TO END', () {
    // The claim that matters, through the real path: build a .gp carrying a
    // barre and a deliberate string choice, import it as the Score Editor does,
    // put it through the document, and export .gp again. Every one of those
    // steps used to drop both facts, and each looked fine on its own.
    final source = Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement(
            pitches: [Pitch.fromMidi(64)],
            duration: NoteDuration.quarter,
            id: 'n0',
          ),
        ]),
      ],
      // E4 voiced on string 1 fret 5, not the open high e — a real choice.
      tabVoicings: const [
        TabVoicing('n0', [1]),
      ],
      tabBarres: const [TabBarre('n0', 5)],
    );
    final gp = writeGpFromGpif(
      scoreToGpif(source, tuning: Tuning.standardGuitar),
    );

    final imported = importScore('riff.gp', gp);
    expect(imported.tabBarres, hasLength(1), reason: 'import kept the barre');
    expect(imported.tabVoicings, hasLength(1));

    final doc = ScoreDocument()..loadScore(imported);
    final rebuilt = doc.buildScore();
    expect(
      rebuilt.tabBarres.single.fret,
      5,
      reason: 'the document kept it — this is the step that used to lose it',
    );

    final out = scoreFromGpif(
      readGpifFromGp(
        writeGpFromGpif(scoreToGpif(rebuilt, tuning: Tuning.standardGuitar)),
      ),
    );
    expect(out.tabBarres.single.fret, 5, reason: 'and the export carries it');
    expect(out.tabVoicings.single.strings, [1]);
  });
}
