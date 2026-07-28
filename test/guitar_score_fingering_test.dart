// test/guitar_score_fingering_test.dart
//
// Guitar left-hand fingering. The tab arranger already chooses string and fret;
// this only decides WHICH FINGER, so the tests assert the finger rule and the
// hand's behaviour, not the fretting.

import 'package:comet_beat/core/notation/guitar_score_fingering.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A one-voice score of single notes with ids `e0`, `e1`, … — ids are required,
/// the same contract as the bowed side.
Score _score(List<int> midi) {
  var n = 0;
  return Score(
    clef: Clef.treble,
    measures: [
      Measure([
        for (final m in midi)
          NoteElement.note(
            Pitch.fromMidi(m),
            NoteDuration.quarter,
            id: 'e${n++}',
          ),
      ]),
    ],
  );
}

List<int?> _firstFingers(Map<String, List<int>> marks, int count) =>
    [for (var i = 0; i < count; i++) marks['e$i']?.first];

void main() {
  final guitar = Tuning.standardGuitar;

  group('the finger rule', () {
    test('an open string is finger 0, and needs no hand position', () {
      // E2 A2 D3 G3 B3 E4 — the six open strings.
      final marks = fingerGuitarScore(_score([40, 45, 50, 55, 59, 64]), guitar);
      expect(marks, isNotEmpty);
      expect(
        _firstFingers(marks, 6).every((f) => f == 0),
        isTrue,
        reason: 'every open string should be finger 0',
      );
    });

    test('one finger per fret, index at the bottom of the hand', () {
      // A chromatic run up the low E string from the 1st fret: F2 F#2 G2 G#2.
      final marks = fingerGuitarScore(_score([41, 42, 43, 44]), guitar);
      final fingers = _firstFingers(marks, 4);
      expect(
        fingers,
        [1, 2, 3, 4],
        reason: 'four consecutive frets under one hand = fingers 1,2,3,4',
      );
    });

    test('every finger is a real one — 0..4, never out of range', () {
      final marks = fingerGuitarScore(
        _score([40, 47, 55, 60, 64, 69, 72, 76]),
        guitar,
      );
      for (final fingers in marks.values) {
        for (final f in fingers) {
          expect(f, inInclusiveRange(0, kGuitarHandSpan));
        }
      }
    });
  });

  group('the hand', () {
    test('stays put while the notes still fit under it', () {
      // Frets 1..4 on one string: the hand is placed once and does not move, so
      // the digits climb rather than resetting to 1 on every note.
      final marks = fingerGuitarScore(_score([41, 42, 43, 44]), guitar);
      expect(_firstFingers(marks, 4), [1, 2, 3, 4]);
    });

    test('re-anchors when a note falls outside the span', () {
      // A jump far up the neck cannot be reached from the first position, so the
      // hand moves and the new note becomes an index finger again.
      final marks = fingerGuitarScore(_score([41, 42, 60]), guitar);
      final fingers = _firstFingers(marks, 3);
      expect(fingers[0], 1);
      expect(fingers[1], 2);
      expect(
        fingers[2],
        1,
        reason:
            'after re-anchoring, the lowest fretted note is the index again',
      );
    });
  });

  group('the score-level API', () {
    test('writes fingerings INTO the notes, so they survive and export', () {
      final score = _score([41, 42, 43]);
      final before = score.measures.first.elements
          .whereType<NoteElement>()
          .every((n) => n.fingerings.isEmpty);
      expect(before, isTrue);

      final fingered = scoreWithGuitarFingerings(score, guitar);
      final after = fingered.measures.first.elements.whereType<NoteElement>();
      expect(after.every((n) => n.fingerings.isNotEmpty), isTrue);
      // The original is untouched — callers get a copy, like the bowed side.
      expect(before, isTrue);
    });

    test(
        'a score whose notes have no ids yields nothing, and says so by '
        'returning an empty map rather than guessing', () {
      final anon = Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement.note(Pitch.fromMidi(41), NoteDuration.quarter),
          ]),
        ],
      );
      expect(fingerGuitarScore(anon, guitar), isEmpty);
      // …and the score-level call is then a no-op rather than a broken copy.
      expect(scoreWithGuitarFingerings(anon, guitar), same(anon));
    });

    test('an empty score is handled without throwing', () {
      expect(fingerGuitarScore(_score(const []), guitar), isEmpty);
    });
  });
}
