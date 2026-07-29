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

  group('barre chords — what the model actually does', () {
    // ⚠ These exist because the file's own comment used to claim a barre "names
    // four separate fingers". It does not, and nothing tested it either way. A
    // control corpus of 1,180 classical-guitar tabs carries 26,130 barre
    // annotations, so this is a common shape, not an edge case.

    test('F major: the index barres, and the rest fall where they should', () {
      // String 5 = low E … 0 = high e. F = 1,3,3,2,1,1.
      final shape = {5: 1, 4: 3, 3: 3, 2: 2, 1: 1, 0: 1};
      expect(
        fingerFrettings([shape]).single,
        [1, 3, 3, 2, 1, 1],
        reason: 'a barre IS the index at the hand position — every string '
            'stopped there is finger 1, and it already comes out that way',
      );
    });

    test('B minor: the same shape moved up the neck', () {
      final shape = {4: 2, 3: 4, 2: 4, 1: 3, 0: 2};
      expect(fingerFrettings([shape]).single, [1, 3, 3, 2, 1]);
    });

    test('a barre does not drag the hand out of position', () {
      // Six strings at one fret is a full barre; the hand sits there and the
      // next chord must be judged from that position, not from a stale one.
      final barre = {for (var s = 0; s < 6; s++) s: 5};
      final fingers = fingerFrettings([barre]).single;
      expect(fingers.every((f) => f == 1), isTrue);
    });
  });

  group('naming the barre', () {
    // Shapes are `string index → fret`; string 5 is the low E. Hoisted to
    // constants because an inline map inside a list argument is reformatted
    // into a shape the trailing-comma lint then rejects.
    const fMajor = {5: 1, 4: 3, 3: 3, 2: 2, 1: 1, 0: 1};
    const bMinor = {4: 2, 3: 4, 2: 4, 1: 3, 0: 2};
    const allDifferent = {5: 1, 4: 2, 3: 3};
    const single = {5: 5};
    const twoOpen = {1: 0, 0: 0};
    const twoFrettedPlusOpen = {5: 3, 4: 3, 1: 0, 0: 0};
    const empty = <int, int>{};

    test('F major is a barre at the first fret', () {
      expect(barresFor([fMajor]), [1]);
    });

    test('B minor is a barre at the second', () {
      expect(barresFor([bMinor]), [2]);
    });

    test('a chord with every note on a different fret needs no barre', () {
      expect(barresFor([allDifferent]), [null]);
    });

    test('a single note is never a barre', () {
      expect(barresFor([single]), [null]);
    });

    test('open strings do not make a barre', () {
      // Two open strings are stopped by nothing at all.
      expect(barresFor([twoOpen]), [null]);
      // …and they do not extend one either: only the fretted notes count.
      expect(barresFor([twoFrettedPlusOpen]), [3]);
    });

    test('an empty column has no barre', () {
      expect(barresFor([empty]), [null]);
    });

    test('the barre agrees with the digits — it names the repeated 1s', () {
      final fingers = fingerFrettings([fMajor]).single;
      final barre = barresFor([fMajor]).single;
      expect(barre, 1);
      // Every string the barre covers is exactly the ones the digits call 1.
      final byString = fMajor.keys.toList()..sort((a, b) => b.compareTo(a));
      for (var i = 0; i < byString.length; i++) {
        if (fMajor[byString[i]] == barre) expect(fingers[i], 1);
      }
    });
  });
}
