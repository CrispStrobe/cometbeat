// Ledger Leap — count the ledger lines. A correct count advances the round and
// scores; a wrong count does not (the app's no-fail loop).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_reading/ledger_leap_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
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
        home: LedgerLeapScreen(),
      ),
    );

LedgerLeapTester _game(WidgetTester tester) =>
    tester.state<State<LedgerLeapScreen>>(find.byType(LedgerLeapScreen))
        as LedgerLeapTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the right ledger-line count advances the round and scores',
      (tester) async {
    await tester.pumpWidget(_app());
    final game = _game(tester);
    expect(find.text('How many ledger lines?'), findsOneWidget);
    expect(game.round, 0);

    await tester.tap(find.widgetWithText(FilledButton, '${game.correctLines}'));
    await tester.pump(const Duration(milliseconds: 800));

    expect(game.round, 1);
    expect(game.score, greaterThan(0));
  });

  testWidgets('a wrong count never advances', (tester) async {
    await tester.pumpWidget(_app());
    final game = _game(tester);

    final wrong = game.correctLines == 1 ? 2 : 1;
    await tester.tap(find.widgetWithText(FilledButton, '$wrong'));
    await tester.pump(const Duration(milliseconds: 800));

    expect(game.round, 0);
    expect(game.score, 0);
  });
}
