import 'package:flutter/material.dart' hide Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_reading/note_reading_quiz_screen.dart';
import 'package:klang_universum/features/games/note_reading/reading_hint.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('computeReadingHint', () {
    test('middle C is its own landmark (zero distance)', () {
      final h = computeReadingHint(Clef.treble, const Pitch(Step.c));
      expect(h.landmarkStep, Step.c);
      expect(h.steps, 0);
    });

    test('treble G4 is a skip up from the bottom line E', () {
      final h = computeReadingHint(Clef.treble, const Pitch(Step.g));
      expect(h.landmarkStep, Step.e);
      expect(h.steps, 2);
    });

    test('treble D4 is one step up from middle C', () {
      final h = computeReadingHint(Clef.treble, const Pitch(Step.d));
      expect(h.landmarkStep, Step.c);
      expect(h.steps, 1);
    });

    test('top staff line resolves to distance zero', () {
      final top = Clef.treble.pitchAt(8); // F5
      final h = computeReadingHint(Clef.treble, top);
      expect(h.landmarkStep, top.step);
      expect(h.steps, 0);
    });

    test('bass clef anchors on its own bottom line, not middle C', () {
      final h = computeReadingHint(Clef.bass, const Pitch(Step.a, octave: 2));
      expect(h.landmarkStep, Step.g); // bottom line G2
      expect(h.steps, 1);
    });
  });

  group('fading hint in the reading quiz', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Widget wrap(Widget home, {ProgressService? progress}) => MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsService()),
            ChangeNotifierProvider(
              create: (_) => SriService(getNow: () => DateTime(2026, 7, 10)),
            ),
            Provider<AudioService>(create: (_) => AudioService()),
            ChangeNotifierProvider(
              create: (_) => progress ?? ProgressService(),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('de')],
            home: home,
          ),
        );

    testWidgets('shows a landmark hint for a fresh (0-star) player',
        (tester) async {
      await tester
          .pumpWidget(wrap(const NoteReadingQuizScreen(clef: Clef.treble)));
      await tester.pump();
      expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
    });

    testWidgets('hides the hint in a review test', (tester) async {
      await tester.pumpWidget(
        wrap(
          const NoteReadingQuizScreen(
            clef: Clef.treble,
            reviewItemIds: ['note_reading.treble.g4'],
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.lightbulb_outline), findsNothing);
    });
  });
}
