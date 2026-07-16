// Unit tests for `reflow` — the pure bar-packing function extracted from
// ScoreDocument (measure-spine slice 1). Being document-free is the point: the
// packing algorithm can now be tested directly on (elements, meter, pickup)
// without building a ScoreDocument, which is the seam the spine work builds on.
//
// The end-to-end packing behaviour is pinned separately (through buildScore) by
// score_document_packing_golden_test.dart; these assert the function in
// isolation and lock the contract slice 2 will call into.

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/features/workshop/model/score_document.dart';

const _whole = NoteDuration(DurationBase.whole);
const _half = NoteDuration(DurationBase.half);
const _quarter = NoteDuration(DurationBase.quarter);
const _eighth = NoteDuration(DurationBase.eighth);

NoteElement _n(Step step, NoteDuration d, {String? id}) =>
    NoteElement(pitches: [Pitch(step)], duration: d, id: id);

/// Compact bar shape: element count per bar (durations don't matter here).
List<int> _shape(List<Measure> bars) =>
    [for (final m in bars) m.elements.length];

void main() {
  const c44 = TimeSignature(4, 4);

  test('an empty stream is one whole-rest bar', () {
    final bars = reflow(const [], timeSignature: c44);
    expect(bars, hasLength(1));
    expect(bars.single.elements.single, isA<RestElement>());
  });

  test('four quarters fill one 4/4 bar; the fifth spills', () {
    final bars = reflow(
      [for (var i = 0; i < 5; i++) _n(Step.c, _quarter)],
      timeSignature: c44,
    );
    expect(_shape(bars), [4, 1]);
  });

  test('meter is honoured (3/4 vs 4/4) with the same input', () {
    final els = [for (var i = 0; i < 6; i++) _n(Step.c, _quarter)];
    expect(
      _shape(reflow(els, timeSignature: const TimeSignature(3, 4))),
      [3, 3],
    );
    expect(_shape(reflow(els, timeSignature: c44)), [4, 2]);
  });

  test('6/8 packs six eighths per bar (compound meter)', () {
    final bars = reflow(
      [for (var i = 0; i < 7; i++) _n(Step.c, _eighth)],
      timeSignature: const TimeSignature(6, 8),
    );
    expect(_shape(bars), [6, 1]);
  });

  group('time changes (capacity switches at the anchor)', () {
    const c44 = TimeSignature(4, 4);
    const c34 = TimeSignature(3, 4);

    test('the meter switches from the anchor bar onward', () {
      // 4 quarters (one 4/4 bar), then switch to 3/4 for 6 more → two 3/4 bars.
      final els = [
        for (var i = 0; i < 10; i++) _n(Step.c, _quarter, id: 'n$i'),
      ];
      final bars = reflow(els, timeSignature: c44, timeChanges: {'n4': c34});
      expect(_shape(bars), [4, 3, 3]);
    });

    test('the switching bar is marked with timeChange; earlier bars are not',
        () {
      final els = [
        for (var i = 0; i < 10; i++) _n(Step.c, _quarter, id: 'n$i'),
      ];
      final bars = reflow(els, timeSignature: c44, timeChanges: {'n4': c34});
      expect(bars[0].timeChange, isNull);
      expect(bars[1].timeChange, c34);
      expect(bars[2].timeChange, isNull, reason: 'the meter carries forward');
    });

    test('a change mid-bar still starts a fresh bar at the anchor', () {
      // Anchor on n2 (3rd quarter of bar 0): bar 0 closes early with 2 beats.
      final els = [for (var i = 0; i < 6; i++) _n(Step.c, _quarter, id: 'n$i')];
      final bars = reflow(els, timeSignature: c44, timeChanges: {'n2': c34});
      expect(_shape(bars), [2, 3, 1]);
      expect(bars[1].timeChange, c34);
    });

    test('a redundant change (same meter) is inert', () {
      final els = [for (var i = 0; i < 8; i++) _n(Step.c, _quarter, id: 'n$i')];
      final bars = reflow(els, timeSignature: c44, timeChanges: {'n4': c44});
      expect(_shape(bars), [4, 4]);
      expect(bars.every((m) => m.timeChange == null), isTrue);
    });
  });

  group('pickup', () {
    test('only the first bar is short, and it is flagged', () {
      final bars = reflow(
        [for (var i = 0; i < 5; i++) _n(Step.c, _quarter)],
        timeSignature: c44,
        pickup: _quarter,
      );
      expect(_shape(bars), [1, 4]);
      expect(bars.first.pickup, isTrue);
      expect(bars.skip(1).every((m) => !m.pickup), isTrue);
    });

    test('no pickup means no bar is flagged', () {
      final bars = reflow([_n(Step.c, _quarter)], timeSignature: c44);
      expect(bars.single.pickup, isFalse);
    });
  });

  test('element identity and order are preserved (nothing is rebuilt)', () {
    final els = [
      _n(Step.c, _half, id: 'a'),
      _n(Step.d, _half, id: 'b'),
      _n(Step.e, _quarter, id: 'c'),
    ];
    final flat = reflow(els, timeSignature: c44).expand((m) => m.elements);
    expect(
      [for (final e in flat) e.id],
      ['a', 'b', 'c'],
      reason: 'reflow re-bars the same elements; it must not clone or reorder',
    );
    expect(identical(flat.first, els.first), isTrue);
  });

  // Pinned as known-wrong (matches the goldens): an overflowing note is not yet
  // split + tied across the barline — it flushes early, short-filling the bar.
  // Slice 7 (RhythmPolicy.split) is where this changes.
  test('known-wrong: an overflowing note short-fills rather than splitting',
      () {
    final bars = reflow(
      [
        _n(Step.c, _half),
        _n(Step.d, const NoteDuration(DurationBase.half, dots: 1)),
      ],
      timeSignature: c44,
    );
    expect(_shape(bars), [1, 1], reason: 'bar0 holds only 2 of its 4 beats');
  });

  test('known-wrong: an over-long note makes an over-full bar', () {
    final bars =
        reflow([_n(Step.c, _whole)], timeSignature: const TimeSignature(3, 4));
    expect(bars, hasLength(1), reason: '4 beats inside a single 3/4 bar');
  });
}
