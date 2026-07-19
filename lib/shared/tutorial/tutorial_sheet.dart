// lib/shared/tutorial/tutorial_sheet.dart
//
// Renders a [Tutorial] as a friendly modal bottom sheet: one page per step, with
// the explanation, an optional engraved example (StaffView), and an optional
// "Listen" button that plays the sound being taught. Also provides the entry
// points: [showTutorial] (open on demand, e.g. the "?" button) and
// [maybeShowTutorial] (open once on a game's first visit, then remember).

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/tts_service.dart';
import 'package:comet_beat/features/games/widgets/playing_staff.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:comet_beat/shared/tutorial/tutorial.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _seenPrefix = 'tutorial_seen_';

/// Open [tutorial] as a modal sheet. Returns when the child dismisses it.
Future<void> showTutorial(BuildContext context, Tutorial tutorial) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TutorialSheet(tutorial: tutorial),
  );
}

/// Show [build]'s tutorial the first time a game (keyed by [gameId]) is opened,
/// then never automatically again. Safe to call from a screen's initState (it
/// waits for the first frame). No-op if already seen.
Future<void> maybeShowTutorial(
  BuildContext context,
  String gameId,
  Tutorial Function(AppLocalizations) build,
) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('$_seenPrefix$gameId') ?? false) return;
  await prefs.setBool('$_seenPrefix$gameId', true);
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context);
  if (l10n == null) return;
  await showTutorial(context, build(l10n));
}

/// Testing/reset hook: forget that [gameId]'s tutorial was seen.
Future<void> resetTutorialSeen(String gameId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('$_seenPrefix$gameId');
}

class _TutorialSheet extends StatefulWidget {
  const _TutorialSheet({required this.tutorial});
  final Tutorial tutorial;

  @override
  State<_TutorialSheet> createState() => _TutorialSheetState();
}

class _TutorialSheetState extends State<_TutorialSheet> {
  final PageController _pages = PageController();
  int _index = 0;
  TtsService? _tts;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Narration is optional: only wired when a TtsService is in the tree (it is
    // in the running app; widget tests that don't provide one just omit the
    // read-aloud button and keep working).
    try {
      _tts = context.read<TtsService>();
    } on ProviderNotFoundException {
      _tts = null;
    }
  }

  @override
  void dispose() {
    _tts?.stop();
    _pages.dispose();
    super.dispose();
  }

  void _readAloud() {
    _tts?.speak(
      widget.tutorial.steps[_index].text,
      locale: Localizations.localeOf(context),
    );
  }

  bool get _isLast => _index == widget.tutorial.steps.length - 1;

