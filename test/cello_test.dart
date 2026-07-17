import 'package:comet_beat/core/models/learning_module.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/debug_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/cello/cello_finger_quiz_screen.dart';
import 'package:comet_beat/features/games/cello/cello_first_position.dart';
import 'package:comet_beat/features/games/cello/cello_string_quiz_screen.dart';
import 'package:comet_beat/features/games/note_reading/note_reading_quiz_screen.dart';
import 'package:comet_beat/features/games/screens/module_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart' hide Step;
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

  test('first-position map is sound', () {
    expect(kCelloFirstPosition.length, 16);
    for (final note in kCelloFirstPosition) {
      // Every note lies on or above its open string, within a fourth.
      final semitonesAboveOpen =
          note.pitch.midiNumber - note.string.openPitch.midiNumber;
      expect(
        semitonesAboveOpen,
        inInclusiveRange(0, 5),
        reason: '${note.pitch} on ${note.string}',
      );
      // Open string <=> finger 0.
      expect(note.finger == 0, semitonesAboveOpen == 0);
      expect(note.finger, inInclusiveRange(0, 4));
    }
  });

  testWidgets('string quiz shows a bass-clef note and four strings',
      (tester) async {
    await tester.pumpWidget(_wrap(const CelloStringQuizScreen(), sri));
    await tester.pump();

    expect(find.text('Which open string is this?'), findsOneWidget);
    expect(find.byType(StaffView), findsOneWidget);
    for (final label in ['C', 'G', 'D', 'A']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('G'));
    await tester.pump();
    expect(sri.getDetailedBreakdown()['cello']!.keys, ['string']);
    await tester.pumpAndSettle();
  });

  testWidgets('finger quiz offers fingers 0-4 and records', (tester) async {
    await tester.pumpWidget(_wrap(const CelloFingerQuizScreen(), sri));
    await tester.pump();

    for (final label in ['0', '1', '2', '3', '4']) {
      expect(find.widgetWithText(FilledButton, label), findsOneWidget);
    }

    await tester.tap(find.widgetWithText(FilledButton, '1'));
    await tester.pump();
    expect(sri.getDetailedBreakdown()['cello']!.keys, ['finger']);
    await tester.pumpAndSettle();
  });

  testWidgets('tenor clef stays locked until the cello basics are starred',
      (tester) async {
    final progress = ProgressService();
    final cello = kLearningModules.firstWhere((m) => m.id == 'cello');

    Widget wrap() => MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsService()),
            ChangeNotifierProvider<SriService>.value(value: sri),
            ChangeNotifierProvider(create: (_) => DebugService()),
            Provider<AudioService>(create: (_) => AudioService()),
            ChangeNotifierProvider<ProgressService>.value(value: progress),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('de')],
            home: ModuleScreen(module: cello),
          ),
        );

    await tester.pumpWidget(wrap());
    await tester.pump();

    // The cello module list is a lazy ListView longer than the viewport, so
    // scroll the tenor tile into the built range before inspecting it.
    await tester.scrollUntilVisible(find.text('Tenor Clef'), 120);
    await tester.pump();

    // Locked: the advanced hint shows and a lock icon is on the tile.
    expect(find.textContaining('Advanced'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsWidgets);

    // Tapping the locked tile only flashes the hint, never navigates.
    await tester.tap(find.text('Tenor Clef'));
    await tester.pump();
    expect(find.byType(NoteReadingQuizScreen), findsNothing);

    // Two stars in each basic cello game clears the gate.
    progress.recordResult('cello_string_quiz', score: 100, stars: 2);
    progress.recordResult('cello_finger_quiz', score: 100, stars: 2);
    // Settle first so the earlier hint SnackBar has auto-dismissed.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock), findsNothing);

    // Now the tile opens the tenor-clef reading game.
    await tester.scrollUntilVisible(find.text('Tenor Clef'), 120);
    await tester.tap(find.text('Tenor Clef'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteReadingQuizScreen), findsOneWidget);
  });
}
