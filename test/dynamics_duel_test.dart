// Louder or Softer? — the dynamic-mark reading duel. Two SMuFL dynamic glyphs
// show as cards; tapping the louder one advances the round. No staff, so a plain
// provider harness is enough; we read the two glyphs and tap the louder.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/explain/answer_explanation.dart';
import 'package:comet_beat/features/games/explain/music_terms.dart';
import 'package:comet_beat/features/games/note_values/dynamics_duel_screen.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/shared/widgets/music_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

/// The dynamic marks currently shown on the answer cards (the tappable
/// InkWells — not the glyphs of the explanation card's loudness ladder).
final _cardGlyphs = find.descendant(
  of: find.byType(InkWell),
  matching: find.byType(MusicGlyph),
);

List<DynamicMark> _shownMarks(WidgetTester tester) => [
      for (final g in tester.widgetList<MusicGlyph>(_cardGlyphs))
        for (final m in kDynamicMarks)
          if (m.code == g.glyph.runes.first) m,
    ];

Future<void> _tapLouder(WidgetTester tester) async {
  final louder = _shownMarks(tester).reduce((a, b) => a.rank >= b.rank ? a : b);
  await tester.tap(
    find.descendant(
      of: find.byType(InkWell),
      matching: find.byWidgetPredicate(
        (w) => w is MusicGlyph && w.glyph.runes.first == louder.code,
      ),
    ),
  );
  // The solved round holds for its explanation, then advances.
  await tester.pump(kExplanationHold + const Duration(milliseconds: 100));
}

/// The explanation's headline for [t]: "mezzoforte = medium loud".
Finder _termLine(MusicTerm t) => find.byWidgetPredicate(
      (w) =>
          w is RichText && w.text.toPlainText().startsWith('${t.italian} = '),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows two dynamic marks and records under reading.dynamics',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const DynamicsDuelScreen(), sri: sri);

    final shown = _shownMarks(tester);
    expect(shown, hasLength(2));
    expect(shown[0].rank == shown[1].rank, isFalse);

    await _tapLouder(tester);
    expect(sri.getDetailedBreakdown()['reading']!.keys, ['dynamics']);
  });

  testWidgets('tapping the louder mark through all rounds finishes with stars',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const DynamicsDuelScreen(), sri: sri);

    for (var i = 0; i < 10; i++) {
      if (find.byType(GameResultView).evaluate().isNotEmpty) break;
      await _tapLouder(tester);
    }
    expect(find.byType(GameResultView), findsOneWidget);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });

  testWidgets(
      'a right answer explains both marks on the loudness ladder, '
      'then the game advances', (tester) async {
    await pumpGame(tester, const DynamicsDuelScreen());
    expect(find.byKey(AnswerExplanation.panelKey), findsNothing);

    final shown = _shownMarks(tester);
    final louder = shown.reduce((a, b) => a.rank >= b.rank ? a : b);
    await tester.tap(
      find.descendant(
        of: find.byType(InkWell),
        matching: find.byWidgetPredicate(
          (w) => w is MusicGlyph && w.glyph.runes.first == louder.code,
        ),
      ),
    );
    await tester.pump();

    // The card names both marks with their meaning ("mezzoforte = medium
    // loud") and draws the six-rung ladder.
    expect(find.byKey(AnswerExplanation.panelKey), findsOneWidget);
    for (final m in shown) {
      final t = MusicTerm.dynamicFromMark(m.name)!;
      expect(_termLine(t), findsOneWidget);
    }
    expect(find.byType(DynamicsLadder), findsOneWidget);
    expect(find.textContaining('Round 1'), findsOneWidget);

    // The demo lights the rung that is sounding (left card first).
    await tester.pump(const Duration(milliseconds: 300));
    final ladder = tester.widget<DynamicsLadder>(find.byType(DynamicsLadder));
    expect(ladder.sounding!.value, MusicTerm.dynamicFromMark(shown.first.name));

    // Still on round 1 well inside the hold; on round 2 after it.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.textContaining('Round 1'), findsOneWidget);
    await tester.pump(kExplanationHold);
    expect(find.textContaining('Round 2'), findsOneWidget);
    expect(find.byKey(AnswerExplanation.panelKey), findsNothing);
  });

  testWidgets('"Next" skips the hold straight to the next round',
      (tester) async {
    await pumpGame(tester, const DynamicsDuelScreen());
    final louder =
        _shownMarks(tester).reduce((a, b) => a.rank >= b.rank ? a : b);
    await tester.tap(
      find.descendant(
        of: find.byType(InkWell),
        matching: find.byWidgetPredicate(
          (w) => w is MusicGlyph && w.glyph.runes.first == louder.code,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('answer_explanation_next')));
    await tester.pump();
    expect(find.textContaining('Round 2'), findsOneWidget);
    await tester.pump(kExplanationHold); // no stray second advance
    expect(find.textContaining('Round 2'), findsOneWidget);
  });

  testWidgets('a wrong answer explains the tapped mark and does not advance',
      (tester) async {
    await pumpGame(tester, const DynamicsDuelScreen());
    final softer =
        _shownMarks(tester).reduce((a, b) => a.rank < b.rank ? a : b);
    await tester.tap(
      find.descendant(
        of: find.byType(InkWell),
        matching: find.byWidgetPredicate(
          (w) => w is MusicGlyph && w.glyph.runes.first == softer.code,
        ),
      ),
    );
    await tester.pump();
    final t = MusicTerm.dynamicFromMark(softer.name)!;
    expect(find.byKey(AnswerExplanation.panelKey), findsOneWidget);
    expect(_termLine(t), findsOneWidget);
    expect(find.byKey(const ValueKey('answer_explanation_next')), findsNothing);
    await tester.pump(kExplanationHold * 2);
    expect(find.textContaining('Round 1'), findsOneWidget);
  });
}
