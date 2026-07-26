// test/bowed_score_fingering_test.dart
//
// The score-level entry point: a notated cello line in, an id-keyed fingering
// table out.

import 'package:comet_beat/core/notation/bowed_arranger.dart';
import 'package:comet_beat/core/notation/bowed_score_fingering.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Score _cScale() {
  // C2 D2 E2 F2 | G2 A2 B2 C3 — the first-position C major scale across the C
  // and G strings, with ids so the fingerings have something to key on.
  const pitches = [
    Pitch(Step.c, octave: 2),
    Pitch(Step.d, octave: 2),
    Pitch(Step.e, octave: 2),
    Pitch(Step.f, octave: 2),
    Pitch(Step.g, octave: 2),
    Pitch(Step.a, octave: 2),
    Pitch(Step.b, octave: 2),
    Pitch(Step.c, octave: 3),
  ];
  var i = 0;
  return Score(
    clef: Clef.bass,
    measures: [
      for (final half in [pitches.sublist(0, 4), pitches.sublist(4)])
        Measure([
          for (final p in half)
            NoteElement.note(p, NoteDuration.quarter, id: 'e${i++}'),
        ]),
    ],
  );
}

void main() {
  test('every notated note gets a fingering, keyed by its id', () {
    final table = fingerBowedScore(_cScale(), skill: BowedSkill.firstPosition);
    expect(table.length, 8);
    expect(table.keys.toSet(), {for (var i = 0; i < 8; i++) 'e$i'});
    expect(table.values.every((v) => v.length == 1), isTrue);
  });

  test('the scale fingers as the method book has it', () {
    final table = fingerBowedScore(_cScale(), skill: BowedSkill.firstPosition);
    // C string 0-1-3-4, then the same shape on the G string.
    expect(
      [for (var i = 0; i < 8; i++) table['e$i']!.single.finger],
      [0, 1, 3, 4, 0, 1, 3, 4],
    );
    expect(
      [for (var i = 0; i < 8; i++) table['e$i']!.single.roman],
      ['IV', 'IV', 'IV', 'IV', 'III', 'III', 'III', 'III'],
    );
  });

  test('marks come out in the notation layer own vocabulary', () {
    final digits =
        bowedFingeringDigits(_cScale(), skill: BowedSkill.firstPosition);
    expect(digits['e0'], [0]);
    expect(digits['e3'], [4]);
  });

  test('a thumb is exactly the value crisp_notation draws as T', () {
    // High enough that only thumb position reaches it. No translation step: the
    // arranger's thumb IS the notation layer's thumb, so the map can go straight
    // to StaffView.extraFingerings.
    final score = Score(
      clef: Clef.bass,
      measures: [
        Measure([
          // A4 — an octave and a fifth above the open A, so only the thumb
          // reaches it (Pitch defaults to octave 4).
          NoteElement.note(
            const Pitch(Step.a),
            NoteDuration.quarter,
            id: 'high',
          ),
        ]),
      ],
    );
    final digits = bowedFingeringDigits(score, skill: BowedSkill.advanced);
    expect(digits['high'], [kFingeringThumb]);
    expect(kThumb, kFingeringThumb);
  });

  test('notes without ids are skipped rather than mis-keyed', () {
    final score = Score(
      clef: Clef.bass,
      measures: [
        Measure([
          NoteElement.note(
            const Pitch(Step.d, octave: 3),
            NoteDuration.quarter,
          ), // no id
          NoteElement.note(
            const Pitch(Step.e, octave: 3),
            NoteDuration.quarter,
            id: 'kept',
          ),
        ]),
      ],
    );
    final table = fingerBowedScore(score, skill: BowedSkill.firstPosition);
    expect(table.keys, ['kept']);
  });

  test('a rest frees the hand instead of pinning it', () {
    final score = Score(
      clef: Clef.bass,
      measures: [
        Measure([
          NoteElement.note(
            const Pitch(Step.f, octave: 2, alter: 1),
            NoteDuration.quarter,
            id: 'a',
          ),
          const RestElement(NoteDuration.quarter),
          NoteElement.note(
            const Pitch(Step.f, octave: 2, alter: 1),
            NoteDuration.quarter,
            id: 'b',
          ),
        ]),
      ],
    );
    final table = fingerBowedScore(score, skill: BowedSkill.neckPositions);
    expect(table['a']!.single.anchor, table['b']!.single.anchor);
  });

  group('written into the model (for files, not screens)', () {
    test('fingerings land on the notes and reach MusicXML', () {
      final fingered = scoreWithBowedFingerings(
        _cScale(),
        skill: BowedSkill.firstPosition,
      );
      final notes = fingered.measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .toList();
      expect(
        notes.map((n) => n.fingerings.single).toList(),
        [0, 1, 3, 4, 0, 1, 3, 4],
      );
      // The point: a file can carry them. The display channel cannot.
      final xml = scoreToMusicXml(fingered);
      expect(xml, contains('<fingering>4</fingering>'));
      expect(scoreToMusicXml(_cScale()), isNot(contains('<fingering>')));
    });

    test('the source score is left alone', () {
      final original = _cScale();
      final before = scoreToMusicXml(original);
      scoreWithBowedFingerings(original, skill: BowedSkill.firstPosition);
      expect(scoreToMusicXml(original), before);
      expect(
        original.measures
            .expand((m) => m.elements)
            .whereType<NoteElement>()
            .every((n) => n.fingerings.isEmpty),
        isTrue,
      );
    });

    test('everything else about the score survives the copy', () {
      final original = _cScale();
      final fingered = scoreWithBowedFingerings(
        original,
        skill: BowedSkill.firstPosition,
      );
      expect(fingered.clef, original.clef);
      expect(fingered.measures.length, original.measures.length);
      // Strip the fingerings back off and the score is the one we started with —
      // which is the check that no other field was dropped in the rebuild.
      final stripped = fingered.copyWith(
        measures: [
          for (final m in fingered.measures)
            m.copyWith(
              elements: [
                for (final e in m.elements)
                  e is NoteElement ? e.copyWith(fingerings: const []) : e,
              ],
            ),
        ],
      );
      expect(stripped, original);
    });
  });

  group('string indications', () {
    /// E3-F3 on the D string, then B2-C3 on the G string: the crossing happens
    /// between two STOPPED notes, which is exactly when the reader cannot infer
    /// the string from the pitch alone.
    Score crossing() {
      var i = 0;
      return Score(
        clef: Clef.bass,
        measures: [
          Measure([
            for (final p in const [
              Pitch(Step.e, octave: 3),
              Pitch(Step.f, octave: 3),
              Pitch(Step.b, octave: 2),
              Pitch(Step.c, octave: 3),
            ])
              NoteElement.note(p, NoteDuration.quarter, id: 'x${i++}'),
          ]),
        ],
      );
    }

    test('marks where the string is not inferable: the start, and the crossing',
        () {
      final marks =
          bowedStringMarks(crossing(), skill: BowedSkill.firstPosition);
      // Two marks for four notes. The opening E3 is marked because a piece has
      // to say where the hand starts — E3 lives on the D string in first
      // position and on the G string higher up, and the pitch does not choose.
      // Then the crossing to the G string. The two notes that merely continue a
      // run get nothing.
      expect(marks, {'x0': 'II', 'x2': 'III'});
    });

    test('a scale whose crossings land on open strings needs no marks at all',
        () {
      // C2 D2 E2 F2 | G2 A2 B2 C3 changes string twice, but each change lands on
      // an open string, and an open pitch names its own string. Marking those
      // would be clutter, so the right answer here is silence.
      expect(
        bowedStringMarks(_cScale(), skill: BowedSkill.firstPosition),
        isEmpty,
      );
    });

    test('an open string is never annotated', () {
      final score = crossing();
      final table = fingerBowedScore(score, skill: BowedSkill.firstPosition);
      final marks = bowedStringMarks(score, skill: BowedSkill.firstPosition);
      for (final id in marks.keys) {
        expect(table[id]!.single.isOpen, isFalse, reason: id);
      }
    });

    test('the copy carries them as annotations, and MusicXML keeps them', () {
      final plain =
          scoreWithBowedFingerings(crossing(), skill: BowedSkill.firstPosition);
      final marked = scoreWithBowedFingerings(
        crossing(),
        skill: BowedSkill.firstPosition,
        markStrings: true,
      );
      expect(plain.annotations, isEmpty);
      expect(marked.annotations.map((a) => a.text), ['II', 'III']);
      expect(scoreToMusicXml(marked), contains('III'));
    });

    test('the source score gains nothing', () {
      final original = crossing();
      scoreWithBowedFingerings(
        original,
        skill: BowedSkill.firstPosition,
        markStrings: true,
      );
      expect(original.annotations, isEmpty);
    });
  });
}
