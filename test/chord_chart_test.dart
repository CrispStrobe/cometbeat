// Chord Chart — lead-sheet reading (symbol → notation). Driven through the UI:
// the correct card varies per round, so tap the option whose chord matches the
// shown symbol (the game reports the target symbol).

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/chords/chord_chart_screen.dart';
import 'package:crisp_notation/crisp_notation.dart' show StaffView;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

ChordChartTester _game(WidgetTester tester) =>
    tester.state<State<ChordChartScreen>>(find.byType(ChordChartScreen))
        as ChordChartTester;

// Tap the notated card that matches the shown symbol (cards are in option order,
// so the target's InkWell is at targetIndex).
Future<void> _answerCorrectly(WidgetTester tester) async {
  await tester.tap(find.byType(InkWell).at(_game(tester).targetIndex));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows a symbol and four notated options', (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const ChordChartScreen(), sri: sri);

    expect(find.text(_game(tester).targetSymbol), findsOneWidget);
    expect(find.byType(StaffView), findsNWidgets(4));
  });

  testWidgets('matching the symbol records under chords.symbol',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const ChordChartScreen(), sri: sri);

    await _answerCorrectly(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(sri.getDetailedBreakdown()['chords']!.keys, ['symbol']);
  });

  testWidgets('clearing all ten rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const ChordChartScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
      await tester.pump(const Duration(seconds: 1)); // auto-advance
    }

    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
    await tester.pump(const Duration(seconds: 1));
  });
}
