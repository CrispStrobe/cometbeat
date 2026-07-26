// Loop Studio notation: which staff a groove track gets.
//
// The old answer was one Clef per track, from `clefForGrooveCells`. That is fine
// for a bassline or a lead but wrong for anything wide: a two-handed keyboard
// part, or a bassline with a high fill, was forced onto a single staff and the
// far end rendered under piles of ledger lines. PLAN.md's retirement map lists
// "hard-coded clef choices" under Replace for exactly this reason.
//
// `grooveStaffForCells` adds the grand-staff case. The interesting content of
// this file is the BOUNDARIES — when a track is wide enough to deserve two
// staves, and when splitting it would be more staff than the music needs.

import 'package:comet_beat/core/audio/loop_engine.dart' show PatternCell;
import 'package:comet_beat/features/games/composition/groove_notation.dart';
import 'package:crisp_notation/crisp_notation.dart' show Clef;
import 'package:flutter_test/flutter_test.dart';

/// One cell per pitch, each an eighth.
List<PatternCell> _cells(List<int> midis) => [
      for (final m in midis) PatternCell(midis: [m], steps: 1),
    ];

void main() {
  group('single-staff cases are unchanged', () {
    test('an empty track defaults to treble', () {
      expect(grooveStaffForCells(const []), GrooveStaff.treble);
      expect(grooveStaffForCells(_cells(const [])), GrooveStaff.treble);
    });

    test('a track of rests defaults to treble', () {
      final rests = [
        for (var i = 0; i < 8; i++) const PatternCell(steps: 1),
      ];
      expect(grooveStaffForCells(rests), GrooveStaff.treble);
    });

    test('a bassline stays on one bass staff', () {
      // E2..C3 — squarely below middle C.
      final staff = grooveStaffForCells(_cells([40, 43, 45, 47, 48]));
      expect(staff, GrooveStaff.bass);
    });

    test('a lead stays on one treble staff', () {
      // C5..G5.
      expect(grooveStaffForCells(_cells([72, 74, 76, 77, 79])),
          GrooveStaff.treble);
    });

    test('it agrees with clefForGrooveCells wherever it stays single-staff',
        () {
      // The single-staff decision is still delegated, so the two must not drift.
      for (final midis in [
        [40, 43, 45],
        [72, 74, 76],
        [55, 57, 59],
        [62, 64, 65],
      ]) {
        final cells = _cells(midis);
        final staff = grooveStaffForCells(cells);
        if (staff == GrooveStaff.grand) continue;
        final expected = clefForGrooveCells(cells) == Clef.bass
            ? GrooveStaff.bass
            : GrooveStaff.treble;
        expect(staff, expected, reason: '$midis');
      }
    });
  });

  group('the grand-staff case', () {
    test('a two-handed part with real content both sides gets a grand staff',
        () {
      // Left hand around C3, right hand around C5 — the canonical case.
      final staff = grooveStaffForCells(_cells([48, 52, 55, 72, 76, 79]));
      expect(staff, GrooveStaff.grand);
    });

    test('a bassline with a high fill gets a grand staff', () {
      expect(
        grooveStaffForCells(_cells([40, 43, 45, 47, 76, 79])),
        GrooveStaff.grand,
      );
    });

    test('a span over two octaves is grand even if the notes bunch up', () {
      // Only two distinct pitches, but 3 octaves apart — no five-line staff
      // holds that without leaving the staff far behind.
      expect(grooveStaffForCells(_cells([36, 36, 84, 84])), GrooveStaff.grand);
    });
  });

  group('it does not split the staff for incidental notes', () {
    test('one stray low note does not make a lead into a grand staff', () {
      // A single pickup below middle C among a treble line: one staff is right.
      expect(
        grooveStaffForCells(_cells([72, 74, 76, 77, 50])),
        isNot(GrooveStaff.grand),
      );
    });

    test('one stray high note does not split a bassline', () {
      expect(
        grooveStaffForCells(_cells([40, 43, 45, 47, 70])),
        isNot(GrooveStaff.grand),
      );
    });

    test('a line hovering around middle C stays on one staff', () {
      // B3/C4/D4 straddle middle C numerically but are all within the margin —
      // splitting here would be more staff than the music needs.
      expect(
        grooveStaffForCells(_cells([59, 60, 62, 60, 59])),
        isNot(GrooveStaff.grand),
      );
    });

    test('two notes are never a two-handed part', () {
      // The "real content both sides" rule needs at least two clear notes each
      // side, so a two-note track cannot trigger a grand staff on that basis.
      expect(grooveStaffForCells(_cells([50, 70])), isNot(GrooveStaff.grand));
    });
  });

  group('chords', () {
    test('a chord spanning both ranges gets a grand staff', () {
      // One cell, five pitches — a spread piano voicing.
      final cells = [
        const PatternCell(midis: [36, 48, 64, 67, 72], steps: 4),
      ];
      expect(grooveStaffForCells(cells), GrooveStaff.grand);
    });

    test('a close treble chord stays on one staff', () {
      final cells = [
        const PatternCell(midis: [67, 71, 74], steps: 4),
      ];
      expect(grooveStaffForCells(cells), GrooveStaff.treble);
    });
  });

  group('the score it engraves is still valid', () {
    test('a grand-staff track still produces an engravable score', () {
      // grooveStaffForCells only chooses the VIEW; grooveScore must still build
      // a score the staff can render either way.
      final cells = _cells([48, 52, 55, 72, 76, 79]);
      expect(grooveStaffForCells(cells), GrooveStaff.grand);
      final score = grooveScore(cells);
      expect(score.measures, isNotEmpty);
      expect(
        score.measures.fold<int>(0, (n, m) => n + m.elements.length),
        greaterThan(0),
      );
    });
  });
}