  void _next() {
    if (_isLast) {
      Navigator.of(context).pop();
    } else {
      _pages.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final steps = widget.tutorial.steps;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Balances the read-aloud button so the title stays centred.
                  if (_tts != null) const SizedBox(width: 48),
                  Expanded(
                    child: Text(
                      widget.tutorial.title,
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (_tts != null)
                    IconButton(
                      icon: const Icon(Icons.record_voice_over_rounded),
                      tooltip: l10n.tutorialReadAloud,
                      onPressed: _readAloud,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: PageView.builder(
                  controller: _pages,
                  onPageChanged: (i) {
                    _tts?.stop(); // don't talk over the next step
                    setState(() => _index = i);
                  },
                  itemCount: steps.length,
                  itemBuilder: (context, i) => _StepView(step: steps[i]),
                ),
              ),
              const SizedBox(height: 12),
              _Dots(count: steps.length, index: _index),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(_isLast ? l10n.tutorialGotIt : l10n.tutorialNext),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepView extends StatefulWidget {
  const _StepView({required this.step});
  final TutorialStep step;

  @override
  State<_StepView> createState() => _StepViewState();
}

class _StepViewState extends State<_StepView> {
  final _pb = ScorePlayback();

  /// Index of the last-tapped "try it" choice (null until the child tries).
  int? _picked;

  /// How many wrong taps so far — after a couple, the sheet gently reveals the
  /// right answer so a stuck child isn't left guessing forever.
  int _wrongTries = 0;

  /// Reveal the answer once the child has missed this many times.
  static const _revealAfter = 2;

  @override
  void dispose() {
    _pb.dispose();
    super.dispose();
  }

  /// Fire the step's audio and, when it carries [TutorialStep.beats], light the
  /// score's notes in time with it.
  void _listen() {
    final step = widget.step;
    final audio = context.read<AudioService>();
    final beats = step.beats;
    if (beats != null) {
      audio.playSequence(beats);
      _pb.play(
        stepsForSequence(beats, [for (var i = 0; i < beats.length; i++) 'n$i']),
      );
    } else {
      step.play?.call(audio);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final step = widget.step;
    return SingleChildScrollView(
      child: Column(
        children: [
          Text(
            step.text,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (step.score != null) ...[
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: PlayingStaffView(
                  score: step.score!,
                  controller: _pb,
                  staffSpace: 12,
                  theme: kidsScoreTheme,
                ),
              ),
            ),
          ],
          if (step.hasAudio) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _listen,
              icon: const Icon(Icons.volume_up_rounded),
              label: Text(step.playLabel ?? l10n.tutorialListen),
            ),
          ],
          if (step.hasChoices) _tryIt(context, step.choices!, l10n, theme),
        ],
      ),
    );
  }

  /// The "try it" practice: tappable options with gentle ✓/✗ feedback. No score
  /// and no gate — a correct tap celebrates, a wrong one invites another try.
  Widget _tryIt(
    BuildContext context,
    List<TutorialChoice> choices,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    final picked = _picked;
    final reveal = _wrongTries >= _revealAfter;
    final gotIt = picked != null && choices[picked].correct;
    return Column(
      children: [
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < choices.length; i++)
              _ChoiceChip(
                label: choices[i].label,
                selected: picked == i,
                correct: choices[i].correct,
                // Once the child is stuck, glow the right answer(s) as a hint —
                // but not after they've already found it.
                hint: reveal && !gotIt && choices[i].correct,
                onTap: () => setState(() {
                  if (!choices[i].correct) _wrongTries++;
                  _picked = i;
                }),
              ),
          ],
        ),
        if (picked != null) ...[
          const SizedBox(height: 10),
          Text(
            gotIt
                ? l10n.tutorialTryCorrect
                : reveal
                    ? l10n.tutorialTryHint
                    : l10n.tutorialTryAgain,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: gotIt
                  ? Colors.green.shade700
                  : reveal
                      ? Colors.green.shade700
                      : theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// One "try it" option. Turns green with a ✓ when it's the right pick, red with
/// a ✗ when it's a wrong pick; otherwise a plain tappable chip.
class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.correct,
    required this.onTap,
    this.hint = false,
  });

  final String label;
  final bool selected;
  final bool correct;
  final VoidCallback onTap;

  /// Gently glow this (correct) option to reveal the answer to a stuck child.
  final bool hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final right = selected && correct;
    final wrong = selected && !correct;
    final Color? bg = right
        ? Colors.green.shade600
        : wrong
            ? theme.colorScheme.errorContainer
            : null;
    final Color fg = right
        ? Colors.white
        : wrong
            ? theme.colorScheme.onErrorContainer
            : theme.colorScheme.onSurface;
    return FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        // The reveal hint: a green ring around the right answer.
        side:
            hint ? BorderSide(color: Colors.green.shade600, width: 2.5) : null,
      ),
      onPressed: onTap,
      icon: Icon(
        right
            ? Icons.check_circle_rounded
            : wrong
                ? Icons.cancel_rounded
                : hint
                    ? Icons.arrow_forward_rounded
                    : Icons.touch_app_rounded,
        size: 18,
      ),
      label: Text(label),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.primary;
    final off = on.withValues(alpha: 0.25);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: i == index ? on : off,
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}
