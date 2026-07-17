// lib/shared/tutorial/tutorial_button.dart
//
// The "?" app-bar action that (re)opens a game's tutorial on demand. Pair it
// with maybeShowTutorial() in the screen's initState for the first-run auto-show.
// Drop into any AppBar `actions:` (or the shared GameAppBar).

import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/tutorial/tutorial.dart';
import 'package:comet_beat/shared/tutorial/tutorial_sheet.dart';
import 'package:flutter/material.dart';

class TutorialButton extends StatelessWidget {
  const TutorialButton({super.key, required this.builder});

  /// Builds the (localized) tutorial to show when tapped.
  final Tutorial Function(AppLocalizations) builder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      icon: const Icon(Icons.help_outline_rounded),
      tooltip: l10n.howToPlayTooltip,
      onPressed: () => showTutorial(context, builder(l10n)),
    );
  }
}
