// WS-L2 (a) + (b) — seeing the loop, and seeing the song.
//
// (a) is a defect with a scale story attached. The lane strip drew a hard-coded
// 16 steps, but polymeter makes the rendered loop `lcm(16, trackLengths)` — up
// to 48. Lanes tile, so nothing ever SOUNDED wrong; the back two-thirds of a
// polymetric loop simply could not be seen, and an edit aimed at it silently
// did nothing, because `withStep` out of range returns the lane unchanged. That
// silent no-op is the part worth pinning: it only happened on long loops, which
// is exactly where nobody was looking.
//
// (b) is a picture of data that already existed — which sections there are, in
// what order the chain plays them, and how many passes each gets. Read-only for
// now, deliberately: the cheapest way to learn whether a song-level view is the
// right idea before it becomes an editor.
//
// And the section count is now a layout budget rather than a model limit, so
// these tests count from `kLoopSectionSlots` rather than from a number.

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

Future<LoopMixerTester> _open(WidgetTester tester) async {
  await pumpGame(tester, const LoopMixerScreen());
  final game = _game(tester)..debugFreezeSeams();
  if (!game.inspectorVisible) game.toggleInspector();
  await tester.pump(const Duration(milliseconds: 50));
  return game;
}

/// Shortens a track so the loop becomes lcm(16, 3) = 48 steps.
Future<void> _makePolymetric(WidgetTester tester, LoopMixerTester game) async {
  // Cycled through the badge's own ladder rather than set directly: that is
  // the only route a player has, and it keeps this honest about what is
  // reachable.
  for (var i = 0; i < 12 && game.trackSteps('drums') != 3; i++) {
    game.cycleTrackSteps('drums');
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(game.trackSteps('drums'), 3);
  expect(game.loopSteps, greaterThan(kPatternSteps));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('(a) the strip shows the loop that is actually playing', () {
    testWidgets('a 2-bar loop still draws exactly 16 cells', (tester) async {
      // The default case must be untouched: every existing lane test taps
      // these by key, and a strip that started scrolling would move them.
      final game = await _open(tester);
      expect(game.loopSteps, kPatternSteps);
      expect(find.byKey(const Key('loop-auto-drums-15')), findsOneWidget);
      expect(find.byKey(const Key('loop-auto-drums-16')), findsNothing);
    });

    testWidgets('a polymetric loop draws all of its steps', (tester) async {
      final game = await _open(tester);
      await _makePolymetric(tester, game);
      // 48 cells now exist, where before the strip stopped at 16.
      expect(find.byKey(const Key('loop-auto-drums-16')), findsOneWidget);
      expect(
        find.byKey(Key('loop-auto-drums-${game.loopSteps - 1}')),
        findsOneWidget,
      );
    });

    testWidgets('an edit BEYOND step 16 lands — it used to silently vanish',
        (tester) async {
      // The actual defect. A 16-step lane and a 48-step loop: `withStep(20, …)`
      // is out of range and returns the lane UNCHANGED, so the tap did nothing
      // at all. The lane is extended by tiling first — which is what it already
      // sounded like, since `at()` wraps.
      final game = await _open(tester);
      await _makePolymetric(tester, game);

      game.cycleAutomationStep('drums', 0);
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.hasAutomationFor('drums'), isTrue);

      final before = game.automationAt('drums', 20);
      game.cycleAutomationStep('drums', 20);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        game.automationAt('drums', 20),
        isNot(before),
        reason: 'the edit must reach a step past the old 16-cell limit',
      );
    });

    testWidgets('extending a lane keeps what it already sounded like',
        (tester) async {
      // Tiling, not padding with neutral: a 16-step lane on a 48-step loop was
      // already heard three times over, so extending it must not change the
      // first 16 steps or what follows them.
      final game = await _open(tester);
      game.cycleAutomationStep('drums', 2);
      await tester.pump(const Duration(milliseconds: 50));
      final drawn = game.automationAt('drums', 2);

      await _makePolymetric(tester, game);
      game.cycleAutomationStep('drums', 40);
      await tester.pump(const Duration(milliseconds: 50));

      expect(game.automationAt('drums', 2), drawn);
      expect(
        game.automationAt('drums', 18),
        drawn,
        reason: 'step 18 is step 2 of the second pass — tiling, not silence',
      );
    });

    testWidgets('the keyboard cursor can reach the far end', (tester) async {
      final game = await _open(tester);
      await _makePolymetric(tester, game);
      await tester.tap(find.byKey(const Key('loop-auto-drums-0')));
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < game.loopSteps + 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(game.laneCursor?.$2, game.loopSteps - 1);
    });
  });

  group('(b) the arrangement strip', () {
    testWidgets('it is hidden until there is a song to show', (tester) async {
      await _open(tester);
      expect(find.byKey(const Key('loop-arrange-0')), findsNothing);
    });

    testWidgets('a captured section appears as a block', (tester) async {
      final game = await _open(tester);
      game.captureScene(0);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('loop-arrange-0')), findsOneWidget);
      expect(find.byKey(const Key('loop-arrange-1')), findsNothing);
    });

    testWidgets('a section that repeats is drawn WIDER', (tester) async {
      // The whole point of the view: a block that plays four times is four
      // times as long in the song, and must look it.
      final game = await _open(tester);
      game.captureScene(0);
      game.captureScene(1);
      await tester.pump(const Duration(milliseconds: 50));
      final oneWide =
          tester.getSize(find.byKey(const Key('loop-arrange-0'))).width;

      while (game.sceneRepeats(0) == 1) {
        game.cycleSceneRepeats(0);
        await tester.pump(const Duration(milliseconds: 50));
      }
      final manyWide =
          tester.getSize(find.byKey(const Key('loop-arrange-0'))).width;

      expect(manyWide, greaterThan(oneWide));
      expect(
        tester.getSize(find.byKey(const Key('loop-arrange-1'))).width,
        oneWide,
        reason: 'the other section did not change',
      );
    });

    testWidgets('empty slots leave no gap in the song', (tester) async {
      // Sections are slots, and a player can fill 0 and 2. The song is what
      // PLAYS, so the strip shows two blocks, not three with a hole.
      final game = await _open(tester);
      game.captureScene(0);
      game.captureScene(2);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('loop-arrange-0')), findsOneWidget);
      expect(find.byKey(const Key('loop-arrange-1')), findsNothing);
      expect(find.byKey(const Key('loop-arrange-2')), findsOneWidget);
    });
  });

  group('the section limit is lifted', () {
    testWidgets('there are more slots than the old four', (tester) async {
      expect(kLoopSectionSlots, greaterThan(4));
      final game = await _open(tester);
      for (var i = 0; i < kLoopSectionSlots; i++) {
        game.captureScene(i);
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(game.sceneIsEmpty(kLoopSectionSlots - 1), isFalse);
      expect(
        find.byKey(const Key('loop-arrange-${kLoopSectionSlots - 1}')),
        findsOneWidget,
      );
    });

    testWidgets('and nothing overflows now that the rows scroll',
        (tester) async {
      // Eight columns do NOT fit the inspector — that is what made the session
      // grid overflow by 93px the moment the limit was raised.
      final game = await _open(tester);
      for (var i = 0; i < kLoopSectionSlots; i++) {
        game.captureScene(i);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });
  });
}
