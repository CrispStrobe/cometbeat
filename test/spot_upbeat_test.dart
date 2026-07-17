// Spot the Upbeat — the anacrusis-reading drill. A staff card is shown, so the
// shared game surface is used; we tap the correct Upbeat / On-the-beat button
// per the game's own report of the answer.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/measures/spot_upbeat_screen.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

SpotUpbeatTester _game(WidgetTester tester) =>
    tester.state<State<SpotUpbeatScreen>>(find.byType(SpotUpbeatScreen))
        as SpotUpbeatTester;

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label = _game(tester).answerUpbeat ? 'Upbeat' : 'On the beat';
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 800)); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers Upbeat / On the beat and records under measures.upbeat',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(tester, const SpotUpbeatScreen(), sri: sri);

    expect(find.text('Upbeat'), findsOneWidget);
    expect(find.text('On the beat'), findsOneWidget);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['measures']!.keys, ['upbeat']);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(tester, const SpotUpbeatScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });

  testWidgets('the structural cue matches the claimed answer every round',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(tester, const SpotUpbeatScreen(), sri: sri);

    // The whole drill rests on the invariant: an "upbeat" round is built with a
    // short pickup first measure, an "on the beat" round with a full one. Check
    // it across all 10 (randomly generated) rounds.
    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      final g = _game(tester);
      expect(g.shownFirstBarIsPickup, g.answerUpbeat);
      await _answerCorrectly(tester);
    }
  });
}
