// Count the Notes — the aural-attention ear game. No staff is shown, so a plain
// provider harness is enough; we tap the count button the game reports as
// correct (matched on the FilledButton so it never collides with the round
// counter's digits).

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/scales/count_notes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

CountNotesTester _game(WidgetTester tester) =>
    tester.state<State<CountNotesScreen>>(find.byType(CountNotesScreen))
        as CountNotesTester;

Future<void> _answerCorrectly(WidgetTester tester) async {
  final finder = find.widgetWithText(
    FilledButton,
    '${_game(tester).answerCount}',
  );
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 800)); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers 2 / 3 / 4 and records under pitch.hear', (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const CountNotesScreen(), sri: sri);

    for (final n in const ['2', '3', '4']) {
      expect(find.widgetWithText(FilledButton, n), findsOneWidget);
    }
    // The correct count is one of the offered options.
    expect(const [2, 3, 4], contains(_game(tester).answerCount));

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['pitch']!.keys, ['hear']);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const CountNotesScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
