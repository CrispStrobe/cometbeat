// A4 — drawing an automation lane.
//
// Per-eighth-step values rather than a breakpoint curve, chosen so a child who
// can already build a beat can build a fade with no new gesture: tapping a step
// cycles it, exactly like the tune grid, the beat grid, the loop-length badge
// and the swing badge.
//
// The property this must not break is the one every slice has carried: a track
// with no lane is DISTINCT from a track with a flat one, because that is what
// keeps a groove without automation byte-for-byte identical. So a lane that has
// been cycled back to flat is dropped, not stored.

import 'package:comet_beat/core/audio/loop_engine.dart' show kPatternSteps;
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

/// The inspector is closed by default; this screen animates continuously, so
/// bounded pumps only.
Future<LoopMixerTester> _open(WidgetTester tester) async {
  await pumpGame(tester, const LoopMixerScreen());
  final game = _game(tester)..debugFreezeSeams();
  if (!game.inspectorVisible) game.toggleInspector();
  await tester.pump(const Duration(milliseconds: 50));
  return game;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a track starts with no lane, reading as full volume',
      (tester) async {
    final game = await _open(tester);
    expect(game.hasAutomationFor('drums'), isFalse);
    expect(game.automationAt('drums', 0), 1.0);
  });

  testWidgets('there is a tappable cell per step', (tester) async {
    final game = await _open(tester);
    expect(find.byKey(const Key('loop-auto-drums-0')), findsOneWidget);
    expect(find.byKey(Key('loop-auto-drums-${kPatternSteps - 1}')),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('loop-auto-drums-0')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.hasAutomationFor('drums'), isTrue);
    expect(game.automationAt('drums', 0), lessThan(1.0));
  });

  testWidgets('cycling a step all the way round DROPS the lane',
      (tester) async {
    // Back to flat must mean "no lane", not "a flat lane" — the byte-identical
    // guarantee depends on the difference.
    final game = await _open(tester);
    for (var i = 0; i < 4; i++) {
      game.cycleAutomationStep('drums', 0);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.automationAt('drums', 0), 1.0);
    expect(game.hasAutomationFor('drums'), isFalse,
        reason: 'a flat lane should not be stored');
  });

  testWidgets('steps are independent', (tester) async {
    final game = await _open(tester);
    game.cycleAutomationStep('drums', 3);
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.automationAt('drums', 3), lessThan(1.0));
    expect(game.automationAt('drums', 4), 1.0, reason: 'only step 3 moved');
  });

  testWidgets('one track keeps its lane while the others have none',
      (tester) async {
    final game = await _open(tester);
    game.cycleAutomationStep('drums', 0);
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.hasAutomationFor('drums'), isTrue);
    expect(game.hasAutomationFor('bass'), isFalse);
  });

  testWidgets('clearing removes the whole lane', (tester) async {
    final game = await _open(tester);
    game.cycleAutomationStep('drums', 0);
    game.cycleAutomationStep('drums', 5);
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.hasAutomationFor('drums'), isTrue);

    game.clearAutomation('drums');
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.hasAutomationFor('drums'), isFalse);
    expect(game.automationAt('drums', 5), 1.0);
  });
}
