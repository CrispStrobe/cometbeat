// The Loop Studio pattern editor's seeding + row-fitting logic.
//
// These tests exist because the old editor's "it shows nothing for that voice"
// failure was FOUR independent bugs wearing one coat, and three of them are
// invisible to any test that only asks "did the widget build". Each group below
// pins one of them against the real engine rather than a fixture, because in
// every case the defect was a disagreement between the editor's assumption and
// what the engine actually returns.

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/features/games/composition/loop_pattern_editor.dart';
import 'package:flutter_test/flutter_test.dart';

LoopEngine _engine() {
  final e = LoopEngine(tempoBpm: 120);
  e.enabled
    ..clear()
    ..addAll(['drums', 'bass', 'melody', 'chords']);
  return e;
}

void main() {
  group('seedCellsFor — the blank-grid bug', () {
    test('a stem in progression mode seeds a full bar-pair, not nothing', () {
      final e = _engine()..progression = kProgressions.first;
      // The regression: cellsFor returns the FOUR-bar resolved shape here, and
      // the old editor rejected anything whose length was not kPatternSteps —
      // so this returned null and the grid drew empty.
      final sounding = e.cellsFor('melody');
      expect(sounding, isNotNull);
      final total = sounding!.fold<int>(0, (a, c) => a + c.steps);
      expect(
        total,
        greaterThan(kPatternSteps),
        reason: 'precondition: a progression tiles the stem past one bar-pair',
      );

      final seeded = seedCellsFor(e, 'melody');
      expect(seeded.cells, isNotEmpty);
      expect(seeded.seed, LoopPatternSeed.resolved);
      expect(
        seeded.cells.fold<int>(0, (a, c) => a + c.steps),
        kPatternSteps,
        reason:
            'an override must be exactly one bar-pair or the render asserts',
      );
    });

    test('truncation shortens the straddling cell, it does not drop it', () {
      // A cell that starts inside the window but runs past its end must survive
      // as a shorter cell. Dropping it would lose a note the user can see.
      final cells = [
        const PatternCell(midis: [60], steps: kPatternSteps - 1),
        const PatternCell(midis: [64], steps: 8),
      ];
      final e = _engine()..setTrackCells('melody', cells);
      final seeded = seedCellsFor(e, 'melody');
      expect(seeded.seed, LoopPatternSeed.override);
      expect(seeded.cells.length, 2);
      expect(seeded.cells.last.midis, [64]);
    });

    test('an override always wins over the sounding shape', () {
      final e = _engine()..progression = kProgressions.first;
      e.setTrackCells('bass', [
        const PatternCell(midis: [48], steps: kPatternSteps),
      ]);
      final seeded = seedCellsFor(e, 'bass');
      expect(seeded.seed, LoopPatternSeed.override);
      expect(seeded.cells.single.midis, [48]);
    });

    test('a chord-following part seeds from what it sounds', () {
      final e = _engine()..progression = kProgressions.first;
      // bass/chords follow the progression and carry no MelodicPattern of their
      // own, so the old path had nothing 2-bar to find even in principle.
      for (final id in ['bass', 'chords']) {
        final seeded = seedCellsFor(e, id);
        expect(seeded.cells, isNotEmpty, reason: '$id seeded empty');
        expect(
          seeded.cells.any((c) => c.midis != null),
          isTrue,
          reason: '$id seeded with no pitched cell',
        );
      }
    });

    test('the user track is legitimately empty before anything is captured',
        () {
      final seeded = seedCellsFor(_engine(), LoopEngine.userTrackId);
      expect(seeded.seed, LoopPatternSeed.empty);
      expect(seeded.cells, isEmpty);
    });
  });

  group('pitchRowsFor — the invisible-bass bug', () {
    test('rows cover the notes that are there, not a fixed C4..C5', () {
      // A bass part an octave and a half below the old fixed window. Every one
      // of these used to snap onto the single bottom lane.
      final cells = [
        const PatternCell(midis: [36], steps: 4),
        const PatternCell(midis: [43], steps: 4),
      ];
      final rows = pitchRowsFor(cells);
      expect(rows.first, lessThanOrEqualTo(36));
      expect(rows.last, greaterThanOrEqualTo(43));
      expect(rows, contains(36));
      expect(rows, contains(43));
    });

    test('a note off the pentatonic grid still gets its own row', () {
      // A resolved minor triad carries a minor third, which is not in
      // {0,2,4,7,9}. Without this it would be drawn on a neighbour's lane.
      final rows = pitchRowsFor([
        const PatternCell(midis: [60, 63, 67], steps: 8),
      ]);
      expect(rows, contains(63));
      expect(rows, containsAll([60, 67]));
    });

    test('rows are sorted ascending and free of duplicates', () {
      final rows = pitchRowsFor([
        const PatternCell(midis: [60, 62, 62, 48], steps: 4),
      ]);
      expect(rows, orderedEquals(rows.toList()..sort()));
      expect(rows.toSet().length, rows.length);
    });

    test('an empty part still gets a usable octave', () {
      final rows = pitchRowsFor(const []);
      expect(rows.length, greaterThan(4));
      expect(rows.first, lessThan(rows.last));
    });

    test('a single note is centred, not stuck on the edge', () {
      final rows = pitchRowsFor([
        const PatternCell(midis: [60], steps: 2),
      ]);
      final i = rows.indexOf(60);
      expect(i, greaterThan(0));
      expect(i, lessThan(rows.length - 1));
    });

    test('chromatic gives every semitone in range', () {
      final rows = pitchRowsFor(
        [
          const PatternCell(midis: [60, 67], steps: 4),
        ],
        chromatic: true,
      );
      for (var m = rows.first; m <= rows.last; m++) {
        expect(rows, contains(m));
      }
    });

    test('rows stay inside the MIDI range at the extremes', () {
      final low = pitchRowsFor([
        const PatternCell(midis: [0], steps: 1),
      ]);
      final high = pitchRowsFor([
        const PatternCell(midis: [127], steps: 1),
      ]);
      expect(low.first, greaterThanOrEqualTo(0));
      expect(high.last, lessThanOrEqualTo(127));
    });
  });

  group('drumLanesFor — the hidden-kit bug', () {
    test('every lane the pattern uses is shown, not just kick/snare/hat', () {
      final pattern = DrumRowsPattern({
        Drum.kick: List<bool>.filled(kPatternSteps, false)..[0] = true,
        Drum.clap: List<bool>.filled(kPatternSteps, false)..[4] = true,
        Drum.ride: List<bool>.filled(kPatternSteps, false)..[2] = true,
      });
      final lanes = drumLanesFor(pattern);
      expect(lanes, containsAll([Drum.clap, Drum.ride]));
    });

    test('kick/snare/hat are always offered so an empty beat is buildable', () {
      expect(
        drumLanesFor(null),
        containsAll([Drum.kick, Drum.snare, Drum.hat]),
      );
    });

    test('an all-silent lane is not shown', () {
      final pattern = DrumRowsPattern({
        Drum.cowbell: List<bool>.filled(kPatternSteps, false),
      });
      expect(drumLanesFor(pattern), isNot(contains(Drum.cowbell)));
    });

    test('lanes keep the enum order so the kit reads consistently', () {
      final pattern = DrumRowsPattern({
        Drum.crash: List<bool>.filled(kPatternSteps, false)..[0] = true,
        Drum.tom: List<bool>.filled(kPatternSteps, false)..[1] = true,
      });
      final lanes = drumLanesFor(pattern);
      final indices = [for (final d in lanes) Drum.values.indexOf(d)];
      expect(indices, orderedEquals(indices.toList()..sort()));
    });
  });

  group('Precise readouts', () {
    test('note names report the SOUNDING pitch, not the authored one', () {
      // Cells are authored in C; the engine shifts them at render. A readout
      // that showed the authored pitch would disagree with what is heard.
      expect(soundingNoteName(60, 0), 'C4');
      expect(soundingNoteName(60, 2), 'D4');
      expect(soundingNoteName(60, 3), 'D♯4');
    });

    test('bar/beat is 1-based and marks the off-eighth', () {
      expect(barBeatOf(0), '1.1');
      expect(barBeatOf(1), '1.1+');
      expect(barBeatOf(2), '1.2');
      expect(barBeatOf(LoopTiming.stepsPerBar), '2.1');
    });
  });
}
