// Characterization ("golden") tests for ScoreDocument's bar packing.
//
// These pin the EXACT Measure structure buildScore() emits today. They exist to
// de-risk the measure-spine refactor (docs/WORKSHOP_PARITY.md, Cause 1): that
// work replaces the flat element list + greedy `_packMeasures` with a real bar
// spine, and its central claim is that reflowing the spine reproduces today's
// output byte-for-byte — so the representation change is invisible and can land
// in small, mergeable slices.
//
// This file is what makes that claim checkable. If the refactor changes any
// expectation here, it changed observable behaviour and needs a decision, not a
// silent test update.
//
// Note that some pinned behaviour is *wrong* on purpose (see "known-wrong"
// below): a golden records what IS, not what SHOULD be. Fixing those is the
// refactor's job, and these tests are where that fix becomes visible.

import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Pitch _p(Step step, {int alter = 0, int octave = 4}) =>
    Pitch(step, alter: alter, octave: octave);

const _whole = NoteDuration(DurationBase.whole);
const _half = NoteDuration(DurationBase.half);
const _quarter = NoteDuration(DurationBase.quarter);
const _eighth = NoteDuration(DurationBase.eighth);
const _dottedHalf = NoteDuration(DurationBase.half, dots: 1);
const _dottedQuarter = NoteDuration(DurationBase.quarter, dots: 1);

/// A compact, readable rendering of the bar structure: one line per bar, so a
/// diff points straight at the bar that moved.
String _describe(Score score) {
  final out = StringBuffer();
  for (var i = 0; i < score.measures.length; i++) {
    final m = score.measures[i];
    final events = m.elements.map((e) {
      final dur = '${e.duration.base.name}${'.' * e.duration.dots}';
      if (e is NoteElement) {
        return '${e.pitches.map((p) => '${p.step.name}${p.octave}').join('+')}'
            '/$dur';
      }
      return 'rest/$dur';
    });
    out.writeln('bar$i${m.pickup ? '(pickup)' : ''}: ${events.join(' ')}');
  }
  return out.toString().trimRight();
}

ScoreDocument _doc({
  TimeSignature time = const TimeSignature(4, 4),
  NoteDuration? pickup,
}) {
  final d = ScoreDocument();
  if (time != const TimeSignature(4, 4)) d.setTimeSignature(time);
  if (pickup != null) d.setPickup(pickup);
  return d;
}

