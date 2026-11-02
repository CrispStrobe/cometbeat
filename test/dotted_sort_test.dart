// Dotted or Not? — the augmentation-dot sort. Drives real drag gestures: each
// note only drops into its correct Dotted/Plain basket, and sorting all four
// advances the round. Uses the shared game surface so the staff cards lay out.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_values/dotted_sort_screen.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sorting every note into its basket advances the round', (
    tester,
  ) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const DottedSortScreen(), sri: sri);

    expect(find.text('Round 1 of 6'), findsOneWidget);

    Finder cards() => find.byWidgetPredicate((w) => w is Draggable<int>);
    Finder buckets() => find.byWidgetPredicate((w) => w is DragTarget<int>);
    expect(cards(), findsNWidgets(DottedSortScreen.cardCount));
    expect(buckets(), findsNWidgets(2));

    Future<bool> tryDrop(int bucketIndex) async {
      final before = cards().evaluate().length;
      final end = tester.getCenter(buckets().at(bucketIndex));
      final gesture = await tester.startGesture(
        tester.getCenter(cards().first),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0, -30)); // cross the touch slop
      await tester.pump();
      await gesture.moveTo(end);
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 650));
      return cards().evaluate().length < before;
    }

    for (var placed = 0; placed < DottedSortScreen.cardCount; placed++) {
      for (var b = 0; b < 2; b++) {
        if (cards().evaluate().isEmpty || await tryDrop(b)) break;
      }
    }
    expect(cards().evaluate().length, 0, reason: 'all cards should be placed');

    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Round 2 of 6'), findsOneWidget);

    // Correct drops score into the note-value dot skill.
    expect(sri.getDetailedBreakdown()['note_values']!.keys, ['dot']);
  });

  group('only a drop on a WRONG basket is an error', () {
    Finder cards() => find.byWidgetPredicate((w) => w is Draggable<int>);
    Finder buckets() => find.byWidgetPredicate((w) => w is DragTarget<int>);

    Future<void> dragTo(WidgetTester tester, Offset end) async {
      final g = await tester.startGesture(tester.getCenter(cards().first));
      await tester.pump();
      await g.moveBy(const Offset(0, -30));
      await tester.pump();
      await g.moveTo(end);
      await tester.pump();
      await g.up();
      await tester.pump(const Duration(milliseconds: 650));
    }

    testWidgets('tap and drops outside any basket record nothing', (
      tester,
    ) async {
      final sri = SriService(getNow: () => DateTime(2026, 7, 11));
      await pumpGame(tester, const DottedSortScreen(), sri: sri);

      await tester.tap(cards().first);
      await tester.pump(const Duration(milliseconds: 650));
      // Released on empty space, and dropped back where it started.
      final home = tester.getCenter(cards().first);
      await dragTo(tester, home + const Offset(0, 1));
      await dragTo(tester, const Offset(5, 5));

      expect(sri.getDetailedBreakdown(), isEmpty);
      expect(cards(), findsNWidgets(DottedSortScreen.cardCount));
    });

    testWidgets('wrong basket counts wrong, right basket counts correct', (
      tester,
    ) async {
      final sri = SriService(getNow: () => DateTime(2026, 7, 11));
      await pumpGame(tester, const DottedSortScreen(), sri: sri);

      await dragTo(tester, tester.getCenter(buckets().at(0)));
      final first = cards().evaluate().length;
      // Exactly one basket takes the card; the other bounces it as a miss.
      if (first == DottedSortScreen.cardCount) {
        await dragTo(tester, tester.getCenter(buckets().at(1)));
        expect(cards().evaluate().length, DottedSortScreen.cardCount - 1);
      } else {
        expect(first, DottedSortScreen.cardCount - 1);
      }
      expect(sri.getDetailedBreakdown(), isNotEmpty);
    });
  });
}
