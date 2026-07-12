// Curriculum alignment — the Leistungsabzeichen / Lehrplan mapping. Guards that
// every mapped game ID is a real registered game (typo protection), that
// readiness reflects stars, and that the screen renders with level cards.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/curriculum/curriculum.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/curriculum/screens/curriculum_screen.dart';
import 'package:klang_universum/features/games/game_registry.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
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

  test('readiness is 0 with no stars and 1 when everything is mastered', () {
    final level = kCurricula.first.levels.firstWhere((l) => l.id == 'g56');
    expect(levelReadiness(level, (_) => 0), 0);
    expect(levelReadiness(level, (_) => 3), 1.0);
    // Partial mastery lands strictly between.
    final mid = levelReadiness(level, (_) => 2);
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));
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
