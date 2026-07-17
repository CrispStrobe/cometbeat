// ScoreDocument — the editable model behind the Composition Workshop.
// Covers insert/rest/repitch/delete, multi-level undo/redo, exact bar-packing
// (including dotted notes), accidental-carrying pitches, and auto clef.

import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('selectNextOfStep jumps to the next note on that pitch, wrapping', () {
    final doc = ScoreDocument();
    final ids = [
      doc.insertNote(_p(Step.c), _quarter), // 0
      doc.insertNote(_p(Step.d), _quarter), // 1
      doc.insertNote(_p(Step.e, alter: 1), _quarter), // 2 — E♯ still "E"
      doc.insertNote(_p(Step.d), _quarter), // 3
    ];
    doc.selectIndex(0); // on the first C

    doc.selectNextOfStep(Step.d);
    expect(doc.selectedId, ids[1], reason: 'jumps to the first D');
    doc.selectNextOfStep(Step.d);
    expect(doc.selectedId, ids[3], reason: 'then the next D');
    doc.selectNextOfStep(Step.d);
    expect(doc.selectedId, ids[1], reason: 'wraps around');

    doc.selectNextOfStep(Step.e);
    expect(doc.selectedId, ids[2], reason: 'accidental ignored (E♯ counts)');

    doc.selectIndex(0);
    doc.selectNextOfStep(Step.b); // no B present
    expect(doc.selectedId, ids[0], reason: 'no match → selection unchanged');
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

  test('clef is an explicit setting (no auto-flip) and is undoable', () {
    final doc = ScoreDocument();
    expect(doc.clef, Clef.treble);
    doc.insertNote(_p(Step.c, octave: 2), _quarter); // low C — no auto-flip
    expect(doc.clef, Clef.treble);
    doc.setClef(Clef.bass);
    expect(doc.clef, Clef.bass);
    doc.undo();
    expect(doc.clef, Clef.treble);
  });

  test('toggling an articulation adds/removes it and is undoable', () {
    final doc = ScoreDocument();
    doc.insertNote(_p(Step.c), _quarter); // auto-selected
    doc.toggleArticulationOfSelected(Articulation.staccato);
    expect(doc.elements.single.articulations, contains(Articulation.staccato));
    doc.toggleArticulationOfSelected(Articulation.staccato); // off again
    expect(doc.elements.single.articulations, isEmpty);
    doc.undo(); // back to staccato
    expect(doc.elements.single.articulations, contains(Articulation.staccato));
  });

  test('tie toggles across the whole selection, and rests are skipped', () {
    final doc = ScoreDocument();
    doc.insertNote(_p(Step.c), _quarter);
    doc.insertRest(_quarter);
    doc.insertNote(_p(Step.d), _quarter); // d selected
    doc.selectPrev(); // rest
    doc.selectPrev(); // c
    doc.extendRight(); // c..rest
    doc.extendRight(); // c..d (whole run)
    doc.toggleTieOfSelected();
    // Both notes tied; the rest is untouched.
    expect(doc.elements[0].tieToNext, isTrue);
    expect(doc.elements[2].tieToNext, isTrue);
    expect(doc.elements[1].tieToNext, isFalse);
  });

  test('an articulation survives export to MusicXML', () {
    final doc = ScoreDocument();
    doc.insertNote(_p(Step.c), _quarter);
    doc.toggleArticulationOfSelected(Articulation.accent);
    final note = doc.buildScore().measures.first.elements.first as NoteElement;
    expect(note.articulations, contains(Articulation.accent));
  });

  test('moveById drags a note to a new pitch, keeping its accidental', () {
    final doc = ScoreDocument();
    final id = doc.insertNote(_p(Step.c, alter: 1), _quarter); // C#4
    final target = StaffTarget(
      staffPosition: _p(Step.e).staffPosition(Clef.treble),
      measureIndex: 0,
    );
    final moved = doc.moveById(id, target);
    expect(moved, isNotNull);
    expect(doc.elements.single.pitch!.step, Step.e);
    expect(doc.elements.single.pitch!.alter, 1); // accidental preserved
    doc.undo();
    expect(doc.elements.single.pitch!.step, Step.c);
  });

  test('a dynamic on a note emits a Score dynamic marking (undoable)', () {
    final doc = ScoreDocument();
    final id = doc.insertNote(_p(Step.c), _quarter);
    doc.setDynamicOfSelected(DynamicLevel.mf);
    expect(doc.elements.single.dynamic, DynamicLevel.mf);
    final score = doc.buildScore();
    expect(score.dynamics, hasLength(1));
    expect(score.dynamics.first.elementId, id);
    expect(score.dynamics.first.level, DynamicLevel.mf);
    // Clearing removes the marking.
    doc.setDynamicOfSelected(null);
    expect(doc.elements.single.dynamic, isNull);
    expect(doc.buildScore().dynamics, isEmpty);
    // Undo brings the marking back.
    doc.undo();
    expect(doc.elements.single.dynamic, DynamicLevel.mf);
  });

  test('loadScore imports a parsed Score and is undoable', () {
    final src = ScoreDocument();
    src.insertNote(_p(Step.c), _quarter);
    src.insertNote(_p(Step.e), const NoteDuration(DurationBase.half));
    // Round-trip through MusicXML, as the "open file" flow does.
    final parsed = scoreFromMusicXml(scoreToMusicXml(src.buildScore()));

    final doc = ScoreDocument();
    doc.loadScore(parsed);
    expect(doc.length, 2);
    expect(doc.elements.map((e) => e.pitch!.step), [Step.c, Step.e]);
    expect(doc.elements[1].duration.base, DurationBase.half);

    doc.undo();
    expect(doc.isEmpty, isTrue);
  });

  test('buildGrandStaff splits the line across both clefs, bars aligned', () {
    final doc = ScoreDocument();
    doc.insertNote(_p(Step.g), _quarter); // G4 (midi 67) → treble
    doc.insertNote(_p(Step.c, octave: 3), _quarter); // C3 (midi 48) → bass
    final gs = doc.buildGrandStaff();
    final upper = gs.upper.measures.expand((m) => m.elements).toList();
    final lower = gs.lower.measures.expand((m) => m.elements).toList();
    // Both staves carry the same number of events (aligned time grid).
    expect(upper.length, 2);
    expect(lower.length, 2);
    expect(upper[0], isA<NoteElement>()); // G4 on the treble staff
    expect(upper[1], isA<RestElement>()); // filler while the bass note sounds
    expect(lower[0], isA<RestElement>());
    expect(lower[1], isA<NoteElement>()); // C3 on the bass staff
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

  test('extendRight grows the selection into a range', () {
    final doc = ScoreDocument();
    doc.insertNote(_p(Step.c), _quarter);
    doc.insertNote(_p(Step.d), _quarter);
    doc.insertNote(_p(Step.e), _quarter); // e selected (index 2)
    doc.selectPrev(); // d
    doc.selectPrev(); // c
    expect(doc.hasRange, isFalse);
    doc.extendRight(); // c..d
    expect(doc.hasRange, isTrue);
    expect(doc.selectedIds.length, 2);
    expect(
      doc.selectedElements.map((e) => e.pitch!.step),
      [Step.c, Step.d],
    );
  });

  test('transpose and delete operate over the whole range', () {
    final doc = ScoreDocument();
    for (final s in [Step.c, Step.d, Step.e]) {
      doc.insertNote(_p(s), _quarter);
    }
    doc.selectPrev(); // d (e was selected after the last insert)
    doc.extendRight(); // d..e
    doc.transposeSelected(1); // both up a semitone
    expect(doc.elements[1].pitch!.midiNumber, _p(Step.d).midiNumber + 1);
    expect(doc.elements[2].pitch!.midiNumber, _p(Step.e).midiNumber + 1);
    doc.deleteSelected(); // removes d..e
    expect(doc.elements.map((e) => e.pitch!.step), [Step.c]);
  });

  test('copy + paste duplicates the range with fresh ids', () {
    final doc = ScoreDocument();
    doc.insertNote(_p(Step.c), _quarter);
    doc.insertNote(_p(Step.d), _quarter); // [c, d], d selected
    doc.selectPrev(); // c
    doc.extendRight(); // c..d
    doc.copySelection();
    doc.paste(); // → [c, d, c, d], the pasted c..d selected
    expect(
      doc.elements.map((e) => e.pitch!.step),
      [Step.c, Step.d, Step.c, Step.d],
    );
    expect(doc.selectedIds.length, 2);
    // Ids are unique (no duplicates from the paste).
    final ids = doc.elements.map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('cut removes the range and pastes it back elsewhere', () {
    final doc = ScoreDocument();
    for (final s in [Step.c, Step.d, Step.e]) {
      doc.insertNote(_p(s), _quarter);
    }
    doc.selectPrev(); // d
    doc.selectPrev(); // c (single-selected)
    doc.cutSelection(); // [d, e], clipboard = [c]
    expect(doc.elements.map((e) => e.pitch!.step), [Step.d, Step.e]);
    doc.toggleSelected(doc.elements[1].id); // select e
    doc.paste(); // insert c after e → [d, e, c]
    expect(doc.elements.map((e) => e.pitch!.step), [Step.d, Step.e, Step.c]);
  });

  test('moveSelectionRight reorders the selected block', () {
    final doc = ScoreDocument();
    for (final s in [Step.c, Step.d, Step.e]) {
      doc.insertNote(_p(s), _quarter);
    }
    doc.toggleSelected(doc.elements[0].id); // select c (index 0)
    doc.moveSelectionRight(); // c swaps past d → [d, c, e]
    expect(doc.elements.map((e) => e.pitch!.step), [Step.d, Step.c, Step.e]);
    expect(doc.selected!.pitch!.step, Step.c);
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

  // Save writes the document out and Open reads it back, so loadScore must be
  // the inverse of buildScore for everything an EditorElement can hold. It
  // wasn't: it kept only pitches.first and dropped ties, articulations,
  // dynamics and the pickup — i.e. save → reopen silently destroyed work.
  group('save → reopen is lossless', () {
    // A document exercising every feature the flat element stream can carry.
    ScoreDocument rich() {
      final doc = ScoreDocument()
        ..setTimeSignature(const TimeSignature(3, 4))
        ..setKeySignature(const KeySignature(-2))
        ..setClef(Clef.bass)
        ..insertNote(_p(Step.c, octave: 3), _quarter)
        ..insertNote(_p(Step.e, alter: -1, octave: 3), _quarter)
        ..insertRest(_quarter)
        ..insertNote(
          _p(Step.g, octave: 3),
          const NoteDuration(DurationBase.half),
        );
      // A chord on element 0, plus a tie, an articulation and a dynamic.
      doc.selectIndex(0);
      doc.addPitchToSelected(_p(Step.e, octave: 3));
      doc.addPitchToSelected(_p(Step.g, octave: 3));
      doc.toggleArticulationOfSelected(Articulation.staccato);
      doc.setDynamicOfSelected(DynamicLevel.pp);
      doc.selectIndex(1);
      doc.toggleTieOfSelected();
      return doc;
    }

    void expectSame(ScoreDocument a, ScoreDocument b) {
      expect(b.length, a.length, reason: 'element count');
      expect(b.clef, a.clef);
      expect(b.keySignature, a.keySignature);
      expect(b.timeSignature, a.timeSignature);
      for (var i = 0; i < a.length; i++) {
        final x = a.elements[i], y = b.elements[i];
        expect(
          y.pitches.map((p) => p.midiNumber),
          x.pitches.map((p) => p.midiNumber),
          reason: 'element $i pitches (chords must survive)',
        );
        expect(
          y.duration.toFraction(),
          x.duration.toFraction(),
          reason: 'element $i duration',
        );
        expect(y.articulations, x.articulations, reason: 'element $i artic');
        expect(y.tieToNext, x.tieToNext, reason: 'element $i tie');
        expect(y.dynamic, x.dynamic, reason: 'element $i dynamic');
      }
    }

    test('buildScore → loadScore preserves chords, ties, artics, dynamics', () {
      final src = rich();
      final reopened = ScoreDocument()..loadScore(src.buildScore());
      expectSame(src, reopened);
    });

    test('a chord survives (it used to collapse to its first pitch)', () {
      final src = ScoreDocument()..insertNote(_p(Step.c), _quarter);
      src.selectIndex(0);
      src.addPitchToSelected(_p(Step.e));
      src.addPitchToSelected(_p(Step.g));
      expect(src.elements.single.pitches, hasLength(3));

      final reopened = ScoreDocument()..loadScore(src.buildScore());
      expect(
        reopened.elements.single.pitches,
        hasLength(3),
        reason: 'a chord must not collapse on reopen',
      );
    });

    test('the pickup survives', () {
      final src = ScoreDocument()
        ..setPickup(const NoteDuration(DurationBase.quarter))
        ..insertNote(_p(Step.g), _quarter)
        ..insertNote(_p(Step.c), _quarter)
        ..insertNote(_p(Step.d), _quarter)
        ..insertNote(_p(Step.e), _quarter);
      expect(src.buildScore().measures.first.pickup, isTrue);

      final reopened = ScoreDocument()..loadScore(src.buildScore());
      expect(reopened.pickup?.toFraction(), src.pickup?.toFraction());
      expect(
        reopened.buildScore().measures.first.pickup,
        isTrue,
        reason: 'the anacrusis must still engrave as a short opening bar',
      );
    });

    test('a score with no pickup does not gain one', () {
      final src = ScoreDocument()..insertNote(_p(Step.g), _quarter);
      final reopened = ScoreDocument()..loadScore(src.buildScore());
      expect(reopened.pickup, isNull);
    });

    test('slurs, hairpins and lyrics still re-anchor', () {
      final src = ScoreDocument()
        ..insertNote(_p(Step.c), _quarter)
        ..insertNote(_p(Step.e), _quarter);
      src.selectIndex(0);
      src.extendRight();
      src.slurSelected();
      src.hairpinSelected(HairpinType.crescendo);
      src.selectIndex(0);
      src.setLyricFor(src.elements.first.id, 'la');

      final reopened = ScoreDocument()..loadScore(src.buildScore());
      final out = reopened.buildScore();
      expect(out.slurs, hasLength(1));
      expect(out.hairpins, hasLength(1));
      expect(out.lyrics.map((l) => l.text), ['la']);
    });

    // The path the app actually uses: Save writes MusicXML into the Song Book,
    // Open parses it back. Anything the interchange drops is lost for real,
    // regardless of how faithful loadScore is.
    test('through MusicXML — the real Save → Open path', () {
      final src = rich();
      final parsed = scoreFromMusicXml(scoreToMusicXml(src.buildScore()));
      final reopened = ScoreDocument()..loadScore(parsed);
      expectSame(src, reopened);
    });
  });
}
