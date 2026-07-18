// ACCEPTANCE GATE for Feature B — per-pattern variable length.
// Owned by the orchestrator (opus tracker-replayer). DO NOT EDIT.
// Implement the contract in docs/TRACKER_ENGINE_CONTRACTS.md until this passes.

import 'dart:math';

import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Feature B — per-pattern variable length', () {
    test('regression: all-equal-length patterns keep the uniform length', () {
      final s = TrackerSong(
        timing: const TrackerTiming(rows: 8),
        patternCount: 2,
      );
      s.engine.setCell(0, 0, const TrackerCell(midi: 60));
      s.order
        ..clear()
        ..addAll([0, 1]);
      s.syncCurrent();
      expect(s.songTotalMs, s.timing.totalMs * 2);
      expect(replaySong(s).pcm.length, s.timing.totalSamples * 2);
    });

    test('setPatternRows resizes ONE pattern; selectPattern re-times', () {
      final s = TrackerSong(
        timing: const TrackerTiming(rows: 8),
        patternCount: 2,
      );
      s.setPatternRows(1, 16);
      expect(s.patterns[1].rows, 16);
      expect(s.patterns[0].rows, 8); // untouched

      s.selectPattern(1);
      expect(s.rows, 16); // engine re-timed to the selected pattern
      s.engine.setCell(0, 15, const TrackerCell(midi: 62)); // edit a new row
      s.syncCurrent();
      expect(s.patterns[1].cells[0][15].midi, 62);
    });

    test('order [0,1] with rows 8 and 16 plays 24 rows; length agrees', () {
      final s = TrackerSong(
        timing: const TrackerTiming(rows: 8),
        patternCount: 2,
      );
      s.setPatternRows(1, 16);
      s.selectPattern(1);
      s.engine.setCell(0, 12, const TrackerCell(midi: 64)); // note in the tail
      s.selectPattern(0);
      s.engine.setCell(0, 0, const TrackerCell(midi: 60));
      s.order
        ..clear()
        ..addAll([0, 1]);
      s.syncCurrent();

      expect(resolveTimingMap(s).length, 24); // 8 + 16
      expect(s.songTotalMs, s.timing.stepMs * 24);

      final pcm = replaySong(s).pcm;
      final expectedSamples = s.timing.stepMs * 24 * kSampleRate ~/ 1000;
      expect((pcm.length - expectedSamples).abs(), lessThan(100));
      // The tail note of the 16-row pattern actually sounds.
      expect(pcm.fold<int>(0, (m, v) => max(m, v.abs())), greaterThan(500));
    });

    test('the timing map maps flat rows back to (order, pattern, row)', () {
      final s = TrackerSong(
        timing: const TrackerTiming(rows: 8),
        patternCount: 2,
      );
      s.setPatternRows(1, 4); // a SHORT second pattern
      s.selectPattern(0);
      s.engine.setCell(0, 0, const TrackerCell(midi: 60));
      s.order
        ..clear()
        ..addAll([0, 1]);
      s.syncCurrent();

      final map = resolveTimingMap(s);
      expect(map.length, 8 + 4); // 12 rows total
      // Entry 0 has 8 rows, entry 1 has 4.
      expect(map.where((r) => r.orderIndex == 0).length, 8);
      expect(map.where((r) => r.orderIndex == 1).length, 4);
      expect(map.last.row, 3); // last row of the 4-row pattern
    });
  });
}
