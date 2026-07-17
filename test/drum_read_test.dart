// Drum Read — read a percussion-clef rhythm and tap it back. Verifies: tapping
// the drum pad on the notated onsets scores hits, and the run finishes with a
// result screen. Also exercises rendering on the percussion clef.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/drums/drum_read_screen.dart';
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
        home: DrumReadScreen(),
      ),
    );

DrumReadTester _game(WidgetTester tester) =>
    tester.state<State<DrumReadScreen>>(find.byType(DrumReadScreen))
        as DrumReadTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping the drum on the notated onsets scores hits',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    final game = _game(tester);
    final count = game.noteCount;
    expect(count, greaterThan(0));

    // Advance the ticker to each onset time and tap the pad there.
    var clock = 0;
    for (var i = 0; i < count; i++) {
      final target = game.onsetTimeMs(i);
      if (target > clock) {
        await tester.pump(Duration(milliseconds: target - clock));
        clock = target;
      }
      await tester.tap(find.byKey(DrumReadScreen.padKey), warnIfMissed: false);
      await tester.pump();
    }

    expect(_game(tester).hits, greaterThan(0));
  });

  testWidgets('the run finishes with a result screen', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    // Let the whole bar play out uncaught; it still ends cleanly.
    for (var i = 0; i < 40 && !_game(tester).finished; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(_game(tester).finished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
