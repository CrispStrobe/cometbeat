// Loop Studio style gallery + whole-groove dice, through the real screen: a
// card switches the band to that generated style (and makes it audible), the
// 🎲 rolls a different style, and each is one undoable edit.

import 'package:comet_beat/core/audio/loop_style_recipes.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

Future<void> _settle(WidgetTester tester) async {
  // The screen animates forever (playhead), so pumpAndSettle never settles.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('gallery lists every style grouped, a card picks it',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    expect(game.recipeId, isNull);

    await tester.tap(find.byKey(const Key('loop-style-gallery')));
    await _settle(tester);
    expect(find.text('Pop & Rock'), findsOneWidget);
    // The first cards are on screen; scroll to reach the rest.
    await tester.scrollUntilVisible(
      find.byKey(const Key('loop-style-card-kinderlied')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text("Children's song"), findsOneWidget);
    await tester.tap(find.byKey(const Key('loop-style-card-kinderlied')));
    await _settle(tester);

    expect(game.recipeId, 'kinderlied');
    expect(game.tempoBpm, 100);
    expect(game.enabledTracks, containsAll(['drums', 'bass', 'melody']));
  });

  testWidgets('the 🎲 rolls a different style and undo restores the last',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    game.pickStyleRecipe('funk', seed: 3);
    await tester.pump();
    expect(game.recipeId, 'funk');

    await tester.tap(find.byKey(const Key('loop-style-dice')));
    await tester.pump();
    expect(game.recipeId, isNot('funk'));
    expect(kStyleRecipes.map((r) => r.id), contains(game.recipeId));
    expect(find.byType(SnackBar), findsOneWidget);

    game.undo();
    await tester.pump();
    expect(game.recipeId, 'funk');
  });
}
