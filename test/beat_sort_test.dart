import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_values/beat_sort_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sort the beats: every card into a bucket advances the round',
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
          home: BeatSortScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Round 1 of 6'), findsOneWidget);

    Finder cards() => find.byWidgetPredicate((w) => w is Draggable<int>);
    Finder buckets() => find.byWidgetPredicate((w) => w is DragTarget<int>);
    expect(cards(), findsNWidgets(BeatSortScreen.cardCount));
    expect(buckets(), findsNWidgets(3));

    Future<bool> tryDrop(int bucketIndex) async {
      final before = cards().evaluate().length;
      final end = tester.getCenter(buckets().at(bucketIndex));
      final gesture =
          await tester.startGesture(tester.getCenter(cards().first));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -30)); // cross the touch slop
      await tester.pump();
      await gesture.moveTo(end);
      await tester.pump();
      await gesture.up();
      // Fixed pump (not pumpAndSettle): the reacting mascot animates for
      // ~550ms after each drop, which pumpAndSettle interleaves badly with the
      // next drag.
      await tester.pump(const Duration(milliseconds: 650));
      return cards().evaluate().length < before;
    }

    // Place every card by trying each bucket until it's accepted.
    for (var placed = 0; placed < BeatSortScreen.cardCount; placed++) {
      for (var b = 0; b < 3; b++) {
        if (cards().evaluate().isEmpty || await tryDrop(b)) break;
      }
    }

    expect(cards().evaluate().length, 0, reason: 'all cards should be placed');

    // A fully sorted round auto-advances after the 700ms delay.
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Round 2 of 6'), findsOneWidget);
  });
}
