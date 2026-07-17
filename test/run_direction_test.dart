// Ascending or Descending? — the run-direction ear game. No staff; we tap the
// correct button per the game's own report of the answer.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/scales/run_direction_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

RunDirectionTester _game(WidgetTester tester) =>
    tester.state<State<RunDirectionScreen>>(find.byType(RunDirectionScreen))
        as RunDirectionTester;

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label = _game(tester).answerAsc ? 'Ascending' : 'Descending';
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 800)); // clear auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers Ascending / Descending and records under pitch.hear', (
    tester,
  ) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const RunDirectionScreen(), sri: sri);

    expect(find.text('Ascending'), findsOneWidget);
    expect(find.text('Descending'), findsOneWidget);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['pitch']!.keys, ['hear']);
  });

  testWidgets('clearing all rounds finishes with a result screen', (
    tester,
  ) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const RunDirectionScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(
      find.byIcon(Icons.star).evaluate().length,
      greaterThanOrEqualTo(1),
    );
  });
}
