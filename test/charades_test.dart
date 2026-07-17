// Dynamics & Tempo Charades — the expressive-vocabulary ear game. Verifies the
// round loop: options appear, picking the right term scores + records SRI under
// expression.hear.*, and clearing all rounds finishes.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/expression/charades_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
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
        home: CharadesScreen(),
      ),
    );

CharadesTester _game(WidgetTester tester) =>
    tester.state<State<CharadesScreen>>(find.byType(CharadesScreen))
        as CharadesTester;

// Tap the button whose label matches the current round's correct answer.
Future<void> _solveRound(WidgetTester tester) async {
  final label = _game(tester).answerLabel;
  await tester.tap(find.widgetWithText(FilledButton, label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a round shows options and records an expression answer',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.byType(FilledButton), findsWidgets);
    final sri = tester.element(find.byType(CharadesScreen)).read<SriService>();

    await _solveRound(tester);
    expect(sri.getDetailedBreakdown()['expression'], isNotNull);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    for (var r = 0; r < 12 && !_game(tester).isFinished; r++) {
      await _solveRound(tester);
    }

    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
