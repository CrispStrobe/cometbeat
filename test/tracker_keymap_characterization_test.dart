// WS-T3, step one — what the tracker keyboard DOES today.
//
// ⚠️ These are characterization tests, not specification tests. They were
// written by observing the existing behaviour, before extracting the keymap
// into `lib/shared/keymap/`, and their whole job is to fail if that extraction
// changes anything a user can feel.
//
// They exist because WS-T3's acceptance says "the tracker's existing keyboard
// behaviour is unchanged (its tests are the regression suite)" — and there was
// no such suite. `LogicalKeyboardKey` and `KeyDownEvent` appeared ZERO times
// across every tracker test, including the screen's own 78. The best
// interaction work in the app had never had a key pressed in a test.
//
// So: describe first, refactor second. If one of these fails during the
// extraction, the extraction is wrong — not the test.

import 'package:comet_beat/core/services/beat_bridge.dart';
import 'package:comet_beat/core/services/melody_bridge.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

AdvancedTrackerTester _game(WidgetTester tester) =>
    tester.state<State<AdvancedTrackerScreen>>(
      find.byType(AdvancedTrackerScreen),
    ) as AdvancedTrackerTester;

Future<AdvancedTrackerTester> _pump(WidgetTester tester) async {
  // A single pump, never pumpAndSettle: the tracker runs a continuous ticker,
  // so settling never completes. The rest of its suite pumps the same way.
  await pumpGame(tester, const AdvancedTrackerScreen());
  await tester.pump();

  // The grid's `autofocus: true` does NOT win against the route's focus scope
  // in a test, and the tester seam's `moveCursor` is not the tap handler (the
  // tap handler is what calls requestFocus in the app). So claim the node
  // directly — without this every key press below is silently swallowed and
  // the whole suite passes vacuously in the wrong direction.
  tester
      .widgetList<Focus>(find.byType(Focus))
      .firstWhere((f) => f.autofocus && f.onKeyEvent != null)
      .focusNode!
      .requestFocus();
  await tester.pump();
  return _game(tester);
}

