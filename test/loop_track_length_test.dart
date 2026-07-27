// Per-track pattern length: the pure core.
//
// The behaviour these pin is the one a groovebox player expects — shortening a
// track keeps the notes where they are and makes the loop come round sooner —
// plus the two traps that make it more than "render it short and repeat it":
// the rendered buffer has to span a whole number of every length (or the short
// track is clipped at the seam once per cycle), and the repetition has to
// happen in CELLS rather than in rendered samples (or swing lands on the wrong
// steps every other pass).

import 'package:comet_beat/core/audio/loop_engine.dart' show PatternCell;
import 'package:comet_beat/core/audio/loop_track_length.dart';
import 'package:flutter_test/flutter_test.dart';

/// One cell per entry: a midi note (or null for a rest) lasting `steps`.
List<PatternCell> _cells(List<(int?, int)> spec) => [
      for (final (midi, steps) in spec)
        PatternCell(midis: midi == null ? null : [midi], steps: steps),
    ];

int _totalSteps(List<PatternCell> cells) =>
    cells.fold(0, (sum, c) => sum + c.steps);

List<int?> _notes(List<PatternCell> cells) =>
    [for (final c in cells) c.midis?.first];

void main() {
  group('takeSteps', () {
    test('keeps the beginning and always fills exactly the window', () {
      final cells = _cells([(60, 1), (62, 1), (64, 1), (65, 1)]);
      final short = takeSteps(cells, 3);
      expect(_totalSteps(short), 3);
      expect(_notes(short), [60, 62, 64]);
    });

    test('clips a straddling cell instead of dropping it', () {
      // A hole would be voiced as silence, which is not what shortening means.
      final cells = _cells([(60, 4), (67, 4)]);
      final short = takeSteps(cells, 3);
      expect(_totalSteps(short), 3, reason: 'must still fill the window');
      expect(_notes(short), [60]);
      expect(short.single.steps, 3);
    });

    test('a window longer than the pattern is padded with a rest', () {
      final short = takeSteps(_cells([(60, 2)]), 5);
      expect(_totalSteps(short), 5);
      expect(_notes(short), [60, null]);
    });

    test('velocity survives a clip', () {
      final cells = [
        const PatternCell(midis: [60], steps: 8, velocity: 0.25),
      ];
      expect(takeSteps(cells, 3).single.velocity, 0.25);
    });

    test('a zero-or-negative window is empty, not an error', () {
      expect(takeSteps(_cells([(60, 4)]), 0), isEmpty);
      expect(takeSteps(_cells([(60, 4)]), -2), isEmpty);
    });
  });

  group('tileCellsTo', () {
    test('a full-length pattern is returned UNCHANGED', () {
      // The no-op case matters: an ordinary track must render byte-identically
      // to before this feature existed.
      final cells = _cells([(60, 8), (67, 8)]);
      expect(identical(tileCellsTo(cells, 16), cells), isTrue);
    });

    test('a short pattern repeats to fill the loop', () {
      final hat = _cells([(42, 1), (null, 1), (42, 1)]); // 3 steps
      final tiled = tileCellsTo(hat, 12);
      expect(_totalSteps(tiled), 12);
      expect(
        _notes(tiled),
        [42, null, 42, 42, null, 42, 42, null, 42, 42, null, 42],
      );
    });

    test('a final partial repetition is clipped, never overshoots', () {
      final tiled = tileCellsTo(_cells([(60, 3)]), 8);
      expect(_totalSteps(tiled), 8, reason: '3 into 8 is 2 whole and a stub');
    });

    test('an empty pattern becomes a rest of the full length', () {
      expect(_totalSteps(tileCellsTo(const [], 16)), 16);
      expect(_notes(tileCellsTo(const [], 16)), [null]);
    });
  });

  group('loopRenderSteps — the phase trap', () {
    test('3 against the 16-step grid needs 48, not 16', () {
      // At 16 the 3-step track restarts mid-repeat every cycle: a clipped tail,
      // not polymeter. 48 is the first length where both land whole.
      expect(loopRenderSteps(16, [3]), 48);
      expect(48 % 3, 0);
      expect(48 % 16, 0);
    });

    test('lengths that already divide the grid change nothing', () {
      for (final length in [1, 2, 4, 8, 16]) {
        expect(loopRenderSteps(16, [length]), 16, reason: 'length $length');
      }
    });

    test('no combination of allowed lengths exceeds 48 steps', () {
      // This is the whole reason kLoopTrackLengths is a curated list: it bounds
      // the buffer. Allowing 5 and 7 would let two tracks demand 560 steps.
      expect(loopRenderSteps(16, kLoopTrackLengths), 48);
      expect(loopRenderSteps(16, [3, 6, 12, 8, 4]), 48);
    });

    test('a length outside the allowed set is ignored, not honoured', () {
      // Rendering a 30-bar buffer because of a stray value is worse than
      // ignoring a value no UI can produce.
      expect(loopRenderSteps(16, [5]), 16);
      expect(loopRenderSteps(16, [7, 11, 13]), 16);
      expect(loopRenderSteps(16, [0, -3]), 16);
    });

    test('it respects a longer base grid (progression mode)', () {
      expect(loopRenderSteps(32, [3]), 96);
      expect(loopRenderSteps(32, [8]), 32);
    });
  });

  group('drum rows tile the same way', () {
    test('a short row repeats across the loop', () {
      expect(
        tileRowTo([true, false, false], 9),
        [true, false, false, true, false, false, true, false, false],
      );
    });

    test('a full-length row is returned unchanged', () {
      final row = [true, false];
      expect(identical(tileRowTo(row, 2), row), isTrue);
    });

    test('an empty row becomes silence of the right length', () {
      expect(tileRowTo(const [], 4), [false, false, false, false]);
      expect(tileValuesTo(const [], 3), [1.0, 1.0, 1.0]);
    });

    test('velocities tile alongside their hits', () {
      expect(tileValuesTo([1.0, 0.5], 5), [1.0, 0.5, 1.0, 0.5, 1.0]);
    });
  });

  test('every allowed length divides the bounded buffer', () {
    // The invariant the curated list exists to guarantee.
    for (final length in kLoopTrackLengths) {
      expect(48 % length, 0, reason: '$length must divide 48');
      expect(isLoopTrackLength(length), isTrue);
    }
    expect(isLoopTrackLength(5), isFalse);
  });
}
