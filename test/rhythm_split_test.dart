// RhythmPolicy.split — an over-long note is notated as tied notes across the
// barline instead of the default short-fill (spill). The largest of the
// notation features; the packing logic lives in reflow + notate().

import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Pitch _p(Step s, {int octave = 4}) => Pitch(s, octave: octave);
const _quarter = NoteDuration(DurationBase.quarter);
const _half = NoteDuration(DurationBase.half);
const _dottedHalf = NoteDuration(DurationBase.half, dots: 1);
const _whole = NoteDuration(DurationBase.whole);

/// Bar shape: (base.name + dots) per element, one list per bar.
List<List<String>> _shape(ScoreDocument d) => [
      for (final m in d.buildScore().measures)
        [
          for (final e in m.elements)
            '${e.duration.base.name}${'.' * e.duration.dots}',
        ],
    ];

NoteElement _n(Measure m, int i) => m.elements[i] as NoteElement;

void main() {
  group('notate()', () {
    Fraction f(int n, int den) => Fraction(n, den);

    test('a single value stays whole', () {
      expect(notate(_quarter.toFraction()), [_quarter]);
    });

    test('5/8 → half + eighth (largest first)', () {
      final r = notate(f(5, 8));
      expect(r.map((d) => '${d.base.name}${'.' * d.dots}'), [
        'half',
        'eighth',
      ]);
    });

    test('3/8 → a single dotted quarter', () {
      final r = notate(f(3, 8));
      expect(r, hasLength(1));
      expect(r.single.base, DurationBase.quarter);
      expect(r.single.dots, 1);
    });

    test('non-positive → empty', () {
      expect(notate(f(0, 1)), isEmpty);
    });
  });

  group('reflow split', () {
    ScoreDocument studio() =>
        ScoreDocument()..rhythmPolicy = RhythmPolicy.split;

    test('spill is the default and short-fills (unchanged)', () {
      final d = ScoreDocument() // spill
        ..insertNote(_p(Step.c), _half)
        ..insertNote(_p(Step.d), _dottedHalf); // 2 + 3 beats
      // Known-wrong spill: bar0 short-fills to 2/4, bar1 holds the dotted half.
      expect(_shape(d), [
        ['half'],
        ['half.'],
      ]);
    });

    test('split ties the overflow across the barline', () {
      final d = studio()
        ..insertNote(_p(Step.c), _half)
        ..insertNote(_p(Step.d), _dottedHalf); // 3 beats: 2 fit, 1 spills
      // bar0: half (c) + half (d, first tied piece); bar1: quarter (d cont).
      expect(_shape(d), [
        ['half', 'half'],
        ['quarter'],
      ]);
      final bars = d.buildScore().measures;
      expect(_n(bars[0], 1).tieToNext, isTrue, reason: 'first piece ties on');
      expect(_n(bars[1], 0).tieToNext, isFalse, reason: 'last piece does not');
      // Same pitch on both pieces of the split D.
      expect(_n(bars[0], 1).pitches.single.step, Step.d);
      expect(_n(bars[1], 0).pitches.single.step, Step.d);
    });

    test('an over-long note (whole in 3/4) splits + ties, no over-full bar',
        () {
      final d = ScoreDocument(timeSignature: const TimeSignature(3, 4))
        ..rhythmPolicy = RhythmPolicy.split
        ..insertNote(_p(Step.c), _whole); // 4 beats into 3/4
      expect(_shape(d), [
        ['half.'],
        ['quarter'],
      ]);
      expect(_n(d.buildScore().measures[0], 0).tieToNext, isTrue);
    });

    test('the split note keeps its bar total exact (fills, never over-fills)',
        () {
      final d = studio()
        ..insertNote(_p(Step.c), _quarter)
        ..insertNote(_p(Step.d), _whole); // 1 + 4 beats in 4/4
      // bar0: quarter + (dotted half tied); bar1: quarter (cont).
      final bars = d.buildScore().measures;
      Fraction barTotal(Measure m) => m.elements.fold(
            Fraction(0, 1),
            (a, e) => a + e.duration.toFraction(),
          );
      expect(barTotal(bars[0]), Fraction(1, 1), reason: 'bar0 is a full 4/4');
      expect(bars, hasLength(2));
    });

    test('the first split piece keeps articulations; continuation does not',
        () {
      final d = studio()..insertNote(_p(Step.c), _dottedHalf);
      d.selectIndex(0);
      d.toggleArticulationOfSelected(Articulation.accent);
      // Fill so the dotted-half-plus overflows... actually one dotted half fits
      // in 4/4. Force overflow with a preceding half:
      final d2 = studio()
        ..insertNote(_p(Step.c), _half)
        ..insertNote(_p(Step.d), _dottedHalf);
      d2.selectIndex(1);
      d2.toggleArticulationOfSelected(Articulation.accent);
      final bars = d2.buildScore().measures;
      expect(_n(bars[0], 1).articulations, contains(Articulation.accent));
      expect(_n(bars[1], 0).articulations, isEmpty);
    });

    test('toggling the policy back to spill restores short-fill', () {
      final d = studio()
        ..insertNote(_p(Step.c), _half)
        ..insertNote(_p(Step.d), _dottedHalf);
      expect(d.buildScore().measures[0].elements, hasLength(2)); // split
      d.rhythmPolicy = RhythmPolicy.spill;
      expect(d.buildScore().measures[0].elements, hasLength(1)); // short-fill
    });
  });
}
