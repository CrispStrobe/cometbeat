// Opt-in timer + personal best: ProgressService keeps the fastest completion,
// and GameResultView shows it (only when opted in and not in review).

import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('keeps the fastest completion and flags a new best', () {
    final p = ProgressService();

    p.recordResult('g', score: 800, stars: 3, elapsedMs: 42000);
    expect(p.progressFor('g').bestTimeMs, 42000);
    expect(p.lastElapsedMs, 42000);
    expect(p.lastWasBest, isTrue);

    // A slower run: best is unchanged, not a new best.
    p.recordResult('g', score: 800, stars: 3, elapsedMs: 55000);
    expect(p.progressFor('g').bestTimeMs, 42000);
    expect(p.lastElapsedMs, 55000);
    expect(p.lastWasBest, isFalse);

    // A faster run: new best.
    p.recordResult('g', score: 800, stars: 3, elapsedMs: 30000);
    expect(p.progressFor('g').bestTimeMs, 30000);
    expect(p.lastWasBest, isTrue);
  });

  testWidgets('result view shows the time only when opted in', (tester) async {
    final progress = ProgressService()
      ..recordResult('note_value_quiz', score: 800, stars: 3, elapsedMs: 42000);
    final settings = SettingsService();

    Future<void> pump() => tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ProgressService>.value(value: progress),
              ChangeNotifierProvider<SettingsService>.value(value: settings),
            ],
            child: MaterialApp(
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en'), Locale('de')],
              home: Scaffold(
                body: GameResultView(
                  gameType: 'note_value_quiz',
                  score: 800,
                  onRestart: () {}, // a normal game (not a review)
                ),
              ),
            ),
          ),
        );

    // Timer off (default): no time shown.
    await pump();
    await tester.pumpAndSettle();
    expect(find.textContaining('Your time'), findsNothing);

    // Opt in: time + "new best" appear (this run set the best).
    await settings.setShowTimer(true);
    await tester.pumpAndSettle();
    expect(find.text('Your time: 0:42'), findsOneWidget);
    expect(find.text('New best time! 🎉'), findsOneWidget);
  });
}
