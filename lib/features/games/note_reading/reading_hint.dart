// lib/features/games/note_reading/reading_hint.dart
//
// Landmark / intervallic reading hints. Instead of naming a note from scratch,
// a beginner anchors on a memorized *landmark* (a staff line, or middle C) and
// counts the interval to the target: "a skip up from E". This is the reading
// strategy real methods teach; here it is a scaffold that fades as the child
// earns stars (see note_reading_quiz_screen.dart).
//
// The computation is pure and clef-agnostic (driven by partitura's diatonic
// staff arithmetic) so it is unit-testable without a widget tree.

import 'package:flutter/widgets.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart';

/// The nearest landmark to a target note and the signed diatonic distance to
/// it (`steps` > 0 means the target is *above* the landmark).
class ReadingHint {
  final Step landmarkStep;
  final int steps;

  const ReadingHint(this.landmarkStep, this.steps);
}

/// Middle C — the universal ledger-line landmark, valid in every clef.
const _middleC = Pitch(Step.c);

/// Picks the landmark nearest [target] on the given [clef].
///
/// Landmarks are the three memorized staff lines (bottom, middle, top) plus
/// middle C. Ties favour middle C, then the lines bottom→top — the order that
/// puts the most iconic anchors first.
ReadingHint computeReadingHint(Clef clef, Pitch target) {
  final landmarks = <Pitch>[
    _middleC,
    clef.pitchAt(0), // bottom line
    clef.pitchAt(4), // middle line
    clef.pitchAt(8), // top line
  ];

  var best = landmarks.first;
  var bestSteps = target.diatonicIndex - best.diatonicIndex;
  for (final lm in landmarks.skip(1)) {
    final d = target.diatonicIndex - lm.diatonicIndex;
    if (d.abs() < bestSteps.abs()) {
      best = lm;
      bestSteps = d;
    }
  }
  return ReadingHint(best.step, bestSteps);
}

/// The hint spelled in the learner's chosen note-naming convention.
String readingHintText(BuildContext context, Clef clef, Pitch target) {
  final l10n = AppLocalizations.of(context)!;
  final hint = computeReadingHint(clef, target);
  final name = noteNameFor(context, hint.landmarkStep);
  final n = hint.steps.abs();
  final up = hint.steps > 0;
  return switch (n) {
    0 => l10n.readingHintSame(name),
    1 => up ? l10n.readingHintStepUp(name) : l10n.readingHintStepDown(name),
    2 => up ? l10n.readingHintSkipUp(name) : l10n.readingHintSkipDown(name),
    _ => up ? l10n.readingHintFarUp(n, name) : l10n.readingHintFarDown(n, name),
  };
}
