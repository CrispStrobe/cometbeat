// Same or Different? — the pitch-discrimination ear game. No staff, so a plain
// provider harness is enough; we tap the correct Same/Different button per the
// game's own report of the answer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/scales/same_diff_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

SameDiffTester _game(WidgetTester tester) =>
    tester.state<State<SameDiffScreen>>(find.byType(SameDiffScreen))
        as SameDiffTester;

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label = _game(tester).answerSame ? 'Same' : 'Different';
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 800)); // clear auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers Same / Different and records under pitch.hear', (
    tester,
  ) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const SameDiffScreen(), sri: sri);

    expect(find.text('Same'), findsOneWidget);
    expect(find.text('Different'), findsOneWidget);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['pitch']!.keys, ['hear']);
  });

  testWidgets('clearing all rounds finishes with a result screen', (
    tester,
  ) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const SameDiffScreen(), sri: sri);

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
