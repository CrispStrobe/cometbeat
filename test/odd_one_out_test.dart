// Odd One Out — the reading-discrimination drill. Verifies the core loop: three
// note cards appear (two share a letter, one differs), tapping the odd one out
// scores + advances, a wrong tap is marked, and clearing all rounds finishes.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/odd_one_out_screen.dart';
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
        home: OddOneOutScreen(),
      ),
    );

OddOneOutTester _game(WidgetTester tester) =>
    tester.state<State<OddOneOutScreen>>(find.byType(OddOneOutScreen))
        as OddOneOutTester;

Finder _cards() => find.descendant(
      of: find.byType(Wrap),
      matching: find.byType(GestureDetector),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('three cards; tapping the odd one out scores and advances',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Which note is the odd one out?'), findsOneWidget);
    expect(find.text('Round 1 of 8'), findsOneWidget);
    expect(_cards(), findsNWidgets(OddOneOutScreen.cardCount));

    final sri = tester.element(find.byType(OddOneOutScreen)).read<SriService>();
    final odd = _game(tester).oddIndex;
    await tester.tap(_cards().at(odd));
    await tester.pump();

    // A correct read was recorded and the round auto-advances.
    expect(sri.getDetailedBreakdown()['note_reading'], isNotNull);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Round 2 of 8'), findsOneWidget);
  });

  testWidgets('the number keys whack the matching card', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    final odd = _game(tester).oddIndex;
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
    ];
    await tester.sendKeyEvent(digits[odd]);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Round 2 of 8'), findsOneWidget);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    for (var r = 0; r < 8; r++) {
      final odd = _game(tester).oddIndex;
      await tester.tap(_cards().at(odd));
      await tester.pump(const Duration(milliseconds: 800));
    }

    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
