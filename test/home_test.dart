import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_values/note_value_quiz_screen.dart';
import 'package:klang_universum/features/home/screens/home_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child, SriService sri) {
  return MultiProvider(
    providers: [
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
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('home renders module cards and the toolbar', (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await tester.pumpWidget(_wrap(const HomeScreen(), sri));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.byIcon(Icons.bar_chart), findsOneWidget);
    expect(find.byType(Card), findsWidgets); // module cards
    // Nothing tracked yet -> no review button, just the plain due line.
    expect(find.byIcon(Icons.replay), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home review button launches the biggest due bucket',
      (tester) async {
    // Mutable clock: schedule items now, then jump ahead so they come due.
    var now = DateTime(2026, 1, 15);
    final sri = SriService(getNow: () => now);
    for (final s in ['whole_note', 'half_note', 'quarter_note']) {
      sri.recordResponse('note_values.symbol.$s', false);
    }
    now = DateTime(2026, 3, 15);

    await tester.pumpWidget(_wrap(const HomeScreen(), sri));
    await tester.pumpAndSettle();

    final review = find.byIcon(Icons.replay);
    expect(review, findsOneWidget);
    await tester.tap(review);
    await tester.pumpAndSettle();

    // Routed into the note-value review runner.
    expect(find.byType(NoteValueQuizScreen), findsOneWidget);
  });
}
