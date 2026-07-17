import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/harmony/cadence_workshop_screen.dart';
import 'package:comet_beat/features/games/note_reading/note_reading_quiz_screen.dart';
import 'package:comet_beat/features/games/scales/scale_builder_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart' hide Key;
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
  late SriService sri;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sri = SriService(getNow: () => DateTime(2026, 7, 10));
  });

  testWidgets('scale builder shows tonic, progress dots and staff',
      (tester) async {
    await tester.pumpWidget(_wrap(const ScaleBuilderScreen(), sri));
    await tester.pump();

    expect(find.byType(InteractiveStaff), findsOneWidget);
    expect(find.textContaining('major scale'), findsOneWidget);
    // 8 progress dots, exactly 1 filled (the pre-placed tonic).
    expect(find.byIcon(Icons.circle), findsOneWidget);
    expect(find.byIcon(Icons.circle_outlined), findsNWidgets(7));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('cadence workshop shows three chord cards and the prompt',
      (tester) async {
    await tester.pumpWidget(_wrap(const CadenceWorkshopScreen(), sri));
    await tester.pump();

    // The prompt starts with the Tonika step.
    expect(find.textContaining('Tap the Tonic'), findsOneWidget);
    // 1 cadence staff + 3 chord cards.
    expect(find.byType(StaffView), findsNWidgets(4));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('note reading review mode drills the given items',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const NoteReadingQuizScreen(
          clef: Clef.treble,
          reviewItemIds: [
            'note_reading.treble.g4',
            'note_reading.treble.b4',
          ],
        ),
        sri,
      ),
    );
    await tester.pump();

    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Round 1 of 2'), findsOneWidget);

    // First round target is G4: answer it correctly.
    await tester.tap(find.widgetWithText(FilledButton, 'G'));
    await tester.pump();
    expect(find.text('Correct!'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Round 2 of 2'), findsOneWidget);
  });
}
