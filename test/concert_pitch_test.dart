// Concert Pitch — transposing-instrument reading (crisp_notation Transposition).
// Verifies the round loop: the correct concert-pitch letter is offered, picking
// it scores + records SRI under transpose.*, and clearing all rounds finishes.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/transpose/concert_pitch_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart' hide Step;
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
        home: ConcertPitchScreen(),
      ),
    );

ConcertPitchTester _game(WidgetTester tester) =>
    tester.state<State<ConcertPitchScreen>>(find.byType(ConcertPitchScreen))
        as ConcertPitchTester;

Future<void> _solveRound(WidgetTester tester) async {
  // English default naming: the button label is the step letter, upper-cased.
  final label = _game(tester).answerStep.name.toUpperCase();
  await tester.tap(find.widgetWithText(FilledButton, label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the concert pitch is offered and picking it advances',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Round 1 of 10'), findsOneWidget);
    final sri =
        tester.element(find.byType(ConcertPitchScreen)).read<SriService>();

    await _solveRound(tester);
    expect(sri.getDetailedBreakdown()['transpose'], isNotNull);
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
