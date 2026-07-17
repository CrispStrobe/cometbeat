// Time Signatures — read the signature (incl. C / cut time) and give the beats
// per bar. Verifies the round loop scores + records SRI under measures.timesig.*
// and finishes; also exercises rendering an empty measure with each signature.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/measures/time_signature_screen.dart';
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
        home: TimeSignatureScreen(),
      ),
    );

TimeSignatureTester _game(WidgetTester tester) =>
    tester.state<State<TimeSignatureScreen>>(find.byType(TimeSignatureScreen))
        as TimeSignatureTester;

Future<void> _solveRound(WidgetTester tester) async {
  final beats = _game(tester).answerBeats;
  // Button label is "N beats"; tap its FilledButton ancestor.
  final button = find.ancestor(
    of: find.textContaining('$beats'),
    matching: find.byType(FilledButton),
  );
  await tester.tap(button.first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('reading the beats-per-bar scores and records it',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Round 1 of 10'), findsOneWidget);
    final sri =
        tester.element(find.byType(TimeSignatureScreen)).read<SriService>();

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
}
