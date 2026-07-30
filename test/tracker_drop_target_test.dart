// WS-X2 — the Tracker as a drop target (the third of four surfaces).
//
// `drag_payload_test.dart` covers the protocol and `tracker_pattern_fit_test`
// covers the fit. What is left, and what only wiring a real surface shows, is
// the surface's OWN constraints — the thing every target in this arc has
// discovered late:
//
//   * a foreign grid breaks `setChannelCells`'s row-count assert, so it must be
//     fitted deliberately;
//   * the drop must stay UNDOABLE, which is why it lands in the current pattern
//     instead of replacing the song the way Loop Studio's does — `_replaceSong`
//     calls `_clearUndo()`, so a replacing drop would be unrecoverable.
//
// ⚠️ Never `pumpAndSettle` here: the playhead Ticker never stops.

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/interop/drag_payload.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

AdvancedTrackerTester _game(WidgetTester tester) =>
    tester.state<State<AdvancedTrackerScreen>>(
      find.byType(AdvancedTrackerScreen),
    ) as AdvancedTrackerTester;

/// A song whose first pattern carries [notes] on channel 0.
TrackerSong _songWith(Map<int, int> notes, {int rows = 16, int channels = 4}) {
  final song = TrackerSong(
    timing: TrackerTiming(rows: rows),
    channels: defaultTrackerChannels(rows: rows).take(channels).toList(),
  );
  notes.forEach((row, midi) {
    song.engine.setCell(0, row, TrackerCell(midi: midi));
  });
  return song;
}

void main() {
  testWidgets('a dropped tracker song lands in the pattern', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    final landed = game.debugDrop(
      MusicDragPayload(
        kind: AppMode.tracker,
        document: _songWith({0: 60, 4: 64}),
      ),
    );
    await tester.pump();

    expect(landed, isTrue);
    expect(game.noteAt(0, 0), 60);
    expect(game.noteAt(0, 4), 64);
  });

  testWidgets('⚠️ the drop is ONE undoable edit — the reason it lands here', (
    tester,
  ) async {
    // If it replaced the song it would go through `_replaceSong`, which calls
    // `_clearUndo()` — an unrecoverable drop, which is worse than a partial one.
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 2, 48);
    await tester.pump();

    game.debugDrop(
      MusicDragPayload(kind: AppMode.tracker, document: _songWith({0: 60})),
    );
    await tester.pump();
    expect(game.noteAt(0, 0), 60);

    game.undo();
    await tester.pump();
    expect(game.noteAt(0, 0), isNull, reason: 'the drop was taken back');
    expect(game.noteAt(0, 2), 48, reason: 'and what was here came back');
  });

  testWidgets('a grid too big for the pattern is FITTED, not thrown', (
    tester,
  ) async {
    // `setChannelCells` asserts the row count. Nothing had ever handed it a
    // grid from another document, so this is the assert a foreign drop trips.
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    final oversized = _songWith(
      {0: 60, 40: 72},
      rows: 64,
      channels: 8,
    );

    final landed = game.debugDrop(
      MusicDragPayload(kind: AppMode.tracker, document: oversized),
    );
    await tester.pump();

    expect(landed, isTrue, reason: 'it landed rather than crashing');
    expect(game.noteAt(0, 0), 60);
    // Row 40 is past the end of the target pattern and is simply not there.
    for (var row = 0; row < game.rows; row++) {
      if (row != 0) expect(game.noteAt(0, row), isNull, reason: 'row $row');
    }
  });

  testWidgets('a smaller grid pads, and clears what it does not carry', (
    tester,
  ) async {
    // The other half of fitting: a 4-row song landing in a 16-row pattern must
    // fill the rest with empties, not leave the previous music showing through.
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 9, 48);
    await tester.pump();

    game.debugDrop(
      MusicDragPayload(
        kind: AppMode.tracker,
        document: _songWith({0: 60}, rows: 4),
      ),
    );
    await tester.pump();

    expect(game.noteAt(0, 0), 60);
    expect(
      game.noteAt(0, 9),
      isNull,
      reason: 'a drop replaces the pattern, it does not merge into it',
    );
  });

  testWidgets('an unsupported kind is refused, and changes nothing', (
    tester,
  ) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 0, 48);
    await tester.pump();

    final landed = game.debugDrop(
      // Audio cannot become a pattern — a bounce is one-way, and the bridge
      // says so.
      const MusicDragPayload(kind: AppMode.audio, document: 'not a document'),
    );
    await tester.pump();

    expect(landed, isFalse);
    expect(game.noteAt(0, 0), 48, reason: 'the pattern is untouched');
  });

  group('what a drop WARNS about — the surface\'s own arithmetic', () {
    // The bridge reports what its conversion cost. It cannot know what this
    // pattern's shape costs, because that happens afterwards — so the warning
    // list is this surface's own and is where a mistake would hide.
    testWidgets('a drop that fits warns about nothing', (tester) async {
      // If it warned anyway, people would learn to dismiss the dialog that
      // mattered.
      await pumpGame(tester, const AdvancedTrackerScreen());
      final game = _game(tester);
      expect(
        game.debugDropWarnings(
          MusicDragPayload(
            kind: AppMode.tracker,
            document: _songWith({0: 60}, rows: game.rows),
          ),
        ),
        isEmpty,
      );
    });

    testWidgets('it counts the NOTES that will not fit', (tester) async {
      await pumpGame(tester, const AdvancedTrackerScreen());
      final game = _game(tester);
      final warnings = game.debugDropWarnings(
        MusicDragPayload(
          kind: AppMode.tracker,
          document: _songWith({40: 60, 50: 62}, rows: 64),
        ),
      );
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('2 notes'));
    });

    testWidgets('it says the other patterns stay behind', (tester) async {
      // The cost of landing in the current pattern rather than replacing the
      // song — which is the choice that keeps a drop undoable. Saying it is the
      // price of making that choice honestly.
      await pumpGame(tester, const AdvancedTrackerScreen());
      final game = _game(tester);
      final song = TrackerSong(
        timing: TrackerTiming(rows: game.rows),
        patternCount: 3,
      );
      final warnings = game.debugDropWarnings(
        MusicDragPayload(kind: AppMode.tracker, document: song),
      );
      expect(warnings.join(' '), contains('other 2'));
    });
  });

  group('what the protocol cannot know', () {
    test('the summary under the finger is short and never empty', () {
      // Read while a finger is held over the grid.
      for (final kind in AppMode.values) {
        final summary = dropSummary(
          dropDecisionFor(
            MusicDragPayload(kind: kind, document: _songWith({0: 60})),
            AppMode.tracker,
          ),
        );
        expect(summary, isNotEmpty, reason: kind.name);
        expect(summary.length, lessThan(60), reason: '${kind.name}: $summary');
      }
    });

    test('tracker → tracker is exact and does not touch the bridge', () {
      final song = _songWith({0: 60});
      final decision = dropDecisionFor(
        MusicDragPayload(kind: AppMode.tracker, document: song),
        AppMode.tracker,
      );
      expect(decision.outcome, DropOutcome.exact);
      expect(identical(decision.document, song), isTrue);
    });
  });
}
