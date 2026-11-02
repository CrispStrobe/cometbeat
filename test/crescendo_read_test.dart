// Crescendo or Diminuendo? — the hairpin-reading drill. A staff card shows a
// phrase under a real crisp_notation hairpin, so the shared game surface is
// used; we tap the button matching the game's own report of the wedge type.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/explain/answer_explanation.dart';
import 'package:comet_beat/features/games/expression/crescendo_read_screen.dart';
import 'package:crisp_notation/crisp_notation.dart' show HairpinType, StaffView;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

CrescendoReadTester _game(WidgetTester tester) =>
    tester.state<State<CrescendoReadScreen>>(
      find.byType(CrescendoReadScreen),
    ) as CrescendoReadTester;

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label =
      _game(tester).answerCrescendo ? 'Getting louder' : 'Getting softer';
  await tester.tap(find.text(label));
  await tester.pump(
    kExplanationHold + const Duration(milliseconds: 100),
  ); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('draws a staff with a hairpin matching the reported answer',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const CrescendoReadScreen(), sri: sri);

    expect(find.byType(StaffView), findsOneWidget);
    // The rendered card carries a real hairpin whose direction matches the
    // game's reported answer (fed to the crisp_notation layout).
    final hairpins =
        tester.widget<StaffView>(find.byType(StaffView)).score.hairpins;
    expect(hairpins, hasLength(1));
    final expected = _game(tester).answerCrescendo
        ? HairpinType.crescendo
        : HairpinType.diminuendo;
    expect(hairpins.first.type, expected);

    expect(find.text('Getting louder'), findsOneWidget);
    expect(find.text('Getting softer'), findsOneWidget);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['reading']!.keys, ['hairpin']);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const CrescendoReadScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });

  testWidgets('an answer explains the hairpin it names (right or wrong)',
      (tester) async {
    await pumpGame(tester, const CrescendoReadScreen());
    final cresc = _game(tester).answerCrescendo;
    // Tap the WRONG button first: the card explains what was tapped.
    await tester.tap(find.text(cresc ? 'Getting softer' : 'Getting louder'));
    await tester.pump();
    expect(find.byKey(AnswerExplanation.panelKey), findsOneWidget);
    expect(find.byType(HairpinRamp), findsOneWidget);
    expect(
      tester.widget<HairpinRamp>(find.byType(HairpinRamp)).rising,
      !cresc,
    );
    // Then the right one: the card switches to the real answer.
    await tester.tap(find.text(cresc ? 'Getting louder' : 'Getting softer'));
    await tester.pump();
    expect(
      tester.widget<HairpinRamp>(find.byType(HairpinRamp)).rising,
      cresc,
    );
  });
}
