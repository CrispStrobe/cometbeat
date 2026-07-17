// Note Snake — reading + arcade snake. Verifies: eating the matching-letter
// food scores + records a read, and eating the wrong letter ends the run.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/note_snake_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
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
        home: NoteSnakeScreen(),
      ),
    );

NoteSnakeTester _game(WidgetTester tester) =>
    tester.state<State<NoteSnakeScreen>>(find.byType(NoteSnakeScreen))
        as NoteSnakeTester;

Step _wrong(Step s) => s == Step.c ? Step.d : Step.c;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('eating the matching note scores and records a read',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    final sri = tester.element(find.byType(NoteSnakeScreen)).read<SriService>();
    final game = _game(tester);
    game.debugFoodAhead(game.targetStep);

    // One step onto the food (level-1 step is 480ms).
    await tester.pump(const Duration(milliseconds: 520));

    expect(_game(tester).score, 1);
    expect(sri.getDetailedBreakdown()['note_reading'], isNotNull);
  });

  testWidgets('eating the wrong note ends the run', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    final game = _game(tester);
    game.debugFoodAhead(_wrong(game.targetStep));
    await tester.pump(const Duration(milliseconds: 520));

    expect(_game(tester).finished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
