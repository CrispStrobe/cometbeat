// "Live" flow tests: the real Bravura font + SMuFL metadata are loaded
// (exactly what production renders with), the full app is booted, and a
// game is played from the home screen to its star screen. Plus a
// registry-wide smoke: every registered game screen must render frames
// with real notation without throwing.

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/game_registry.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/main.dart';
import 'package:crisp_notation/crisp_notation.dart' show Bravura, SmuflMetadata;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> loadRealBravura() async {
  const base = '../crisp_notation-public/packages/crisp_notation/assets';
  Bravura.debugOverrideMetadata(
    SmuflMetadata.fromJson(
      jsonDecode(File('$base/smufl/bravura_metadata.json').readAsStringSync())
          as Map<String, Object?>,
    ),
  );
  final bytes = File('$base/fonts/Bravura.otf').readAsBytesSync();
  final loader = FontLoader('packages/crisp_notation/Bravura')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadRealBravura();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'full flow: home -> Note Values -> Symbol Quiz -> finish -> stars on tile',
      (tester) async {
    await tester.pumpWidget(const CometBeatApp());
    await tester.pumpAndSettle();

    // Home -> module (module cards show localized EN titles in tests).
    await tester.tap(find.text('Note Values'));
    await tester.pumpAndSettle();

    // Module -> game.
    await tester.tap(find.text('Symbol Quiz'));
    await tester.pumpAndSettle();
    expect(find.text('Round 1 of 10'), findsOneWidget);

    // Play all 10 rounds: tap options until each round resolves. The final
    // correct answer jumps straight to the result screen (no banner).
    bool finished() => find.text('Play again').evaluate().isNotEmpty;
    for (var round = 0; round < 10 && !finished(); round++) {
      for (var attempt = 0; attempt < 4; attempt++) {
        if (finished() || find.text('Correct!').evaluate().isNotEmpty) {
          break;
        }
        await tester.tap(find.byType(FilledButton).at(attempt));
        await tester.pump();
      }
      await tester.pumpAndSettle(); // 700 ms advance delay
    }

    // Result screen: stars + play again.
    expect(find.text('Play again'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsWidgets);

    // Back to the module list: the game tile now shows earned stars.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Symbol Quiz'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListTile).first,
        matching: find.byIcon(Icons.star),
      ),
      findsWidgets,
      reason: 'finished game should show at least one filled star',
    );
  });

  testWidgets('registry smoke: every game screen renders with real notation',
      (tester) async {
    final failures = <String>[];

    for (final games in kGamesByModule.values) {
      for (final game in games) {
        SharedPreferences.setMockInitialValues({});
        final sri = SriService(getNow: () => DateTime(2026, 7, 11));

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => SettingsService()),
              ChangeNotifierProvider<SriService>.value(value: sri),
              Provider<AudioService>(create: (_) => AudioService()),
              ChangeNotifierProvider(create: (_) => ProgressService()),
              ChangeNotifierProvider(create: (_) => UserSongsService()),
            ],
            child: MaterialApp(
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en'), Locale('de')],
              home: Builder(builder: game.builder),
            ),
          ),
        );
        // A few real frames incl. post-frame autoplay callbacks.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final exception = tester.takeException();
        if (exception != null) {
          failures.add('${game.id}: $exception');
        }

        // Tear down between games; flush any pending one-shot timers.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      }
    }

    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
