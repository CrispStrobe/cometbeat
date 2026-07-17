// Sharp or Flat? — the accidental-sign sort. Drives real drag gestures: each
// note only drops into its correct ♯/♭ basket, and sorting all four advances the
// round. Uses the shared game surface so the staff cards lay out on CI.

import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/accidental_sort_screen.dart';
import 'package:crisp_notation/crisp_notation.dart' show Clef, StaffView;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

Finder _cards() => find.byWidgetPredicate((w) => w is Draggable<int>);
Finder _buckets() => find.byWidgetPredicate((w) => w is DragTarget<int>);

/// Drags every card into a basket that accepts it (each note only drops into
/// its correct ♯/♭ basket, so try both).
Future<void> _sortAllCards(WidgetTester tester) async {
  Future<bool> tryDrop(int bucketIndex) async {
    final before = _cards().evaluate().length;
    final end = tester.getCenter(_buckets().at(bucketIndex));
    final gesture = await tester.startGesture(tester.getCenter(_cards().first));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -30)); // cross the touch slop
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 650));
    return _cards().evaluate().length < before;
  }

  final bucketCount = _buckets().evaluate().length;
  for (var placed = 0; placed < AccidentalSortScreen.cardCount; placed++) {
    for (var b = 0; b < bucketCount; b++) {
      if (_cards().evaluate().isEmpty || await tryDrop(b)) break;
    }
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sorting every note into its basket advances the round',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const AccidentalSortScreen(), sri: sri);

    expect(find.text('Round 1 of 6'), findsOneWidget);
    expect(_cards(), findsNWidgets(AccidentalSortScreen.cardCount));
    expect(_buckets(), findsNWidgets(2));

    await _sortAllCards(tester);
    expect(_cards().evaluate().length, 0, reason: 'all cards should be placed');

    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Round 2 of 6'), findsOneWidget);

    // Correct drops score into the accidental-sign skill.
    expect(sri.getDetailedBreakdown()['accidentals']!.keys, ['sign']);
  });

  testWidgets('the bass variant reads in the bass clef and still sorts',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(
      tester,
      const AccidentalSortScreen(clef: Clef.bass),
      sri: sri,
    );

    // The cards engrave a bass clef.
    expect(
      tester.widgetList<StaffView>(find.byType(StaffView)).first.score.clef,
      Clef.bass,
    );

    await _sortAllCards(tester);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Round 2 of 6'), findsOneWidget);
    expect(sri.getDetailedBreakdown()['accidentals']!.keys, ['sign']);
  });

  testWidgets('at 2 stars it widens to three baskets incl. Natural',
      (tester) async {
    final progress = ProgressService();
    await progress.load();
    progress.recordResult('accidental_sort', score: 550, stars: 2);

    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(
      tester,
      const AccidentalSortScreen(),
      sri: sri,
      extraProviders: [
        ChangeNotifierProvider<ProgressService>.value(value: progress),
      ],
    );

    // Three baskets now, one of them Natural (♮ is guaranteed in play).
    expect(_buckets(), findsNWidgets(3));
    expect(find.textContaining('♮'), findsOneWidget);

    await _sortAllCards(tester);
    expect(_cards().evaluate().length, 0, reason: 'all cards should be placed');
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Round 2 of 6'), findsOneWidget);
  });
}
