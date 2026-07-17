import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_values/duration_duel_screen.dart';
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

  testWidgets('duel shows two symbols and records both on answer',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 10));

    await tester.pumpWidget(_wrap(const DurationDuelScreen(), sri));
    await tester.pumpAndSettle();

    expect(find.text('Which one lasts longer?'), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(2));

    expect(sri.totalTrackedItems, 0);
    await tester.tap(find.byType(Card).first);
    await tester.pump();
    // Both duel symbols get an SRI record.
    expect(sri.totalTrackedItems, 2);

    await tester.pumpAndSettle();
  });

  testWidgets('review mode drills exactly the given items', (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 10));

    await tester.pumpWidget(
      _wrap(
        const NoteValueQuizScreen(
          reviewItemIds: [
            'note_values.symbol.quarter_note',
            'note_values.symbol.half_rest',
          ],
        ),
        sri,
      ),
    );
    await tester.pumpAndSettle();

    // Review title instead of the game title, and only 2 rounds.
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Round 1 of 2'), findsOneWidget);

    // First round target is the quarter note: its name must be among the
    // four options.
    expect(find.text('Quarter note'), findsOneWidget);

    // Answer correctly.
    await tester.tap(find.widgetWithText(FilledButton, 'Quarter note'));
    await tester.pump();
    expect(find.text('Correct!'), findsOneWidget);
    expect(sri.totalTrackedItems, 1);

    await tester.pumpAndSettle();
    expect(find.text('Round 2 of 2'), findsOneWidget);
    expect(find.text('Half rest'), findsOneWidget);
  });
}
