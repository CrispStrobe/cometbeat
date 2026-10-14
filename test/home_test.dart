import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/debug_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/measures/spot_upbeat_screen.dart';
import 'package:comet_beat/features/games/note_values/note_value_quiz_screen.dart';
import 'package:comet_beat/features/home/screens/home_screen.dart';
import 'package:comet_beat/features/recital/recital_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(
  Widget child,
  SriService sri, {
  ProgressService? progress,
  bool studioMode = false,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) {
          final settings = SettingsService();
          if (studioMode) settings.setStudioMode(true);
          return settings;
        },
      ),
      ChangeNotifierProvider<SriService>.value(value: sri),
      Provider<AudioService>(create: (_) => AudioService()),
      ChangeNotifierProvider<ProgressService>.value(
        value: progress ?? ProgressService(),
      ),
      ChangeNotifierProvider(create: (_) => DebugService()),
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
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('home renders module cards and the toolbar', (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await tester.pumpWidget(_wrap(const HomeScreen(), sri));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.byIcon(Icons.bar_chart), findsOneWidget);
    expect(find.byType(Card), findsWidgets); // module cards
    // Nothing tracked yet -> no review button, no streak bar.
    expect(find.byIcon(Icons.replay), findsNothing);
    expect(find.byIcon(Icons.local_fire_department), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Continue card opens the recommended level as a session',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await tester.pumpWidget(_wrap(const HomeScreen(), sri));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final card = find.byKey(const Key('home-continue'));
    expect(card, findsOneWidget);
    // A brand-new learner starts at the first level.
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining(l10n.curLevelGrades12),
      ),
      findsOneWidget,
    );

    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byType(RecitalScreen), findsOneWidget);
    expect(find.text(l10n.homeContinueTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home is the learning app only until Studio tools are on',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await tester.pumpWidget(_wrap(const HomeScreen(), sri));
    await tester.pumpAndSettle();

    final bar = find.byType(AppBar);
    expect(
      find.descendant(of: bar, matching: find.byIcon(Icons.piano)),
      findsNothing,
    );
    expect(find.byKey(const Key('home-projects')), findsNothing);
    // The learning destinations stay.
    expect(find.byIcon(Icons.menu_book), findsOneWidget);
    expect(find.byIcon(Icons.bar_chart), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  testWidgets('a locked module shows how close it is to opening',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    // Three of the six reading items that open Measures.
    for (final n in ['c4', 'd4', 'e4']) {
      sri.recordResponse('note_reading.treble.$n', true);
    }
    await tester.pumpWidget(_wrap(const HomeScreen(), sri));
    await tester.pumpAndSettle();

    final ring = find.byKey(const Key('unlock-progress-measures'));
    await tester.scrollUntilVisible(ring, 200);
    expect(
      tester.widget<CircularProgressIndicator>(ring).value,
      closeTo(0.5, 0.01),
    );
    // An open module carries no ring.
    expect(find.byKey(const Key('unlock-progress-note_reading')), findsNothing);

    await tester.tap(ring);
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      find.text(l10n.unlockHintProgress(l10n.moduleNoteReading, 3, 6)),
      findsOneWidget,
    );
  });

  testWidgets('authoring menu exposes the five product modes', (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await tester.pumpWidget(_wrap(const HomeScreen(), sri, studioMode: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-projects')), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.piano),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.text(l10n.workshopModeScore), findsOneWidget);
    expect(find.text(l10n.workshopModeTracker), findsOneWidget);
    expect(find.text(l10n.workshopModeLoopStudio), findsOneWidget);
    expect(find.text(l10n.workshopModeTab), findsOneWidget);
    expect(find.text(l10n.dawTitle), findsOneWidget);
    expect(find.text(l10n.workshopModePerform), findsNothing);
    expect(find.text(l10n.workshopModeDrums), findsNothing);
    expect(find.text(l10n.workshopModeTranscribe), findsNothing);
    // The project mixer left this menu — it is an overlay inside Loop Studio
    // and the Audio Editor now, not a sixth destination.
    expect(find.text(l10n.mixerConsoleTitle), findsNothing);
  });

  testWidgets('seven taps on the title reveal the debug settings',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    final debug = DebugService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider<SriService>.value(value: sri),
          Provider<AudioService>(create: (_) => AudioService()),
          ChangeNotifierProvider(create: (_) => ProgressService()),
          ChangeNotifierProvider<DebugService>.value(value: debug),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('en'), Locale('de')],
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(debug.menuEnabled, isFalse);
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.text('CometBeat'));
      await tester.pump();
    }
    // The menu is revealed, but games stay locked until toggled in Settings.
    expect(debug.menuEnabled, isTrue);
    expect(debug.unlockAll, isFalse);
    expect(find.text('Debug settings unlocked!'), findsOneWidget);
  });

  testWidgets('home shows the practice-streak bar once a game is finished',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    final progress = ProgressService(now: () => DateTime(2026, 7, 11))
      ..recordResult('note_value_quiz', score: 300, stars: 3);

    await tester.pumpWidget(_wrap(const HomeScreen(), sri, progress: progress));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
    expect(find.text('1-day streak'), findsOneWidget);
  });

  testWidgets('home review button launches the biggest due bucket',
      (tester) async {
    // Mutable clock: schedule items now, then jump ahead so they come due.
    var now = DateTime(2026, 1, 15);
    final sri = SriService(getNow: () => now);
    for (final s in ['whole_note', 'half_note', 'quarter_note']) {
      sri.recordResponse('note_values.symbol.$s', false);
    }
    now = DateTime(2026, 3, 15);

    await tester.pumpWidget(_wrap(const HomeScreen(), sri));
    await tester.pumpAndSettle();

    final review = find.byIcon(Icons.replay);
    expect(review, findsOneWidget);
    await tester.tap(review);
    await tester.pumpAndSettle();

    // Routed into the note-value review runner.
    expect(find.byType(NoteValueQuizScreen), findsOneWidget);
  });

  testWidgets('review reaches a skill that has no quiz runner of its own',
      (tester) async {
    // Before the review router this showed "N to review" and then answered
    // the tap with "coming soon".
    var now = DateTime(2026, 1, 15);
    final sri = SriService(getNow: () => now);
    for (final s in ['a', 'b']) {
      sri.recordResponse('measures.upbeat.$s', false);
    }
    now = DateTime(2026, 3, 15);

    await tester.pumpWidget(_wrap(const HomeScreen(), sri));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.replay));
    await tester.pumpAndSettle();

    expect(find.byType(SpotUpbeatScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
