// The interactive "try it" tutorial step: an optional set of tap choices with
// gentle ✓/✗ feedback (active recall before the graded game).

import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/tutorial/primers.dart';
import 'package:comet_beat/shared/tutorial/tutorial.dart';
import 'package:comet_beat/shared/tutorial/tutorial_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('foundational primers include a hands-on "try it" step', () async {
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    final primers = <Tutorial>[
      noteValuesPrimer(l),
      measuresPrimer(l),
      accidentalsPrimer(l),
      timeSignaturePrimer(l),
      strongBeatPrimer(l),
      readingPrimer(l),
      scalesPrimer(l),
      intervalsPrimer(l),
    ];
    for (final primer in primers) {
      expect(
        primer.steps.any((s) => s.hasChoices),
        isTrue,
        reason: '${primer.title} should end with a try-it step',
      );
    }
  });

  test('a choices step reports hasChoices and needs at least two options', () {
    final step = TutorialStep(
      text: 'How many beats?',
      choices: const [TutorialChoice('4', correct: true), TutorialChoice('1')],
    );
    expect(step.hasChoices, isTrue);
    expect(const TutorialStep(text: 'plain').hasChoices, isFalse);
    // A single-option "try it" is an authoring error.
    expect(
      () => TutorialStep(text: 'q', choices: const [TutorialChoice('only')]),
      throwsA(isA<AssertionError>()),
    );
  });

  testWidgets('tapping a choice shows correct / try-again feedback', (
    tester,
  ) async {
    final tutorial = Tutorial(
      title: 'Note values',
      steps: [
        TutorialStep(
          text: 'How many beats does a whole note last?',
          choices: const [
            TutorialChoice('4', correct: true),
            TutorialChoice('2'),
            TutorialChoice('1'),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showTutorial(ctx, tutorial),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // All three options render, no feedback yet.
    expect(find.text('4'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text("That's right! 🎉"), findsNothing);

    // A wrong pick invites another try (no gate).
    await tester.tap(find.text('1'));
    await tester.pump();
    expect(find.text('Not quite — try again!'), findsOneWidget);

    // The right pick celebrates.
    await tester.tap(find.text('4'));
    await tester.pump();
    expect(find.text("That's right! 🎉"), findsOneWidget);
    expect(find.text('Not quite — try again!'), findsNothing);
  });
}
