// test/play_along_view_test.dart
//
// Switches the play-along screen through all four scroll modes and asserts each
// renders without throwing — the notation mode in particular builds a crisp_notation
// Score, which the highway-only smoke test never exercises.

import 'package:comet_beat/core/audio/play_along.dart';
import 'package:comet_beat/core/notation/bowed_arranger.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/playalong/play_along_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show MultiSystemView, NoteElement;
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

  testWidgets(
      'the cello chart shows fingering digits in notation, toggleable; a '
      'non-bowed chart has no toggle', (tester) async {
    SharedPreferences.setMockInitialValues({});

    Widget app(PlayAlongChart chart, BowedInstrument? instrument) =>
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsService()),
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
            home: PlayAlongScreen(
              chart: chart,
              title: 'Play along',
              gameId: 'cello_play_along',
              sriPrefix: 'cello.play_along',
              fingeringInstrument: instrument,
            ),
          ),
        );

    bool notationHasFingerings() {
      final view = tester.widget<MultiSystemView>(find.byType(MultiSystemView));
      return view.score.measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .any((n) => n.fingerings.isNotEmpty);
    }

    Future<void> toNotation() async {
      await tester.tap(find.byIcon(Icons.grid_view));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notation').last);
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Cello chart: notation view carries fingerings by default, and a toggle is
    // offered to hide them.
    await tester.pumpWidget(
      app(PlayAlongCharts.celloFirstPosition, BowedInstrument.cello),
    );
    await tester.pump();
    await toNotation();
    expect(
      notationHasFingerings(),
      isTrue,
      reason: 'cello notation should engrave fingerings by default',
    );
    expect(find.byTooltip('Show fingering'), findsOneWidget);

    // Toggle off → the digits are gone.
    await tester.tap(find.byTooltip('Show fingering'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      notationHasFingerings(),
      isFalse,
      reason: 'toggling fingerings off should clear the digits',
    );

    // A chart with no bowed instrument (e.g. voice/keyboard) offers no toggle
    // and engraves no fingerings.
    await tester.pumpWidget(app(PlayAlongCharts.celloFirstPosition, null));
    await tester.pump();
    await toNotation();
    expect(find.byTooltip('Show fingering'), findsNothing);
    expect(notationHasFingerings(), isFalse);
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

  testWidgets('a Starting-note cue shows for sung charts, not instrument ones',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    Widget app(PlayAlongChart chart) => MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsService()),
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
            home: PlayAlongScreen(
              chart: chart,
              title: 'Sing',
              gameId: 'sing_along',
              sriPrefix: 'voice.sing_along',
            ),
          ),
        );

    // Sung (octave-agnostic) chart → the cue is offered, and tapping it plays a
    // pitch without throwing.
    await tester.pumpWidget(app(PlayAlongCharts.twinkleSing));
    await tester.pump();
    expect(find.text('Starting note'), findsOneWidget);
    await tester.tap(find.text('Starting note'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Instrument (exact-pitch) chart → no cue (you read the exact notes).
    await tester.pumpWidget(app(PlayAlongCharts.celloFirstPosition));
    await tester.pump();
    expect(find.text('Starting note'), findsNothing);
  });
}
