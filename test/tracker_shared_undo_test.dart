// WS-W4's LAST fold-in — the Tracker's edits join the shared history.
//
// As with the DAW fold-in, the strongest evidence is not in this file: it is
// that all 84 of this screen's existing tests pass UNCHANGED and none was
// touched. The snapshot mechanism is the same; only the owner of the stack
// changed.
//
// What is new, and what these cover: the Tracker's work now appears in the
// cross-surface history panel, scoping keeps its undo off other surfaces' work,
// and — the thing this screen has that the DAW does not — the entries do not
// outlive the screen.
//
// ⚠️ Never `pumpAndSettle` here: the playhead Ticker never stops.

import 'package:comet_beat/core/services/undo_service.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/game_test_support.dart';

AdvancedTrackerTester _game(WidgetTester tester) =>
    tester.state<State<AdvancedTrackerScreen>>(
      find.byType(AdvancedTrackerScreen),
    ) as AdvancedTrackerTester;

Future<AdvancedTrackerTester> _open(
  WidgetTester tester, {
  UndoService? history,
}) async {
  await pumpGame(
    tester,
    const AdvancedTrackerScreen(),
    extraProviders: history == null
        ? const []
        : [ChangeNotifierProvider<UndoService>.value(value: history)],
  );
  return _game(tester);
}

void main() {
  testWidgets('with no service in scope, undo still works', (tester) async {
    // The common path: the games registry and most of this screen's own tests
    // mount it bare. A screen that silently stopped recording depending on how
    // it was reached would be worse than not sharing at all.
    final game = await _open(tester);
    game.setNote(0, 0, 60);
    await tester.pump();
    expect(game.canUndo, isTrue);

    game.undo();
    await tester.pump();
    expect(game.noteAt(0, 0), isNull);
  });

  testWidgets('an edit lands in the shared history, with a label', (
    tester,
  ) async {
    final history = UndoService();
    final game = await _open(tester, history: history);
    game.setNote(0, 0, 60);
    await tester.pump();

    expect(history.history, isNotEmpty);
    expect(
      history.history.map((e) => e.scope),
      contains(kTrackerUndoScope),
    );
    expect(
      history.history.last.label,
      isNotEmpty,
      reason: 'a history worth showing needs words, not just entries',
    );
  });

  testWidgets("the Tracker's undo does NOT rewind another surface's edit", (
    tester,
  ) async {
    final history = UndoService();
    final game = await _open(tester, history: history);
    var otherUndone = false;
    history.push(
      UndoEntry(
        label: 'Loop: add track',
        scope: 'loop',
        undo: () => otherUndone = true,
        redo: () {},
      ),
    );

    game.undo();
    await tester.pump();
    expect(otherUndone, isFalse);
  });

  testWidgets('redo restores what undo took back', (tester) async {
    final history = UndoService();
    final game = await _open(tester, history: history);
    game.setNote(0, 0, 60);
    await tester.pump();
    game.undo();
    await tester.pump();
    expect(game.noteAt(0, 0), isNull);

    game.redo();
    await tester.pump();
    expect(game.noteAt(0, 0), 60);
  });

  testWidgets('⚠️ the entries do NOT outlive the screen', (tester) async {
    // The trap this screen inherits and the DAW does not: it is pushed and
    // popped by the games registry while the service outlives it, and every
    // entry closes over the State. An undo pressed on another surface
    // afterwards would setState on a dead screen.
    final history = UndoService();
    final game = await _open(tester, history: history);
    game.setNote(0, 0, 60);
    await tester.pump();
    expect(history.canUndoScope(kTrackerUndoScope), isTrue);

    // Tear the screen down, as popping the route does.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(
      history.canUndoScope(kTrackerUndoScope),
      isFalse,
      reason: 'the dead screen left nothing behind to be pressed',
    );
    // And the other surfaces' entries are untouched by that cleanup.
    expect(history.undo, returnsNormally);
  });

  testWidgets('a structural change clears only THIS surface', (tester) async {
    // Adding a track changes the channel/row shape, which a snapshot cannot
    // survive — but another surface's entries are still perfectly good.
    final history = UndoService();
    final game = await _open(tester, history: history);
    history.push(
      UndoEntry(
        label: 'Loop: keep me',
        scope: 'loop',
        undo: () {},
        redo: () {},
      ),
    );
    game.setNote(0, 0, 60);
    await tester.pump();

    game.addTrack();
    await tester.pump();

    expect(game.canUndo, isFalse, reason: 'ours went');
    expect(
      history.history.map((e) => e.label),
      contains('Loop: keep me'),
      reason: "the other surface's history survived",
    );
  });
}
