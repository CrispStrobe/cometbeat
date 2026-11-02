// Smooth or Short? — the articulation ear game. No staff is shown, so a plain
// provider harness is enough; we tap the correct button per the game's own
// report of the answer.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/explain/answer_explanation.dart';
import 'package:comet_beat/features/games/expression/articulation_ear_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

ArticulationEarTester _game(WidgetTester tester) =>
    tester.state<State<ArticulationEarScreen>>(
      find.byType(ArticulationEarScreen),
    ) as ArticulationEarTester;

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label = _game(tester).answerLegato ? 'Smooth' : 'Short';
  await tester.tap(find.text(label));
  await tester.pump(
    kExplanationHold + const Duration(milliseconds: 100),
  ); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers Smooth / Short and records under articulation.hear',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const ArticulationEarScreen(), sri: sri);

    expect(find.text('Smooth'), findsOneWidget);
    expect(find.text('Short'), findsOneWidget);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['articulation']!.keys, ['hear']);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const ArticulationEarScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
