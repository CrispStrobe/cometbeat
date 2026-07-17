// Strong Beat? — metric-accent training via crisp_notation's beatStrength. Driven
// through the UI: the correct answer (strong/weak) varies per round, so read the
// game's target and tap the matching button.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/measures/strong_beat_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

Widget _wrap(SriService sri) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider<SriService>.value(value: sri),
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
        home: StrongBeatScreen(),
      ),
    );

StrongBeatTester _game(WidgetTester tester) =>
    tester.state<State<StrongBeatScreen>>(find.byType(StrongBeatScreen))
        as StrongBeatTester;

// Beat 1 (the downbeat) is always strong; at 0 stars the meter is 4/4, so the
// game grades the highlighted beat with beatStrength — tap the right button.
Future<void> _answer(WidgetTester tester) async {
  final label = _game(tester).targetIsStrong ? 'Strong' : 'Weak';
  await tester.tap(find.widgetWithText(FilledButton, label));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('grades the highlighted beat and records under measures.accent',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await useGameSurface(tester);
    await tester.pumpWidget(_wrap(sri));
    await tester.pump();

    expect(find.text('Strong'), findsOneWidget);
    expect(find.text('Weak'), findsOneWidget);

    await _answer(tester);
    await tester.pump();

    expect(sri.getDetailedBreakdown()['measures']!.keys, ['accent']);
    await tester
        .pump(const Duration(seconds: 1)); // drain replay/advance timers
  });

  testWidgets('clearing all ten rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await useGameSurface(tester);
    await tester.pumpWidget(_wrap(sri));
    await tester.pump();

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answer(tester);
      await tester.pump(const Duration(seconds: 1)); // auto-advance + replay
    }

    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
    await tester.pump(const Duration(seconds: 1));
  });
}
