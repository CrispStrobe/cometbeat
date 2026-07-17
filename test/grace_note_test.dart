// Grace notes — a per-note attribute on EditorElement (like ornaments): a LIST
// of pitches plus a GraceStyle (acciaccatura/appoggiatura), emitted onto
// NoteElement.graceNotes/graceStyle and drawn as small notes to the left by
// crisp_notation's layout. Grace notes have zero bar duration, so reflow ignores
// them for packing — they never affect bar capacity.

import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Pitch _p(Step s, {int octave = 4}) => Pitch(s, octave: octave);
const _quarter = NoteDuration(DurationBase.quarter);

NoteElement _firstNote(ScoreDocument d) =>
    d.buildScore().measures.first.elements.first as NoteElement;

void main() {
  test('setting grace notes emits them onto the note', () {
    final d = ScoreDocument()..insertNote(_p(Step.c), _quarter);
    d.selectIndex(0);
    d.setGraceNotesOfSelected([_p(Step.b, octave: 3), _p(Step.d)]);

    expect(d.elements.single.graceNotes, [_p(Step.b, octave: 3), _p(Step.d)]);
    expect(_firstNote(d).graceNotes, [_p(Step.b, octave: 3), _p(Step.d)]);
  });

  test('the style is carried through to the note', () {
    final d = ScoreDocument()..insertNote(_p(Step.c), _quarter);
    d.selectIndex(0);
    d.setGraceNotesOfSelected([_p(Step.d)], style: GraceStyle.appoggiatura);
    expect(d.elements.single.graceStyle, GraceStyle.appoggiatura);
    expect(_firstNote(d).graceStyle, GraceStyle.appoggiatura);
  });

  test('it applies to every selected note', () {
    final d = ScoreDocument()
      ..insertNote(_p(Step.c), _quarter)
      ..insertNote(_p(Step.d), _quarter);
    final ids = d.elements.map((e) => e.id).toList();
    d.selectByIds(ids); // both
    d.setGraceNotesOfSelected([_p(Step.e)]);
    expect(
      d.elements.every((e) => e.graceNotes.length == 1),
      isTrue,
    );
  });

  test('clearing (empty list) removes them, and it is undoable', () {
    final d = ScoreDocument()..insertNote(_p(Step.c), _quarter);
    d.selectIndex(0);
    d.setGraceNotesOfSelected([_p(Step.d)]);
    expect(d.elements.single.graceNotes, isNotEmpty);

    d.setGraceNotesOfSelected(const []);
    expect(d.elements.single.graceNotes, isEmpty);

    d.undo();
    expect(d.elements.single.graceNotes, [_p(Step.d)]);
  });

  test('grace notes do not change bar packing (zero duration)', () {
    final d = ScoreDocument(); // 4/4 → 4 quarters per bar
    for (var i = 0; i < 4; i++) {
      d.insertNote(_p(Step.c), _quarter);
    }
    expect(d.barCount, 1, reason: 'four quarters fill exactly one bar');

    d.selectIndex(0);
    d.setGraceNotesOfSelected([_p(Step.b, octave: 3), _p(Step.d), _p(Step.e)]);
    expect(
      d.barCount,
      1,
      reason: 'grace notes carry zero bar duration, so packing is unchanged',
    );
  });

  test('a rest never takes grace notes', () {
    final d = ScoreDocument()..insertRest(_quarter);
    d.selectIndex(0);
    d.setGraceNotesOfSelected([_p(Step.c)]); // no selected NOTE
    expect(d.elements.single.graceNotes, isEmpty);
  });

  test('no grace notes → the note carries none (nothing spurious)', () {
    final d = ScoreDocument()..insertNote(_p(Step.c), _quarter);
    expect(_firstNote(d).graceNotes, isEmpty);
  });

  test('paste carries the grace notes onto the fresh copy', () {
    final d = ScoreDocument()..insertNote(_p(Step.c), _quarter);
    d.selectIndex(0);
    d.setGraceNotesOfSelected([_p(Step.d)], style: GraceStyle.appoggiatura);
    d.copySelection();
    d.paste();
    expect(d.length, 2);
    expect(
      d.elements.every(
        (e) =>
            e.graceNotes.length == 1 && e.graceStyle == GraceStyle.appoggiatura,
      ),
      isTrue,
    );
  });

  test('save → reopen preserves grace notes and their style', () {
    final src = ScoreDocument()..insertNote(_p(Step.c), _quarter);
    src.selectIndex(0);
    src.setGraceNotesOfSelected(
      [_p(Step.b, octave: 3), _p(Step.d)],
      style: GraceStyle.appoggiatura,
    );

    final parsed = scoreFromMusicXml(scoreToMusicXml(src.buildScore()));
    final reopened = ScoreDocument()..loadScore(parsed);
    expect(
      reopened.elements.single.graceNotes,
      [_p(Step.b, octave: 3), _p(Step.d)],
    );
    expect(reopened.elements.single.graceStyle, GraceStyle.appoggiatura);
  });
}
