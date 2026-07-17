// ScoreDocument — deeper coverage: bar-packing across meters, clipboard/range
// invariants, grand-staff boundaries, ornament ranges, and format round-trips
// (compose → export → re-import). Complements score_document_test.dart.

import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Pitch _p(Step step, {int alter = 0, int octave = 4}) =>
    Pitch(step, alter: alter, octave: octave);

const _q = NoteDuration(DurationBase.quarter);
const _h = NoteDuration(DurationBase.half);
const _e = NoteDuration(DurationBase.eighth);

/// The note steps of every element in the document, in order.
List<Step> _steps(ScoreDocument d) => [
      for (final el in d.elements)
        if (!el.isRest) el.pitch!.step,
    ];

void main() {
  group('bar packing', () {
    test('3/4 fits three quarters per bar', () {
      final d = ScoreDocument(timeSignature: TimeSignature.threeFour);
      for (var i = 0; i < 6; i++) {
        d.insertNote(_p(Step.c), _q);
      }
      expect(d.barCount, 2);
    });

    test('6/8 fits six eighths per bar', () {
      final d = ScoreDocument(timeSignature: TimeSignature.sixEight);
      for (var i = 0; i < 7; i++) {
        d.insertNote(_p(Step.c), _e);
      }
      expect(d.barCount, 2, reason: '6 eighths fill a 6/8 bar');
    });

    test('barCount stays consistent with buildScore', () {
      final d = ScoreDocument();
      for (final dur in [_q, _h, _e, _q, _h]) {
        d.insertNote(_p(Step.c), dur);
      }
      expect(d.barCount, d.buildScore().measures.length);
    });

    test('a mid-range note never overflows a bar', () {
      final d = ScoreDocument(); // 4/4
      d.insertNote(_p(Step.c), _h); // 2 beats
      d.insertNote(_p(Step.d), _h); // fills the bar (4)
      d.insertNote(_p(Step.e), _q); // new bar
      final firstBarBeats = d
          .buildScore()
          .measures
          .first
          .elements
          .fold<double>(0, (a, el) => a + el.duration.toFraction().toDouble());
      expect(firstBarBeats, lessThanOrEqualTo(1.0)); // ≤ a whole note
    });
  });

  group('clipboard & range invariants', () {
    test('copy with nothing selected is a no-op', () {
      final d = ScoreDocument();
      d.insertNote(_p(Step.c), _q);
      d.clearSelection();
      d.copySelection();
      expect(d.canPaste, isFalse);
    });

    test('paste with an empty clipboard is a no-op', () {
      final d = ScoreDocument();
      d.insertNote(_p(Step.c), _q);
      final before = d.length;
      d.paste();
      expect(d.length, before);
    });

    test('paste preserves articulations, dynamics and ties', () {
      final d = ScoreDocument();
      d.insertNote(_p(Step.c), _q);
      d.toggleArticulationOfSelected(Articulation.staccato);
      d.setDynamicOfSelected(DynamicLevel.f);
      d.toggleTieOfSelected();
      d.copySelection();
      d.paste();
      final pasted = d.elements.last;
      expect(pasted.articulations, contains(Articulation.staccato));
      expect(pasted.dynamic, DynamicLevel.f);
      expect(pasted.tieToNext, isTrue);
    });

    test('extendLeft/Right clamp at the ends', () {
      final d = ScoreDocument();
      d.insertNote(_p(Step.c), _q);
      d.insertNote(_p(Step.d), _q); // d selected (index 1)
      d.extendRight(); // already at the end → clamps
      expect(d.selectedIds.length, 1);
      d.selectPrev(); // c
      d.extendLeft(); // already at the start → clamps
      expect(d.selectedIds.length, 1);
    });

    test('move is a no-op at the boundaries', () {
      final d = ScoreDocument();
      d.insertNote(_p(Step.c), _q);
      d.insertNote(_p(Step.d), _q);
      d.toggleSelected(d.elements.first.id); // select c (index 0)
      d.moveSelectionLeft(); // can't go left of 0
      expect(_steps(d), [Step.c, Step.d]);
      d.toggleSelected(d.elements.last.id); // select d (last)
      d.moveSelectionRight(); // can't go past the end
      expect(_steps(d), [Step.c, Step.d]);
    });

    test('clearAll empties the document and the selection', () {
      final d = ScoreDocument();
      d.insertNote(_p(Step.c), _q);
      d.clearAll();
      expect(d.isEmpty, isTrue);
      expect(d.hasSelection, isFalse);
      d.undo();
      expect(d.length, 1);
    });
  });

  group('grand staff split', () {
    List<bool> isNote(Score s) => [
          for (final el in s.measures.expand((m) => m.elements))
            el is NoteElement,
        ];

    test('middle C (60) goes on the treble staff', () {
      final d = ScoreDocument();
      d.insertNote(_p(Step.c), _q); // C4 = midi 60
      final gs = d.buildGrandStaff();
      expect(isNote(gs.upper).first, isTrue); // note on treble
      expect(isNote(gs.lower).first, isFalse); // rest on bass
    });

    test('B3 (59) goes on the bass staff', () {
      final d = ScoreDocument();
      d.insertNote(_p(Step.b, octave: 3), _q); // B3 = midi 59
      final gs = d.buildGrandStaff();
      expect(isNote(gs.upper).first, isFalse);
      expect(isNote(gs.lower).first, isTrue);
    });

    test('an all-treble line leaves the bass staff all rests', () {
      final d = ScoreDocument();
      for (final s in [Step.c, Step.e, Step.g]) {
        d.insertNote(_p(s, octave: 5), _q); // high notes
      }
      final gs = d.buildGrandStaff();
      expect(isNote(gs.lower).every((n) => !n), isTrue);
    });
  });

  group('ornament ranges', () {
    test('toggling an articulation on a mixed range adds it to all', () {
      final d = ScoreDocument();
      d.insertNote(_p(Step.c), _q);
      d.insertNote(_p(Step.d), _q);
      d.insertNote(_p(Step.e), _q); // e selected
      // Give only the middle note staccato first.
      d.selectPrev(); // d
      d.toggleArticulationOfSelected(Articulation.staccato);
      // Now select c..e and toggle: since not all have it, all get it.
      d.selectPrev(); // c
      d.extendRight();
      d.extendRight(); // c..e
      d.toggleArticulationOfSelected(Articulation.staccato);
      expect(
        d.elements
            .every((el) => el.articulations.contains(Articulation.staccato)),
        isTrue,
      );
    });

    test('a dynamic lands only on the first selected note', () {
      final d = ScoreDocument();
      d.insertNote(_p(Step.c), _q);
      d.insertNote(_p(Step.d), _q); // d selected
      d.selectPrev(); // c
      d.extendRight(); // c..d
      d.setDynamicOfSelected(DynamicLevel.mf);
      expect(d.elements[0].dynamic, DynamicLevel.mf);
      expect(d.elements[1].dynamic, isNull);
    });
  });

  group('chords', () {
    test('addPitchToSelected stacks pitches into one chord element', () {
      final doc = ScoreDocument();
      doc.insertNote(_p(Step.c), _q); // C, auto-selected
      doc.addPitchToSelected(_p(Step.e));
      doc.addPitchToSelected(_p(Step.g));
      final el = doc.elements.single;
      expect(el.isChord, isTrue);
      expect(el.pitches.map((p) => p.step), [Step.c, Step.e, Step.g]);
      // Renders as a single NoteElement carrying all three pitches.
      final note =
          doc.buildScore().measures.first.elements.first as NoteElement;
      expect(note.pitches.length, 3);
    });

    test('addPitch keeps low→high order and dedupes', () {
      final doc = ScoreDocument();
      doc.insertNote(_p(Step.g), _q); // G4
      doc.addPitchToSelected(_p(Step.c)); // C4 sorts below
      doc.addPitchToSelected(_p(Step.g)); // duplicate → ignored
      expect(doc.elements.single.pitches.map((p) => p.step), [Step.c, Step.g]);
    });

    test('transposing a chord moves every note; undo restores it', () {
      final doc = ScoreDocument();
      doc.insertNote(_p(Step.c), _q);
      doc.addPitchToSelected(_p(Step.e));
      final before =
          doc.elements.single.pitches.map((p) => p.midiNumber).toList();
      doc.transposeSelected(2);
      final after =
          doc.elements.single.pitches.map((p) => p.midiNumber).toList();
      expect(after, [before[0] + 2, before[1] + 2]);
      doc.undo();
      expect(
        doc.elements.single.pitches.map((p) => p.midiNumber).toList(),
        before,
      );
    });

    test('moving a chord transposes it as a block', () {
      final doc = ScoreDocument();
      doc.insertNote(_p(Step.c), _q); // C4
      doc.addPitchToSelected(_p(Step.e)); // → chord C4·E4
      doc.repitchSelected(_p(Step.d)); // lowest → D4 (block +2)
      final midis =
          doc.elements.single.pitches.map((p) => p.midiNumber).toList();
      expect(midis[0], _p(Step.d).midiNumber); // D4
      expect(midis[1], _p(Step.e).midiNumber + 2); // E4 + 2
    });
  });

  group('slurs & lyrics', () {
    ScoreDocument threeNotes() {
      final d = ScoreDocument();
      d.insertNote(_p(Step.c), _q);
      d.insertNote(_p(Step.d), _q);
      d.insertNote(_p(Step.e), _q); // e selected (index 2)
      return d;
    }

    test('slurring a range adds one slur from the first to the last note', () {
      final d = threeNotes();
      d.selectIndex(0);
      d.extendRight();
      d.extendRight(); // c..e
      d.slurSelected();
      expect(d.slurs.length, 1);
      final s = d.slurs.single;
      expect(s.startId, d.elements.first.id);
      expect(s.endId, d.elements.last.id);
      // Rendered on the Score.
      expect(d.buildScore().slurs.length, 1);
    });

    test('slurring the same range again removes it (toggle); undo restores',
        () {
      final d = threeNotes();
      d.selectIndex(0);
      d.extendRight();
      d.extendRight();
      d.slurSelected();
      d.slurSelected(); // toggle off
      expect(d.slurs, isEmpty);
      d.undo(); // back to slurred
      expect(d.slurs.length, 1);
    });

    test('a slur needs at least two notes', () {
      final d = threeNotes(); // single note selected
      expect(d.canSlur, isFalse);
      d.slurSelected();
      expect(d.slurs, isEmpty);
    });

    test('deleting a slurred endpoint prunes the dangling slur', () {
      final d = threeNotes();
      d.selectIndex(0);
      d.extendRight();
      d.extendRight();
      d.slurSelected();
      expect(d.slurs.length, 1);
      d.selectIndex(2); // the end note
      d.deleteSelected();
      expect(d.slurs, isEmpty, reason: 'slur end was removed');
    });

    test('setting a lyric attaches it to the note and renders it', () {
      final d = threeNotes();
      final id = d.elements.first.id;
      d.setLyricFor(id, 'la');
      expect(d.lyricOf(id), 'la');
      final rendered = d.buildScore().lyrics;
      expect(rendered.length, 1);
      expect(rendered.single.text, 'la');
      expect(rendered.single.elementId, id);
    });

    test('clearing a lyric (empty text) removes it; undo restores', () {
      final d = threeNotes();
      final id = d.elements.first.id;
      d.setLyricFor(id, 'la');
      d.setLyricFor(id, '  ');
      expect(d.lyricOf(id), isNull);
      d.undo();
      expect(d.lyricOf(id), 'la');
    });

    test('verses are independent and both render', () {
      final d = threeNotes();
      final id = d.elements.first.id;
      d.setLyricFor(id, 'first');
      d.setLyricFor(id, 'second', verse: 2);
      expect(d.lyricOf(id), 'first');
      expect(d.lyricOf(id, verse: 2), 'second');
      expect(d.maxVerse, 2);
      final rendered = d.buildScore().lyrics.where((l) => l.elementId == id);
      expect(rendered.map((l) => l.verse).toSet(), {1, 2});
    });

    test('clearing verse 2 leaves verse 1 intact', () {
      final d = threeNotes();
      final id = d.elements.first.id;
      d.setLyricFor(id, 'a');
      d.setLyricFor(id, 'b', verse: 2);
      d.setLyricFor(id, '', verse: 2);
      expect(d.lyricOf(id), 'a');
      expect(d.lyricOf(id, verse: 2), isNull);
      expect(d.maxVerse, 1);
    });

    test('a lyric cannot attach to a rest', () {
      final d = ScoreDocument();
      final id = d.insertRest(_q);
      d.setLyricFor(id, 'x');
      expect(d.lyricOf(id), isNull);
    });

    test('paste carries the lyric onto the pasted copy', () {
      final d = ScoreDocument();
      final id = d.insertNote(_p(Step.c), _q);
      d.setLyricFor(id, 'do');
      d.copySelection();
      d.paste();
      final pasted = d.elements.last;
      expect(pasted.id, isNot(id));
      expect(d.lyricOf(pasted.id), 'do');
    });

    test('MusicXML round-trip preserves slurs and lyrics', () {
      final src = threeNotes();
      src.selectIndex(0);
      src.extendRight();
      src.extendRight();
      src.slurSelected();
      src.setLyricFor(src.elements[0].id, 'ah');
      final reloaded = ScoreDocument()
        ..loadScore(scoreFromMusicXml(scoreToMusicXml(src.buildScore())));
      expect(reloaded.slurs.length, 1);
      final withLyric =
          reloaded.elements.where((e) => reloaded.lyricOf(e.id) == 'ah');
      expect(withLyric.length, 1);
    });
  });

  group('drag reorder (bar level)', () {
    test('moving a note into a later bar reorders the stream', () {
      final d = ScoreDocument(); // 4/4
      for (final s in [Step.c, Step.d, Step.e, Step.f]) {
        d.insertNote(_p(s), _q); // bar 0: C D E F
      }
      d.insertNote(_p(Step.g), _q); // bar 1: G
      expect(d.measureIndexOf(d.elements.first.id), 0);
      // Drag C (index 0) into bar 1.
      final moved = d.moveByIdToMeasure(d.elements.first.id, 1);
      expect(moved, isTrue);
      // C now sits at the boundary of bar 1 (after D E F).
      expect(_steps(d), [Step.d, Step.e, Step.f, Step.c, Step.g]);
    });

    test('dropping a note back in its own bar is a no-op', () {
      final d = ScoreDocument();
      d.insertNote(_p(Step.c), _q);
      d.insertNote(_p(Step.d), _q);
      expect(d.moveByIdToMeasure(d.elements.first.id, 0), isFalse);
    });

    test('moveByIdToIndex reorders to an exact slot; undo restores', () {
      final d = ScoreDocument();
      for (final s in [Step.c, Step.d, Step.e, Step.f]) {
        d.insertNote(_p(s), _q);
      }
      final eId = d.elements[2].id; // E
      expect(d.moveByIdToIndex(eId, 0), isTrue); // → front
      expect(_steps(d), [Step.e, Step.c, Step.d, Step.f]);
      d.undo();
      expect(_steps(d), [Step.c, Step.d, Step.e, Step.f]);
    });

    test('moveByIdToIndex to its own slot is a no-op', () {
      final d = ScoreDocument();
      d.insertNote(_p(Step.c), _q);
      d.insertNote(_p(Step.d), _q);
      expect(d.moveByIdToIndex(d.elements.first.id, 0), isFalse);
    });
  });

  group('marquee selection', () {
    test('selectByIds selects exactly the enclosed ids (discontiguous)', () {
      final d = ScoreDocument();
      for (final s in [Step.c, Step.d, Step.e, Step.f]) {
        d.insertNote(_p(s), _q);
      }
      d.clearSelection();
      // The marquee returns d (1) and f (3) → the selection is exactly {d, f}
      // (no longer widened to d..f — that widening was the old behaviour).
      d.selectByIds([d.elements[3].id, d.elements[1].id]);
      expect(d.selectedIds.length, 2);
      expect(
        d.selectedElements.map((e) => e.pitch!.step).toList(),
        [Step.d, Step.f],
        reason: 'e (index 2), between them, is NOT selected',
      );
    });

    test('selectByIds with no matches clears the selection', () {
      final d = ScoreDocument();
      d.insertNote(_p(Step.c), _q);
      d.selectByIds(const ['nope']);
      expect(d.hasSelection, isFalse);
    });
  });

  group('discontiguous selection', () {
    ScoreDocument four() {
      final d = ScoreDocument();
      for (final s in [Step.c, Step.d, Step.e, Step.f]) {
        d.insertNote(_p(s), _q);
      }
      return d;
    }

    test('an edit applies to every selected note, not the span between', () {
      final d = four();
      final ids = d.elements.map((e) => e.id).toList();
      d.selectByIds([ids[0], ids[2]]); // C and E, not D
      d.transposeSelected(12); // up an octave

      final oct = d.elements.map((e) => e.pitch!.octave).toList();
      expect(oct[0], 5, reason: 'C transposed');
      expect(oct[1], 4, reason: 'D (between, unselected) untouched');
      expect(oct[2], 5, reason: 'E transposed');
      expect(oct[3], 4);
    });

    test('delete removes exactly the selected notes (gaps and all)', () {
      final d = four();
      final ids = d.elements.map((e) => e.id).toList();
      d.selectByIds([ids[0], ids[2]]); // C and E
      d.deleteSelected();
      expect(
        d.elements.map((e) => e.pitch!.step).toList(),
        [Step.d, Step.f],
      );
    });

    test('toggleInSelection adds and removes members', () {
      final d = four();
      final ids = d.elements.map((e) => e.id).toList();
      d.clearSelection();
      d.toggleInSelection(ids[0]);
      d.toggleInSelection(ids[2]);
      expect(d.selectedIds, {ids[0], ids[2]});
      d.toggleInSelection(ids[0]); // off
      expect(d.selectedIds, {ids[2]});
    });

    test('block move is a no-op on a discontiguous selection', () {
      final d = four();
      final ids = d.elements.map((e) => e.id).toList();
      final before = d.elements.map((e) => e.pitch!.step).toList();
      d.selectByIds([ids[0], ids[2]]);
      d.moveSelectionRight(); // gapped → refused
      expect(d.elements.map((e) => e.pitch!.step).toList(), before);
    });

    test('a contiguous selection still moves as a block', () {
      final d = four();
      final ids = d.elements.map((e) => e.id).toList();
      d.selectByIds([ids[0], ids[1]]); // C,D contiguous
      d.moveSelectionRight(); // E hops before them
      expect(
        d.elements.map((e) => e.pitch!.step).toList(),
        [Step.e, Step.c, Step.d, Step.f],
      );
    });
  });

  group('caret', () {
    test('sits before the element after the selection', () {
      final d = ScoreDocument();
      d.insertNote(_p(Step.c), _q);
      d.insertNote(_p(Step.d), _q);
      d.insertNote(_p(Step.e), _q); // e selected (last) → caret at end
      expect(d.caretBeforeId, isNull);
      d.selectIndex(0); // select c → caret before d
      expect(d.caretBeforeId, d.elements[1].id);
    });

    test('is null on an empty document', () {
      expect(ScoreDocument().caretBeforeId, isNull);
    });
  });

  group('hairpins', () {
    ScoreDocument twoSelected() {
      final d = ScoreDocument();
      d.insertNote(_p(Step.c), _q);
      d.insertNote(_p(Step.d), _q);
      d.selectIndex(0);
      d.extendRight(); // c..d
      return d;
    }

    test('applying a crescendo adds one wedge over the range', () {
      final d = twoSelected();
      d.hairpinSelected(HairpinType.crescendo);
      expect(d.hairpins.length, 1);
      expect(d.hairpins.single.type, HairpinType.crescendo);
      expect(d.buildScore().hairpins.length, 1);
    });

    test('same type toggles off; a different type replaces it', () {
      final d = twoSelected();
      d.hairpinSelected(HairpinType.crescendo);
      d.hairpinSelected(HairpinType.diminuendo); // replace
      expect(d.hairpins.length, 1);
      expect(d.hairpins.single.type, HairpinType.diminuendo);
      d.hairpinSelected(HairpinType.diminuendo); // toggle off
      expect(d.hairpins, isEmpty);
    });

    test('deleting an endpoint prunes the hairpin', () {
      final d = twoSelected();
      d.hairpinSelected(HairpinType.crescendo);
      d.selectIndex(1);
      d.deleteSelected();
      expect(d.hairpins, isEmpty);
    });
  });

  group('pickup (anacrusis)', () {
    test('a quarter pickup makes the first bar hold one beat', () {
      final d = ScoreDocument(); // 4/4
      d.setPickup(_q); // one-beat upbeat
      d.insertNote(_p(Step.g), _q); // the upbeat
      d.insertNote(_p(Step.c), _q); // downbeat → new (full) bar
      d.insertNote(_p(Step.d), _q);
      final measures = d.buildScore().measures;
      expect(measures.first.pickup, isTrue);
      expect(measures.first.elements.length, 1, reason: 'only the upbeat');
      expect(measures[1].elements.length, 2);
    });

    test('setPickup is undoable', () {
      final d = ScoreDocument();
      d.setPickup(_q);
      expect(d.pickup, _q);
      d.undo();
      expect(d.pickup, isNull);
    });

    test('no pickup keeps the first bar full', () {
      final d = ScoreDocument();
      for (var i = 0; i < 4; i++) {
        d.insertNote(_p(Step.c), _q);
      }
      expect(d.buildScore().measures.first.pickup, isFalse);
      expect(d.buildScore().measures.length, 1);
    });
  });

  group('round-trips', () {
    test('MusicXML preserves pitches and durations', () {
      final src = ScoreDocument();
      src.insertNote(_p(Step.c), _q);
      src.insertNote(_p(Step.d), _h);
      src.insertNote(_p(Step.g, octave: 3), _e);
      final reloaded = ScoreDocument()
        ..loadScore(scoreFromMusicXml(scoreToMusicXml(src.buildScore())));
      expect(_steps(reloaded), [Step.c, Step.d, Step.g]);
      expect(
        reloaded.elements.map((e) => e.duration.base).toList(),
        [DurationBase.quarter, DurationBase.half, DurationBase.eighth],
      );
    });

    test('MIDI preserves the sounding pitches', () {
      final src = ScoreDocument();
      src.insertNote(_p(Step.c), _q);
      src.insertNote(_p(Step.f, alter: 1), _q); // F#4
      final midi = src.elements.map((e) => e.pitch!.midiNumber).toList();
      final reloaded = ScoreDocument()
        ..loadScore(scoreFromMidi(scoreToMidi(src.buildScore())));
      final back = reloaded.elements
          .where((e) => !e.isRest)
          .map((e) => e.pitch!.midiNumber)
          .toList();
      expect(back, midi);
    });

    test('ABC preserves step and octave', () {
      final src = ScoreDocument();
      src.insertNote(_p(Step.c), _q);
      src.insertNote(_p(Step.e), _q);
      src.insertNote(_p(Step.g), _q);
      final reloaded = ScoreDocument()
        ..loadScore(scoreFromAbc(scoreToAbc(src.buildScore())));
      expect(_steps(reloaded), [Step.c, Step.e, Step.g]);
    });
  });
}
