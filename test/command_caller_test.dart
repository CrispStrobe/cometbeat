// Follow the Conductor — conducting patterns. The Ticker is the master clock
// (driven by pump): tapping the lit direction zone on the beat scores; letting
// a beat pass untapped does not.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/scales/command_caller_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
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
        home: CommandCallerScreen(),
      ),
    );

CommandCallerTester _game(WidgetTester tester) =>
    tester.state<State<CommandCallerScreen>>(find.byType(CommandCallerScreen))
        as CommandCallerTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('conducting the beat on the downbeat scores a hit',
      (tester) async {
    await tester.pumpWidget(_app());
    final game = _game(tester);

    // Advance to the first beat (the count-in lead is 1400ms).
    await tester.pump(const Duration(milliseconds: 1400));
    final dir = game.expectedNow;
    expect(dir, isNotNull, reason: 'a beat should be active');

    await tester.tap(find.byKey(CommandCallerScreen.zoneKey(dir!)));
    await tester.pump();

    expect(game.hits, 1);
    expect(game.score, greaterThan(0));
  });

  testWidgets('a wrong direction does not score', (tester) async {
    await tester.pumpWidget(_app());
    final game = _game(tester);

    await tester.pump(const Duration(milliseconds: 1400));
    final dir = game.expectedNow!;
    // Tap a different zone than the one expected.
    final wrong = Beat.values.firstWhere((b) => b != dir);
    await tester.tap(find.byKey(CommandCallerScreen.zoneKey(wrong)));
    await tester.pump();

    expect(game.hits, 0);
    expect(game.score, 0);
  });
}
