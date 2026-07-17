// Key Signature Detective — read a key signature, name the major key. A correct
// answer advances and scores; a wrong one holds the round (no-fail loop).

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/scales/key_signature_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Step;
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
        home: KeySignatureScreen(),
      ),
    );

KeySignatureTester _game(WidgetTester tester) =>
    tester.state<State<KeySignatureScreen>>(find.byType(KeySignatureScreen))
        as KeySignatureTester;

// English label for the tonic (auto naming = C..B).
String _label(Step tonic) => '${tonic.name.toUpperCase()} major';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('naming the right major key advances and scores', (tester) async {
    await tester.pumpWidget(_app());
    final game = _game(tester);
    expect(find.text('Which major key is this?'), findsOneWidget);
    expect(game.round, 0);

    await tester.tap(
      find.widgetWithText(FilledButton, _label(game.correctTonic)),
    );
    await tester.pump(const Duration(milliseconds: 800));

    expect(game.round, 1);
    expect(game.score, greaterThan(0));
  });

  testWidgets('a wrong key never advances', (tester) async {
    await tester.pumpWidget(_app());
    final game = _game(tester);

    // Tap a different option than the correct one.
    final wrong = find.byWidgetPredicate(
      (w) =>
          w is FilledButton &&
          w.child is Text &&
          (w.child! as Text).data != _label(game.correctTonic),
    );
    await tester.tap(wrong.first);
    await tester.pump(const Duration(milliseconds: 800));

    expect(game.round, 0);
    expect(game.score, 0);
  });
}
