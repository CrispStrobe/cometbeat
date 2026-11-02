// Getting Louder or Softer? — the dynamics-direction ear game. No staff is
// shown, so a plain provider harness is enough; we tap the correct button per
// the game's own report of the answer.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/explain/answer_explanation.dart';
import 'package:comet_beat/features/games/expression/crescendo_ear_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

CrescendoEarTester _game(WidgetTester tester) =>
    tester.state<State<CrescendoEarScreen>>(find.byType(CrescendoEarScreen))
        as CrescendoEarTester;

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label =
      _game(tester).answerCrescendo ? 'Getting louder' : 'Getting softer';
  await tester.tap(find.text(label));
  await tester.pump(
    kExplanationHold + const Duration(milliseconds: 100),
  ); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers Louder / Softer and records under dynamics.hear',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const CrescendoEarScreen(), sri: sri);

    expect(find.text('Getting louder'), findsOneWidget);
    expect(find.text('Getting softer'), findsOneWidget);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['dynamics']!.keys, ['hear']);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const CrescendoEarScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
