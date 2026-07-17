// Louder or Softer? — the dynamic-mark reading duel. Two SMuFL dynamic glyphs
// show as cards; tapping the louder one advances the round. No staff, so a plain
// provider harness is enough; we read the two glyphs and tap the louder.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_values/dynamics_duel_screen.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/shared/widgets/music_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

/// The dynamic marks currently shown on the cards (filtering out any other
/// MusicGlyphs on screen).
List<DynamicMark> _shownMarks(WidgetTester tester) => [
      for (final g in tester.widgetList<MusicGlyph>(find.byType(MusicGlyph)))
        for (final m in kDynamicMarks)
          if (m.code == g.glyph.runes.first) m,
    ];

Future<void> _tapLouder(WidgetTester tester) async {
  final louder = _shownMarks(tester).reduce((a, b) => a.rank >= b.rank ? a : b);
  await tester.tap(
    find.byWidgetPredicate(
      (w) => w is MusicGlyph && w.glyph.runes.first == louder.code,
    ),
  );
  await tester.pump(const Duration(milliseconds: 800));
}

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
}
