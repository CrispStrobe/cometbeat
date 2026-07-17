// Sing the Interval — ear→voice interval training. The mic can't run headless,
// so drive it via debug hooks: singing the top note scores + records an interval
// item, skipping doesn't, and resolving all intervals finishes.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/chords/sing_interval_screen.dart';
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
        home: SingIntervalScreen(),
      ),
    );

SingIntervalTester _game(WidgetTester tester) =>
    tester.state<State<SingIntervalScreen>>(find.byType(SingIntervalScreen))
        as SingIntervalTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('singing the top note scores and records an interval item',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    final sri =
        tester.element(find.byType(SingIntervalScreen)).read<SriService>();
    // The target pitch class is the interval's top note (0..11).
    expect(_game(tester).targetPitchClass, inInclusiveRange(0, 11));

    _game(tester).debugSang();
    await tester.pump();

    expect(_game(tester).score, 10);
    expect(sri.getDetailedBreakdown()['intervals']!.keys, ['sing']);

    await tester.pump(const Duration(seconds: 1)); // drain the reveal timer
    expect(_game(tester).done, 1);
  });

  testWidgets('a skip advances without credit', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    _game(tester).debugSkip();
    await tester.pump();

    expect(_game(tester).done, 1);
    expect(_game(tester).score, 0);
  });

  testWidgets('singing every interval finishes with a result screen',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    for (var i = 0; i < 8 && !_game(tester).finished; i++) {
      _game(tester).debugSang();
      await tester.pump(const Duration(seconds: 1)); // let the reveal advance
    }

    expect(_game(tester).finished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
