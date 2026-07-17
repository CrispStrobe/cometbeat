// Faster or Slower? — the tempo-term reading duel. Two Italian tempo words show
// as cards; tapping the faster one advances the round. No staff, so a plain
// provider harness is enough; we read the two shown terms and tap the faster.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_values/tempo_duel_screen.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

int _rankOf(String name) => kTempoTerms.firstWhere((t) => t.name == name).rank;

/// The two tempo-term names currently shown on the cards.
List<String> _shownTerms() => [
      for (final t in kTempoTerms)
        if (find.text(t.name).evaluate().isNotEmpty) t.name,
    ];

/// Taps the faster of the two tempo cards currently shown.
Future<void> _tapFaster(WidgetTester tester) async {
  final names = _shownTerms()
    ..sort((a, b) => _rankOf(b).compareTo(_rankOf(a))); // fastest first
  await tester.tap(find.text(names.first));
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows two tempo terms and records under reading.tempo',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const TempoDuelScreen(), sri: sri);

    // Two distinct tempo-word cards are shown.
    final shown = _shownTerms();
    expect(shown, hasLength(2));
    expect(_rankOf(shown[0]) == _rankOf(shown[1]), isFalse);

    await _tapFaster(tester);
    expect(sri.getDetailedBreakdown()['reading']!.keys, ['tempo']);
  });

  testWidgets('tapping the faster term through all rounds finishes with stars',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const TempoDuelScreen(), sri: sri);

    for (var i = 0; i < 10; i++) {
      if (find.byType(GameResultView).evaluate().isNotEmpty) break;
      await _tapFaster(tester);
    }
    expect(find.byType(GameResultView), findsOneWidget);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
