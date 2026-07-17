// In the Scale? — scale-membership swipe drill. The card is also tap-playable
// (the In/Out labels have onTap), so tap the correct label per the game's report.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/scales/in_scale_screen.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

InScaleTester _game(WidgetTester tester) =>
    tester.state<State<InScaleScreen>>(find.byType(InScaleScreen))
        as InScaleTester;

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label = _game(tester).answerInScale ? 'In' : 'Out';
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 800)); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers In / Out and records under scales.member',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const InScaleScreen(), sri: sri);

    expect(find.text('In'), findsOneWidget);
    expect(find.text('Out'), findsOneWidget);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['scales']!.keys, ['member']);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const InScaleScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
