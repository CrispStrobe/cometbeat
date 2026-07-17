import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/which_clef_screen.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

WhichClefTester _game(WidgetTester tester) =>
    tester.state<State<WhichClefScreen>>(find.byType(WhichClefScreen))
        as WhichClefTester;

const _label = {
  'treble': 'Treble',
  'bass': 'Bass',
  'alto': 'Alto',
  'tenor': 'Tenor',
};

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label = _label[_game(tester).answerClef]!;
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 800)); // clear auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers Treble / Bass and records under reading.clef', (
    tester,
  ) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const WhichClefScreen(), sri: sri);

    // At 0 stars the answer set is the two basic clefs.
    expect(find.text('Treble'), findsOneWidget);
    expect(find.text('Bass'), findsOneWidget);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['reading']!.keys, ['clef']);
  });

  testWidgets('clearing all rounds finishes with a result screen', (
    tester,
  ) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const WhichClefScreen(), sri: sri);

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
