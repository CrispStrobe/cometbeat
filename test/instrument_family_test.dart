import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/songs/instrument_family_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

InstrumentFamilyTester _game(WidgetTester tester) =>
    tester.state<State<InstrumentFamilyScreen>>(
      find.byType(InstrumentFamilyScreen),
    ) as InstrumentFamilyTester;

const _label = {
  'strings': 'Strings',
  'woodwind': 'Woodwind',
  'brass': 'Brass',
  'percussion': 'Percussion',
  'keyboard': 'Keyboard',
};

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label = _label[_game(tester).answerFamily]!;
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 800)); // clear auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers the five families and records under timbre.family', (
    tester,
  ) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const InstrumentFamilyScreen(), sri: sri);

    // All five family options are offered.
    for (final label in _label.values) {
      expect(find.text(label), findsOneWidget);
    }

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['timbre']!.keys, ['family']);
  });

  testWidgets('clearing all rounds finishes with a result screen', (
    tester,
  ) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const InstrumentFamilyScreen(), sri: sri);

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
