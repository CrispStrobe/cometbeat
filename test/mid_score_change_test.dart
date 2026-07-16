// Mid-score clef + key changes — the first feature built on the element-id-anchor
// mechanism (docs/WORKSHOP_PARITY.md, Cause 1). A clef change is stored against
// an element id, not a bar number, so it rides along as the music is re-barred
// by reflow; buildScore stamps it onto whichever bar that element lands in.
//
// This deliberately does NOT need the full "bars as source of truth" flip: the
// change is a side-map on the existing flat document, applied after reflow.

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/features/workshop/model/score_document.dart';

Pitch _p(Step s, {int octave = 4}) => Pitch(s, octave: octave);
const _quarter = NoteDuration(DurationBase.quarter);

/// The clefChange stamped on each bar (null = none), in order.
List<Clef?> _clefChangesPerBar(ScoreDocument d) =>
    [for (final m in d.buildScore().measures) m.clefChange];

void main() {
  // Fills [count] quarter notes and returns their ids in order.
  List<String> fill(ScoreDocument d, int count) =>
      [for (var i = 0; i < count; i++) d.insertNote(_p(Step.c), _quarter)];

  test('a clef change lands on the bar of its anchor element', () {
    final d = ScoreDocument(); // 4/4 → 4 quarters per bar
    final ids = fill(d, 8); // two full bars
    d.setClefChangeAt(ids[4], Clef.bass); // first note of bar 1

    expect(_clefChangesPerBar(d), [null, Clef.bass]);
    expect(
      d.buildScore().measures[1].clefChange,
      Clef.bass,
      reason: 'the change is drawn where bar 1 begins',
    );
  });

  test('the anchor rides re-barring: insert earlier and it stays with its note',
      () {
    final d = ScoreDocument();
    final ids = fill(d, 8);
    d.setClefChangeAt(ids[4], Clef.bass); // start of bar 1
    expect(_clefChangesPerBar(d), [null, Clef.bass]);

    // Insert a note at the very front → everything shifts one slot right, so the
    // anchored note is now the LAST of bar 1, and bar 2 begins with it... no:
    // it moves to bar 1's end, pushing the change bar. The point is the change
    // follows the element, not a fixed bar index.
    d.selectIndex(0);
    d.insertNote(_p(Step.d), _quarter); // inserted after selection (index 1)
    final bars = d.buildScore().measures;
    // Find which bar now carries the change and assert it's where the anchor is.
    final anchorBar = bars.indexWhere(
      (m) => m.elements.any((e) => e.id == ids[4]),
    );
    expect(bars[anchorBar].clefChange, Clef.bass);
    expect(
      bars.where((m) => m.clefChange == Clef.bass),
      hasLength(1),
      reason: 'exactly one bar carries the change',
    );
  });

  test('a redundant change (same as running clef) is not drawn', () {
    final d = ScoreDocument(); // treble
    final ids = fill(d, 8);
    d.setClefChangeAt(ids[4], Clef.treble); // same as the document clef
    expect(
      _clefChangesPerBar(d),
      [null, null],
      reason: 'no bar draws a treble→treble change',
    );
  });

  test('only the changing bar is marked; the clef carries forward', () {
    final d = ScoreDocument();
    final ids = fill(d, 12); // three bars
    d.setClefChangeAt(ids[4], Clef.bass); // bar 1 → bass
    // bar 2 stays bass (engine carries it), so no second mark.
    expect(_clefChangesPerBar(d), [null, Clef.bass, null]);
  });

  test('setting, clearing, and undo', () {
    final d = ScoreDocument();
    final ids = fill(d, 8);
    d.setClefChangeAt(ids[4], Clef.bass);
    expect(d.clefChanges, {ids[4]: Clef.bass});

    d.setClefChangeAt(ids[4], null); // clear
    expect(d.clefChanges, isEmpty);
    expect(_clefChangesPerBar(d), [null, null]);

    d.undo(); // brings the change back
    expect(d.clefChanges, {ids[4]: Clef.bass});
    expect(d.buildScore().measures[1].clefChange, Clef.bass);
  });

  test('an unknown anchor id is ignored', () {
    final d = ScoreDocument();
    fill(d, 4);
    d.setClefChangeAt('does-not-exist', Clef.bass);
    expect(d.clefChanges, isEmpty);
  });

  test('no clef changes → buildScore is untouched (goldens stay valid)', () {
    final d = ScoreDocument();
    fill(d, 8);
    expect(
      d.buildScore().measures.every((m) => m.clefChange == null),
      isTrue,
    );
  });

  test('save → reopen preserves a mid-score clef change', () {
    final src = ScoreDocument();
    final ids = fill(src, 8);
    src.setClefChangeAt(ids[4], Clef.bass);

    // Through MusicXML, the real Save → Open path.
    final parsed = scoreFromMusicXml(scoreToMusicXml(src.buildScore()));
    final reopened = ScoreDocument()..loadScore(parsed);

    expect(
      reopened.buildScore().measures[1].clefChange,
      Clef.bass,
      reason: 'the clef change survives the round-trip',
    );
  });

  // Key changes use the exact same element-id-anchor mechanism as clef, so this
  // group mirrors the clef cases. Key changes do NOT affect bar capacity, so
  // they're a pure post-reflow stamp too.
  group('mid-score key change', () {
    const gMajor = KeySignature(1);

    List<KeySignature?> keyChangesPerBar(ScoreDocument d) =>
        [for (final m in d.buildScore().measures) m.keyChange];

    test('a key change lands on the bar of its anchor element', () {
      final d = ScoreDocument(); // C major (0 fifths), 4 quarters/bar
      final ids = fill(d, 8);
      d.setKeyChangeAt(ids[4], gMajor); // start of bar 1

      expect(keyChangesPerBar(d), [null, gMajor]);
    });

    test('the anchor rides re-barring', () {
      final d = ScoreDocument();
      final ids = fill(d, 8);
      d.setKeyChangeAt(ids[4], gMajor);
      d.selectIndex(0);
      d.insertNote(_p(Step.d), _quarter); // shift everything right

      final bars = d.buildScore().measures;
      final anchorBar =
          bars.indexWhere((m) => m.elements.any((e) => e.id == ids[4]));
      expect(bars[anchorBar].keyChange, gMajor);
      expect(bars.where((m) => m.keyChange == gMajor), hasLength(1));
    });

    test('a redundant change (same as running key) is not drawn', () {
      final d = ScoreDocument(); // C major
      final ids = fill(d, 8);
      d.setKeyChangeAt(ids[4], const KeySignature(0)); // still C
      expect(keyChangesPerBar(d), [null, null]);
    });

    test('setting, clearing, and undo', () {
      final d = ScoreDocument();
      final ids = fill(d, 8);
      d.setKeyChangeAt(ids[4], gMajor);
      expect(d.keyChanges, {ids[4]: gMajor});

      d.setKeyChangeAt(ids[4], null);
      expect(d.keyChanges, isEmpty);

      d.undo();
      expect(d.buildScore().measures[1].keyChange, gMajor);
    });

    test('clef and key can coexist on the same bar', () {
      final d = ScoreDocument();
      final ids = fill(d, 8);
      d.setClefChangeAt(ids[4], Clef.bass);
      d.setKeyChangeAt(ids[4], gMajor);

      final bar1 = d.buildScore().measures[1];
      expect(bar1.clefChange, Clef.bass);
      expect(bar1.keyChange, gMajor, reason: 'both stamps survive on one bar');
    });

    test('save → reopen preserves a mid-score key change', () {
      final src = ScoreDocument();
      final ids = fill(src, 8);
      src.setKeyChangeAt(ids[4], gMajor);

      final parsed = scoreFromMusicXml(scoreToMusicXml(src.buildScore()));
      final reopened = ScoreDocument()..loadScore(parsed);
      expect(reopened.buildScore().measures[1].keyChange, gMajor);
    });
  });

  // Time changes differ: they alter bar capacity, so they re-bar the score from
  // the anchor onward (handled in reflow, not a post-reflow stamp). The reflow
  // unit tests cover the packing; these cover the document wiring end-to-end.
  group('mid-score time change', () {
    const c34 = TimeSignature(3, 4);

    test('a time change re-bars from the anchor and marks the bar', () {
      final d = ScoreDocument(); // 4/4
      final ids = fill(d, 10);
      d.setTimeChangeAt(ids[4], c34); // 4/4 for one bar, then 3/4

      final bars = d.buildScore().measures;
      expect([for (final m in bars) m.elements.length], [4, 3, 3]);
      expect(bars[1].timeChange, c34);
      expect(bars[0].timeChange, isNull);
    });

    test('the anchor rides re-barring (insert earlier, meter follows the note)',
        () {
      final d = ScoreDocument();
      final ids = fill(d, 8);
      d.setTimeChangeAt(ids[4], c34);
      d.selectIndex(0);
      d.insertNote(_p(Step.d), _quarter); // shift right

      final bars = d.buildScore().measures;
      final changeBar = bars.indexWhere((m) => m.timeChange == c34);
      // The 3/4 run begins with the anchored note wherever it landed.
      expect(bars[changeBar].elements.first.id, ids[4]);
    });

    test('setting, clearing, and undo', () {
      final d = ScoreDocument();
      final ids = fill(d, 8);
      d.setTimeChangeAt(ids[4], c34);
      expect(d.timeChanges, {ids[4]: c34});

      d.setTimeChangeAt(ids[4], null);
      expect(d.timeChanges, isEmpty);
      expect(
        d.buildScore().measures.every((m) => m.timeChange == null),
        isTrue,
      );

      d.undo();
      expect(d.buildScore().measures[1].timeChange, c34);
    });

    test('clef, key and time can all land on the same bar', () {
      final d = ScoreDocument();
      final ids = fill(d, 8);
      d.setClefChangeAt(ids[4], Clef.bass);
      d.setKeyChangeAt(ids[4], const KeySignature(1));
      d.setTimeChangeAt(ids[4], c34);

      final bars = d.buildScore().measures;
      final b = bars.firstWhere((m) => m.timeChange == c34);
      expect(b.clefChange, Clef.bass);
      expect(b.keyChange, const KeySignature(1));
      expect(b.timeChange, c34);
    });

    test('save → reopen preserves a mid-score time change', () {
      final src = ScoreDocument();
      final ids = fill(src, 10);
      src.setTimeChangeAt(ids[4], c34);

      final parsed = scoreFromMusicXml(scoreToMusicXml(src.buildScore()));
      final reopened = ScoreDocument()..loadScore(parsed);
      final bars = reopened.buildScore().measures;
      expect(bars[1].timeChange, c34);
      expect([for (final m in bars) m.elements.length], [4, 3, 3]);
    });
  });
}
