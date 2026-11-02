// Slow to Fast — order Italian tempo words. Driven through the UI: the game
// reports the correct tap order (slowest→fastest); tap the cards by key in
// that order.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/explain/answer_explanation.dart';
import 'package:comet_beat/features/games/note_values/tempo_order_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

TempoOrderTester _game(WidgetTester tester) =>
    tester.state<State<TempoOrderScreen>>(find.byType(TempoOrderScreen))
        as TempoOrderTester;

Future<void> _solveRound(WidgetTester tester) async {
  for (final i in _game(tester).tapOrder) {
    await tester.tap(find.byKey(ValueKey('tempo_card_$i')));
    await tester.pump();
  }
  await tester.pump(
    kExplanationHold + const Duration(milliseconds: 100),
  ); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('ordering slowest→fastest records under reading.tempo',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const TempoOrderScreen(), sri: sri);

    expect(find.byKey(const ValueKey('tempo_card_0')), findsOneWidget);
    await _solveRound(tester);

    expect(sri.getDetailedBreakdown()['reading']!.keys, contains('tempo'));
  });

  testWidgets('a wrong tap buzzes but the round can still be finished',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const TempoOrderScreen(), sri: sri);

    // Tap the fastest (last in order) first — wrong.
    final order = _game(tester).tapOrder;
    await tester.tap(find.byKey(ValueKey('tempo_card_${order.last}')));
    await tester.pump();
    await _solveRound(tester);
    expect(sri.getDetailedBreakdown()['reading']!.keys, contains('tempo'));
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const TempoOrderScreen(), sri: sri);

    for (var r = 0; r < 8 && !_game(tester).isFinished; r++) {
      await _solveRound(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
