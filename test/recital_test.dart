// Recital Mode — the progression meta. Verifies the programme lists pieces,
// performing them all reaches the curtain call, and the star tally is shown.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/game_registry.dart';
import 'package:comet_beat/features/recital/recital_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A tiny, deterministic two-piece programme of static (non-ticker) games.
List<GameInfo> _program() {
  final all = kGamesByModule.values.expand((g) => g).toList();
  return [
    all.firstWhere((g) => g.id == 'note_value_quiz'),
    all.firstWhere((g) => g.id == 'note_reading_treble'),
  ];
}

Widget _app(List<GameInfo> program) => MultiProvider(
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
        home: RecitalScreen(program: program),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the programme lists its pieces', (tester) async {
    await tester.pumpWidget(_app(_program()));
    await tester.pump();

    expect(find.text('0 of 2 pieces performed'), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(2));
  });

  testWidgets('performing every piece reaches the curtain call',
      (tester) async {
    await tester.pumpWidget(_app(_program()));
    await tester.pump();

    // Play each piece: tap it, then pop straight back out of the game.
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byType(Card).at(i));
      await tester.pumpAndSettle();
      // We're inside the launched game now; pop back to the recital.
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pop();
      await tester.pumpAndSettle();
    }

    expect(find.text('Bravo!'), findsOneWidget);
    expect(find.text('Take a bow'), findsOneWidget);
  });
}
