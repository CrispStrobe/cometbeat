// ScoreDocument — the editable model behind the Composition Workshop.
// Covers insert/rest/repitch/delete, multi-level undo/redo, exact bar-packing
// (including dotted notes), accidental-carrying pitches, and auto clef.

import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/features/workshop/model/score_document.dart';
import 'package:partitura/partitura.dart';

Pitch _p(Step step, {int alter = 0, int octave = 4}) =>
    Pitch(step, alter: alter, octave: octave);

const _quarter = NoteDuration(DurationBase.quarter);

void main() {
  test('inserts notes and packs bars per the time signature', () {
    final doc = ScoreDocument(); // 4/4
    for (var i = 0; i < 5; i++) {
      doc.insertNote(_p(Step.c), _quarter);
    }
    expect(doc.length, 5);
    expect(doc.barCount, 2, reason: '4 quarters fill a 4/4 bar');
  });

  test('a dotted half (3 beats) plus a quarter exactly fills a 4/4 bar', () {
    final doc = ScoreDocument(); // 4/4
    doc.insertNote(_p(Step.c), const NoteDuration(DurationBase.half, dots: 1));
    doc.insertNote(_p(Step.d), _quarter);
    expect(doc.barCount, 1, reason: 'dotted half (3) + quarter (1) = 4 beats');
  });

  test('undo/redo is multi-level and restores exact state', () {
    final doc = ScoreDocument();
    expect(doc.canUndo, isFalse);

    doc.insertNote(_p(Step.c), _quarter);
    doc.insertNote(_p(Step.d), _quarter);
    expect(doc.length, 2);

    doc.undo();
    expect(doc.length, 1);
    doc.undo();
    expect(doc.length, 0);
    expect(doc.canUndo, isFalse);

    doc.redo();
    doc.redo();
    expect(doc.length, 2);
    expect(doc.canRedo, isFalse);
  });

  test('a new command clears the redo stack', () {
    final doc = ScoreDocument();
    doc.insertNote(_p(Step.c), _quarter);
    doc.undo();
    expect(doc.canRedo, isTrue);
    doc.insertNote(_p(Step.e), _quarter);
    expect(doc.canRedo, isFalse);
    expect(doc.length, 1);
  });

  test('repitch affects the selected note, and is undoable', () {
    final doc = ScoreDocument();
    doc.insertNote(_p(Step.c), _quarter); // inserted note is auto-selected
    doc.repitchSelected(_p(Step.g));
    expect(doc.elements.single.pitch!.step, Step.g);
    doc.undo();
    expect(doc.elements.single.pitch!.step, Step.c);
  });

  test('a placed note keeps its accidental (alter)', () {
    final doc = ScoreDocument();
    doc.insertNote(_p(Step.f, alter: 1), _quarter); // F#
    final note = doc.buildScore().measures.first.elements.first as NoteElement;
    expect(note.pitches.single.alter, 1);
  });

  test('rests are elements and render as RestElement', () {
    final doc = ScoreDocument();
    doc.insertRest(_quarter);
    expect(doc.length, 1);
    expect(
      doc.buildScore().measures.first.elements.first,
      isA<RestElement>(),
    );
  });

  test('low material switches the clef to bass', () {
    final doc = ScoreDocument();
    expect(doc.clef, Clef.treble);
    doc.insertNote(_p(Step.c, octave: 2), _quarter); // C2, below G3
    expect(doc.clef, Clef.bass);
  });

  test('empty document renders a single whole-rest bar', () {
    final doc = ScoreDocument();
    expect(doc.isEmpty, isTrue);
    final score = doc.buildScore();
    expect(score.measures, hasLength(1));
    expect(score.measures.first.elements.first, isA<RestElement>());
  });

  test('insertion goes after the selection (caret), not the end', () {
    final doc = ScoreDocument();
    final a = doc.insertNote(_p(Step.c), _quarter); // [c]
    doc.insertNote(_p(Step.e), _quarter); // [c, e], e selected
    doc.toggleSelected(a); // select c
    doc.insertNote(_p(Step.d), _quarter); // insert after c → [c, d, e]
    expect(
      doc.elements.map((e) => e.pitch!.step).toList(),
      [Step.c, Step.d, Step.e],
    );
  });

  test('selectNext / selectPrev walk the element stream', () {
    final doc = ScoreDocument();
    doc.insertNote(_p(Step.c), _quarter);
    doc.insertNote(_p(Step.d), _quarter); // d selected (just inserted)
    doc.selectPrev();
    expect(doc.selected!.pitch!.step, Step.c);
    doc.selectNext();
    expect(doc.selected!.pitch!.step, Step.d);
    doc.selectNext(); // clamps at the end
    expect(doc.selected!.pitch!.step, Step.d);
  });

  test('transposeSelected nudges pitch, is undoable, and clamps', () {
    final doc = ScoreDocument();
    doc.insertNote(_p(Step.c), _quarter); // C4 = midi 60
    doc.transposeSelected(2); // D4
    expect(doc.selected!.pitch!.midiNumber, 62);
    doc.undo();
    expect(doc.selected!.pitch!.midiNumber, 60);
    // Way out of range is refused (no change, no snapshot).
    doc.transposeSelected(1000);
    expect(doc.selected!.pitch!.midiNumber, 60);
  });

  test('setAccidentalOfSelected keeps letter/octave, changes alter', () {
    final doc = ScoreDocument();
    doc.insertNote(_p(Step.f), _quarter);
    doc.setAccidentalOfSelected(1); // F#4
    expect(doc.selected!.pitch!.step, Step.f);
    expect(doc.selected!.pitch!.octave, 4);
    expect(doc.selected!.pitch!.alter, 1);
  });

  test('deleting selects the neighbour so editing continues', () {
    final doc = ScoreDocument();
    doc.insertNote(_p(Step.c), _quarter);
    final b = doc.insertNote(_p(Step.d), _quarter);
    doc.insertNote(_p(Step.e), _quarter); // [c, d, e]
    doc.toggleSelected(b); // select d
    doc.deleteSelected(); // → [c, e], e (former next) selected
    expect(doc.elements.map((e) => e.pitch!.step), [Step.c, Step.e]);
    expect(doc.selected!.pitch!.step, Step.e);
  });
}
