// Verifies the registry -> tutorial wiring: opening a game via gameRoute()
// auto-shows its tutorial on the first visit only, without the game screen
// having to know anything about tutorials.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/features/games/game_registry.dart';
import 'package:klang_universum/features/games/tutorial_gate.dart';
import 'package:klang_universum/shared/tutorial/primers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

final _game = GameInfo(
  id: 'demo_reading',
  icon: Icons.music_note,
  title: (l) => 'Demo',
  subtitle: (l) => 'demo',
  builder: (_) => Scaffold(
    appBar: AppBar(title: const Text('Demo')),
    body: const Center(child: Text('game screen')),
  ),
  tutorial: readingPrimer,
);

void main() {
  // The auto-show is off by default (so it never disturbs other tests); this
  // test is exactly the one exercising it.
  setUp(() => autoShowTutorials = true);
  tearDown(() => autoShowTutorials = false);

  testWidgets('gameRoute auto-shows the tutorial on the first visit only',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpGame(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(gameRoute(_game)),
              child: const Text('open game'),
            ),
          ),
        ),
      ),
    );

    // First open → game screen AND its tutorial.
    await tester.tap(find.text('open game'));
    await tester.pumpAndSettle();
    expect(find.text('game screen'), findsOneWidget);
    expect(find.text('Reading notes'), findsOneWidget);

    // Dismiss the tutorial (page to the end) and leave the game.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Got it!'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Second open → game screen, but NO tutorial (already seen).
    await tester.tap(find.text('open game'));
    await tester.pumpAndSettle();
    expect(find.text('game screen'), findsOneWidget);
    expect(find.text('Reading notes'), findsNothing);
  });

  testWidgets('the "?" overlay reopens the primer on demand', (tester) async {
    // Reopen must work regardless of the (first-run) auto-show.
    autoShowTutorials = false;
    SharedPreferences.setMockInitialValues({});

    await pumpGame(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(gameRoute(_game)),
              child: const Text('open game'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open game'));
    await tester.pumpAndSettle();
    // No auto-show (flag off), but the game exposes a "?" reopen button.
    expect(find.text('Reading notes'), findsNothing);
    expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);

    // Tapping it opens the primer.
    await tester.tap(find.byIcon(Icons.help_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Reading notes'), findsOneWidget);
  });

  group('helpPrimerFor — module-primer fallback', () {
    test('every registered game offers help (own primer or module fallback)',
        () {
      for (final game in kGamesById.values) {
        expect(
          helpPrimerFor(game),
          isNotNull,
          reason: '${game.id} should have a "?" primer',
        );
      }
    });

    test('a game with its own primer uses it', () {
      final g = gameInfoById('note_reading_bass')!;
      expect(helpPrimerFor(g), same(readingBassPrimer));
    });

    test('a game without its own primer falls back to its module primer', () {
      final g = gameInfoById('rhythm_tap')!; // note_values, no own tutorial
      expect(g.tutorial, isNull);
      expect(helpPrimerFor(g), same(noteValuesPrimer));
    });
  });
}