void main() {
  group('bar packing golden — 4/4', () {
    test('five quarters spill into a second bar', () {
      final d = _doc();
      for (final s in [Step.c, Step.d, Step.e, Step.f, Step.g]) {
        d.insertNote(_p(s), _quarter);
      }
      expect(_describe(d.buildScore()), '''
bar0: c4/quarter d4/quarter e4/quarter f4/quarter
bar1: g4/quarter''');
    });

    test('a dotted half plus a quarter exactly fills one bar', () {
      final d = _doc()
        ..insertNote(_p(Step.c), _dottedHalf)
        ..insertNote(_p(Step.d), _quarter);
      expect(_describe(d.buildScore()), 'bar0: c4/half. d4/quarter');
    });

    test('an empty document is a single whole-rest bar', () {
      expect(_describe(_doc().buildScore()), 'bar0: rest/whole');
    });

    test('rests pack exactly like notes', () {
      final d = _doc()
        ..insertNote(_p(Step.c), _half)
        ..insertRest(_half)
        ..insertNote(_p(Step.e), _quarter);
      expect(_describe(d.buildScore()), '''
bar0: c4/half rest/half
bar1: e4/quarter''');
    });

    test('a chord occupies one slot', () {
      final d = _doc()..insertNote(_p(Step.c), _whole);
      d.selectIndex(0);
      d.addPitchToSelected(_p(Step.e));
      d.addPitchToSelected(_p(Step.g));
      expect(_describe(d.buildScore()), 'bar0: c4+e4+g4/whole');
    });
  });

  group('bar packing golden — other meters', () {
    test('6/8 packs six eighths per bar (compound meter)', () {
      // 6/8 was not offerable before (picker capped at 2/4·3/4·4/4), but the
      // packer sizes bars by timeSignature.toFraction() — 6/8 = six eighths —
      // so it always worked; only the UI was capped. (Beaming as 3+3 is the
      // engine's job via beamGroups(), not the packer's.)
      final d = _doc(time: const TimeSignature(6, 8));
      for (var i = 0; i < 7; i++) {
        d.insertNote(_p(Step.values[i % 7]), _eighth);
      }
      expect(_describe(d.buildScore()), '''
bar0: c4/eighth d4/eighth e4/eighth f4/eighth g4/eighth a4/eighth
bar1: b4/eighth''');
    });

    test('5/4 packs five quarters per bar', () {
      final d = _doc(time: const TimeSignature(5, 4));
      for (var i = 0; i < 6; i++) {
        d.insertNote(_p(Step.values[i % 7]), _quarter);
      }
      final bars = d.buildScore().measures;
      expect(bars.map((m) => m.elements.length), [5, 1]);
    });

    test('3/4 packs three quarters per bar', () {
      final d = _doc(time: const TimeSignature(3, 4));
      for (final s in [Step.c, Step.d, Step.e, Step.f]) {
        d.insertNote(_p(s), _quarter);
      }
      expect(_describe(d.buildScore()), '''
bar0: c4/quarter d4/quarter e4/quarter
bar1: f4/quarter''');
    });

    test('2/4 packs two quarters per bar', () {
      final d = _doc(time: const TimeSignature(2, 4));
      for (final s in [Step.c, Step.d, Step.e]) {
        d.insertNote(_p(s), _quarter);
      }
      expect(_describe(d.buildScore()), '''
bar0: c4/quarter d4/quarter
bar1: e4/quarter''');
    });
  });

  group('bar packing golden — pickup', () {
    test('a quarter pickup holds only the upbeat, then full bars', () {
      final d = _doc(pickup: _quarter);
      for (final s in [Step.g, Step.c, Step.d, Step.e, Step.f]) {
        d.insertNote(_p(s), _quarter);
      }
      expect(_describe(d.buildScore()), '''
bar0(pickup): g4/quarter
bar1: c4/quarter d4/quarter e4/quarter f4/quarter''');
    });

    test('an eighth pickup', () {
      final d = _doc(pickup: _eighth)
        ..insertNote(_p(Step.g), _eighth)
        ..insertNote(_p(Step.c), _quarter);
      expect(_describe(d.buildScore()), '''
bar0(pickup): g4/eighth
bar1: c4/quarter''');
    });

    test('a dotted-quarter pickup in 3/4', () {
      final d = _doc(time: const TimeSignature(3, 4), pickup: _dottedQuarter)
        ..insertNote(_p(Step.g), _dottedQuarter)
        ..insertNote(_p(Step.c), _quarter);
      expect(_describe(d.buildScore()), '''
bar0(pickup): g4/quarter.
bar1: c4/quarter''');
    });

    test('only the FIRST bar is short; the pickup never recurs', () {
      final d = _doc(pickup: _quarter);
      for (var i = 0; i < 9; i++) {
        d.insertNote(_p(Step.c), _quarter);
      }
      final bars = d.buildScore().measures;
      expect(bars.first.pickup, isTrue);
      expect(bars.skip(1).every((m) => !m.pickup), isTrue);
      expect(bars.map((m) => m.elements.length), [1, 4, 4]);
    });
  });

  // These pin behaviour that is KNOWN-WRONG and that the measure-spine work is
  // expected to change. They are here so the change is loud and deliberate
  // rather than a silently-updated expectation.
  group('bar packing golden — known-wrong (spine refactor should change these)',
      () {
    test('an over-long note makes an OVER-FULL bar (never split + tied)', () {
      // A whole note does not fit in 3/4, but packing only flushes a bar that
      // already has content -- so the note lands whole in a 4-beat 3/4 bar.
      // Correct engraving is a tied half+quarter across the barline.
      final d = _doc(time: const TimeSignature(3, 4))
        ..insertNote(_p(Step.c), _whole);
      expect(
        _describe(d.buildScore()),
        'bar0: c4/whole',
        reason: 'known-wrong: 4 beats inside a 3/4 bar',
      );
    });

    test('a note that overflows starts a new bar, SHORT-FILLING the old one',
        () {
      // c(half) + d(dotted half) = 5 beats in 4/4. Rather than splitting d into
      // a tied half + quarter, packing flushes early and bar0 holds only 2 of
      // its 4 beats.
      final d = _doc()
        ..insertNote(_p(Step.c), _half)
        ..insertNote(_p(Step.d), _dottedHalf);
      expect(
        _describe(d.buildScore()),
        '''
bar0: c4/half
bar1: d4/half.''',
        reason: 'known-wrong: bar0 is 2/4 long, bar1 is 3/4 long, both in 4/4',
      );
    });
  });

  // buildGrandStaff is a SECOND, independent packing path (it pitch-splits the
  // line across two staves and packs each). It has to stay in step with the
  // single-staff path or the two views silently disagree -- easy to miss during
  // the refactor, so pin it too.
  group('bar packing golden — grand staff shares the bar grid', () {
    test('both staves keep the same bar count and aligned slots', () {
      final d = _doc()
        ..insertNote(_p(Step.g), _quarter) // treble
        ..insertNote(_p(Step.c, octave: 3), _quarter) // bass
        ..insertNote(_p(Step.a), _quarter)
        ..insertNote(_p(Step.d, octave: 3), _quarter)
        ..insertNote(_p(Step.b), _quarter); // spills to bar 1
      final gs = d.buildGrandStaff();
      expect(_describe(gs.upper), '''
bar0: g4/quarter rest/quarter a4/quarter rest/quarter
bar1: b4/quarter''');
      expect(_describe(gs.lower), '''
bar0: rest/quarter c3/quarter rest/quarter d3/quarter
bar1: rest/quarter''');
    });
  });
}
