// Covers the tutorial framework: the sheet renders a primer's steps (text +
// engraved example + a Listen button on audio steps), pages through to the end,
// and maybeShowTutorial auto-shows only on the first visit.

import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/tutorial/primers.dart';
import 'package:comet_beat/shared/tutorial/tutorial.dart';
import 'package:comet_beat/shared/tutorial/tutorial_sheet.dart';
import 'package:crisp_notation/crisp_notation.dart' show StaffView;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

void main() {
  testWidgets('the reading primer sheet shows text, notation and a Listen step',
      (tester) async {
    await pumpGame(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showTutorial(
                context,
                readingPrimer(AppLocalizations.of(context)!),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Step 1: title + staff explanation + an engraved example, no Listen yet.
    expect(find.text('Reading notes'), findsOneWidget);
    expect(find.textContaining('five lines'), findsOneWidget);
    expect(find.byType(StaffView), findsOneWidget);
    expect(find.text('Listen'), findsNothing);

    // Advance to step 2 — the "higher sounds higher" step has a Listen button.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Listen'), findsOneWidget);
    await tester
        .tap(find.text('Listen')); // plays via AudioService (no-op here)
    await tester.pump();

    // Page to the last step; the button becomes "Got it!" and dismisses.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Got it!'), findsOneWidget);
    await tester.tap(find.text('Got it!'));
    await tester.pumpAndSettle();
    expect(find.byType(StaffView), findsNothing); // sheet closed
  });

  testWidgets('maybeShowTutorial auto-shows once, then not again',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpGame(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                maybeShowTutorial(context, 'demo_game', readingPrimer),
            child: const Text('maybe'),
          ),
        ),
      ),
    );

    // First visit → the sheet appears.
    await tester.tap(find.text('maybe'));
    await tester.pumpAndSettle();
    expect(find.text('Reading notes'), findsOneWidget);
    // Page to the last step, then dismiss.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Got it!'));
    await tester.pumpAndSettle();

    // Second visit → nothing (already seen).
    await tester.tap(find.text('maybe'));
    await tester.pumpAndSettle();
    expect(find.text('Reading notes'), findsNothing);
  });

  testWidgets('every module primer builds and renders (incl. a stacked chord)',
      (tester) async {
    final primers = <String, Tutorial Function(AppLocalizations)>{
      'Reading notes': readingPrimer,
      'How long is a note?': noteValuesPrimer,
      'Filling a measure': measuresPrimer,
      'What is a scale?': scalesPrimer,
      'Building a chord': chordsPrimer, // the multi-pitch NoteElement path
      'Chords have jobs': harmonyPrimer,
      'Make a melody': compositionPrimer,
      'Your four strings': celloPrimer, // bass-clef Score path
      'Six strings and tab': guitarPrimer,
      'Follow the tune': songsPrimer,
      'The piano keys': keyboardPrimer,
      'Read one note, hear another': transposePrimer,
      'Reading drums': drumsPrimer, // bass-clef Score path
      // Per-game ★ primers (distinct facts within covered modules).
      'The bass clef': readingBassPrimer,
      'Ledger lines': ledgerPrimer,
      'Sharps and flats': accidentalsPrimer,
      'Steps and skips': stepSkipPrimer,
      'How far apart?': intervalsPrimer,
      'Key signatures': keySignaturePrimer, // key-signature Score path
      'Time signatures': timeSignaturePrimer, // time-signature Score path
      'Chord symbols': chordChartPrimer, // chord-symbol Score path
      'Starting on the upbeat': upbeatPrimer,
      'The same note, two names': enharmonicPrimer,
      'How fast? Tempo words': tempoTermsPrimer,
      'How loud? p and f': dynamicsPrimer,
      'The dot that adds half': dottedNotePrimer, // dotted-duration Score path
      'Silence has length': restsPrimer, // RestElement Score path
      'Ties and slurs': tieSlurPrimer, // tie + Slur Score path
      'How to play the note': articulationPrimer, // articulations Score path
      'Flags and beams': beamPrimer,
      'Half steps and whole steps': wholeHalfPrimer,
      'Which clef?': clefsPrimer, // bass-clef Score path
      'Four voices at once': voicesPrimer,
      'Up or down?': directionPrimer,
      'Same or different?': sameDiffPrimer,
      'How many notes?': countNotesPrimer,
      'Strong and weak beats': strongBeatPrimer, // time-signature Score path
      'Adding a seventh': seventhPrimer,
      'Numbering the chords': romanPrimer,
      'How a phrase ends': cadencePrimer,
      'Question and answer': phrasePrimer,
      'Which way the bow goes': bowingPrimer, // bow-articulation Score path
      'The tenor clef': tenorClefPrimer, // tenor-clef Score path
      'Two staves, two hands': grandStaffPrimer,
      'Fast or slow, loud or soft': expressionPrimer,
      'On the beat, or off?': syncopationPrimer,
      'Two or three in a beat': tripletPrimer, // tuplet Score path
      'Decorating a note': ornamentPrimer, // ornament Score path
      'The shape of a piece': formPrimer,
      'Same key, or a new one?': modulationPrimer,
    };
    for (final entry in primers.entries) {
      await pumpGame(
        tester,
        Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showTutorial(context, entry.value(AppLocalizations.of(context)!));
            });
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      );
      await tester.pumpAndSettle();
      // The title showing proves the primer built (ARB keys resolve) and its
      // first step rendered without throwing — for chordsPrimer that first step
      // IS the stacked-triad StaffView, so this covers the multi-pitch path.
      expect(
        find.text(entry.key),
        findsOneWidget,
        reason: '${entry.key} primer should show its title',
      );
      // Dismiss the modal (tap the scrim above the sheet) before the next one.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    }
  });
}
