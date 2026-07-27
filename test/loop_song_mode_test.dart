// L4 — per-section repeats: A×4, B×2, A×4.
//
// Chaining advanced after exactly one pass through each section, so an
// arrangement could only ever be "one of each, round and round". Real song mode
// needs a section to hold for a few bars before the next one arrives.
//
// The default is 1, which is precisely the behaviour that shipped, so an
// existing chain sounds unchanged until somebody asks for more.

import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

/// Sections A (drums) and B (drums+bass), chaining on, A playing.
Future<LoopMixerTester> _chained(WidgetTester tester) async {
  await pumpGame(tester, const LoopMixerScreen());
  final game = _game(tester)..debugFreezeSeams();

  game.toggleTrack('drums');
  await tester.pump();
  game.captureScene(0);
  await tester.pump();

  game.toggleTrack('bass');
  await tester.pump();
  game.captureScene(1);
  await tester.pump();

  game.launchScene(0);
  await tester.pump();
  if (!game.isChaining) game.toggleChain();
  await tester.pump();
  return game;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the default is one pass per section, exactly as before',
      (tester) async {
    final game = await _chained(tester);
    expect(game.sceneRepeats(0), 1);

    expect(game.enabledTracks, {'drums'});
    game.debugLoopWrap();
    await tester.pump();
    expect(game.enabledTracks, {'drums', 'bass'}, reason: 'advanced after one');
  });

  testWidgets('a repeat count holds the section for that many loops',
      (tester) async {
    final game = await _chained(tester);
    game.cycleSceneRepeats(0); // 1 -> 2
    await tester.pump();
    expect(game.sceneRepeats(0), 2);

    game.debugLoopWrap();
    await tester.pump();
    expect(
      game.enabledTracks,
      {'drums'},
      reason: 'still on A for its second pass',
    );

    game.debugLoopWrap();
    await tester.pump();
    expect(game.enabledTracks, {'drums', 'bass'}, reason: 'now it advances');
  });

  testWidgets('the count ladder wraps back to 1', (tester) async {
    // The child's undo is another tap.
    final game = await _chained(tester);
    for (final expected in [2, 4, 8, 1]) {
      game.cycleSceneRepeats(0);
      await tester.pump();
      expect(game.sceneRepeats(0), expected);
    }
  });

  testWidgets('each section keeps its own count', (tester) async {
    final game = await _chained(tester);
    game.cycleSceneRepeats(1); // B -> 2
    await tester.pump();
    expect(game.sceneRepeats(0), 1, reason: 'A untouched');
    expect(game.sceneRepeats(1), 2);
  });

  testWidgets('launching a section restarts its count', (tester) async {
    // Otherwise a half-finished pass from last time would cut the new one short.
    final game = await _chained(tester);
    game.cycleSceneRepeats(0);
    await tester.pump();

    game.debugLoopWrap(); // A pass 1 of 2
    await tester.pump();
    game.launchScene(0); // jump back to A
    await tester.pump();

    game.debugLoopWrap();
    await tester.pump();
    expect(
      game.enabledTracks,
      {'drums'},
      reason: 'the count should have restarted, giving A a full two passes',
    );
  });
}
