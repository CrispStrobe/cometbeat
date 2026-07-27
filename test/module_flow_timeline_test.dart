// Unit tests for the native flow/order timeline (module_flow_timeline.dart).
//
// The timeline groups [walkFlow]'s flat played-row sequence back into one entry
// per contiguous order-visit, so a jumped/looped song shows the same order more
// than once — the non-linear playback made legible. Every expectation here is
// derived from [walkFlow]'s ACTUAL output for the synthetic song, so the test is
// pinned to the real replayer behaviour, not an assumed one.

import 'package:comet_beat/core/audio/mod/module_flow_timeline.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

/// A cell with an effect-column command (and optional note).
TrackerCell fx(int cmd, int param, {int? midi}) =>
    TrackerCell(midi: midi, fxCmd: cmd, fxParam: param);

/// A song of [patternCount] patterns × [rows] rows with the given [order],
/// authored via [author]; cells are synced so [walkFlow] sees the edits. Same
/// helper shape as the flow tests in tracker_replayer_test.dart.
TrackerSong flowSong({
  int patternCount = 3,
  int rows = 8,
  required List<int> order,
  required void Function(TrackerSong) author,
}) {
  final s = TrackerSong(
    timing: TrackerTiming(rows: rows),
    patternCount: patternCount,
  );
  s.order
    ..clear()
    ..addAll(order);
  author(s);
  s.syncCurrent();
  return s;
}

