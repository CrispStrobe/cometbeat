import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/note_order_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('order the notes: solving a round in pitch order advances',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
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
          home: NoteOrderScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Tap the notes from lowest to highest!'), findsOneWidget);
    expect(find.text('Round 1 of 8'), findsOneWidget);

    final cards = find.descendant(
      of: find.byType(Wrap),
      matching: find.byType(GestureDetector),
    );
    expect(cards, findsNWidgets(NoteOrderScreen.cardCount));

    // Solve by trial: a correct next-lowest tap adds a numbered badge
    // (CircleAvatar); wrong/placed taps don't. Find the order card by card.
    int badges() => find.byType(CircleAvatar).evaluate().length;
    for (var rank = 0; rank < NoteOrderScreen.cardCount; rank++) {
      final before = badges();
      for (var i = 0; i < NoteOrderScreen.cardCount; i++) {
        await tester.tap(cards.at(i), warnIfMissed: false);
        await tester.pump();
        if (badges() > before) break;
      }
    }
    expect(badges(), NoteOrderScreen.cardCount);

    // The solved round auto-advances.
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Round 2 of 8'), findsOneWidget);
  });
}
