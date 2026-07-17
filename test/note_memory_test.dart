import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/note_memory_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('note memory deals 12 cards and counts moves', (tester) async {
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
          home: NoteMemoryScreen(),
        ),
      ),
    );
    await tester.pump();

    // 12 face-down cards (6 pairs), a prompt, and a zero move count.
    expect(find.byIcon(Icons.music_note), findsNWidgets(12));
    expect(find.textContaining('Find the pairs'), findsOneWidget);
    expect(find.text('0 moves'), findsOneWidget);

    // Flip two distinct cards — completing a turn ticks the move counter.
    final tiles = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(GestureDetector),
    );
    await tester.tap(tiles.at(0));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(tiles.at(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 move'), findsOneWidget);

    // Let any mismatch flip-back timer fire so teardown is clean.
    await tester.pump(const Duration(milliseconds: 1000));
  });
}
