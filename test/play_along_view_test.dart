// test/play_along_view_test.dart
//
// Switches the play-along screen through all four scroll modes and asserts each
// renders without throwing — the notation mode in particular builds a crisp_notation
// Score, which the highway-only smoke test never exercises.

import 'package:comet_beat/core/audio/play_along.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/playalong/play_along_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart' show MultiSystemView;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('every scroll mode renders without throwing', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsService()),
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
          home: PlayAlongScreen(
            chart: PlayAlongCharts.celloFirstPosition,
            title: 'Play along',
            gameId: 'cello_play_along',
            sriPrefix: 'cello.play_along',
          ),
        ),
      ),
    );
    await tester.pump();

    // Default view (highway) is up with no exception.
    expect(tester.takeException(), isNull);

    // Switch through each mode via the view menu.
    for (final label in ['Notation', 'Falling', 'Coach', 'Highway']) {
      await tester.tap(find.byIcon(Icons.grid_view));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: '$label mode threw');
    }

    // The notation mode leaves a real engraved staff in the tree.
    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notation').last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(MultiSystemView), findsOneWidget);
  });

  test('difficulty loosens the pitch window and coverage as it eases', () {
    // Easy is the most forgiving, hard the strictest — a monotone ordering
    // so the levels can never silently invert.
    const easy = PlayAlongDifficulty.easy;
    const medium = PlayAlongDifficulty.medium;
    const hard = PlayAlongDifficulty.hard;
    expect(easy.centsTolerance, greaterThan(medium.centsTolerance));
    expect(medium.centsTolerance, greaterThan(hard.centsTolerance));
    expect(easy.hitCoverage, lessThan(medium.hitCoverage));
    expect(medium.hitCoverage, lessThan(hard.hitCoverage));
  });

  test('playAlongSriId spells the note with its accidental', () {
    expect(playAlongSriId('cello.play_along', 57), 'cello.play_along.a3');
    expect(
      playAlongSriId('cello.play_along', 54),
      'cello.play_along.fs3',
    ); // F#3
    expect(playAlongSriId('keyboard.play_along', 60), 'keyboard.play_along.c4');
  });
}
