// Strum Toy — the free creative jam. Verifies it builds, chords are selectable,
// and strumming / plucking runs without error (no scoring to assert — it's a toy).

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/guitar/strum_toy_screen.dart';
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
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en'), Locale('de')],
        home: StrumToyScreen(),
      ),
    );

StrumToyTester _toy(WidgetTester tester) =>
    tester.state<State<StrumToyScreen>>(find.byType(StrumToyScreen))
        as StrumToyTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('chords are selectable and default to C', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(_toy(tester).chordName, 'C');
    expect(find.widgetWithText(ChoiceChip, 'G'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Em'));
    await tester.pump();
    expect(_toy(tester).chordName, 'Em');
  });

  testWidgets('strumming down then up runs without error', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    _toy(tester).debugStrum(down: true);
    await tester.pump(const Duration(milliseconds: 250));
    _toy(tester).debugStrum(down: false);
    await tester.pump(const Duration(milliseconds: 250));

    expect(tester.takeException(), isNull);
  });
}
