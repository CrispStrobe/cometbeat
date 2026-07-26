// Unit tests for the EDITABLE flow/order-command timeline authoring helpers
// (module_flow_timeline.dart): setPositionJump / setPatternBreak / setSpeed /
// setTempo / setPatternLoop / clearFlowCommand.
//
// Each helper must write the correct fxCmd/fxParam to the documented target cell
// (channel 0; last row for jump/break; a chosen row for speed/tempo/loop), and
// the pure songFlowTimeline + walkFlow must then reflect the authored command.
// The break case round-trips through the walk to prove it actually changes the
// played-row sequence.

import 'package:comet_beat/core/audio/mod/module_flow_timeline.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

/// A song of [patternCount] patterns × [rows] rows with the given [order]; a note
/// on channel 0 row 0 so it isn't empty. Mirrors flowSong in
/// module_flow_timeline_test.dart.
TrackerSong editSong({
  int patternCount = 2,
  int rows = 8,
  required List<int> order,
}) {
  final s = TrackerSong(
    timing: const TrackerTiming(rows: 8),
    patternCount: patternCount,
  );
  if (rows != 8) s.setRows(rows);
  s.order
    ..clear()
    ..addAll(order);
  s.engine.setCell(0, 0, const TrackerCell(midi: 60));
  s.syncCurrent();
  return s;
}

/// The cell on channel 0, [row] of the pattern order entry [orderIndex] uses.
TrackerCell cellAt(TrackerSong s, int orderIndex, int row) {
  s.syncCurrent();
  return s.patterns[s.order[orderIndex]].cells[0][row];
}

/// The single command of [kind] the timeline reports for order entry
/// [orderIndex] (first visit), or null.
FlowCommand? cmdOf(TrackerSong s, int orderIndex, FlowCommandKind kind) {
  for (final e in songFlowTimeline(s)) {
    if (e.orderIndex != orderIndex) continue;
    for (final c in e.commands) {
      if (c.kind == kind) return c;
    }
  }
  return null;
}

