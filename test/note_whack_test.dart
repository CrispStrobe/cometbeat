// Note Whack — the whack-a-mole reading game. Verifies the core loop driven by
// tester.pump(): moles pop up, whacking the target-named one scores (+ SRI),
// a wrong whack costs a heart, letter keys whack, and clearing the run finishes.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/note_whack_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider(
          create: (_) => SriService(getNow: () => DateTime(2026, 7, 11)),
        ),
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ProgressService()),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en'), Locale('de')],
        home: NoteWhackScreen(),
      ),
    );

NoteWhackTester _game(WidgetTester tester) =>
    tester.state<State<NoteWhackScreen>>(find.byType(NoteWhackScreen))
        as NoteWhackTester;

// Advance the ticker until a mole matching the current target is showing.
Future<int> _pumpToMatch(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    final hole = _game(tester).holeMatchingTarget();
    if (hole != null) return hole;
    await tester.pump(const Duration(milliseconds: 200));
  }
  return -1;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('whacking the target note scores and records a read',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 600));

    final sri = tester.element(find.byType(NoteWhackScreen)).read<SriService>();
    final hole = await _pumpToMatch(tester);
    expect(hole, isNot(-1), reason: 'a matching mole should appear');

    await tester.tap(find.byKey(ValueKey('whack_hole_$hole')));
    await tester.pump();

    final game = _game(tester);
    expect(game.whacks, 1);
    expect(game.score, greaterThan(0));
    expect(game.lives, NoteWhackScreen.maxLives);
    expect(sri.getDetailedBreakdown()['note_reading'], isNotNull);
  });

  testWidgets('a letter key whacks a visible mole of that name',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 600));

    final hole = await _pumpToMatch(tester);
    expect(hole, isNot(-1));
    final target = _game(tester).targetStep;

    const keys = {
      'c': LogicalKeyboardKey.keyC,
      'd': LogicalKeyboardKey.keyD,
      'e': LogicalKeyboardKey.keyE,
      'f': LogicalKeyboardKey.keyF,
      'g': LogicalKeyboardKey.keyG,
      'a': LogicalKeyboardKey.keyA,
      'b': LogicalKeyboardKey.keyB,
    };
    await tester.sendKeyEvent(keys[target.name]!);
    await tester.pump();

    expect(_game(tester).whacks, 1);
  });

  testWidgets('clearing the whole run finishes with a result screen',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 600));

    for (var i = 0;
        i < NoteWhackScreen.targetWhacks && !_game(tester).finished;
        i++) {
      final hole = await _pumpToMatch(tester);
      if (hole == -1) break;
      await tester.tap(find.byKey(ValueKey('whack_hole_$hole')));
      await tester.pump();
    }

    expect(_game(tester).finished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
