// Cello Play It — mic grading on the real cello. The mic can't run headless, so
// drive it via debug hooks: playing the shown note scores + records a cello
// item, skipping doesn't, and resolving all notes finishes.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/cello/cello_play_it_screen.dart';
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
        home: CelloPlayItScreen(),
      ),
    );

CelloPlayItTester _game(WidgetTester tester) =>
    tester.state<State<CelloPlayItScreen>>(find.byType(CelloPlayItScreen))
        as CelloPlayItTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('playing the shown note scores and records a cello item',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    final sri =
        tester.element(find.byType(CelloPlayItScreen)).read<SriService>();
    _game(tester).debugPlayed();
    await tester.pump();

    expect(_game(tester).score, 10);
    expect(_game(tester).done, 1);
    expect(sri.getDetailedBreakdown()['cello'], isNotNull);

    await tester.pump(const Duration(seconds: 1)); // drain the hit-flash timer
  });

  testWidgets('a skip advances without credit', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    _game(tester).debugSkip();
    await tester.pump();

    expect(_game(tester).done, 1);
    expect(_game(tester).score, 0);
  });

  testWidgets('playing every note finishes with a result screen',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    for (var i = 0; i < 8 && !_game(tester).finished; i++) {
      _game(tester).debugPlayed();
      await tester.pump();
    }

    expect(_game(tester).finished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
    await tester.pump(const Duration(seconds: 1)); // drain hit-flash timers
  });
}
