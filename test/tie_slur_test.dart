// Tie or Slur? — the curve-reading drill. A staff card is shown, so the shared
// game surface is used; we tap the correct Tie/Slur button per the game's own
// report of the answer.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/tie_slur_screen.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

TieSlurTester _game(WidgetTester tester) =>
    tester.state<State<TieSlurScreen>>(find.byType(TieSlurScreen))
        as TieSlurTester;

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label = _game(tester).answerTie ? 'Tie' : 'Slur';
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 800)); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers Tie / Slur and records under reading.curve',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const TieSlurScreen(), sri: sri);

    expect(find.text('Tie'), findsOneWidget);
    expect(find.text('Slur'), findsOneWidget);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['reading']!.keys, ['curve']);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const TieSlurScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
