import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/whole_half_screen.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

WholeHalfTester _game(WidgetTester tester) =>
    tester.state<State<WholeHalfScreen>>(find.byType(WholeHalfScreen))
        as WholeHalfTester;

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label = _game(tester).answerHalf ? 'Half step' : 'Whole step';
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 800)); // clear auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers Whole / Half and records under reading.tone', (
    tester,
  ) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const WholeHalfScreen(), sri: sri);

    expect(find.text('Whole step'), findsOneWidget);
    expect(find.text('Half step'), findsOneWidget);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['reading']!.keys, ['tone']);
  });

  testWidgets('clearing all rounds finishes with a result screen', (
    tester,
  ) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const WholeHalfScreen(), sri: sri);

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
