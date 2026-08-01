// Notation → the Loop Studio's 2-bar grid.
//
// Loop Studio was the only authoring surface with no route to the music
// library, because its document is a fixed 16-step grid rather than a score and
// nothing decided what a 40-bar piece means as a loop. These pin that decision,
// especially the two rules that are easy to get subtly wrong and impossible to
// notice afterwards: which part is the melody, and what a tie means.

import 'package:comet_beat/core/interop/score_to_loop.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _quarter = NoteDuration(DurationBase.quarter);
const _half = NoteDuration(DurationBase.half);
const _eighth = NoteDuration(DurationBase.eighth);

Score _part(List<MusicElement> elements, {Clef clef = Clef.treble}) =>
    Score(clef: clef, measures: [Measure(elements)]);

void main() {
  group('melodyPartOf', () {
    test('picks by register, NOT by note count', () {
      // The trap this exists for: a broken-chord accompaniment routinely has
      // more notes than the tune it accompanies, so counting notes fingerprints
      // the arpeggio. Here the low part has 8 notes and the high part has 2.
      final accompaniment = _part([
        for (var i = 0; i < 8; i++)
          NoteElement.note(const Pitch(Step.c, octave: 3), _eighth),
      ]);
      final tune = _part([
        NoteElement.note(const Pitch(Step.g, octave: 5), _half),
        NoteElement.note(const Pitch(Step.e, octave: 5), _half),
      ]);
      final picked = melodyPartOf(MultiPartScore([accompaniment, tune]));
      expect(picked, same(tune));
    });

    test('one high note cannot carry a low part', () {
      // Mean, not max: a single high grace-ish note in a bass line must not
      // make it look like the melody.
      final bass = _part([
        NoteElement.note(const Pitch(Step.c, octave: 6), _eighth),
        for (var i = 0; i < 7; i++)
          NoteElement.note(const Pitch(Step.c, octave: 2), _eighth),
      ]);
      final tune = _part([
        for (var i = 0; i < 4; i++)
          NoteElement.note(const Pitch(Step.a, octave: 5), _quarter),
      ]);
      expect(melodyPartOf(MultiPartScore([bass, tune])), same(tune));
    });

    test('a part with no notes is never chosen', () {
      final empty = _part([const RestElement(_quarter)]);
      final tune = _part([NoteElement.note(const Pitch(Step.c), _quarter)]);
      expect(melodyPartOf(MultiPartScore([empty, tune])), same(tune));
    });

    test('a wholly empty score yields null', () {
      expect(
        melodyPartOf(
          MultiPartScore([
            _part([const RestElement(_quarter)]),
          ]),
        ),
        isNull,
      );
    });
  });

  group('midiRowsFromScore', () {
    test('quarters land on every other eighth step', () {
      final walked = midiRowsFromScore(
        _part([
          NoteElement.note(const Pitch(Step.c), _quarter),
          NoteElement.note(const Pitch(Step.d), _quarter),
        ]),
      );
      expect(walked.rows[0], 60);
      expect(walked.rows[1], isNull, reason: 'the quarter rings through');
      expect(walked.rows[2], 62);
    });

    test('a tie does NOT re-strike — one long note, not two', () {
      // `tieToNext` is declared by the note BEFORE the continuation, so a walk
      // that forgets to carry it forward turns a tied half into two attacks.
      final walked = midiRowsFromScore(
        _part([
          const NoteElement(
            pitches: [Pitch(Step.c)],
            duration: _quarter,
            tieToNext: true,
          ),
          NoteElement.note(const Pitch(Step.c), _quarter),
        ]),
      );
      expect(walked.rows[0], 60);
      expect(
        walked.rows[2],
        isNull,
        reason: 'the tied half must not re-strike',
      );
    });

    test('a rest ends a tie', () {
      final walked = midiRowsFromScore(
        _part([
          const NoteElement(
            pitches: [Pitch(Step.c)],
            duration: _quarter,
            tieToNext: true,
          ),
          const RestElement(_quarter),
          NoteElement.note(const Pitch(Step.e), _quarter),
        ]),
      );
      expect(walked.rows[4], 64, reason: 'the note after a rest still strikes');
    });

    test('a chord keeps its top note and says so', () {
      final walked = midiRowsFromScore(
        _part([
          const NoteElement(
            pitches: [Pitch(Step.c), Pitch(Step.e), Pitch(Step.g)],
            duration: _quarter,
          ),
        ]),
      );
      expect(walked.rows[0], 67, reason: 'G4, the top of the C-major triad');
      expect(walked.report.chordsFlattened, isTrue);
    });

    test('a longer piece is windowed and reports it', () {
      final walked = midiRowsFromScore(
        _part([
          for (var i = 0; i < 40; i++)
            NoteElement.note(const Pitch(Step.c), _quarter),
        ]),
      );
      expect(walked.rows.length, 16);
      expect(walked.report.truncated, isTrue);
      expect(walked.report.totalSteps, 80);
    });

    test('a note finer than the grid is kept, not dropped', () {
      // Rounding a 32nd onto the grid is lossy; deleting it is worse. Whichever
      // we do must be reported rather than silent.
      final walked = midiRowsFromScore(
        _part([
          NoteElement.note(
            const Pitch(Step.c),
            const NoteDuration(DurationBase.thirtySecond),
          ),
        ]),
      );
      expect(walked.rows[0], 60);
      expect(walked.report.quantized, isTrue);
    });
  });

  group('loopCellsFromScore', () {
    test('cells always account for the whole 2-bar grid', () {
      final result = loopCellsFromScore(
        MultiPartScore([
          _part([
            NoteElement.note(const Pitch(Step.c), _quarter),
            NoteElement.note(const Pitch(Step.e), _quarter),
          ]),
        ]),
      );
      expect(result, isNotNull);
      expect(result!.cells.fold<int>(0, (a, c) => a + c.steps), 16);
      expect(result.cells.first.midis, [60]);
    });

    test('a silent score returns null rather than a silent track', () {
      expect(
        loopCellsFromScore(
          MultiPartScore([
            _part([const RestElement(_quarter)]),
          ]),
        ),
        isNull,
      );
    });
  });
}
