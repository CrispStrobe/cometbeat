// WS-L1 — driving the Loop Studio's lane grid from the keyboard.
//
// The card's acceptance is one sentence: "a widget test drives the grid
// entirely from the keyboard". That is the whole point of this file — not
// "the key handler was called", but a shape drawn into a lane using nothing but
// key presses, and then read back out of the engine.
//
// Half the card was already shipped by the thing that unblocked it: WS-T3's
// step three wired space, stop, undo and redo into this screen. What was
// missing is a CURSOR — Loop Studio had no notion of a selected cell at all —
// so that is what these tests are about.
//
// Two properties matter beyond "it moves":
//
//   the cursor does not EXIST until a key asks for it, because an outline
//   around a cell nobody selected reads as a selection they did not make;
//
//   typing keeps the drop-when-neutral rule the tap path has, because "no lane"
//   must stay distinguishable from "a flat lane" — that is what keeps a groove
//   using no automation byte-identical, and a second way in must not be a way
//   around it.

import 'package:comet_beat/core/audio/loop_automation.dart';
import 'package:comet_beat/core/audio/loop_engine.dart' show kPatternSteps;
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

/// The inspector hosts the lane strip, and the screen animates continuously —
/// bounded pumps only.
Future<LoopMixerTester> _open(WidgetTester tester) async {
  await pumpGame(tester, const LoopMixerScreen());
  final game = _game(tester)..debugFreezeSeams();
  if (!game.inspectorVisible) game.toggleInspector();
  await tester.pump(const Duration(milliseconds: 50));
  // The screen's key handler lives on a focus node; give it the focus a real
  // player gives it by tapping into the surface.
  await tester.tap(find.byKey(const Key('loop-auto-drums-0')));
  await tester.pump(const Duration(milliseconds: 50));
  return game;
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the cursor', () {
    testWidgets('does not exist until a key asks for it', (tester) async {
      await pumpGame(tester, const LoopMixerScreen());
      final game = _game(tester)..debugFreezeSeams();
      if (!game.inspectorVisible) game.toggleInspector();
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.laneCursor, isNull);
    });

    testWidgets('a tap puts it where the finger was', (tester) async {
      // So the keyboard carries on from where the touch left off rather than
      // from some other remembered cell.
      final game = await _open(tester);
      expect(game.laneCursor, ('drums', 0));
    });

    testWidgets('arrows move it across steps and tracks', (tester) async {
      final game = await _open(tester);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(game.laneCursor, ('drums', 2));

      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(game.laneCursor?.$1, isNot('drums'));
      expect(game.laneCursor?.$2, 2, reason: 'the step is kept');

      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(game.laneCursor, ('drums', 2));

      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(game.laneCursor, ('drums', 1));
    });

    testWidgets('it CLAMPS at the edges rather than wrapping', (tester) async {
      // Wrapping steps would jump from the end of a bar to its start, which
      // reads as a mis-key; wrapping tracks would jump the drums to the
      // sparkle. Staying put is the honest answer.
      final game = await _open(tester);
      for (var i = 0; i < 4; i++) {
        await _press(tester, LogicalKeyboardKey.arrowLeft);
        await _press(tester, LogicalKeyboardKey.arrowUp);
      }
      expect(game.laneCursor, ('drums', 0));

      for (var i = 0; i < kPatternSteps + 4; i++) {
        await _press(tester, LogicalKeyboardKey.arrowRight);
      }
      expect(game.laneCursor?.$2, kPatternSteps - 1);
    });
  });

  group('typing a value', () {
    testWidgets('a digit sets the cell under the cursor', (tester) async {
      final game = await _open(tester);
      await _press(tester, LogicalKeyboardKey.digit0);
      expect(game.automationAt('drums', 0), 0.0);
      expect(
        game.automationAt('drums', 1),
        1.0,
        reason: 'only the cell under the cursor moved',
      );
    });

    testWidgets('0 is the bottom of the range and 9 the top', (tester) async {
      final game = await _open(tester);
      await _press(tester, LogicalKeyboardKey.digit0);
      expect(game.automationAt('drums', 0), 0.0);
      await _press(tester, LogicalKeyboardKey.digit9);
      expect(game.automationAt('drums', 0), 1.0);
      await _press(tester, LogicalKeyboardKey.digit4);
      expect(game.automationAt('drums', 0), closeTo(4 / 9, 1e-9));
    });

    testWidgets('the numeric keypad works too', (tester) async {
      final game = await _open(tester);
      await _press(tester, LogicalKeyboardKey.numpad3);
      expect(game.automationAt('drums', 0), closeTo(3 / 9, 1e-9));
    });

    testWidgets('typing needs a cursor — a stray digit does nothing',
        (tester) async {
      await pumpGame(tester, const LoopMixerScreen());
      final game = _game(tester)..debugFreezeSeams();
      if (!game.inspectorVisible) game.toggleInspector();
      await tester.pump(const Duration(milliseconds: 50));
      await _press(tester, LogicalKeyboardKey.digit0);
      expect(game.hasAutomationFor('drums'), isFalse);
    });

    testWidgets('a lane typed back to flat is DROPPED, not stored',
        (tester) async {
      // The rule the whole automation arc rests on, restated for the keyboard:
      // "no lane" and "a flat lane" have to stay different, because that is
      // what keeps an un-automated groove byte-identical.
      final game = await _open(tester);
      await _press(tester, LogicalKeyboardKey.digit3);
      expect(game.hasAutomationFor('drums'), isTrue);
      await _press(tester, LogicalKeyboardKey.digit9);
      expect(
        game.hasAutomationFor('drums'),
        isFalse,
        reason: '9 is full volume, i.e. neutral — the lane must go',
      );
    });

    testWidgets('delete returns a cell to neutral', (tester) async {
      final game = await _open(tester);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await _press(tester, LogicalKeyboardKey.digit0);
      await _press(tester, LogicalKeyboardKey.digit0);
      expect(game.hasAutomationFor('drums'), isTrue);
      await _press(tester, LogicalKeyboardKey.delete);
      expect(game.automationAt('drums', 1), 1.0);
    });
  });

  testWidgets('the whole grid is drivable from the keyboard alone',
      (tester) async {
    // The card's acceptance, stated as the thing a player would actually do:
    // draw a descending fade across the first four steps without touching the
    // screen again, then read it back off the engine.
    final game = await _open(tester);
    const digits = [
      LogicalKeyboardKey.digit9,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit0,
    ];
    for (var i = 0; i < digits.length; i++) {
      await _press(tester, digits[i]);
      if (i < digits.length - 1) {
        await _press(tester, LogicalKeyboardKey.arrowRight);
      }
    }
    expect(game.automationAt('drums', 0), 1.0);
    expect(game.automationAt('drums', 1), closeTo(6 / 9, 1e-9));
    expect(game.automationAt('drums', 2), closeTo(3 / 9, 1e-9));
    expect(game.automationAt('drums', 3), 0.0);
    expect(game.laneCursor, ('drums', 3));
  });

  testWidgets('the cursor follows the PARAMETER switch', (tester) async {
    // The strip edits one parameter at a time (D2), so typing has to land on
    // whichever one is on show — not always the volume lane.
    final game = await _open(tester);
    // `_open` taps a cell to take focus, and a tap CYCLES the level lane — so
    // clear it first, or the assertion below would be reading that tap.
    game.clearAutomation('drums');
    await tester.pump(const Duration(milliseconds: 50));
    game.setAutomationParam(AutomationParam.pan);
    await tester.pump(const Duration(milliseconds: 50));
    await _press(tester, LogicalKeyboardKey.digit0);
    expect(game.hasAutomationForParam('drums', AutomationParam.pan), isTrue);
    expect(
      game.hasAutomationForParam('drums', AutomationParam.level),
      isFalse,
      reason: 'the volume lane was not the one on show',
    );
  });

  testWidgets('Ctrl+D duplicates the track the cursor is on', (tester) async {
    // The last item on the card. I had recorded this as undoable for want of a
    // duplicate intent; @daw-suite corrected me — `AppIntent.duplicate` has
    // been in the shared vocabulary all along, bound to Ctrl+D.
    final game = await _open(tester);
    final before = game.trackIds.length;
    await _press(tester, LogicalKeyboardKey.arrowDown);
    final onTrack = game.laneCursor!.$1;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await _press(tester, LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump(const Duration(milliseconds: 50));

    expect(game.trackIds.length, before + 1);
    expect(
      game.trackIds.last,
      startsWith(onTrack),
      reason: 'it duplicates the track under the CURSOR, not the first one',
    );
  });

  // NOTE on what is deliberately NOT tested here: WS-T3's own transport and
  // undo bindings. They are covered by `keymap_hosting_test`, which belongs to
  // the agent who wrote them; re-asserting them from this file would be two
  // suites owning one behaviour, and the one that matters when I extend
  // `_onKey` is theirs staying green.
}
