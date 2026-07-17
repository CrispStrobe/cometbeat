// Read the Voice — read one line out of a multi-voice chord. Driven through the
// UI: the highlighted voice varies per round, so tap the note-name button that
// matches the game's reported answer.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/read_voice_screen.dart';
import 'package:crisp_notation/crisp_notation.dart' show Step, StaffSystemView;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

ReadVoiceTester _game(WidgetTester tester) =>
    tester.state<State<ReadVoiceScreen>>(find.byType(ReadVoiceScreen))
        as ReadVoiceTester;

// English note letters (auto naming under the EN test locale).
const _letters = {
  Step.c: 'C',
  Step.d: 'D',
  Step.e: 'E',
  Step.f: 'F',
  Step.g: 'G',
  Step.a: 'A',
  Step.b: 'B',
};

Future<void> _answerCorrectly(WidgetTester tester) async {
  final letter = _letters[_game(tester).answerStep]!;
  await tester.tap(find.widgetWithText(FilledButton, letter));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows a voice chord and records under note_reading',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const ReadVoiceScreen(), sri: sri);

    expect(find.byType(StaffSystemView), findsOneWidget);

    await _answerCorrectly(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(sri.getDetailedBreakdown()['note_reading'], isNotNull);
  });

  testWidgets('clearing all ten rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const ReadVoiceScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
      await tester.pump(const Duration(seconds: 1)); // auto-advance
    }

    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
    await tester.pump(const Duration(seconds: 1));
  });
}
