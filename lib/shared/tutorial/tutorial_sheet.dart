// lib/shared/tutorial/tutorial_sheet.dart
//
// Renders a [Tutorial] as a friendly modal bottom sheet: one page per step, with
// the explanation, an optional engraved example (StaffView), and an optional
// "Listen" button that plays the sound being taught. Also provides the entry
// points: [showTutorial] (open on demand, e.g. the "?" button) and
// [maybeShowTutorial] (open once on a game's first visit, then remember).

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:comet_beat/shared/tutorial/tutorial.dart';
import 'package:crisp_notation/crisp_notation.dart' show StaffView;
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

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
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
              Text(
                widget.tutorial.title,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: PageView.builder(
                  controller: _pages,
                  onPageChanged: (i) => setState(() => _index = i),
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

class _StepView extends StatelessWidget {
  const _StepView({required this.step});
  final TutorialStep step;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
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
                child: StaffView(
                  score: step.score!,
                  staffSpace: 12,
                  theme: kidsScoreTheme,
                ),
              ),
            ),
          ],
          if (step.play != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => step.play!(context.read<AudioService>()),
              icon: const Icon(Icons.volume_up_rounded),
              label: Text(step.playLabel ?? l10n.tutorialListen),
            ),
          ],
        ],
      ),
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
