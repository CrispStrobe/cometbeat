import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_reading/note_reading_quiz_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart';
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

  testWidgets('renders a staff and records answers under the clef skill',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 10));

    await tester.pumpWidget(
        _wrap(const NoteReadingQuizScreen(clef: Clef.treble), sri));
    await tester.pump();

    expect(find.text('What is this note called?'), findsOneWidget);
    expect(find.byType(StaffView), findsOneWidget);
    expect(find.byType(FilledButton), findsNWidgets(4));

    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();

    expect(sri.totalTrackedItems, 1);
    final breakdown = sri.getDetailedBreakdown();
    expect(breakdown.keys, ['note_reading']);
    expect(breakdown['note_reading']!.keys, ['treble']);

    await tester.pumpAndSettle();
  });

  testWidgets('bass clef records under the bass skill', (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 10));

    await tester.pumpWidget(
        _wrap(const NoteReadingQuizScreen(clef: Clef.bass), sri));
    await tester.pump();

    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();

    expect(sri.getDetailedBreakdown()['note_reading']!.keys, ['bass']);
    await tester.pumpAndSettle();
  });
}
