// grandStaffFromScore — splits a single-staff Score into a treble+bass grand
// staff (each note at/above middle C on top, the rest on the bass staff, a chord
// split per-note), with a matching rest on the other staff so the bars align.

import 'package:comet_beat/features/workshop/model/score_document.dart'
    show grandStaffFromScore;
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _midis(Score s) => [
      for (final m in s.measures)
        for (final e in m.elements)
          if (e is NoteElement) ...e.pitches.map((p) => p.midiNumber),
    ];

int _rests(Score s) => [
      for (final m in s.measures)
        for (final e in m.elements)
          if (e is RestElement) e,
    ].length;

void main() {
  test('splits notes across treble/bass at middle C, keeping the bars aligned',
      () {
    // One 4/4 bar: a high note (C5=72), a low note (E2=40), a chord spanning the
    // split (C3=48 + C5=72), and a rest.
    final score = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [
        Measure([
          NoteElement.note(
            const Pitch(Step.c, octave: 5),
            NoteDuration.quarter,
          ),
          NoteElement.note(
            const Pitch(Step.e, octave: 2),
            NoteDuration.quarter,
          ),
          const NoteElement(
            pitches: [
              Pitch(Step.c, octave: 3),
              Pitch(Step.c, octave: 5),
            ],
            duration: NoteDuration.quarter,
          ),
          const RestElement(NoteDuration.quarter),
        ]),
      ],
    );

    final gs = grandStaffFromScore(score);

    // Two clefs, same bar grid.
    expect(gs.upper.clef, Clef.treble);
    expect(gs.lower.clef, Clef.bass);
    expect(gs.upper.measures.length, gs.lower.measures.length);

    // Treble keeps the two ≥60 pitches (C5 + the chord's C5); bass keeps the two
    // below (E2 + the chord's C3).
    expect(_midis(gs.upper)..sort(), [72, 72]);
    expect(_midis(gs.lower)..sort(), [40, 48]);

    // Each staff has a rest wherever the other has the only note, plus the shared
    // rest — so both staves stay bar-aligned.
    expect(_rests(gs.upper), 2); // low note position + the shared rest
    expect(_rests(gs.lower), 2); // high note position + the shared rest
  });

  test('a purely high line leaves the bass staff resting', () {
    final score = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [
        Measure([
          NoteElement.note(const Pitch(Step.g), NoteDuration.half), // G4
          NoteElement.note(const Pitch(Step.a), NoteDuration.half), // A4
        ]),
      ],
    );
    final gs = grandStaffFromScore(score);
    expect(_midis(gs.upper), isNotEmpty);
    expect(_midis(gs.lower), isEmpty); // all notes went to the treble staff
  });
}
