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
}
