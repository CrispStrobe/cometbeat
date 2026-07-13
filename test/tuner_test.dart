// Tuner upgrades — the mic can't run headless, but the A4 reference selector,
// the instrument selector and the guided per-string chips are pure UI state, so
// we can drive them and assert the screen reshapes without throwing.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/features/games/cello/tuner_spike_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => ChangeNotifierProvider(
      create: (_) => SettingsService(),
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en'), Locale('de')],
        home: TunerSpikeScreen(),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('reference-pitch menu offers 415/440/442 and switches',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text('A4 = 415 Hz'), findsOneWidget);
    expect(find.text('A4 = 440 Hz'), findsOneWidget);
    expect(find.text('A4 = 442 Hz'), findsOneWidget);

    await tester.tap(find.text('A4 = 442 Hz'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking an instrument reveals its open-string chips',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    // Chromatic (default) shows no string chips.
    expect(find.byType(ChoiceChip), findsNothing);

    await tester.tap(find.byIcon(Icons.music_note));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guitar'));
    await tester.pumpAndSettle();

    // Guitar has six strings → six selectable chips, and a "pick a string" hint.
    expect(find.byType(ChoiceChip), findsNWidgets(6));
    expect(find.text('Tap a string to tune it'), findsOneWidget);

    // Selecting a string is a guided target: the hint goes away, no throw.
    await tester.tap(find.byType(ChoiceChip).first);
    await tester.pumpAndSettle();
    expect(find.text('Tap a string to tune it'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
