// lib/features/games/widgets/game_widgets.dart
//
// Shared building blocks for minigame screens: the round header (progress +
// prompt) and the end-of-game result view (stars, score, replay).

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/tuning.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/note_mascot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class RoundHeader extends StatelessWidget {
  final int round; // 1-based
  final int totalRounds;
  final String prompt;

  /// Whether the mascot presents the question in a speech bubble (a
  /// [MascotPrompt]). It greets with a one-shot bob on each new [prompt].
  /// Screens with a very tight vertical layout (or their own prominent mascot)
  /// pass false to fall back to the plain centered prompt.
  final bool showMascot;

  /// Last-answer state for the presenting mascot's reaction: null = presenting
  /// (idle), true = happy, false = oops. Pass the same value the screen gives
  /// [FeedbackLine], so the header mascot both presents AND reacts (the
  /// feedback line then shows text only).
  final bool? correct;

  const RoundHeader({
    super.key,
    required this.round,
    required this.totalRounds,
    required this.prompt,
    this.showMascot = true,
    this.correct,
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
        if (showMascot)
          MascotPrompt(prompt: prompt, correct: correct)
        else
          Text(
            prompt,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
      ],
    );
  }
}

/// The mascot presenting the question: a [NoteMascot] beside a speech bubble
/// reading the [prompt]. Keyed by prompt so a fresh mascot greets (one-shot
/// bob) on each new question. Compact so it fits the shared round header.
class MascotPrompt extends StatelessWidget {
  const MascotPrompt({super.key, required this.prompt, this.correct});

  final String prompt;

  /// null = presenting (idle), true = happy, false = oops.
  final bool? correct;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Keyed by prompt so a fresh mascot greets each new question; within a
    // question, changing [correct] animates the reaction via didUpdateWidget.
    final mood = correct == null
        ? NoteMascotMood.idle
        : correct!
            ? NoteMascotMood.happy
            : NoteMascotMood.oops;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NoteMascot(key: ValueKey(prompt), mood: mood, size: 26),
        const SizedBox(width: 6),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              prompt,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

class FeedbackLine extends StatelessWidget {
  /// null = not answered yet, true/false = last answer correct/wrong.
  final bool? correct;

  /// Whether to show a reacting mascot here. Defaults to **false**: the
  /// mascot now presents AND reacts in [RoundHeader] (pass it `correct:`), so
  /// the feedback line shows text only. Set true only for a screen that has no
  /// [RoundHeader] mascot but still wants a reacting one here.
  final bool showMascot;

  const FeedbackLine({
    super.key,
    required this.correct,
    this.showMascot = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mood = correct == null
        ? NoteMascotMood.idle
        : correct!
            ? NoteMascotMood.happy
            : NoteMascotMood.oops;
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showMascot) NoteMascot(mood: mood, size: 30),
          if (correct != null) ...[
            if (showMascot) const SizedBox(width: 10),
            Text(
              correct! ? l10n.feedbackCorrect : l10n.feedbackTryAgain,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: correct! ? Colors.green : Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A capped two-column grid of answer buttons: centered and no wider than
/// 480 px, with flat (aspect 3.2) cells — so the choices stay compact and never
/// take up more than the lower part of the screen, even on wide/web layouts.
///
/// Keyboard-steerable: number keys 1..N activate the matching option (the
/// child must be a [ButtonStyleButton]), so every quiz built on this grid is
/// playable without a mouse. This is why the grid is a `Focus` that grabs
/// focus on build.
class AnswerGrid extends StatelessWidget {
  final List<Widget> children;

  const AnswerGrid({super.key, required this.children});

  static int? _digit(LogicalKeyboardKey key) {
    final digits = <LogicalKeyboardKey, int>{
      LogicalKeyboardKey.digit1: 1,
      LogicalKeyboardKey.digit2: 2,
      LogicalKeyboardKey.digit3: 3,
      LogicalKeyboardKey.digit4: 4,
      LogicalKeyboardKey.digit5: 5,
      LogicalKeyboardKey.digit6: 6,
      LogicalKeyboardKey.digit7: 7,
      LogicalKeyboardKey.numpad1: 1,
      LogicalKeyboardKey.numpad2: 2,
      LogicalKeyboardKey.numpad3: 3,
      LogicalKeyboardKey.numpad4: 4,
      LogicalKeyboardKey.numpad5: 5,
      LogicalKeyboardKey.numpad6: 6,
      LogicalKeyboardKey.numpad7: 7,
    };
    return digits[key];
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final n = _digit(event.logicalKey);
    if (n == null || n > children.length) return KeyEventResult.ignored;
    final child = children[n - 1];
    if (child is ButtonStyleButton && child.onPressed != null) {
      child.onPressed!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 3.2,
            children: children,
          ),
        ),
      ),
    );
  }
}

class GameResultView extends StatelessWidget {
  /// Game type key into [kStarThresholds].
  final String gameType;
  final int score;

