// Find the Key — staff note → tap the piano key, treble and bass. Taps are
// driven through the game's KeyFindTester seam (by MIDI number), so the test
// doesn't depend on keyboard hit-test geometry.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/keyboard/key_find_screen.dart';
import 'package:crisp_notation/crisp_notation.dart' show Clef;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

KeyFindTester _game(WidgetTester tester) =>
    tester.state<State<KeyFindScreen>>(find.byType(KeyFindScreen))
        as KeyFindTester;

Future<void> _answerCorrectly(WidgetTester tester) async {
  _game(tester).tapKey(_game(tester).targetMidi);
  await tester.pump(const Duration(milliseconds: 800)); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'treble: tapping the right key clears rounds and records the read',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const KeyFindScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
    expect(sri.getDetailedBreakdown()['keyboard']!.keys, ['find']);
  });

  testWidgets('bass: the low staff notes land on real keys and score',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const KeyFindScreen(clef: Clef.bass), sri: sri);

    // Bass targets sit two octaves down (G2..A3 = MIDI 43..57), inside the
    // shifted keyboard (C2..B3 = 36..59).
    expect(_game(tester).targetMidi, inInclusiveRange(36, 59));

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(sri.getDetailedBreakdown()['keyboard']!.keys, ['find']);
  });
}
