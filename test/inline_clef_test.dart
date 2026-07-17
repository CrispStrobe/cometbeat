// Mid-*bar* clef changes (`Measure.inlineClefs`) — an onset-addressed clef change
// that draws right *before* the anchored note, vs the bar-*start* `clefChange`
// (see mid_score_change_test.dart). Built on the same element-id-anchor mechanism:
// the clef is stored against an element id; buildScore walks each reflowed bar,
// accumulates the onset (a Fraction of a whole note from the bar start, using the
// same tuplet-scaled durations reflow packed with) and emits an InlineClefChange
// at the anchored element's onset. The id moves with its note, so the change rides
// re-barring for free.
//
// Save → reopen is lossless: crisp_notation's MusicXML writer emits a mid-measure
// `<attributes><clef>` at each `inlineClefs` onset (`3c1b8bd`) and the reader
// parses it back, so both the in-memory Score round-trip AND the full MusicXML
// file round-trip preserve mid-bar clefs.

import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Pitch _p(Step s, {int octave = 4}) => Pitch(s, octave: octave);
const _quarter = NoteDuration(DurationBase.quarter);
final _half = Fraction(1, 2);

/// The inlineClefs stamped on each bar, in order.
List<List<InlineClefChange>> _inlinePerBar(ScoreDocument d) =>
    [for (final m in d.buildScore().measures) m.inlineClefs];

void main() {
  List<String> fill(ScoreDocument d, int count) =>
      [for (var i = 0; i < count; i++) d.insertNote(_p(Step.c), _quarter)];

  test('a mid-bar clef lands at the anchored note\'s onset', () {
    final d = ScoreDocument(); // 4/4 → 4 quarters per bar
    final ids = fill(d, 4);
    d.setInlineClefAt(ids[2], Clef.bass); // 3rd note → onset 2 quarters = 1/2

    final bars = _inlinePerBar(d);
    expect(bars, hasLength(1));
    expect(bars[0], [InlineClefChange(_half, Clef.bass)]);
  });

  test('an anchor on the first note of a bar produces no inline mark (onset 0)',
      () {
    final d = ScoreDocument();
    final ids = fill(d, 4);
    // onset 0 → a bar-start change, not inline
    d.setInlineClefAt(ids[0], Clef.bass);
    expect(_inlinePerBar(d), [<InlineClefChange>[]]);
  });

  test('the anchor rides re-barring: it stays with its note', () {
    final d = ScoreDocument();
    final ids = fill(d, 8); // two bars
    d.setInlineClefAt(ids[6], Clef.bass); // 3rd note of bar 1 → onset 1/2 there
    expect(_inlinePerBar(d)[1], [InlineClefChange(_half, Clef.bass)]);

    // Insert a note at the front → everything shifts one slot right. The anchor
    // moves with its note; find whatever bar it now sits in and assert exactly
    // one inline clef, on that bar.
    d.selectIndex(0);
    d.insertNote(_p(Step.d), _quarter);
    final bars = d.buildScore().measures;
    final anchorBar =
        bars.indexWhere((m) => m.elements.any((e) => e.id == ids[6]));
    expect(bars[anchorBar].inlineClefs, hasLength(1));
    expect(bars[anchorBar].inlineClefs.single.clef, Clef.bass);
    expect(
      bars.where((m) => m.inlineClefs.isNotEmpty),
      hasLength(1),
      reason: 'exactly one bar carries the inline clef',
    );
  });

  test('set / clear / undo', () {
    final d = ScoreDocument();
    final ids = fill(d, 4);
    d.setInlineClefAt(ids[2], Clef.alto);
    expect(d.inlineClefs[ids[2]], Clef.alto);

    d.setInlineClefAt(ids[2], null); // clear
    expect(d.inlineClefs, isEmpty);
    expect(_inlinePerBar(d), [<InlineClefChange>[]]);

    d.undo(); // brings it back
    expect(d.inlineClefs[ids[2]], Clef.alto);
  });

  test('setInlineClefAt on an unknown id is a no-op', () {
    final d = ScoreDocument();
    fill(d, 4);
    final canUndo = d.canUndo;
    d.setInlineClefAt('nope', Clef.bass);
    expect(d.canUndo, canUndo);
    expect(_inlinePerBar(d), [<InlineClefChange>[]]);
  });

  test('byte-identity: no inline clef → no inlineClefs stamped', () {
    final d = ScoreDocument();
    fill(d, 8);
    expect(
      d.buildScore().measures.every((m) => m.inlineClefs.isEmpty),
      isTrue,
    );
  });

  test('in-memory Score round-trip (buildScore ↔ loadScore) is lossless', () {
    final src = ScoreDocument();
    final ids = fill(src, 4);
    src.setInlineClefAt(ids[2], Clef.bass);

    // Load the built Score straight back — no MusicXML in the loop.
    final reopened = ScoreDocument()..loadScore(src.buildScore());
    expect(
      reopened.buildScore().measures[0].inlineClefs,
      [InlineClefChange(_half, Clef.bass)],
      reason: 'the mid-bar clef survives buildScore → loadScore',
    );
  });

  test('MusicXML file round-trip (save → reopen) is lossless', () {
    final src = ScoreDocument();
    final ids = fill(src, 4);
    src.setInlineClefAt(ids[2], Clef.bass);

    final parsed = scoreFromMusicXml(scoreToMusicXml(src.buildScore()));
    final reopened = ScoreDocument()..loadScore(parsed);
    expect(
      reopened.buildScore().measures[0].inlineClefs,
      [InlineClefChange(_half, Clef.bass)],
      reason: 'the mid-bar clef survives export → import',
    );
  });

  test('coexists with a bar-start clef change in the same bar', () {
    final d = ScoreDocument();
    final ids = fill(d, 4);
    d.setClefChangeAt(ids[0], Clef.bass); // bar start → treble..bass
    d.setInlineClefAt(ids[2], Clef.treble); // mid-bar → back to treble

    final m = d.buildScore().measures[0];
    expect(m.clefChange, Clef.bass, reason: 'bar-start change unaffected');
    expect(m.inlineClefs, [InlineClefChange(_half, Clef.treble)]);
  });
}
