// Beat Runner — read & play a rhythm. The Ticker is the master clock (driven by
// pump): tapping as a note lands scores; letting a note pass untapped does not.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/measures/beat_runner_screen.dart';
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
        home: BeatRunnerScreen(),
      ),
    );

BeatRunnerTester _game(WidgetTester tester) =>
    tester.state<State<BeatRunnerScreen>>(find.byType(BeatRunnerScreen))
        as BeatRunnerTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping as the first note lands scores a hit', (tester) async {
    await tester.pumpWidget(_app());
    final game = _game(tester);
    expect(game.noteCount, greaterThan(0));

    await tester.pump(Duration(milliseconds: game.noteTimeMs(0)));
    await tester.tap(find.byKey(BeatRunnerScreen.padKey));
    await tester.pump();

    expect(game.hits, 1);
    expect(game.score, greaterThan(0));
  });

  testWidgets('letting a note pass untapped is not a hit', (tester) async {
    await tester.pumpWidget(_app());
    final game = _game(tester);

    await tester.pump(Duration(milliseconds: game.noteTimeMs(0) + 300));
    expect(game.hits, 0);
    expect(game.score, 0);
  });
}
