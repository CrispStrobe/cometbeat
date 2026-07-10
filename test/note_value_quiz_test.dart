import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_values/note_value_quiz_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child, SriService sri) {
  return ChangeNotifierProvider<SriService>.value(
    value: sri,
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

  testWidgets('answering correctly advances to the next round',
      (tester) async {
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
