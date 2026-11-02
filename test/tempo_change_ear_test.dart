// Speeding Up or Slowing Down? — the tempo-direction ear game. No staff is
// shown, so a plain provider harness is enough; we tap the correct button per
// the game's own report of the answer.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/explain/answer_explanation.dart';
import 'package:comet_beat/features/games/expression/tempo_change_ear_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

TempoChangeEarTester _game(WidgetTester tester) =>
    tester.state<State<TempoChangeEarScreen>>(
      find.byType(TempoChangeEarScreen),
    ) as TempoChangeEarTester;

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label =
      _game(tester).answerAccelerando ? 'Speeding up' : 'Slowing down';
  await tester.tap(find.text(label));
  await tester.pump(
    kExplanationHold + const Duration(milliseconds: 100),
  ); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers Faster / Slower and records under tempo.hear',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const TempoChangeEarScreen(), sri: sri);

    expect(find.text('Speeding up'), findsOneWidget);
    expect(find.text('Slowing down'), findsOneWidget);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['tempo']!.keys, ['hear']);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const TempoChangeEarScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
