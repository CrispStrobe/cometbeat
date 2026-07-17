// Bowing — reading up-bow / down-bow marks (crisp_notation articulations). Verifies
// the round loop: choosing the correct stroke scores + records SRI under
// cello.bowing.*, and clearing all rounds finishes.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/cello/bowing_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
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
        home: BowingScreen(),
      ),
    );

BowingTester _game(WidgetTester tester) =>
    tester.state<State<BowingScreen>>(find.byType(BowingScreen))
        as BowingTester;

Future<void> _solveRound(WidgetTester tester) async {
  // The down-bow button label contains "Down-bow"; up contains "Up-bow"
  // (prefixed by the bow glyph, so match the substring's button ancestor).
  final want = _game(tester).isDown ? 'Down-bow' : 'Up-bow';
  final button = find.ancestor(
    of: find.textContaining(want),
    matching: find.byType(FilledButton),
  );
  await tester.tap(button);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('choosing the marked stroke scores and records it',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Round 1 of 10'), findsOneWidget);
    final sri = tester.element(find.byType(BowingScreen)).read<SriService>();

    await _solveRound(tester);
    expect(sri.getDetailedBreakdown()['cello'], isNotNull);
    expect(find.text('Round 2 of 10'), findsOneWidget);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    for (var r = 0; r < 10; r++) {
      await _solveRound(tester);
    }

    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
