// Replay-fidelity ladder X5 (partial): E6x pattern loop + EEx pattern delay.
//
// These are the two trickiest row-level flow commands and the flow-timeline
// suite did not cover either. `walkFlow` is the ground truth — the flat played-
// row sequence the renderer and the timeline both read — so every expectation
// here is the sequence a ProTracker would walk, derived by hand and checked
// against pt2-clone's semantics:
//
//   E60      set the pattern-loop start to this row.
//   E6x x>0  loop back to the start; the marked span plays x+1 times TOTAL
//            (original + x repeats), the counter cleared when it reaches 0.
//   EEx      pattern delay: repeat THIS row x extra times (x+1 total) before
//            advancing — the notes do not re-trigger, the row's time is extended.
//
// Pure model + walk, so this runs everywhere (no audio, no external players).

import 'package:comet_beat/core/audio/mod/module_flow_timeline.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

TrackerCell _fx(int cmd, int param, {int? midi}) =>
    TrackerCell(midi: midi, fxCmd: cmd, fxParam: param);

/// E6x cell (low nibble = count; 0 marks the loop start).
TrackerCell _loop(int count) => _fx(kFxExtended, (kExPatternLoop << 4) | count);

/// EEx cell (low nibble = extra repeats of this row).
TrackerCell _delay(int count) =>
    _fx(kFxExtended, (kExPatternDelay << 4) | count);

TrackerSong _song({
  int patternCount = 2,
  int rows = 4,
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

/// The (order, row) pairs walkFlow actually played, in order.
List<(int, int)> _walk(TrackerSong s) =>
    [for (final p in walkFlow(s)) (p.orderIndex, p.row)];

void main() {
  group('E6x pattern loop', () {
    test('E60 + E62 plays the marked span 3 times (x+1), then moves on', () {
      // Pattern 0 (rows 0..3): E60 at row 1 (loop start), E62 at row 3.
      // Span = rows 1..3, played 2+1 = 3 times; row 0 plays once. Then order 1.
      final s = _song(
        order: [0, 1],
        author: (s) {
          s.engine.setCell(0, 1, _loop(0)); // E60 — set start at row 1
          s.engine.setCell(0, 3, _loop(2)); // E62 — loop back twice
        },
      );
      expect(
        _walk(s),
        [
          (0, 0), (0, 1), (0, 2), (0, 3), // first pass
          (0, 1), (0, 2), (0, 3), // repeat 1
          (0, 1), (0, 2), (0, 3), // repeat 2
          (1, 0), (1, 1), (1, 2), (1, 3), // order advances, loop done
        ],
      );
    });

    test('with no E60 the loop start defaults to row 0', () {
      // E62 at row 2 (the last row), no E60 anywhere → span rows 0..2 (the whole
      // 3-row pattern) plays 3 times.
      final s = _song(
        order: [0],
        rows: 3,
        author: (s) => s.engine.setCell(0, 2, _loop(2)),
      );
      expect(
        _walk(s),
        [
          (0, 0),
          (0, 1),
          (0, 2),
          (0, 0),
          (0, 1),
          (0, 2),
          (0, 0),
          (0, 1),
          (0, 2),
        ],
      );
    });

    test('E61 plays the span twice (one repeat)', () {
      final s = _song(
        order: [0],
        author: (s) {
          s.engine.setCell(0, 0, _loop(0)); // start at row 0
          s.engine.setCell(0, 1, _loop(1)); // loop once
        },
      );
      // Rows 0..1 played 1+1 = 2 times, then rows 2..3 play out.
      expect(
        _walk(s),
        [(0, 0), (0, 1), (0, 0), (0, 1), (0, 2), (0, 3)],
      );
    });

    test('songFlowTimeline shows a looped pattern as one entry per visit', () {
      final s = _song(
        order: [0],
        author: (s) {
          s.engine.setCell(0, 0, _loop(0));
          s.engine.setCell(0, 3, _loop(2)); // span 0..3, three passes
        },
      );
      final tl = songFlowTimeline(s);
      // Each backward jump starts a fresh visit, so three passes = three entries,
      // all of order 0.
      expect(tl, hasLength(3));
      expect(tl.every((e) => e.orderIndex == 0), isTrue);
      expect(tl.map((e) => e.rowCount), everyElement(4));
      expect(
        tl.expand((e) => e.commands).any(
              (c) => c.kind == FlowCommandKind.patternLoop,
            ),
        isTrue,
      );
    });
  });

  group('EEx pattern delay', () {
    test('EE2 repeats its row 3 times (x+1) before advancing', () {
      final s = _song(
        order: [0],
        rows: 3,
        author: (s) => s.engine.setCell(0, 1, _delay(2)),
      );
      expect(
        _walk(s),
        [(0, 0), (0, 1), (0, 1), (0, 1), (0, 2)],
      );
    });

    test('the delayed row is counted in the visit rowCount', () {
      final s = _song(
        order: [0],
        rows: 3,
        author: (s) => s.engine.setCell(0, 0, _delay(2)),
      );
      final tl = songFlowTimeline(s);
      expect(tl, hasLength(1));
      // rows 0,0,0,1,2 = 5 played rows across the single visit.
      expect(tl.single.rowCount, 5);
    });

    test('a zero delay (EE0) is a no-op', () {
      final s = _song(
        order: [0],
        rows: 3,
        author: (s) => s.engine.setCell(0, 1, _delay(0)),
      );
      expect(_walk(s), [(0, 0), (0, 1), (0, 2)]);
    });
  });

  group('Fxx speed vs tempo boundary', () {
    test('param 0x1F is a SPEED, 0x20 is a TEMPO', () {
      final s = _song(
        order: [0],
        rows: 2,
        author: (s) {
          s.engine.setCell(0, 0, _fx(kFxSetSpeed, 0x1F)); // speed 31
          s.engine.setCell(0, 1, _fx(kFxSetSpeed, 0x20)); // tempo 32
        },
      );
      final played = walkFlow(s);
      // Row 0: speed set to 31, tempo still the song default (120).
      expect(played[0].ticksPerRow, 31);
      expect(played[0].tempoBpm, 120);
      // Row 1: tempo now 32, speed unchanged at 31.
      expect(played[1].ticksPerRow, 31);
      expect(played[1].tempoBpm, 32);
    });
  });
}
