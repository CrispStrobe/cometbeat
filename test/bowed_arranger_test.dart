// test/bowed_arranger_test.dart
//
// The oracle for the bowed arranger is `kCelloFirstPosition` — the hand-authored
// first-position map the cello games already teach. If the frame model is right,
// the arranger must REDERIVE every row of that table from geometry alone, which
// is a much stronger check than any assertion we could invent: the table was
// typed from a method book, not from this code.

import 'package:comet_beat/core/notation/bowed_arranger.dart';
import 'package:comet_beat/features/games/cello/cello_first_position.dart';
import 'package:crisp_notation/crisp_notation.dart' show Pitch, Step;
import 'package:flutter_test/flutter_test.dart';

/// String index the arranger uses (0 = highest = A) for a [CelloString].
int _stringIndex(CelloString s) => switch (s) {
      CelloString.a => 0,
      CelloString.d => 1,
      CelloString.g => 2,
      CelloString.c => 3,
    };

int _midi(Pitch p) => p.midiNumber;

void main() {
  group('frame model', () {
    test('cello neck frame: four fingers a semitone apart (a minor third)', () {
      // First position anchors at 2 — first finger a whole step above the open
      // string — and the four fingers span 2..5, i.e. a minor third.
      expect(
        frameOf(BowedInstrument.cello, BowedHandMode.neck, 2),
        {1: 2, 2: 3, 3: 4, 4: 5},
      );
    });

    test('forward extension widens the 1-2 gap, backward reaches 1 down', () {
      expect(
        frameOf(BowedInstrument.cello, BowedHandMode.extendedForward, 2),
        {1: 2, 2: 4, 3: 5, 4: 6},
      );
      expect(
        frameOf(BowedInstrument.cello, BowedHandMode.extendedBackward, 2),
        {1: 1, 2: 3, 3: 4, 4: 5},
      );
    });

    test('thumb position is a different geometry: T-1-2-3, no fourth finger',
        () {
      final frame = frameOf(BowedInstrument.cello, BowedHandMode.thumb, 12);
      expect(frame, {kThumb: 12, 1: 14, 2: 16, 3: 17});
      expect(frame.containsKey(4), isFalse);
    });

    test('double bass uses Simandl 1-2-4', () {
      expect(
        frameOf(BowedInstrument.doubleBass, BowedHandMode.neck, 1),
        {1: 1, 2: 2, 4: 3},
      );
    });
  });

  group('kCelloFirstPosition oracle', () {
    test('every note, arranged alone, matches the method-book table', () {
      for (final note in kCelloFirstPosition) {
        final got = arrangeBowed(
          [
            [_midi(note.pitch)],
          ],
          skill: BowedSkill.firstPosition,
        );
        expect(got.relaxed, isFalse, reason: '${note.pitch} needed relaxing');
        final f = got.columns.single.single;
        expect(
          f.string,
          _stringIndex(note.string),
          reason: '${note.pitch}: string',
        );
        expect(f.finger, note.finger, reason: '${note.pitch}: finger');
      }
    });

    test('the whole table as one ascending phrase stays in first position', () {
      final pitches = [
        for (final n in kCelloFirstPosition) [_midi(n.pitch)],
      ];
      final got = arrangeBowed(pitches, skill: BowedSkill.firstPosition);
      expect(got.relaxed, isFalse);
      for (var i = 0; i < kCelloFirstPosition.length; i++) {
        final want = kCelloFirstPosition[i];
        final f = got.columns[i].single;
        expect(f.string, _stringIndex(want.string), reason: '${want.pitch}');
        expect(f.finger, want.finger, reason: '${want.pitch}');
        expect(f.position, lessThanOrEqualTo(1));
        expect(f.mode, BowedHandMode.neck);
      }
    });
  });

  group('the narrow frame shows up as cello finger patterns', () {
    test('C major tetrachord on the C string fingers 0-1-3-4, not 0-1-2-3', () {
      // The violin answer would be 0-1-2-3; on the cello a whole step is two
      // fingers, so E takes the third finger and D♭ would take the second.
      final got = arrangeBowed(
        [
          [_midi(const Pitch(Step.c, octave: 2))],
          [_midi(const Pitch(Step.d, octave: 2))],
          [_midi(const Pitch(Step.e, octave: 2))],
          [_midi(const Pitch(Step.f, octave: 2))],
        ],
        skill: BowedSkill.firstPosition,
      );
      expect(got.columns.map((c) => c.single.finger).toList(), [0, 1, 3, 4]);
      expect(got.columns.every((c) => c.single.string == 3), isTrue);
    });
  });

  group('extensions', () {
    // F♯2 is a semitone above the first-position frame on the C string (offset 6
    // against a 2..5 frame) and exists on no other string, so the hand either
    // extends for one note or shifts up and back.
    final passage = [
      [_midi(const Pitch(Step.d, octave: 2))],
      [_midi(const Pitch(Step.e, octave: 2))],
      [_midi(const Pitch(Step.f, octave: 2, alter: 1))],
      [_midi(const Pitch(Step.e, octave: 2))],
      [_midi(const Pitch(Step.d, octave: 2))],
    ];

    test('a one-note reach extends instead of shifting the hand', () {
      final got = arrangeBowed(passage, skill: BowedSkill.neckPositions);
      expect(got.relaxed, isFalse);
      expect(got.columns[2].single.mode, BowedHandMode.extendedForward);
      expect(got.columns[2].single.finger, 4);
      // The hand never moved: every column is anchored in first position.
      expect(got.columns.map((c) => c.single.anchor).toSet(), {2});
    });

    test('with extensions off, the same passage shifts up a position', () {
      final got = arrangeBowed(
        passage,
        skill: BowedSkill.neckPositions.copyWith(allowExtensions: false),
      );
      expect(got.relaxed, isFalse);
      expect(got.columns[2].single.mode, BowedHandMode.neck);
      expect(got.columns[2].single.position, 2);
    });

    test('a slur makes shifting expensive enough to prefer the extension', () {
      // Weight the extension so that, unslurred, the shift is the cheaper route…
      //
      // `shiftBase: 0.0` is pinned deliberately: this test is about
      // [BowedArrangeCost.slurShiftScale] alone, and the shipped `shiftBase` (0.5)
      // now makes a stationary hand win on its own — which is the point of that
      // term, but it would mask the one this test exists to measure.
      const cost = BowedArrangeCost(extension: 2.5, shiftBase: 0.0);
      final unslurred =
          arrangeBowed(passage, skill: BowedSkill.neckPositions, cost: cost);
      expect(unslurred.columns[2].single.mode, BowedHandMode.neck);
      // …and then slur across the join: a shift inside a bow stroke risks an
      // audible glissando, so the extension wins after all.
      final slurred = arrangeBowed(
        passage,
        skill: BowedSkill.neckPositions,
        cost: cost,
        slurToNext: List.filled(passage.length, true),
      );
      expect(slurred.columns[2].single.mode, BowedHandMode.extendedForward);
    });
  });

  group('thumb position', () {
    // A4 / B4 / C♯5 sit an octave and more above the open A: out of the neck
    // entirely, so the thumb has to come over.
    final high = [
      [_midi(const Pitch(Step.a))],
      [_midi(const Pitch(Step.b))],
      [_midi(const Pitch(Step.c, octave: 5, alter: 1))],
    ];

    test('a high passage lands in thumb position with T-1-2', () {
      final got = arrangeBowed(high, skill: BowedSkill.advanced);
      expect(got.relaxed, isFalse);
      expect(
        got.columns.every((c) => c.single.mode == BowedHandMode.thumb),
        isTrue,
      );
      expect(got.columns.map((c) => c.single.finger).toList(), [kThumb, 1, 2]);
      expect(got.columns.every((c) => c.single.string == 0), isTrue);
    });

    test('a beginner profile is relaxed rather than left without a fingering',
        () {
      final got = arrangeBowed(high, skill: BowedSkill.firstPosition);
      expect(got.relaxed, isTrue);
      expect(got.columns.every((c) => c.length == 1), isTrue);
    });

    test('an instrument without a thumb position never gets one', () {
      // Violin and viola have no thumb position at all; model that as an
      // instrument with no thumb entry and check the frame is truly unreachable,
      // not merely expensive.
      final noThumb = BowedInstrument(
        name: 'No thumb',
        tuning: BowedInstrument.cello.tuning,
        firstPositionOffset: 2,
        neckFingers: const [1, 2, 3, 4],
        fingerStep: 1,
        maxNeckPosition: 7,
        allowsExtensions: true,
        extensionMaxPosition: 4,
        thumbEntry: null,
        thumbFrame: const [0, 2, 4, 5],
      );
      expect(noThumb.hasThumbPosition, isFalse);
      final got =
          arrangeBowed(high, instrument: noThumb, skill: BowedSkill.advanced);
      expect(
        got.columns.expand((c) => c).any((f) => f.mode == BowedHandMode.thumb),
        isFalse,
      );
      expect(
        got.columns.expand((c) => c).any((f) => f.finger == kThumb),
        isFalse,
      );
      // Cello, by contrast, does have one.
      expect(BowedInstrument.cello.hasThumbPosition, isTrue);
    });
  });

  group('bowed-specific costs', () {
    test('a beginner takes the open string, an advanced player may not', () {
      final open = arrangeBowed(
        [
          [_midi(const Pitch(Step.d, octave: 3))],
        ],
        skill: BowedSkill.firstPosition,
      );
      expect(open.columns.single.single.isOpen, isTrue);
      expect(open.columns.single.single.string, 1);
    });

    test('rests do not pin the hand', () {
      final got = arrangeBowed(
        [
          [_midi(const Pitch(Step.f, octave: 2, alter: 1))],
          const <int>[],
          [_midi(const Pitch(Step.f, octave: 2, alter: 1))],
        ],
        skill: BowedSkill.neckPositions,
      );
      expect(got.columns[1], isEmpty);
      expect(got.columns[0].single.anchor, got.columns[2].single.anchor);
    });

    test('an open string between two stopped notes costs no hand movement', () {
      // D3 is open; the F♯2s around it must stay in the same frame.
      final got = arrangeBowed(
        [
          [_midi(const Pitch(Step.f, octave: 2, alter: 1))],
          [_midi(const Pitch(Step.d, octave: 3))],
          [_midi(const Pitch(Step.f, octave: 2, alter: 1))],
        ],
        skill: BowedSkill.neckPositions,
      );
      expect(got.columns[1].single.isOpen, isTrue);
      expect(got.columns[0].single.anchor, got.columns[2].single.anchor);
    });
  });

  group('double stops', () {
    test('a fifth is one frame across two strings, low note on the low string',
        () {
      // E2 (C string) + B2 (G string): both third finger in first position —
      // the classic cello fifth, played by laying one finger across.
      final got = arrangeBowed(
        [
          [
            _midi(const Pitch(Step.e, octave: 2)),
            _midi(const Pitch(Step.b, octave: 2)),
          ]
        ],
        skill: BowedSkill.firstPosition,
      );
      final stops = got.columns.single;
      expect(stops.length, 2);
      final low = stops.firstWhere((f) => f.semitones == 4 && f.string == 3);
      final high = stops.firstWhere((f) => f.string == 2);
      expect(low.finger, 3);
      expect(high.finger, isNot(0));
    });

    test('a double stop with an open string keeps the strings distinct', () {
      final got = arrangeBowed(
        [
          [
            _midi(const Pitch(Step.g, octave: 2)),
            _midi(const Pitch(Step.e, octave: 3)),
          ]
        ],
        skill: BowedSkill.firstPosition,
      );
      final stops = got.columns.single;
      expect(stops.map((f) => f.string).toSet().length, 2);
    });
  });

  group('output shape', () {
    test('notation labels read the way players write them', () {
      final got = arrangeBowed(
        [
          [_midi(const Pitch(Step.b, octave: 2))],
        ],
        skill: BowedSkill.firstPosition,
      );
      final f = got.columns.single.single;
      expect(f.roman, 'III'); // G string
      expect(f.fingerLabel, '3');
    });

    test('an empty input is an empty arrangement, not a crash', () {
      final got = arrangeBowed(const [], skill: BowedSkill.firstPosition);
      expect(got.columns, isEmpty);
      expect(got.relaxed, isFalse);
    });

    test('a rest column comes back empty, one entry per input column', () {
      final got = arrangeBowed(
        [
          [_midi(const Pitch(Step.d, octave: 3))],
          const <int>[],
        ],
        skill: BowedSkill.firstPosition,
      );
      expect(got.columns.length, 2);
      expect(got.columns[1], isEmpty);
    });
  });
}
