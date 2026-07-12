// Chord Builder — build the named chord, graded by partitura's identifyChord so
// any voicing (incl. inversions) counts. Verifies: placing the target notes and
// checking scores + records SRI under chords.build.*; an inverted voicing is
// also accepted; clearing all rounds finishes.

import 'package:flutter/material.dart' hide Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/chords/chord_builder_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => MultiProvider(
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
        home: ChordBuilderScreen(),
      ),
    );

ChordBuilderTester _game(WidgetTester tester) =>
    tester.state<State<ChordBuilderScreen>>(find.byType(ChordBuilderScreen))
        as ChordBuilderTester;

Future<void> _solveRound(WidgetTester tester, {bool invert = false}) async {
  final game = _game(tester);
  final pitches = List<Pitch>.from(game.targetPitches);
  if (invert) {
    // First inversion: move the root up an octave — a different voicing.
    final root = pitches.removeAt(0);
    pitches.add(Pitch(root.step, alter: root.alter, octave: root.octave + 1));
  }
  for (final p in pitches) {
    game.debugPlace(p);
  }
  game.debugCheck();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('building the target chord (root position) scores and records it',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Round 1 of 8'), findsOneWidget);
    final sri =
        tester.element(find.byType(ChordBuilderScreen)).read<SriService>();

    await _solveRound(tester);
    expect(sri.getDetailedBreakdown()['chords'], isNotNull);
    expect(find.text('Round 2 of 8'), findsOneWidget);
  });

  testWidgets('an inverted voicing is also accepted', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await _solveRound(tester, invert: true);
    expect(find.text('Round 2 of 8'), findsOneWidget);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    for (var r = 0; r < 8; r++) {
      await _solveRound(tester);
    }

    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
