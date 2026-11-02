// Soft to Loud — order dynamic marks pp…ff. Driven through the UI: the game
// reports the correct tap order (softest→loudest); tap the cards by key in that
// order.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/explain/answer_explanation.dart';
import 'package:comet_beat/features/games/note_values/dynamics_order_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

DynamicsOrderTester _game(WidgetTester tester) =>
    tester.state<State<DynamicsOrderScreen>>(find.byType(DynamicsOrderScreen))
        as DynamicsOrderTester;

Future<void> _solveRound(WidgetTester tester) async {
  for (final i in _game(tester).tapOrder) {
    await tester.tap(find.byKey(ValueKey('dynamic_card_$i')));
    await tester.pump();
  }
  await tester.pump(
    kExplanationHold + const Duration(milliseconds: 100),
  ); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('ordering softest→loudest records under reading.dynamics',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const DynamicsOrderScreen(), sri: sri);

    expect(find.byKey(const ValueKey('dynamic_card_0')), findsOneWidget);
    await _solveRound(tester);

    expect(sri.getDetailedBreakdown()['reading']!.keys, contains('dynamics'));
  });

  testWidgets('a wrong tap buzzes but the round can still be finished',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const DynamicsOrderScreen(), sri: sri);

    // Tap the loudest (last in order) first — wrong.
    final order = _game(tester).tapOrder;
    await tester.tap(find.byKey(ValueKey('dynamic_card_${order.last}')));
    await tester.pump();
    // Now solve correctly.
    await _solveRound(tester);
    expect(sri.getDetailedBreakdown()['reading']!.keys, contains('dynamics'));
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const DynamicsOrderScreen(), sri: sri);

    for (var r = 0; r < 8 && !_game(tester).isFinished; r++) {
      await _solveRound(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });

  testWidgets('a finished ladder is explained soft→loud and still advances',
      (tester) async {
    await pumpGame(tester, const DynamicsOrderScreen());
    for (final i in _game(tester).tapOrder) {
      expect(find.byKey(AnswerExplanation.panelKey), findsNothing);
      await tester.tap(find.byKey(ValueKey('dynamic_card_$i')));
      await tester.pump();
    }
    expect(find.byKey(AnswerExplanation.panelKey), findsOneWidget);
    final card =
        tester.widget<AnswerExplanation>(find.byType(AnswerExplanation));
    expect(card.terms, hasLength(DynamicsOrderScreen.cardCount));
    for (var i = 1; i < card.terms.length; i++) {
      expect(card.terms[i].rank, greaterThan(card.terms[i - 1].rank));
    }
    expect(find.textContaining('Round 1'), findsOneWidget);
    await tester.pump(kExplanationHold + const Duration(milliseconds: 100));
    expect(find.textContaining('Round 2'), findsOneWidget);
    expect(find.byKey(AnswerExplanation.panelKey), findsNothing);
  });
}
