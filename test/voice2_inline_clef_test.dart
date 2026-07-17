// Mid-*bar* clef changes anchored on a voice-2 note. Inline clefs are a Measure-
// level (voice-independent) change, but _withInlineClefs used to walk voice-1
// elements only, so one anchored in voice 2 was stored and never emitted. It now
// collects from both voices (merged, onset-sorted) and loadScore recovers a
// voice-2 anchor whose onset has no matching voice-1 boundary. This closes the
// last voice-1-only harvest in buildScore. (A TIME change anchored on voice 2
// remains out of scope — it drives reflow's bar capacity by id.)

import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Pitch _p(Step s, {int octave = 4}) => Pitch(s, octave: octave);
const _quarter = NoteDuration(DurationBase.quarter);
const _half = NoteDuration(DurationBase.half);

/// Voice 1 = two half notes (boundaries at 0, 1/2); voice 2 = quarter, quarter,
/// half (boundaries at 0, 1/4, 1/2). The inline clef sits at onset 1/4 — a
/// position voice 1 does NOT have a boundary at, so recovery must consult v2.
(ScoreDocument, List<String>) _doc() {
  final d = ScoreDocument();
  d.insertNote(_p(Step.c), _half);
  d.insertNote(_p(Step.c), _half); // voice 1: one bar
  d.setActiveVoice(1);
  final v2 = [
    d.insertNote(_p(Step.e), _quarter), // onset 0
    d.insertNote(_p(Step.e), _quarter), // onset 1/4
    d.insertNote(_p(Step.e), _half), // onset 1/2
  ];
  return (d, v2);
}

void main() {
  test('a mid-bar clef anchored on a voice-2 note is emitted', () {
    final (d, v2) = _doc();
    d.setInlineClefAt(v2[1], Clef.bass); // onset 1/4

    final m = d.buildScore().measures.single;
    expect(m.inlineClefs, hasLength(1));
    expect(m.inlineClefs.single.clef, Clef.bass);
    expect(m.inlineClefs.single.onset, Fraction(1, 4));
  });

  test(
      'a voice-2 mid-bar clef survives save → reopen (no v1 boundary at its '
      'onset)', () {
    final (d, v2) = _doc();
    d.setInlineClefAt(v2[1], Clef.bass);

    final m = (ScoreDocument()..loadScore(d.buildScore()))
        .buildScore()
        .measures
        .single;
    expect(m.inlineClefs, hasLength(1));
    expect(m.inlineClefs.single.clef, Clef.bass);
    expect(m.inlineClefs.single.onset, Fraction(1, 4));
  });

  test('voice-1 and voice-2 mid-bar clefs coexist, onset-sorted', () {
    final d = ScoreDocument();
    final v1b = d.insertNote(_p(Step.c), _half); // v1 onset 0
    d.insertNote(_p(Step.c), _half); // v1 onset 1/2
    d.setActiveVoice(1);
    final v2 = [
      d.insertNote(_p(Step.e), _quarter),
      d.insertNote(_p(Step.e), _quarter), // v2 onset 1/4
      d.insertNote(_p(Step.e), _half),
    ];
    d.setActiveVoice(0);
    d.setInlineClefAt(v1b, Clef.treble); // onset 0 → skipped (bar-start)
    // Anchor a real mid-bar change in v1 at onset 1/2 and one in v2 at 1/4.
    final v1SecondId = d.buildScore().measures.single.elements[1].id!;
    d.setInlineClefAt(v1SecondId, Clef.alto); // onset 1/2
    d.setActiveVoice(1);
    d.setInlineClefAt(v2[1], Clef.bass);

    final clefs = d.buildScore().measures.single.inlineClefs;
    expect(clefs.map((c) => c.onset), [Fraction(1, 4), Fraction(1, 2)]);
    expect(clefs.map((c) => c.clef), [Clef.bass, Clef.alto]);
  });
}
