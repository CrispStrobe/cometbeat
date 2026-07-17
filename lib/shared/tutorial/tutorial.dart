// lib/shared/tutorial/tutorial.dart
//
// The data model for a minigame's "how to play + what you need to know"
// tutorial. A [Tutorial] is a short deck of [TutorialStep]s; each step is a bit
// of plain-language explanation, optionally paired with a **notated example** (a
// crisp_notation Score rendered on a StaffView) and/or a **playable audio example**
// (a callback onto AudioService). Together they let a child with zero music
// knowledge see it, hear it, then play the game.
//
// Tutorials are built per game, localized, from a factory —
// `Tutorial Function(AppLocalizations)` — so the text follows the app language.
// See tutorial_sheet.dart for how it's shown and tutorial_button.dart for the
// "?" entry point + first-run gating. Rendering-only: no BuildContext here, so
// tutorials stay easy to unit-test.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:crisp_notation/crisp_notation.dart' show Score;
import 'package:flutter/foundation.dart';

/// One page of a tutorial.
@immutable
class TutorialStep {
  const TutorialStep({
    required this.text,
    this.score,
    this.play,
    this.playLabel,
  });

  /// The explanation shown on this step (already localized).
  final String text;

  /// Optional engraved example, drawn on a StaffView.
  final Score? score;

  /// Optional "listen" example — given the app's [AudioService], play the sound
  /// this step is teaching (a note, a chord, a little melody). When null, no
  /// listen button is shown.
  final void Function(AudioService audio)? play;

  /// Label for the listen button (already localized); defaults handled by the
  /// sheet when null.
  final String? playLabel;

  bool get hasAudio => play != null;
}

/// A game's tutorial: a titled deck of steps.
@immutable
class Tutorial {
  const Tutorial({required this.title, required this.steps})
      : assert(steps.length > 0, 'a tutorial needs at least one step');

  /// Heading shown at the top of the sheet (already localized).
  final String title;

  final List<TutorialStep> steps;
}
