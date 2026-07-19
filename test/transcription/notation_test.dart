// W-NOTATION slice 1 — key estimation + enharmonic spelling. The headline: a
// melody in F major spells B-flat (not A-sharp) and carries a 1-flat key
// signature; a melody in D major spells F-sharp/C-sharp with 2 sharps.

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/notation.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

List<NoteEvent> _notes(List<int> midis) => [
      for (var i = 0; i < midis.length; i++)
        (
          midi: midis[i],
          onMs: i * 500.0,
          offMs: i * 500.0 + 450,
          confidence: 1
        ),
    ];

void main() {
  group('estimateKey', () {
    test('a C-major scale is C major, 0 accidentals', () {
      final k = estimateKey(_notes([60, 62, 64, 65, 67, 69, 71, 72]));
      expect(k.fifths, 0);
      expect(k.minor, isFalse);
      expect(k.tonic, 0);
    });

    test('an F-major scale is 1 flat', () {
      // F G A Bb C D E F
      final k = estimateKey(_notes([65, 67, 69, 70, 72, 74, 76, 77]));
      expect(k.fifths, -1);
      expect(k.minor, isFalse);
    });

    test('a D-major scale is 2 sharps', () {
      // D E F# G A B C# D
      final k = estimateKey(_notes([62, 64, 66, 67, 69, 71, 73, 74]));
      expect(k.fifths, 2);
    });

    test('an A-minor melody is 0 accidentals, minor', () {
      // A B C D E F G A, emphasise A and E (tonic/dominant)
      final k = estimateKey(_notes([57, 57, 59, 60, 62, 64, 64, 65, 67, 57]));
      expect(k.fifths, 0);
      expect(k.minor, isTrue);
    });
  });

  group('spellMidi', () {
    test(
        'the black key at MIDI 70 is B-flat in a flat key, A-sharp in a sharp key',
        () {
      expect(spellMidi(70, fifths: -1).step, Step.b);
      expect(spellMidi(70, fifths: -1).alter, -1); // Bb
      expect(spellMidi(70, fifths: 5).step, Step.a);
      expect(spellMidi(70, fifths: 5).alter, 1); // A#
    });

    test('spelled pitches still sound at the right MIDI (octave is correct)',
        () {
      for (final f in const [-3, -1, 0, 2, 5]) {
        for (final midi in const [55, 58, 60, 61, 66, 70, 73]) {
          expect(
            spellMidi(midi, fifths: f).midiNumber,
            midi,
            reason: 'midi $midi in key $f',
          );
        }
      }
    });

    test('naturals spell as naturals in C', () {
      expect(spellMidi(60).step, Step.c);
      expect(spellMidi(60).alter, 0);
      expect(spellMidi(67).step, Step.g);
    });
  });

  group('chooseClef', () {
    test('a low (cello) line picks bass clef', () {
      // C2–C3 arpeggio, all below middle C.
      expect(chooseClef(_notes([36, 40, 43, 48, 40, 36])), Clef.bass);
    });

    test('a treble-register melody picks treble clef', () {
      expect(chooseClef(_notes([64, 65, 67, 69, 71, 72])), Clef.treble);
    });

    test('empty input defaults to treble', () {
      expect(chooseClef(const []), Clef.treble);
    });
  });

  group('respell', () {
    Score makeScore(List<int> midis) => Score(
          clef: Clef.treble,
          timeSignature: TimeSignature.fourFour,
          measures: [
            Measure([
              for (final m in midis)
                NoteElement(
                  pitches: [Pitch.fromMidi(m)],
                  duration: NoteDuration.quarter,
                ),
            ]),
          ],
        );

    test('re-spells an F-major score to flats + sets the 1-flat key signature',
        () {
      // Built with sharp spelling (Pitch.fromMidi → A#), respell should flip to Bb.
      final respelled = respell(makeScore([65, 67, 69, 70, 72]));
      expect(respelled.keySignature.fifths, -1);
      final steps = [
        for (final e in respelled.measures.first.elements)
          if (e is NoteElement)
            '${e.pitches.first.step.name}${e.pitches.first.alter}',
      ];
      expect(steps, contains('b-1')); // B-flat present
      expect(steps, isNot(contains('a1'))); // no A-sharp
    });

    test('preserves note durations and ids', () {
      final src = Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement(
              pitches: [Pitch.fromMidi(70)],
              duration: NoteDuration.half,
              id: 'e0',
            ),
          ]),
        ],
      );
      final out = respell(src, fifths: -1).measures.first.elements.first;
      expect(out, isA<NoteElement>());
      expect((out as NoteElement).duration.base, DurationBase.half);
      expect(out.id, 'e0');
    });
  });
}
