// Longest First — order note values by length. Driven through the UI: the game
// reports the correct tap order (card indices longest→shortest); tap the cards
// by their keys in that order.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_values/value_order_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

ValueOrderTester _game(WidgetTester tester) =>
    tester.state<State<ValueOrderScreen>>(find.byType(ValueOrderScreen))
        as ValueOrderTester;

Future<void> _solveRound(WidgetTester tester) async {
  for (final i in _game(tester).tapOrder) {
    await tester.tap(find.byKey(ValueKey('value_card_$i')));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 800)); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('ordering longest→shortest records under note_values.order',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const ValueOrderScreen(), sri: sri);

    expect(find.byKey(const ValueKey('value_card_0')), findsOneWidget);
    await _solveRound(tester);

    expect(sri.getDetailedBreakdown()['note_values']!.keys, ['order']);
  });

  testWidgets('a wrong tap buzzes but the round can still be finished',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const ValueOrderScreen(), sri: sri);

    // Tap the shortest (last in order) first — wrong.
    final order = _game(tester).tapOrder;
    await tester.tap(find.byKey(ValueKey('value_card_${order.last}')));
    await tester.pump();
    // Now solve correctly.
    await _solveRound(tester);
    expect(sri.getDetailedBreakdown()['note_values']!.keys, ['order']);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const ValueOrderScreen(), sri: sri);

    for (var r = 0; r < 8 && !_game(tester).isFinished; r++) {
      await _solveRound(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
