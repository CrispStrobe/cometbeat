// Note ornaments (trill / mordent / turn) — a per-note attribute on
// EditorElement (like articulations), emitted onto NoteElement.ornament and
// drawn above the note by crisp_notation's layout_marks.

import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Pitch _p(Step s, {int octave = 4}) => Pitch(s, octave: octave);
const _quarter = NoteDuration(DurationBase.quarter);

NoteElement _firstNote(ScoreDocument d) =>
    d.buildScore().measures.first.elements.first as NoteElement;

void main() {
  test('setting an ornament emits it onto the note', () {
    final d = ScoreDocument()..insertNote(_p(Step.c), _quarter);
    d.selectIndex(0);
    d.setOrnamentOfSelected(Ornament.trill);

    expect(d.elements.single.ornament, Ornament.trill);
    expect(_firstNote(d).ornament, Ornament.trill);
  });

  test('it applies to every selected note', () {
    final d = ScoreDocument()
      ..insertNote(_p(Step.c), _quarter)
      ..insertNote(_p(Step.d), _quarter);
    final ids = d.elements.map((e) => e.id).toList();
    d.selectByIds(ids); // both
    d.setOrnamentOfSelected(Ornament.mordent);
    expect(d.elements.every((e) => e.ornament == Ornament.mordent), isTrue);
  });

  test('clearing (null) removes it, and it is undoable', () {
    final d = ScoreDocument()..insertNote(_p(Step.c), _quarter);
    d.selectIndex(0);
    d.setOrnamentOfSelected(Ornament.turn);
    expect(d.elements.single.ornament, Ornament.turn);

    d.setOrnamentOfSelected(null);
    expect(d.elements.single.ornament, isNull);

    d.undo();
    expect(d.elements.single.ornament, Ornament.turn);
  });

  test('a rest never takes an ornament', () {
    final d = ScoreDocument()..insertRest(_quarter);
    d.selectIndex(0);
    d.setOrnamentOfSelected(Ornament.trill); // no selected NOTE
    expect(d.elements.single.ornament, isNull);
  });

  test('no ornament → the note carries none (nothing spurious)', () {
    final d = ScoreDocument()..insertNote(_p(Step.c), _quarter);
    expect(_firstNote(d).ornament, isNull);
  });

  test('paste carries the ornament onto the fresh copy', () {
    final d = ScoreDocument()..insertNote(_p(Step.c), _quarter);
    d.selectIndex(0);
    d.setOrnamentOfSelected(Ornament.trill);
    d.copySelection();
    d.paste();
    expect(d.length, 2);
    expect(d.elements.every((e) => e.ornament == Ornament.trill), isTrue);
  });

  test('save → reopen preserves the ornament', () {
    final src = ScoreDocument()..insertNote(_p(Step.c), _quarter);
    src.selectIndex(0);
    src.setOrnamentOfSelected(Ornament.mordent);

    final parsed = scoreFromMusicXml(scoreToMusicXml(src.buildScore()));
    final reopened = ScoreDocument()..loadScore(parsed);
    expect(reopened.elements.single.ornament, Ornament.mordent);
  });
}
