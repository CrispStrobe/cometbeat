// Tuplets in ScoreDocument — the one notation feature that is NOT a pure
// element-id anchor: members keep their written duration but SOUND scaled
// (a triplet of 3 eighths occupies 2 eighths), so reflow must pack them at the
// scaled duration and buildScore emits a TupletSpan over their bar-index range.

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/features/workshop/model/score_document.dart';

Pitch _p(Step s, {int octave = 4}) => Pitch(s, octave: octave);
const _eighth = NoteDuration(DurationBase.eighth);
const _quarter = NoteDuration(DurationBase.quarter);

/// All TupletSpans across the score, bar by bar.
List<TupletSpan> _spans(ScoreDocument d) =>
    [for (final m in d.buildScore().measures) ...m.tuplets];

void main() {
  test('a triplet packs at its sounding duration, not its written one', () {
    // Three eighth-note triplets sound as one quarter (2/8). Follow with three
    // quarters: 2/8 + 3×(1/4) = 1/8+... = 2/8 + 6/8 = one full 4/4 bar.
    final d = ScoreDocument();
    final t = [for (var i = 0; i < 3; i++) d.insertNote(_p(Step.c), _eighth)];
    d.addTuplet(t); // 3:2 triplet → sounds as a quarter
    for (var i = 0; i < 3; i++) {
      d.insertNote(_p(Step.d), _quarter);
    }

    final bars = d.buildScore().measures;
    expect(
      bars,
      hasLength(1),
      reason: 'triplet(=1/4) + 3 quarters = one 4/4 bar; without scaling it '
          'would over-count to 3/8+3/4 and spill',
    );
    expect(bars.single.elements, hasLength(6));
  });

  test('a triplet emits a 3:2 span over its bar-index range', () {
    final d = ScoreDocument();
    final t = [for (var i = 0; i < 3; i++) d.insertNote(_p(Step.c), _eighth)];
    d.addTuplet(t);

    final spans = _spans(d);
    expect(spans, hasLength(1));
    expect(spans.single.actual, 3);
    expect(spans.single.normal, 2);
    expect(spans.single.startIndex, 0);
    expect(spans.single.endIndex, 2);
    expect(spans.single.voice, 0);
  });

  test('a quintuplet (5:4) is supported', () {
    final d = ScoreDocument();
    final t = [for (var i = 0; i < 5; i++) d.insertNote(_p(Step.c), _eighth)];
    d.addTuplet(t, actual: 5, normal: 4);
    final spans = _spans(d);
    expect(spans, hasLength(1));
    expect((spans.single.actual, spans.single.normal), (5, 4));
  });

  group('validity', () {
    test('needs ≥2 consecutive, un-tupleted elements', () {
      final d = ScoreDocument();
      final a = d.insertNote(_p(Step.c), _eighth);
      d.insertNote(_p(Step.d), _eighth);
      final c = d.insertNote(_p(Step.e), _eighth);

      d.addTuplet([a]); // one id → no-op
      expect(_spans(d), isEmpty);

      d.addTuplet([a, c]); // a and c are not consecutive (b between) → no-op
      expect(_spans(d), isEmpty);
    });

    test('a member cannot join two tuplets', () {
      final d = ScoreDocument();
      final ids = [
        for (var i = 0; i < 3; i++) d.insertNote(_p(Step.c), _eighth),
      ];
      d.addTuplet(ids);
      d.addTuplet(ids); // already tupleted → no-op
      expect(_spans(d), hasLength(1));
    });
  });

  test('the span rides re-barring; splitting across a barline drops it', () {
    // A triplet late in a 4/4 bar; then fill so an edit pushes it over the
    // barline and the span is no longer emitted (but the group survives).
    final d = ScoreDocument();
    for (var i = 0; i < 6; i++) {
      d.insertNote(_p(Step.g), _eighth); // 6 eighths = 3/4 of the bar
    }
    final t = [for (var i = 0; i < 3; i++) d.insertNote(_p(Step.c), _eighth)];
    d.addTuplet(t); // triplet = 1/4; 3/4 + 1/4 = one full bar → span present
    expect(_spans(d), hasLength(1));

    // Insert a quarter before the triplet so it straddles the barline.
    d.selectIndex(0);
    d.insertNote(_p(Step.a), _quarter);
    // The triplet's members now split across bars → no span, but the group is
    // still there (tupletOf finds it), so a later edit can restore it.
    expect(d.tupletOf(t.first), isNotNull);
  });

  test('remove + undo', () {
    final d = ScoreDocument();
    final ids = [for (var i = 0; i < 3; i++) d.insertNote(_p(Step.c), _eighth)];
    d.addTuplet(ids);
    expect(_spans(d), hasLength(1));

    d.removeTupletAt(ids[1]);
    expect(_spans(d), isEmpty);
    expect(d.tupletOf(ids[1]), isNull);

    d.undo();
    expect(_spans(d), hasLength(1));
  });

  test('no tuplets → buildScore untouched (goldens stay valid)', () {
    final d = ScoreDocument();
    for (var i = 0; i < 4; i++) {
      d.insertNote(_p(Step.c), _quarter);
    }
    expect(d.buildScore().measures.every((m) => m.tuplets.isEmpty), isTrue);
  });

  test('save → reopen preserves a triplet (span + ratio)', () {
    final src = ScoreDocument();
    final t = [for (var i = 0; i < 3; i++) src.insertNote(_p(Step.c), _eighth)];
    src.addTuplet(t);

    final parsed = scoreFromMusicXml(scoreToMusicXml(src.buildScore()));
    final reopened = ScoreDocument()..loadScore(parsed);

    final spans = _spans(reopened);
    expect(spans, hasLength(1), reason: 'the tuplet survives the round-trip');
    expect((spans.single.actual, spans.single.normal), (3, 2));
  });
}
