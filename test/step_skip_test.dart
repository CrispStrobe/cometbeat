// Step or Skip? — the melodic-motion reading drill. A staff card is shown, so
// the shared game surface is used; we tap the correct Step/Skip button per the
// game's own report of the answer.

import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/step_skip_screen.dart';
import 'package:crisp_notation/crisp_notation.dart' show Clef, StaffView;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

StepSkipTester _game(WidgetTester tester) =>
    tester.state<State<StepSkipScreen>>(find.byType(StepSkipScreen))
        as StepSkipTester;

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label = _game(tester).answerStep ? 'Step' : 'Skip';
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 800)); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers Step / Skip and records under reading.motion',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const StepSkipScreen(), sri: sri);

    expect(find.text('Step'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['reading']!.keys, ['motion']);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const StepSkipScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });

  testWidgets('the bass variant reads in the bass clef and still works',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const StepSkipScreen(clef: Clef.bass), sri: sri);

    // Same Step / Skip drill; the card renders a bass clef (F clef glyph).
    expect(find.text('Step'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.byType(StaffView), findsOneWidget);
    expect(
      tester.widget<StaffView>(find.byType(StaffView)).score.clef,
      Clef.bass,
    );

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['reading']!.keys, ['motion']);
  });

  testWidgets('at 2 stars it becomes a three-way with a Leap option',
      (tester) async {
    final progress = ProgressService();
    await progress.load();
    progress.recordResult('step_skip', score: 700, stars: 2);

    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(
      tester,
      const StepSkipScreen(),
      sri: sri,
      extraProviders: [
        ChangeNotifierProvider<ProgressService>.value(value: progress),
      ],
    );

    // The harder tier offers all three motions.
    expect(find.text('Step'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Leap'), findsOneWidget);
    expect(
      const ['step', 'skip', 'leap'],
      contains(_game(tester).answerMotion),
    );
  });

  testWidgets('below 2 stars it stays a binary Step / Skip', (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const StepSkipScreen(), sri: sri);
    expect(find.text('Leap'), findsNothing);
  });
}
