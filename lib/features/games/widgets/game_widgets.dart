// lib/features/games/widgets/game_widgets.dart
//
// Shared building blocks for minigame screens: the round header (progress +
// prompt) and the end-of-game result view (stars, score, replay).

import 'package:flutter/material.dart';

import '../../../core/tuning.dart';
import '../../../l10n/app_localizations.dart';

class RoundHeader extends StatelessWidget {
  final int round; // 1-based
  final int totalRounds;
  final String prompt;

  const RoundHeader({
    super.key,
    required this.round,
    required this.totalRounds,
    required this.prompt,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Text(
          l10n.roundOf(round, totalRounds),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          prompt,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class FeedbackLine extends StatelessWidget {
  /// null = not answered yet, true/false = last answer correct/wrong.
  final bool? correct;

  const FeedbackLine({super.key, required this.correct});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 28,
      child: Text(
        correct == null
            ? ''
            : correct!
                ? l10n.feedbackCorrect
                : l10n.feedbackTryAgain,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: (correct ?? false) ? Colors.green : Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class GameResultView extends StatelessWidget {
  /// Game type key into [kStarThresholds].
  final String gameType;
  final int score;
  final VoidCallback? onRestart;

  const GameResultView({
    super.key,
    required this.gameType,
    required this.score,
    this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final stars = scoreToStars(gameType, score, true);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Icon(
                  i < stars ? Icons.star : Icons.star_border,
                  size: 56,
                  color: Colors.amber,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            l10n.resultScore(score),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          if (onRestart != null)
            FilledButton.icon(
              onPressed: onRestart,
              icon: const Icon(Icons.replay),
              label: Text(l10n.playAgain),
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.backButton),
          ),
        ],
      ),
    );
  }
}

/// Shared round bookkeeping for the common quiz shape: N rounds, points on
/// first-try success, retry allowed, auto-advance after a short delay.
mixin QuizRoundMixin<T extends StatefulWidget> on State<T> {
  int round = 0;
  int score = 0;
  bool answeredWrong = false;
  bool finished = false;

  int get totalRounds;
  int get pointsPerRound => 100;

  /// Set up the next round's data. Called once initially and after each
  /// advance; also on restart.
  void prepareRound();

  /// Handle a resolved answer. Returns true if the round advances.
  /// Call from the tap handler AFTER recording SRI.
  bool resolveAnswer({required bool correct}) {
    setState(() {
      if (correct) {
        if (!answeredWrong) score += pointsPerRound;
        if (round + 1 >= totalRounds) finished = true;
      } else {
        answeredWrong = true;
      }
    });

    if (correct && !finished) {
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        setState(() {
          round++;
          answeredWrong = false;
          prepareRound();
        });
      });
    }
    return correct;
  }

  void restartGame() {
    setState(() {
      round = 0;
      score = 0;
      answeredWrong = false;
      finished = false;
      prepareRound();
    });
  }
}
