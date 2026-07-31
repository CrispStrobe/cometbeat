// ScoreDocument — chord symbols survive the Workshop.
//
// `Score.chordSymbols` is what every reader fills in from a lead sheet's
// `<harmony>` / `\chordmode` / `<Harmony>`, and the layout engine engraves it.
// The Workshop document neither read nor wrote it, so opening a chart-bearing
// score there dropped its harmony on the floor and exporting could never put it
// back — the same silent loss the `_annotations` field was added to fix, found
// the same way.

import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Pitch _p(Step step, {int alter = 0, int octave = 4}) =>
    Pitch(step, alter: alter, octave: octave);

const _quarter = NoteDuration(DurationBase.quarter);

/// A four-note score carrying a chord symbol on each note.
Score _charted() {
  final doc = ScoreDocument();
  for (final step in [Step.c, Step.d, Step.e, Step.f]) {
    doc.insertNote(_p(step), _quarter);
  }
  final built = doc.buildScore();
  final ids = built.measures
      .expand((m) => m.elements.whereType<NoteElement>())
      .map((n) => n.id!)
      .toList();
  return Score(
    clef: built.clef,
    keySignature: built.keySignature,
    timeSignature: built.timeSignature,
    measures: built.measures,
    chordSymbols: [
      ChordSymbol(ids[0], const Pitch(Step.c), ChordSymbolKind.major),
      ChordSymbol(ids[1], const Pitch(Step.a), ChordSymbolKind.minor),
      ChordSymbol(ids[2], const Pitch(Step.f), ChordSymbolKind.major),
      ChordSymbol(
        ids[3],
        const Pitch(Step.g),
        ChordSymbolKind.dominantSeventh,
        bass: const Pitch(Step.b),
      ),
    ],
  );
}

void main() {
  test('a loaded score keeps its chord symbols', () {
    // The regression: this used to come back empty.
    final doc = ScoreDocument()..loadScore(_charted());
    expect(doc.buildScore().chordSymbols.map((c) => c.text),
        ['C', 'Am', 'F', 'G7/B']);
  });

  test('symbols stay anchored to the right notes', () {
    final doc = ScoreDocument()..loadScore(_charted());
    final score = doc.buildScore();
    final notes =
        score.measures.expand((m) => m.elements.whereType<NoteElement>());
    final byId = {for (final c in score.chordSymbols) c.elementId: c.text};

    // Am belongs over the D, not wherever the list happened to land.
    final second = notes.elementAt(1);
    expect(byId[second.id], 'Am');
    expect(second.pitches.single.step, Step.d);
  });

  test('a slash bass survives the round trip', () {
    final doc = ScoreDocument()..loadScore(_charted());
    final g7 = doc.buildScore().chordSymbols.last;
    expect(g7.bass?.step, Step.b);
  });

  test('deleting the note prunes its symbol', () {
    // Otherwise the symbol outlives its anchor, and `_layoutAnnotations` THROWS
    // on an id it cannot resolve rather than skipping it — a crash, not a
    // cosmetic leak.
    final doc = ScoreDocument()..loadScore(_charted());
    doc.selectByIds({doc.buildScore().chordSymbols.first.elementId});
    doc.deleteSelected();

    final score = doc.buildScore();
    final ids = score.measures
        .expand((m) => m.elements.whereType<NoteElement>())
        .map((n) => n.id)
        .toSet();
    expect(score.chordSymbols, hasLength(3));
    expect(
      score.chordSymbols.every((c) => ids.contains(c.elementId)),
      isTrue,
      reason: 'a symbol survived its note',
    );
  });

  test('undo restores a pruned symbol', () {
    final doc = ScoreDocument()..loadScore(_charted());
    doc.selectByIds({doc.buildScore().chordSymbols.first.elementId});
    doc.deleteSelected();
    expect(doc.buildScore().chordSymbols, hasLength(3));

    doc.undo();
    expect(doc.buildScore().chordSymbols.map((c) => c.text),
        ['C', 'Am', 'F', 'G7/B']);
  });

  test('loading a different score clears the previous symbols', () {
    final doc = ScoreDocument()..loadScore(_charted());
    doc.loadScore(
      Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: (ScoreDocument()..insertNote(_p(Step.g), _quarter))
            .buildScore()
            .measures,
      ),
    );
    expect(doc.buildScore().chordSymbols, isEmpty);
  });

  test('a score with no chord symbols is unaffected', () {
    final doc = ScoreDocument()..insertNote(_p(Step.c), _quarter);
    expect(doc.buildScore().chordSymbols, isEmpty);
  });
}
