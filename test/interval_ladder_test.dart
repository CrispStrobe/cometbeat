// Interval Ladder — the interval-construction game. Verifies the round loop:
// four note options appear, tapping the one at the called interval scores +
// records SRI under chords.interval.build.*, and clearing all rounds finishes.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/chords/interval_ladder_screen.dart';
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
        home: IntervalLadderScreen(),
      ),
    );

IntervalLadderTester _game(WidgetTester tester) =>
    tester.state<State<IntervalLadderScreen>>(
      find.byType(IntervalLadderScreen),
    ) as IntervalLadderTester;

// Option cards are GestureDetectors inside the Wrap.
Finder _options() => find.descendant(
      of: find.byType(Wrap),
      matching: find.byType(GestureDetector),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping the interval target scores and records a build',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(_options(), findsNWidgets(IntervalLadderScreen.optionCount));
    final sri =
        tester.element(find.byType(IntervalLadderScreen)).read<SriService>();

    await tester.tap(_options().at(_game(tester).correctIndex));
    await tester.pump();
    expect(sri.getDetailedBreakdown()['chords'], isNotNull);

    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Round 2 of 8'), findsOneWidget);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    for (var r = 0; r < 8; r++) {
      await tester.tap(_options().at(_game(tester).correctIndex));
      await tester.pump(const Duration(milliseconds: 800));
    }

    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
