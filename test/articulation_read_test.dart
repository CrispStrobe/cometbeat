// Read the Mark — the articulation-reading drill. A staff card shows one note
// with an articulation glyph, so the shared game surface is used; we tap the
// button matching the game's own report of the correct mark.

import 'package:crisp_notation/crisp_notation.dart'
    show Articulation, NoteElement, StaffView;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_reading/articulation_read_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

ArticulationReadTester _game(WidgetTester tester) =>
    tester.state<State<ArticulationReadScreen>>(
      find.byType(ArticulationReadScreen),
    ) as ArticulationReadTester;

const _labels = {
  Articulation.staccato: 'Staccato',
  Articulation.tenuto: 'Tenuto',
  Articulation.accent: 'Accent',
  Articulation.marcato: 'Marcato',
};

Future<void> _answerCorrectly(WidgetTester tester) async {
  await tester.tap(find.text(_labels[_game(tester).answer]!));
  await tester.pump(const Duration(milliseconds: 800)); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows a staff card + Staccato/Accent and records the SRI',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const ArticulationReadScreen(), sri: sri);

    expect(find.byType(StaffView), findsOneWidget);
    // The rendered card carries the real articulation glyph (fed to the
    // crisp_notation layout), matching the game's reported answer.
    final note = tester
        .widget<StaffView>(find.byType(StaffView))
        .score
        .measures
        .first
        .elements
        .first as NoteElement;
    expect(note.articulations, contains(_game(tester).answer));

    expect(find.text('Staccato'), findsOneWidget);
    expect(find.text('Accent'), findsOneWidget);
    // Binary tier below 2★ — the harder marks aren't offered yet.
    expect(find.text('Marcato'), findsNothing);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['reading']!.keys, ['articulation']);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const ArticulationReadScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });

  testWidgets('a wrong tap records the miss and stays on the round',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const ArticulationReadScreen(), sri: sri);

    // Tap the wrong one of the two binary options.
    final answer = _game(tester).answer;
    final wrong = answer == Articulation.staccato ? 'Accent' : 'Staccato';
    await tester.tap(find.text(wrong));
    await tester.pump();
    expect(_game(tester).isFinished, isFalse);
  });

  testWidgets('at 2 stars it becomes a four-way with Tenuto and Marcato',
      (tester) async {
    final progress = ProgressService();
    await progress.load();
    progress.recordResult('articulation_read', score: 700, stars: 2);

    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(
      tester,
      const ArticulationReadScreen(),
      sri: sri,
      extraProviders: [
        ChangeNotifierProvider<ProgressService>.value(value: progress),
      ],
    );

    expect(find.text('Staccato'), findsOneWidget);
    expect(find.text('Tenuto'), findsOneWidget);
    expect(find.text('Accent'), findsOneWidget);
    expect(find.text('Marcato'), findsOneWidget);
    expect(
      const [
        Articulation.staccato,
        Articulation.tenuto,
        Articulation.accent,
        Articulation.marcato,
      ],
      contains(_game(tester).answer),
    );
  });
}
