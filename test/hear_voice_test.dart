// Hear the Voice — aural SATB. Audio can't be heard in a test, but the game
// reports which voice plays alone, so tap that voice button; timers are cancelled
// on dispose.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/hear_voice_screen.dart';
import 'package:comet_beat/features/games/note_reading/satb_voicing.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

HearVoiceTester _game(WidgetTester tester) =>
    tester.state<State<HearVoiceScreen>>(find.byType(HearVoiceScreen))
        as HearVoiceTester;

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

  testWidgets('offers a replay and records under note_reading.ear_voice',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const HearVoiceScreen(), sri: sri);

    expect(find.byIcon(Icons.replay), findsOneWidget);

    await _answerCorrectly(tester);
    await tester.pump(const Duration(seconds: 1)); // drain audio timers

    expect(sri.getDetailedBreakdown()['note_reading']!.keys, ['ear_voice']);
  });

  testWidgets('clearing all ten rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const HearVoiceScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
      await tester.pump(const Duration(seconds: 1));
    }

    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
    await tester.pump(const Duration(seconds: 1));
  });
}
