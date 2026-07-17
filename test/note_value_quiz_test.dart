import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_values/note_value_quiz_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child, SriService sri) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SettingsService()),
      ChangeNotifierProvider<SriService>.value(value: sri),
      Provider<AudioService>(create: (_) => AudioService()),
      ChangeNotifierProvider(create: (_) => ProgressService()),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('de')],
      home: child,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('quiz shows a symbol, four options, and records answers',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 10));

    await tester.pumpWidget(_wrap(const NoteValueQuizScreen(), sri));
    await tester.pumpAndSettle();

    expect(find.text('What is this symbol called?'), findsOneWidget);
    expect(find.text('Round 1 of 10'), findsOneWidget);
    expect(find.byType(FilledButton), findsNWidgets(4));

    // Answer (any option) — an SRI record must appear either way.
    expect(sri.totalTrackedItems, 0);
    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();
    expect(sri.totalTrackedItems, 1);

    // Feedback is visible (either outcome).
    final correct = find.text('Correct!').evaluate().isNotEmpty;
    final wrong = find.text('Oops — try again!').evaluate().isNotEmpty;
    expect(correct || wrong, isTrue);

    await tester.pumpAndSettle();
  });

  testWidgets('a wrong answer shows the note-length explanation',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 10));
    await tester.pumpWidget(_wrap(const NoteValueQuizScreen(), sri));
    await tester.pumpAndSettle();

    // Tap options until a wrong one lands (keeps the round put).
    var sawWrong = false;
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byType(FilledButton).at(i));
      await tester.pump();
      if (find.text('Oops — try again!').evaluate().isNotEmpty) {
        sawWrong = true;
        break;
      }
      await tester.pumpAndSettle(); // correct -> advanced; try the next round
    }

    expect(sawWrong, isTrue);
    expect(find.text('Hear the length'), findsOneWidget);
  });

  testWidgets('answering correctly advances to the next round', (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 10));

    await tester.pumpWidget(_wrap(const NoteValueQuizScreen(), sri));
    await tester.pumpAndSettle();

    // Tap options until the correct one is hit (at most 4).
    for (var i = 0; i < 4; i++) {
      if (find.text('Correct!').evaluate().isNotEmpty) break;
      await tester.tap(find.byType(FilledButton).at(i));
      await tester.pump();
    }
    expect(find.text('Correct!'), findsOneWidget);

    await tester.pumpAndSettle(); // wait out the 700ms advance delay
    expect(find.text('Round 2 of 10'), findsOneWidget);
  });
}
