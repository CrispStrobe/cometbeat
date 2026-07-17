// Key Change? — the modulation ear game. No staff, so a plain provider harness
// is enough; we tap the correct Same/Changed button per the game's own report
// of the answer.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/scales/modulation_ear_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

ModulationEarTester _game(WidgetTester tester) =>
    tester.state<State<ModulationEarScreen>>(find.byType(ModulationEarScreen))
        as ModulationEarTester;

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label = _game(tester).answerChanged ? 'Key changed' : 'Same key';
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 800)); // clear auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'offers Same key / Key changed and records under scales.modulation',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(tester, const ModulationEarScreen(), sri: sri);

    expect(find.text('Same key'), findsOneWidget);
    expect(find.text('Key changed'), findsOneWidget);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['scales']!.keys, ['modulation']);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(tester, const ModulationEarScreen(), sri: sri);

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
