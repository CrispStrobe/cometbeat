// Roman Numerals — read/hear a diatonic triad, name its numeral. Driven through
// the UI: the correct symbol varies per round, so tap whatever the game reports
// as the target and check it scores + records under harmony.roman.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/harmony/roman_numeral_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

Widget _wrap(SriService sri) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider<SriService>.value(value: sri),
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
        home: RomanNumeralScreen(),
      ),
    );

RomanNumeralTester _game(WidgetTester tester) =>
    tester.state<State<RomanNumeralScreen>>(find.byType(RomanNumeralScreen))
        as RomanNumeralTester;

// Same tree but with a ProgressService pre-seeded to a mastery level, so the
// game runs its widened pool (minor keys + inversions).
Widget _wrapMastered(
  SriService sri,
  ProgressService progress, {
  Random? random,
}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider<SriService>.value(value: sri),
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider<ProgressService>.value(value: progress),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('de')],
        home: RomanNumeralScreen(random: random),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('at mastery, minor keys + inversions stay answerable',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    final progress = ProgressService();
    progress.recordResult('roman_numeral', score: 900, stars: 3); // wide pool
    await useGameSurface(tester);
    await tester.pumpWidget(_wrapMastered(sri, progress));
    await tester.pump();

    // Every round's target — which may now be a minor numeral or carry a
    // figure (V6, ii6/4) — is present as a button and clears the round.
    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      expect(
        find.widgetWithText(FilledButton, _game(tester).targetSymbol),
        findsWidgets,
      );
      await tester.tap(
        find.widgetWithText(FilledButton, _game(tester).targetSymbol).first,
      );
      await tester.pump(const Duration(milliseconds: 900));
    }
    expect(_game(tester).isFinished, isTrue);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('at mastery, seventh-chord rounds appear and are answerable',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    final progress = ProgressService();
    progress.recordResult('roman_numeral', score: 900, stars: 3);
    await useGameSurface(tester);
    // Seeded RNG → a deterministic round sequence that includes sevenths.
    await tester.pumpWidget(_wrapMastered(sri, progress, random: Random(7)));
    await tester.pump();

    var sawSeventh = false;
    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      final g = _game(tester);
      if (g.isSeventhRound) {
        sawSeventh = true;
        // A seventh numeral carries a 7 figure (V7, ii7, viiø7…).
        expect(g.targetSymbol, contains('7'), reason: g.targetSymbol);
      }
      // Whatever the target is, its button clears the round.
      await tester.tap(
        find.widgetWithText(FilledButton, g.targetSymbol).first,
      );
      await tester.pump(const Duration(milliseconds: 900));
    }
    expect(sawSeventh, isTrue, reason: 'mastery mixes in seventh chords');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('offers four numeral choices incl. the target and a replay',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await useGameSurface(tester);
    await tester.pumpWidget(_wrap(sri));
    await tester.pump();

    // The target's button is on screen, and a "hear again" control exists.
    expect(
      find.widgetWithText(FilledButton, _game(tester).targetSymbol),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
  });

  testWidgets('answering the target scores and records under harmony.roman',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await useGameSurface(tester);
    await tester.pumpWidget(_wrap(sri));
    await tester.pump();

    await tester.tap(
      find.widgetWithText(FilledButton, _game(tester).targetSymbol),
    );
    await tester.pump();

    expect(sri.getDetailedBreakdown()['harmony']!.keys, ['roman']);
    await tester
        .pump(const Duration(seconds: 1)); // drain advance/replay timers
  });

  testWidgets('clearing all ten rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await useGameSurface(tester);
    await tester.pumpWidget(_wrap(sri));
    await tester.pump();

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await tester.tap(
        find.widgetWithText(FilledButton, _game(tester).targetSymbol),
      );
      await tester.pump(const Duration(milliseconds: 900)); // auto-advance
    }

    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
    await tester.pump(const Duration(seconds: 1)); // drain any trailing timers
  });
}
