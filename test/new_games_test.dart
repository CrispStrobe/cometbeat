import 'package:flutter/material.dart' hide Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/chords/chord_quiz_screen.dart';
import 'package:klang_universum/features/games/harmony/harmony_quiz_screen.dart';
import 'package:klang_universum/features/games/measures/measure_fill_screen.dart';
import 'package:klang_universum/features/games/note_reading/place_note_screen.dart';
import 'package:klang_universum/features/games/scales/scale_detective_screen.dart';
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
  late SriService sri;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sri = SriService(getNow: () => DateTime(2026, 7, 10));
  });

  testWidgets('place-the-note renders an interactive staff', (tester) async {
    await tester
        .pumpWidget(_wrap(const PlaceNoteScreen(clef: Clef.treble), sri));
    await tester.pump();

    expect(find.byType(InteractiveStaff), findsOneWidget);
    expect(find.textContaining('Place the note'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('measure filler offers four glyph options and records answers',
      (tester) async {
    await tester.pumpWidget(_wrap(const MeasureFillScreen(), sri));
    await tester.pump();

    expect(
        find.text('Which note completes the measure?'), findsOneWidget);
    expect(find.byType(StaffView), findsOneWidget);
    // 4 glyph option cards + the staff card.
    expect(find.byType(InkWell), findsNWidgets(4));

    await tester.tap(find.byType(InkWell).first);
    await tester.pump();
    expect(sri.totalTrackedItems, 1);
    expect(sri.getDetailedBreakdown().keys, ['measures']);
    await tester.pumpAndSettle();
  });

  testWidgets('scale detective renders 8 tappable scale notes',
      (tester) async {
    await tester.pumpWidget(_wrap(const ScaleDetectiveScreen(), sri));
    await tester.pump();

    expect(find.textContaining('major scale'), findsOneWidget);
    expect(find.byType(StaffView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('chord quiz records under chords.triad', (tester) async {
    await tester.pumpWidget(_wrap(const ChordQuizScreen(), sri));
    await tester.pump();

    expect(find.text('What chord is this?'), findsOneWidget);
    expect(find.byType(FilledButton), findsNWidgets(4));

    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();
    expect(sri.getDetailedBreakdown()['chords']!.keys, ['triad']);
    await tester.pumpAndSettle();
  });

  testWidgets('harmony quiz offers the three functions', (tester) async {
    await tester.pumpWidget(_wrap(const HarmonyQuizScreen(), sri));
    await tester.pump();

    expect(find.text('Tonic'), findsOneWidget);
    expect(find.text('Subdominant'), findsOneWidget);
    expect(find.text('Dominant'), findsOneWidget);

    await tester.tap(find.text('Tonic'));
    await tester.pump();
    expect(sri.getDetailedBreakdown()['harmony']!.keys, ['function']);
    await tester.pumpAndSettle();
  });
}