void main() {
  group('songFlowTimeline', () {
    test('(a) a plain 2-order song → 2 linear entries', () {
      final s = flowSong(
        patternCount: 2,
        order: [0, 1],
        author: (s) => s.engine.setCell(0, 0, const TrackerCell(midi: 60)),
      );
      final tl = songFlowTimeline(s);
      expect(tl, hasLength(2));

      // Entry 0: order 0 → pattern 0, full rows 0..7, song default 120 BPM /
      // speed 6, no flow commands.
      expect(tl[0].orderIndex, 0);
      expect(tl[0].patternIndex, 0);
      expect(tl[0].firstRow, 0);
      expect(tl[0].lastRow, 7);
      expect(tl[0].rowCount, 8);
      expect(tl[0].tempoBpm, 120);
      expect(tl[0].ticksPerRow, 6);
      expect(tl[0].commands, isEmpty);

      // Entry 1: order 1 → pattern 1, same shape.
      expect(tl[1].orderIndex, 1);
      expect(tl[1].patternIndex, 1);
      expect(tl[1].firstRow, 0);
      expect(tl[1].lastRow, 7);
      expect(tl[1].tempoBpm, 120);
      expect(tl[1].commands, isEmpty);
    });

    test('(b) an Fxx tempo change → the later entry reports the new tempo', () {
      final s = flowSong(
        patternCount: 2,
        order: [0, 1],
        author: (s) {
          s.selectPattern(0);
          s.engine.setCell(0, 0, const TrackerCell(midi: 60));
          s.selectPattern(1);
          s.engine.setCell(0, 0, fx(kFxSetSpeed, 0x50)); // F50 → 80 BPM
        },
      );
      final tl = songFlowTimeline(s);
      expect(tl, hasLength(2));

      // Before the change: song default tempo.
      expect(tl[0].tempoBpm, 120);
      expect(tl[0].commands, isEmpty);

      // After the change: the new tempo is in effect, and the tempoChange
      // command is recorded with its BPM value.
      expect(tl[1].tempoBpm, 80);
      expect(tl[1].commands, hasLength(1));
      expect(tl[1].commands.single.kind, FlowCommandKind.tempoChange);
      expect(tl[1].commands.single.target, 80); // 0x50
      expect(tl[1].commands.single.row, 0);
    });

    test('(c) a Bxx position jump shows the jump target and skips an order',
        () {
      final s = flowSong(
        order: [0, 1, 2],
        author: (s) {
          s.selectPattern(0);
          s.engine.setCell(0, 1, fx(kFxPositionJump, 0x02)); // B02 at row 1
        },
      );
      final tl = songFlowTimeline(s);
      expect(tl, hasLength(2));

      // Entry 0: order 0 plays rows 0..1, then jumps — order 1 is skipped.
      expect(tl[0].orderIndex, 0);
      expect(tl[0].firstRow, 0);
      expect(tl[0].lastRow, 1);
      expect(tl[0].rowCount, 2);
      expect(tl[0].commands, hasLength(1));
      expect(tl[0].commands.single.kind, FlowCommandKind.positionJump);
      expect(tl[0].commands.single.target, 2); // → order 2
      expect(tl[0].commands.single.row, 1);

      // Entry 1: the jump target order 2 (order 1 never appears).
      expect(tl[1].orderIndex, 2);
      expect(tl[1].patternIndex, 2);
      expect(tl.map((e) => e.orderIndex), isNot(contains(1)));
    });

    test('(c2) a backward Bxx makes the re-visited order appear twice', () {
      // order 0 breaks at row 2 → order 1; order 1 (Bxx+Dxx) jumps back to
      // order 0 row 5 (unvisited), which replays order 0, then returns to
      // order 1. Both orders appear twice in play order.
      final s = flowSong(
        patternCount: 2,
        order: [0, 1],
        author: (s) {
          s.selectPattern(0);
          s.engine.setCell(0, 2, fx(kFxPatternBreak, 0x00)); // order0 rows 0..2
          s.selectPattern(1);
          s.engine.setCell(0, 1, fx(kFxPositionJump, 0x00)); // ch0 B00 → order0
          s.addChannel();
          s.selectPattern(1);
          s.engine.setCell(1, 1, fx(kFxPatternBreak, 0x05)); // ch1 D05 → row 5
        },
      );
      final tl = songFlowTimeline(s);
      expect(tl, hasLength(4));

      expect(tl[0].orderIndex, 0);
      expect(tl[0].firstRow, 0);
      expect(tl[0].lastRow, 2);

      expect(tl[1].orderIndex, 1);
      // The jump target 0 is recorded on the order-1 visit.
      expect(
        tl[1].commands.any(
              (c) => c.kind == FlowCommandKind.positionJump && c.target == 0,
            ),
        isTrue,
      );

      // Order 0 is RE-VISITED, this time landing on row 5 (the Dxx target).
      expect(tl[2].orderIndex, 0);
      expect(tl[2].firstRow, 5);
      expect(tl[2].lastRow, 7);

      expect(tl[3].orderIndex, 1);
    });

    test('(d) a Dxx pattern break reports the break target row', () {
      final s = flowSong(
        patternCount: 2,
        order: [0, 1],
        author: (s) {
          s.selectPattern(0);
          s.engine.setCell(0, 0, fx(kFxPatternBreak, 0x03)); // D03 → row 3
        },
      );
      final tl = songFlowTimeline(s);
      expect(tl, hasLength(2));

      // Entry 0: order 0 plays only row 0 (the break is on row 0).
      expect(tl[0].orderIndex, 0);
      expect(tl[0].firstRow, 0);
      expect(tl[0].lastRow, 0);
      expect(tl[0].commands, hasLength(1));
      expect(tl[0].commands.single.kind, FlowCommandKind.patternBreak);
      expect(tl[0].commands.single.target, 3); // decimal target row

      // Entry 1: order 1 begins at the break's target row 3.
      expect(tl[1].orderIndex, 1);
      expect(tl[1].firstRow, 3);
      expect(tl[1].lastRow, 7);
    });

    test('empty / edge: a single-order song → one entry', () {
      final s = flowSong(
        patternCount: 1,
        rows: 4,
        order: [0],
        author: (s) => s.engine.setCell(0, 0, const TrackerCell(midi: 60)),
      );
      final tl = songFlowTimeline(s);
      expect(tl, hasLength(1));
      expect(tl.single.orderIndex, 0);
      expect(tl.single.rowCount, 4);
    });

    test('(e) an Fxx speed change (param < 0x20) → a speedChange command', () {
      final s = flowSong(
        patternCount: 2,
        order: [0, 1],
        author: (s) {
          s.selectPattern(0);
          s.engine.setCell(0, 0, const TrackerCell(midi: 60));
          s.selectPattern(1);
          s.engine.setCell(0, 0, fx(kFxSetSpeed, 0x04)); // F04 → 4 ticks/row
        },
      );
      final tl = songFlowTimeline(s);
      expect(tl[1].ticksPerRow, 4);
      expect(tl[1].commands.single.kind, FlowCommandKind.speedChange);
      expect(tl[1].commands.single.target, 4);
    });

    test('(f) an Axx full-range speed (kFxSetSpeedFull) → a speedChange', () {
      // IT/S3M Axx is a speed even when its value is >= 0x20 (it must not be
      // misread as a tempo).
      final s = flowSong(
        patternCount: 2,
        order: [0, 1],
        author: (s) {
          s.selectPattern(0);
          s.engine.setCell(0, 0, const TrackerCell(midi: 60));
          s.selectPattern(1);
          s.engine.setCell(0, 0, fx(kFxSetSpeedFull, 0x30)); // A30
        },
      );
      final tl = songFlowTimeline(s);
      expect(
        tl[1].commands.any((c) => c.kind == FlowCommandKind.speedChange),
        isTrue,
      );
    });
  });

  group('flow mutators + clearFlowCommand recognise every kind', () {
    test('setSpeed / setTempo / setPatternLoop then clear each', () {
      final s = flowSong(
        patternCount: 2,
        order: [0, 1],
        author: (s) => s.engine.setCell(0, 0, const TrackerCell(midi: 60)),
      );

      setSpeed(s, 1, 4);
      expect(
        songFlowTimeline(s)[1].commands.any(
              (c) => c.kind == FlowCommandKind.speedChange,
            ),
        isTrue,
      );
      clearFlowCommand(s, 1, FlowCommandKind.speedChange);
      expect(
        songFlowTimeline(s)[1].commands.any(
              (c) => c.kind == FlowCommandKind.speedChange,
            ),
        isFalse,
      );

      setTempo(s, 1, 80);
      clearFlowCommand(s, 1, FlowCommandKind.tempoChange);
      expect(
        songFlowTimeline(s)[1].commands.any(
              (c) => c.kind == FlowCommandKind.tempoChange,
            ),
        isFalse,
      );

      setPatternLoop(s, 1, 2, row: 0);
      expect(
        songFlowTimeline(s)[1].commands.any(
              (c) => c.kind == FlowCommandKind.patternLoop,
            ),
        isTrue,
      );
      clearFlowCommand(s, 1, FlowCommandKind.patternLoop);
      expect(
        songFlowTimeline(s)[1].commands.any(
              (c) => c.kind == FlowCommandKind.patternLoop,
            ),
        isFalse,
      );
    });

    test('setPositionJump / setPatternBreak on the current pattern, cleared',
        () {
      final s = flowSong(
        patternCount: 2,
        order: [0, 1],
        author: (s) => s.engine.setCell(0, 0, const TrackerCell(midi: 60)),
      );
      s.selectPattern(0); // clearing the current pattern re-imports its cells

      setPositionJump(s, 0, 1);
      expect(
        songFlowTimeline(s).any(
          (e) => e.commands.any((c) => c.kind == FlowCommandKind.positionJump),
        ),
        isTrue,
      );
      clearFlowCommand(s, 0, FlowCommandKind.positionJump);
      expect(
        songFlowTimeline(s).any(
          (e) => e.commands.any((c) => c.kind == FlowCommandKind.positionJump),
        ),
        isFalse,
      );

      setPatternBreak(s, 0, 2);
      expect(
        songFlowTimeline(s).any(
          (e) => e.commands.any((c) => c.kind == FlowCommandKind.patternBreak),
        ),
        isTrue,
      );
      clearFlowCommand(s, 0, FlowCommandKind.patternBreak);
      expect(
        songFlowTimeline(s).any(
          (e) => e.commands.any((c) => c.kind == FlowCommandKind.patternBreak),
        ),
        isFalse,
      );
    });
  });

  group('value semantics', () {
    test('FlowCommand equality, hashCode and toString', () {
      const a = FlowCommand(FlowCommandKind.tempoChange, 80, 2);
      const b = FlowCommand(FlowCommandKind.tempoChange, 80, 2);
      const c = FlowCommand(FlowCommandKind.tempoChange, 90, 2);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.toString(), contains('tempoChange'));
      expect(a.toString(), contains('@row 2'));
    });

    test('FlowTimelineEntry.toString names the order/pattern/rows', () {
      final s = flowSong(
        patternCount: 1,
        rows: 4,
        order: [0],
        author: (s) => s.engine.setCell(0, 0, const TrackerCell(midi: 60)),
      );
      final entry = songFlowTimeline(s).single;
      expect(entry.toString(), contains('FlowTimelineEntry'));
      expect(entry.toString(), contains('order 0'));
    });
  });
}
