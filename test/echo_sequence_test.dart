import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/scales/echo_sequence_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('echo sequence: watch phase grows to one, then hands over',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
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
          home: EchoSequenceScreen(),
        ),
      ),
    );
    await tester.pump();

    // Four coloured pads, and the game opens in the "watch" phase.
    final pads = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(GestureDetector),
    );
    expect(pads, findsNWidgets(4));
    expect(find.text('Watch and listen…'), findsOneWidget);

    // The start timer adds the first note.
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Length: 1'), findsOneWidget);

    // After the one-note sequence plays out, it's the child's turn.
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Your turn — repeat it!'), findsOneWidget);
  });
}
