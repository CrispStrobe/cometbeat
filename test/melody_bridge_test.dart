// MelodyBridge — the pitched shared-tune backbone.

import 'package:comet_beat/core/audio/loop_engine.dart'
    show PatternCell, kPatternSteps;
import 'package:comet_beat/core/services/melody_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(MelodyBridge.instance.clear);

  test('publish → current + hasMelody; clear resets', () {
    expect(MelodyBridge.instance.hasMelody, isFalse);

    final m = SharedMelody(
      cells: const <PatternCell>[
        PatternCell(midis: [60], steps: 2),
        PatternCell(steps: 2),
        PatternCell(midis: [67], steps: 4),
      ],
      tempoBpm: 100,
      instrument: 'flute',
      source: 'loopmixer',
    );
    MelodyBridge.instance.publish(m);

    expect(MelodyBridge.instance.hasMelody, isTrue);
    expect(MelodyBridge.instance.current!.instrument, 'flute');
    expect(MelodyBridge.instance.current!.toCells(), hasLength(3));

    MelodyBridge.instance.clear();
    expect(MelodyBridge.instance.hasMelody, isFalse);
    expect(MelodyBridge.instance.current, isNull);
  });

  test('an all-rest tune counts as empty (not offered)', () {
    MelodyBridge.instance.publish(
      SharedMelody(
        cells: const <PatternCell>[PatternCell(steps: 16)],
        tempoBpm: 100,
      ),
    );
    expect(MelodyBridge.instance.current, isNotNull);
    expect(MelodyBridge.instance.hasMelody, isFalse); // empty → not offered
  });

  test('cells are unmodifiable (a snapshot)', () {
    final m = SharedMelody(
      cells: const <PatternCell>[
        PatternCell(midis: [60], steps: 16),
      ],
      tempoBpm: 100,
    );
    expect(
      () => m.cells.add(const PatternCell(steps: 1)),
      throwsUnsupportedError,
    );
  });

  group('midi-row ↔ PatternCell converters', () {
    test('folds trailing empties into the preceding note (ring), sums to 16',
        () {
      // C at step 0 held for 3 steps, rest for 1, G at step 4 held to the end.
      final rows = <int?>[
        60, null, null, null, // C. . .
        67, null, null, null, // G. . .
        ...List<int?>.filled(8, null), // G rings on
      ];
      final cells = patternCellsFromMidiRows(rows);
      expect(
        cells.fold<int>(0, (a, c) => a + c.steps),
        kPatternSteps,
        reason: 'the run-list must fill the 2-bar grid',
      );
      // (compare field-wise — a list inside a record is not `==` by value)
      expect(cells.map((c) => (c.midis?.first, c.steps)).toList(), [
        (60, 4),
        (67, 12),
      ]);
    });

    test('a leading rest run becomes one rest cell', () {
      final rows = <int?>[null, null, 64, ...List<int?>.filled(13, null)];
      final cells = patternCellsFromMidiRows(rows);
      expect(cells.first.midis, isNull);
      expect(cells.first.steps, 2);
      expect(cells[1].midis, [64]);
      expect(cells[1].steps, 14);
    });

    test('round-trips a grid: rows → cells → rows places notes at onsets', () {
      final rows = <int?>[
        62, null, 64, null, 65, null, null, null, //
        ...List<int?>.filled(8, null),
      ];
      final back = midiRowsFromPatternCells(
        patternCellsFromMidiRows(rows),
        rows.length,
      );
      expect(back, rows); // onsets + sustained-empties preserved 1:1
    });

    test('load applies the transpose (authoring key folds into pitch)', () {
      final rows = midiRowsFromPatternCells(
        const <PatternCell>[
          PatternCell(midis: [60], steps: 8),
          PatternCell(midis: [64], steps: 8),
        ],
        16,
        transpose: 2,
      );
      expect(rows[0], 62); // C+2
      expect(rows[8], 66); // E+2
    });

    test('carries per-note dynamics from the onset step', () {
      // C at step 0 (soft), rest, G at step 4 (normal).
      final rows = <int?>[
        60, null, null, null, 67, //
        ...List<int?>.filled(11, null),
      ];
      final vels = <double>[0.4, 1, 1, 1, 1.0, ...List<double>.filled(11, 1)];
      final cells = patternCellsFromMidiRows(rows, velocities: vels);
      final c = cells.firstWhere((c) => c.midis?.contains(60) ?? false);
      final g = cells.firstWhere((c) => c.midis?.contains(67) ?? false);
      expect(c.velocity, closeTo(0.4, 1e-9)); // soft onset preserved
      expect(g.velocity, 1.0); // normal note stays full
    });
  });
}
