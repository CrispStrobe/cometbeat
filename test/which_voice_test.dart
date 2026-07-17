// Which Voice? — identify the voice of a highlighted note. Driven through the
// UI: tap the voice button the game reports as the answer.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/satb_voicing.dart';
import 'package:comet_beat/features/games/note_reading/which_voice_screen.dart';
import 'package:crisp_notation/crisp_notation.dart' show StaffSystemView;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

WhichVoiceTester _game(WidgetTester tester) =>
    tester.state<State<WhichVoiceScreen>>(find.byType(WhichVoiceScreen))
        as WhichVoiceTester;

const _labels = {
  SatbVoice.soprano: 'Soprano',
  SatbVoice.alto: 'Alto',
  SatbVoice.tenor: 'Tenor',
  SatbVoice.bass: 'Bass',
};

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label = _labels[_game(tester).answerVoice]!;
  await tester.tap(find.widgetWithText(FilledButton, label));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the chord and records under note_reading.voice',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const WhichVoiceScreen(), sri: sri);

    expect(find.byType(StaffSystemView), findsOneWidget);

    await _answerCorrectly(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(sri.getDetailedBreakdown()['note_reading']!.keys, ['voice']);
  });

  testWidgets('clearing all ten rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const WhichVoiceScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
      await tester.pump(const Duration(seconds: 1));
    }

    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
    await tester.pump(const Duration(seconds: 1));
  });
}