  /// Score used for the star rating, when it differs from the displayed
  /// [score]. Lets variable-length review sessions normalize to the same star
  /// brackets as a full game. Defaults to [score].
  final int? starScore;
  final VoidCallback? onRestart;

  const GameResultView({
    super.key,
    required this.gameType,
    required this.score,
    this.starScore,
    this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final stars = scoreToStars(gameType, starScore ?? score, true);
    // Time is shown only in normal games (onRestart != null, so not a review)
    // and only when the learner opted in.
    final progress = context.watch<ProgressService>();
    final showTime = onRestart != null &&
        context.watch<SettingsService>().showTimer &&
        progress.lastElapsedMs > 0;

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
          if (showTime) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer_outlined, size: 20),
                const SizedBox(width: 6),
                Text(
                  l10n.resultTime(_formatTime(progress.lastElapsedMs)),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            Text(
              progress.lastWasBest
                  ? l10n.resultNewBest
                  : l10n.resultBest(_formatTime(progress.lastBestMs)),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: progress.lastWasBest
                        ? Colors.amber.shade700
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: progress.lastWasBest
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
            ),
          ],
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

  /// Key into [kStarThresholds] for the star rating.
  String get gameType;

  /// ID the result is recorded under in [ProgressService]; defaults to
  /// [gameType]. Override where one screen serves several registry entries
  /// (e.g. place-the-note per clef).
  String get progressId => gameType;

  /// Retro correct/wrong blips on every answer. Games that play their own
  /// pitch/chord feedback (place-the-note, chord quiz) override to false.
  bool get playFeedbackSounds => true;

  /// Review sessions don't count toward stars; screens with a review mode
  /// override this accordingly.
  bool get isReviewSession => false;

  /// Set up the next round's data. Called once initially and after each
  /// advance; also on restart.
  void prepareRound();

  /// Times the whole session (first answer → finish), for the personal best.
  final Stopwatch _timer = Stopwatch();

  /// Handle a resolved answer. Returns true if the round advances.
  /// Call from the tap handler AFTER recording SRI.
  bool resolveAnswer({required bool correct}) {
    _timer.start(); // no-op once already running
    final audio = context.read<AudioService>();
    if (correct && round + 1 >= totalRounds) {
      audio.playFanfare();
      _timer.stop();
      if (!isReviewSession) {
        final finalScore = score + (answeredWrong ? 0 : pointsPerRound);
        context.read<ProgressService>().recordResult(
              progressId,
              score: finalScore,
              stars: scoreToStars(gameType, finalScore, true),
              elapsedMs: _timer.elapsedMilliseconds,
            );
      }
    } else if (playFeedbackSounds) {
      correct ? audio.playCorrect() : audio.playWrong();
    }
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
    _timer
      ..stop()
      ..reset();
    setState(() {
      round = 0;
      score = 0;
      answeredWrong = false;
      finished = false;
      prepareRound();
    });
  }
}

/// Milliseconds as `m:ss`.
String _formatTime(int ms) {
  final total = (ms / 1000).round();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}