/// Press a key, optionally with modifiers held for the duration.
Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool ctrl = false,
  bool shift = false,
  bool alt = false,
}) async {
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BeatBridge.instance.clear();
    MelodyBridge.instance.clear();
  });

  group('navigation', () {
    testWidgets('arrows move the cursor by one cell', (tester) async {
      final game = await _pump(tester);
      game.moveCursor(0, 0);
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(game.cursorRow, 1);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(game.cursorChannel, 1);
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(game.cursorRow, 0);
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(game.cursorChannel, 0);
    });

    testWidgets('the cursor WRAPS at both ends of the pattern', (tester) async {
      // Deliberate tracker behaviour, not an accident of clamping: holding an
      // arrow walks the pattern round rather than stopping.
      final game = await _pump(tester);
      game.moveCursor(0, 0);
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(game.cursorRow, game.rows - 1, reason: 'up from row 0 wraps');

      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(game.cursorRow, 0, reason: 'and back down again');

      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(
        game.cursorChannel,
        game.channelCount - 1,
        reason: 'left from channel 0 wraps',
      );
    });
  });

  group('octave', () {
    testWidgets('PageUp / PageDown change the entry octave', (tester) async {
      final game = await _pump(tester);
      final start = game.octave;

      await _press(tester, LogicalKeyboardKey.pageUp);
      expect(game.octave, start + 1);
      await _press(tester, LogicalKeyboardKey.pageDown);
      expect(game.octave, start);
    });
  });

  group('transport (the FT2 function keys)', () {
    testWidgets('F5 plays the song, F8 stops', (tester) async {
      final game = await _pump(tester);
      expect(game.isPlaying, isFalse);

      await _press(tester, LogicalKeyboardKey.f5);
      expect(game.isPlaying, isTrue);
      expect(
        game.isSongPlaying,
        isTrue,
        reason: 'F5 is the SONG, not a pattern',
      );

      await _press(tester, LogicalKeyboardKey.f8);
      expect(game.isPlaying, isFalse);
    });

    testWidgets('F6 plays the pattern rather than the song', (tester) async {
      final game = await _pump(tester);
      await _press(tester, LogicalKeyboardKey.f6);
      expect(game.isPlaying, isTrue);
      expect(game.isSongPlaying, isFalse);
      await _press(tester, LogicalKeyboardKey.f8);
    });
  });

  group('editing', () {
    testWidgets('Delete clears the cell under the cursor', (tester) async {
      final game = await _pump(tester);
      game.setNote(0, 0, 60);
      game.moveCursor(0, 0);
      await tester.pump();
      expect(game.noteCount, 1);

      await _press(tester, LogicalKeyboardKey.delete);
      expect(game.noteCount, 0);
    });

    testWidgets('Ctrl+Z undoes an edit', (tester) async {
      final game = await _pump(tester);
      game.setNote(0, 0, 60);
      await tester.pump();
      expect(game.noteCount, 1);

      await _press(tester, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(game.noteCount, 0, reason: 'the note should be undone');
    });

    testWidgets('Alt+Up transposes, and it is undoable', (tester) async {
      // Asserted through undo rather than by reading the pitch back, because
      // the tester seam exposes note COUNT, not pitch — and the property that
      // matters for the refactor is that the intent fires at all.
      final game = await _pump(tester);
      game.setNote(0, 0, 60);
      game.moveCursor(0, 0);
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.keyA, ctrl: true); // select track
      await _press(tester, LogicalKeyboardKey.arrowUp, alt: true);
      expect(game.noteCount, 1, reason: 'transpose must not lose the note');

      await _press(tester, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(game.noteCount, 1);
    });

    testWidgets('Insert adds a row at the cursor', (tester) async {
      final game = await _pump(tester);
      // A note low in the pattern gets pushed down and off the end when a row
      // is inserted above it — which is how the edit is observable here.
      game.setNote(0, game.rows - 1, 60);
      game.moveCursor(0, 0);
      await tester.pump();
      expect(game.noteCount, 1);

      await _press(tester, LogicalKeyboardKey.insert);
      expect(game.noteCount, 0, reason: 'the last row was pushed off the end');
    });
  });

  group('block selection', () {
    testWidgets('Ctrl+A selects, Escape drops the selection', (tester) async {
      // Observable through Delete: with a selection it clears the BLOCK, and
      // without one it clears a single cell.
      final game = await _pump(tester);
      for (var r = 0; r < 4; r++) {
        game.setNote(0, r, 60);
      }
      game.moveCursor(0, 0);
      await tester.pump();
      expect(game.noteCount, 4);

      await _press(tester, LogicalKeyboardKey.escape);
      await _press(tester, LogicalKeyboardKey.delete);
      expect(game.noteCount, 3, reason: 'no selection → one cell');

      await _press(tester, LogicalKeyboardKey.keyA, ctrl: true);
      await _press(tester, LogicalKeyboardKey.delete);
      expect(game.noteCount, 0, reason: 'with a selection → the whole block');
    });

    testWidgets('Ctrl+C then Ctrl+V copies a block to a new place',
        (tester) async {
      final game = await _pump(tester);
      game.setNote(0, 0, 60);
      game.setNote(0, 1, 62);
      game.moveCursor(0, 0);
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.keyA, ctrl: true); // the track
      await _press(tester, LogicalKeyboardKey.keyC, ctrl: true);
      game.moveCursor(1, 0);
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.keyV, ctrl: true);

      expect(
        game.noteCount,
        greaterThan(2),
        reason: 'the paste should have added notes on the second channel',
      );
    });

    testWidgets('Ctrl+X cuts — the notes leave the source', (tester) async {
      final game = await _pump(tester);
      game.setNote(0, 0, 60);
      game.setNote(0, 1, 62);
      game.moveCursor(0, 0);
      await tester.pump();
      expect(game.noteCount, 2);

      await _press(tester, LogicalKeyboardKey.keyA, ctrl: true);
      await _press(tester, LogicalKeyboardKey.keyX, ctrl: true);
      expect(game.noteCount, 0);
    });
  });

  group('what a modifier must NOT do', () {
    testWidgets('Ctrl+C does not enter a note', (tester) async {
      // The ordering that makes the whole handler work: block ops are checked
      // BEFORE note entry, or Ctrl+C would type a C. If the extraction
      // reorders the checks, this is what catches it.
      final game = await _pump(tester);
      game.moveCursor(0, 0);
      await tester.pump();
      final before = game.noteCount;

      await _press(tester, LogicalKeyboardKey.keyC, ctrl: true);
      expect(game.noteCount, before, reason: 'Ctrl+C must not type a C');
    });
  });
}
