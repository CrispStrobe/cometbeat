// Beam or Flag? — the beamed-vs-flagged reading drill. A staff card is shown, so
// the shared game surface is used; we tap the correct Beam/Flag button per the
// game's own report of the answer.

import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_reading/beam_flag_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

BeamFlagTester _game(WidgetTester tester) =>
    tester.state<State<BeamFlagScreen>>(find.byType(BeamFlagScreen))
        as BeamFlagTester;

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label = _game(tester).answerBeamed ? 'Beam' : 'Flag';
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 800)); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers Beam / Flag and records under reading.beam',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const BeamFlagScreen(), sri: sri);

    expect(find.text('Beam'), findsOneWidget);
    expect(find.text('Flag'), findsOneWidget);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['reading']!.keys, ['beam']);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const BeamFlagScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