void main() {
  group('setPositionJump', () {
    test(
        'writes Bxx on the last row of the entry pattern; timeline reflects it',
        () {
      final s = editSong(order: [0, 1]);
      setPositionJump(s, 1, 0); // entry 1 jumps back to order 0

      // Target cell = channel 0, last row (row 7) of pattern order[1] = 1.
      final c = cellAt(s, 1, 7);
      expect(c.fxCmd, kFxPositionJump);
      expect(c.fxParam, 0); // param IS the target order

      // Timeline reports the jump on entry 1.
      final cmd = cmdOf(s, 1, FlowCommandKind.positionJump);
      expect(cmd, isNotNull);
      expect(cmd!.target, 0);
      expect(cmd.row, 7);

      // The walk follows it: after order 0 then order 1, it jumps to order 0
      // (already played) and stops — every played row is order 0 or 1.
      final played = walkFlow(s);
      expect(played.map((p) => p.orderIndex).toSet(), {0, 1});
    });
  });

  group('setPatternBreak', () {
    test(
        'writes Dxx (decimal-encoded row) on the last row; timeline reflects it',
        () {
      final s = editSong(order: [0, 1]);
      setPatternBreak(s, 0, 13); // break to row 13 (decimal → 0x13)

      final c = cellAt(s, 0, 7);
      expect(c.fxCmd, kFxPatternBreak);
      expect(c.fxParam, 0x13); // (1<<4)|3

      final cmd = cmdOf(s, 0, FlowCommandKind.patternBreak);
      expect(cmd, isNotNull);
      expect(cmd!.target, 13); // decoded back to decimal
    });

    test('round-trips through the walk: an authored break changes played rows',
        () {
      final base = editSong(order: [0, 1]);
      final before = walkFlow(base).length; // 8 + 8 = 16 rows

      final s = editSong(order: [0, 1]);
      setPatternBreak(s, 0, 4); // break into order 1 at row 4 → skips rows 0..3
      final after = walkFlow(s).length; // 8 (order 0) + 4 (rows 4..7) = 12

      expect(before, 16);
      expect(after, lessThan(before));
      expect(after, 12);
    });
  });

  group('setSpeed / setTempo', () {
    test('setSpeed writes Fxx (<0x20) on row 0 by default', () {
      final s = editSong(order: [0]);
      setSpeed(s, 0, 3);

      final c = cellAt(s, 0, 0);
      expect(c.fxCmd, kFxSetSpeed);
      expect(c.fxParam, 3);

      final cmd = cmdOf(s, 0, FlowCommandKind.speedChange);
      expect(cmd, isNotNull);
      expect(cmd!.target, 3);
      // The walk carries the new speed on every played row.
      expect(walkFlow(s).first.ticksPerRow, 3);
    });

    test('setSpeed honours an explicit row and clamps to 1..0x1F', () {
      final s = editSong(order: [0]);
      setSpeed(s, 0, 99, row: 2); // clamps to 0x1F
      final c = cellAt(s, 0, 2);
      expect(c.fxCmd, kFxSetSpeed);
      expect(c.fxParam, 0x1F);
    });

    test('setTempo writes Fxx (>=0x20) and clamps to 32..255', () {
      final s = editSong(order: [0]);
      setTempo(s, 0, 200);

      final c = cellAt(s, 0, 0);
      expect(c.fxCmd, kFxSetSpeed);
      expect(c.fxParam, 200);

      final cmd = cmdOf(s, 0, FlowCommandKind.tempoChange);
      expect(cmd, isNotNull);
      expect(cmd!.target, 200);

      final s2 = editSong(order: [0]);
      setTempo(s2, 0, 10); // below 0x20 → clamps up
      expect(cellAt(s2, 0, 0).fxParam, 0x20);
    });
  });

  group('setPatternLoop', () {
    test('writes E6x on the last row by default; timeline reflects the count',
        () {
      final s = editSong(order: [0]);
      setPatternLoop(s, 0, 2); // repeat twice

      final c = cellAt(s, 0, 7);
      expect(c.fxCmd, kFxExtended);
      expect(c.fxParam, (kExPatternLoop << 4) | 2); // 0x62

      final cmd = cmdOf(s, 0, FlowCommandKind.patternLoop);
      expect(cmd, isNotNull);
      expect(cmd!.target, 2);

      // Loop back to row 0 replays the pattern, so more rows play than one pass.
      expect(walkFlow(s).length, greaterThan(8));
    });
  });

  group('clearFlowCommand', () {
    test('removes a previously authored jump; timeline no longer shows it', () {
      final s = editSong(order: [0, 1]);
      setPositionJump(s, 1, 0);
      expect(cmdOf(s, 1, FlowCommandKind.positionJump), isNotNull);

      clearFlowCommand(s, 1, FlowCommandKind.positionJump);
      expect(cmdOf(s, 1, FlowCommandKind.positionJump), isNull);

      // The cell command is gone; the note it shared the pattern with survives.
      final c = cellAt(s, 1, 7);
      expect(c.fxCmd, 0);
      expect(c.fxParam, 0);

      // Walk plays both orders in full again (16 rows).
      expect(walkFlow(s).length, 16);
    });

    test('preserves an existing note in the cleared cell', () {
      final s = editSong(order: [0]);
      // Put a note on channel 0, last row, then a speed command on the same cell.
      s.engine.setCell(0, 7, const TrackerCell(midi: 64));
      s.syncCurrent();
      setSpeed(s, 0, 4, row: 7);
      expect(cellAt(s, 0, 7).fxCmd, kFxSetSpeed);
      expect(cellAt(s, 0, 7).midi, 64);

      clearFlowCommand(s, 0, FlowCommandKind.speedChange);
      final c = cellAt(s, 0, 7);
      expect(c.fxCmd, 0);
      expect(c.midi, 64); // note preserved
    });
  });

  group('out-of-range guards', () {
    test('bad order index is a no-op', () {
      final s = editSong(order: [0]);
      setPositionJump(s, 9, 0); // out of range
      // No flow command anywhere.
      expect(
        songFlowTimeline(s).every((e) => e.commands.isEmpty),
        isTrue,
      );
    });
  });
}
