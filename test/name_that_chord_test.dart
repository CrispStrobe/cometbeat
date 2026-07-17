// Name That Chord — chord identification quiz (crisp_notation identifyChord). Verifies
// the round loop: options appear, the answer symbol is among them, picking it
// scores + records SRI under chords.name.*, and clearing all rounds finishes.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/chords/name_that_chord_screen.dart';
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
        home: NameThatChordScreen(),
      ),
    );

NameThatChordTester _game(WidgetTester tester) =>
    tester.state<State<NameThatChordScreen>>(find.byType(NameThatChordScreen))
        as NameThatChordTester;

Future<void> _solveRound(WidgetTester tester) async {
  final symbol = _game(tester).answerSymbol;
  await tester.tap(find.widgetWithText(FilledButton, symbol));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the correct symbol is offered and picking it advances',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Round 1 of 10'), findsOneWidget);
    final symbol = _game(tester).answerSymbol;
    expect(find.widgetWithText(FilledButton, symbol), findsOneWidget);

    final sri =
        tester.element(find.byType(NameThatChordScreen)).read<SriService>();
    await _solveRound(tester);

    expect(sri.getDetailedBreakdown()['chords'], isNotNull);
    expect(find.text('Round 2 of 10'), findsOneWidget);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    for (var r = 0; r < 10; r++) {
      await _solveRound(tester);
    }

    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
