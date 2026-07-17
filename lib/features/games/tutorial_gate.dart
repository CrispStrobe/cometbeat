// lib/features/games/tutorial_gate.dart
//
// Bridges the registry's per-game [GameInfo.tutorial] to the tutorial UI without
// touching individual game screens: [gameRoute] wraps a game in a [TutorialGate]
// that auto-shows its tutorial the first time the game is opened (afterwards
// it's silent; reopen via the "?" button). Every game-launch site pushes
// gameRoute(game) instead of MaterialPageRoute(builder: game.builder).

import 'package:comet_beat/features/games/game_registry.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/tutorial/tutorial_sheet.dart';
import 'package:flutter/material.dart';

/// Whether opening a game auto-pops its first-run tutorial. `main()` turns this
/// on for the real app; it stays **off** by default so widget tests that drive a
/// game flow aren't interrupted by a modal (they never call `main`). Tests that
/// specifically exercise the auto-show set it true themselves.
bool autoShowTutorials = false;

/// A route to [game] that auto-shows its tutorial (if any) on the first visit.
Route<void> gameRoute(GameInfo game) =>
    MaterialPageRoute<void>(builder: (_) => TutorialGate(game: game));

/// Renders [GameInfo.builder] and, on the first frame of the first-ever visit,
/// pops up the game's tutorial. A transparent passthrough otherwise.
class TutorialGate extends StatefulWidget {
  const TutorialGate({super.key, required this.game});
  final GameInfo game;

  @override
  State<TutorialGate> createState() => _TutorialGateState();
}

class _TutorialGateState extends State<TutorialGate> {
  @override
  void initState() {
    super.initState();
    final tutorial = widget.game.tutorial;
    if (autoShowTutorials && tutorial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) maybeShowTutorial(context, widget.game.id, tutorial);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.game.builder(context);
    // The "?" opens the game's own primer, or its module's general one as a
    // fallback, so every game offers help (auto-show above stays curated).
    final help = helpPrimerFor(widget.game);
    if (help == null) return child;
    // Overlay a small "?" so the child can (re)open it any time, without every
    // screen wiring up its own button. No game screen uses a
    // FloatingActionButton, so this never collides with one.
    final l10n = AppLocalizations.of(context)!;
    return Stack(
      children: [
        child,
        Positioned(
          right: 8,
          bottom: 8,
          child: SafeArea(
            child: FloatingActionButton.small(
              heroTag: null, // avoid hero collisions with the child
              tooltip: l10n.howToPlayTooltip,
              onPressed: () => showTutorial(context, help(l10n)),
              child: const Icon(Icons.help_outline_rounded),
            ),
          ),
        ),
      ],
    );
  }
}
