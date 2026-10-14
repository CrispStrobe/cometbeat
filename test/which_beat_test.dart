// Which Beat? — rhythmic placement (crisp_notation beat-number overlay). Verifies the
// round loop: tapping the correct beat scores + records SRI under measures.beat.*,
// and clearing all rounds finishes.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/measures/which_beat_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app({WhichBeatScreen screen = const WhichBeatScreen()}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider(
          create: (_) => SriService(getNow: () => DateTime(2026, 7, 11)),
        ),
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
        home: screen,
      ),
    );

WhichBeatTester _game(WidgetTester tester) =>
    tester.state<State<WhichBeatScreen>>(find.byType(WhichBeatScreen))
        as WhichBeatTester;

Future<void> _solveRound(WidgetTester tester) async {
  final beat = _game(tester).answerBeat;
  await tester.tap(find.widgetWithText(FilledButton, '$beat'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping the correct beat scores and records it', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Round 1 of 10'), findsOneWidget);
    final sri = tester.element(find.byType(WhichBeatScreen)).read<SriService>();

    await _solveRound(tester);
    expect(sri.getDetailedBreakdown()['measures'], isNotNull);
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

  testWidgets('review mode asks only notes on the due beat', (tester) async {
    await tester.pumpWidget(
      _app(screen: const WhichBeatScreen(reviewItemIds: ['measures.beat.3'])),
    );
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      expect(_game(tester).answerBeat, 3);
      await _solveRound(tester);
    }
  });
}
