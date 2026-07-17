// Curriculum alignment — the Leistungsabzeichen / Lehrplan mapping. Guards that
// every mapped game ID is a real registered game (typo protection), that
// readiness reflects stars, and that the screen renders with level cards.

import 'package:comet_beat/core/curriculum/curriculum.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/curriculum/screens/curriculum_screen.dart';
import 'package:comet_beat/features/games/game_registry.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('every curriculum game ID maps to a registered game', () {
    for (final curriculum in kCurricula) {
      for (final level in curriculum.levels) {
        for (final topic in level.topics) {
          for (final id in topic.gameIds) {
            expect(
              gameInfoById(id),
              isNotNull,
              reason: '${curriculum.id}/${level.id}: unknown game "$id"',
            );
          }
        }
      }
    }
  });

  test('readiness blends star coverage with SM-2 retention', () {
    final level = kCurricula.first.levels.firstWhere((l) => l.id == 'g56');
    // No stars → 0 regardless of retention.
    expect(levelReadiness(level, (_) => 0, (_) => null), 0);
    // Full stars, no SM-2 signal yet (null = neutral) → full coverage.
    expect(levelReadiness(level, (_) => 3, (_) => null), 1.0);
    // Full stars but nothing retained → SM-2 pulls readiness to 0.
    expect(levelReadiness(level, (_) => 3, (_) => 0.0), 0);
    // Full stars, half-retained → about half.
    expect(levelReadiness(level, (_) => 3, (_) => 0.5), closeTo(0.5, 1e-9));
    // Partial stars, neutral retention → strictly between.
    final mid = levelReadiness(level, (_) => 2, (_) => null);
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));
  });

  test('SriService.masteryUnder aggregates by namespace', () {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    expect(sri.masteryUnder('note_reading'), isNull); // nothing practised
    sri.recordResponse('note_reading.treble.c4', true);
    final m = sri.masteryUnder('note_reading');
    expect(m, isNotNull);
    expect(m, greaterThanOrEqualTo(0));
    expect(m, lessThanOrEqualTo(1));
    // A different namespace is still untouched.
    expect(sri.masteryUnder('chords'), isNull);
  });

  testWidgets('the curriculum screen lists levels with readiness',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MultiProvider(
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
          home: CurriculumScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Grades 1–2'), findsOneWidget);
    expect(find.text('Grades 9–10'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
  });
}
