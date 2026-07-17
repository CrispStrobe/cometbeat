// Staff Runner — the endless sight-reading sprint. Verifies: naming the note
// scores + records a read, a timeout costs a life, and three misses end the run.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/staff_runner_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
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
        home: StaffRunnerScreen(),
      ),
    );

StaffRunnerTester _game(WidgetTester tester) =>
    tester.state<State<StaffRunnerScreen>>(find.byType(StaffRunnerScreen))
        as StaffRunnerTester;

const _keys = {
  'c': LogicalKeyboardKey.keyC,
  'd': LogicalKeyboardKey.keyD,
  'e': LogicalKeyboardKey.keyE,
  'f': LogicalKeyboardKey.keyF,
  'g': LogicalKeyboardKey.keyG,
  'a': LogicalKeyboardKey.keyA,
  'b': LogicalKeyboardKey.keyB,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('naming the note scores and records a read', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));

    final sri =
        tester.element(find.byType(StaffRunnerScreen)).read<SriService>();
    await tester.sendKeyEvent(_keys[_game(tester).targetStep.name]!);
    await tester.pump();

    expect(_game(tester).score, 1);
    expect(_game(tester).lives, StaffRunnerScreen.maxLives);
    expect(sri.getDetailedBreakdown()['note_reading'], isNotNull);
  });

  testWidgets('letting the timer run out costs a life', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));
    expect(_game(tester).lives, StaffRunnerScreen.maxLives);

    // The level-1 budget is 4s; pump past it so the note times out.
    await tester.pump(const Duration(milliseconds: 4200));
    expect(_game(tester).lives, lessThan(StaffRunnerScreen.maxLives));
    expect(_game(tester).score, 0);
  });

  testWidgets('three misses end the run', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));

    // Deliberately name the wrong letter three times.
    for (var i = 0; i < 3 && !_game(tester).finished; i++) {
      final wrong = _game(tester).targetStep == Step.c ? Step.d : Step.c;
      await tester.sendKeyEvent(_keys[wrong.name]!);
      await tester.pump();
    }

    expect(_game(tester).finished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
