// Triad or Seventh? — the added-seventh ear game. No staff, so a plain provider
// tree is enough; we tap the correct Triad/Seventh button per the game's own
// report of the answer.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/chords/triad_seventh_screen.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

TriadSeventhTester _game(WidgetTester tester) =>
    tester.state<State<TriadSeventhScreen>>(find.byType(TriadSeventhScreen))
        as TriadSeventhTester;

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label = _game(tester).answerSeventh ? 'Seventh' : 'Triad';
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 800)); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers Triad / Seventh and records under chords.hear',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const TriadSeventhScreen(), sri: sri);

    expect(find.text('Triad'), findsOneWidget);
    expect(find.text('Seventh'), findsOneWidget);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['chords']!.keys, ['hear']);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const TriadSeventhScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
