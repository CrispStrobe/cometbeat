// lib/features/home/screens/home_screen.dart
//
// Module overview: one card per learning module from the registry.
// Tapping an unlocked module will navigate to its game selection screen
// (features/games, not yet implemented — shows a "coming soon" snackbar).

import 'package:flutter/material.dart';
import 'package:klang_universum/core/models/learning_module.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/core/tuning.dart';
import 'package:klang_universum/features/games/chords/chord_quiz_screen.dart';
import 'package:klang_universum/features/games/harmony/function_ear_screen.dart';
import 'package:klang_universum/features/games/harmony/harmony_quiz_screen.dart';
import 'package:klang_universum/features/games/note_reading/note_reading_quiz_screen.dart';
import 'package:klang_universum/features/games/note_values/note_value_quiz_screen.dart';
import 'package:klang_universum/features/games/scales/scale_detective_screen.dart';
import 'package:klang_universum/features/games/screens/module_screen.dart';
import 'package:klang_universum/features/progress/screens/progress_screen.dart';
import 'package:klang_universum/features/settings/screens/settings_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart' show Clef;
import 'package:provider/provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// Starts a review session over due items. Runners exist for the
  /// note_values symbol items and the note_reading items (per clef);
  /// per session, the biggest due bucket wins. Other skills join as
  /// their review runners land.
  void _startReview(BuildContext context) {
    final sri = context.read<SriService>();

    // Collect due items of the reviewable modules (one fetch per module;
    // resetSessionFirst so the buckets are complete).
    final symbolIds = sri
        .getItemsForReview(
          limit: 10,
          moduleId: 'note_values',
          resetSessionFirst: true,
        )
        .where((id) => id.startsWith('note_values.symbol.'))
        .toList();
    final readingIds = sri.getItemsForReview(
      limit: 20,
      moduleId: 'note_reading',
      resetSessionFirst: true,
    );
    final treble = readingIds
        .where((id) => id.startsWith('note_reading.treble.'))
        .toList();
    final bass =
        readingIds.where((id) => id.startsWith('note_reading.bass.')).toList();
    final tenor =
        readingIds.where((id) => id.startsWith('note_reading.tenor.')).toList();
    List<String> dueOf(String moduleId, String prefix) => sri
        .getItemsForReview(
          limit: 10,
          moduleId: moduleId,
          resetSessionFirst: true,
        )
        .where((id) => id.startsWith(prefix))
        .toList();
    final scaleSpots = dueOf('scales', 'scales.spot.');
    final triads = dueOf('chords', 'chords.triad.');
    final functions = dueOf('harmony', 'harmony.function.');
    final hearFunctions = dueOf('harmony', 'harmony.hear.');

    // Pick the biggest due bucket.
    final buckets = <(int, Widget Function())>[
      (symbolIds.length, () => NoteValueQuizScreen(reviewItemIds: symbolIds)),
      (
        treble.length,
        () => NoteReadingQuizScreen(
              clef: Clef.treble,
              reviewItemIds: treble.take(10).toList(),
            )
      ),
      (
        bass.length,
        () => NoteReadingQuizScreen(
              clef: Clef.bass,
              reviewItemIds: bass.take(10).toList(),
            )
      ),
      (
        tenor.length,
        () => NoteReadingQuizScreen(
              clef: Clef.tenor,
              reviewItemIds: tenor.take(10).toList(),
            )
      ),
      (
        scaleSpots.length,
        () => ScaleDetectiveScreen(reviewItemIds: scaleSpots)
      ),
      (triads.length, () => ChordQuizScreen(reviewItemIds: triads)),
      (functions.length, () => HarmonyQuizScreen(reviewItemIds: functions)),
      (
        hearFunctions.length,
        () => FunctionEarScreen(reviewItemIds: hearFunctions)
      ),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    final runner = buckets.first.$1 > 0 ? buckets.first.$2() : null;

    if (runner == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.comingSoon),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    Navigator.of(context).push(MaterialPageRoute(builder: (_) => runner));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sri = context.watch<SriService>();
    final progress = context.watch<ProgressService>();
    final dueCount = sri.getAvailableReviewCount();

    // Soft engagement gate: a module unlocks once the previous one has
    // kModuleUnlockTracked SRI items (docs/PLAN.md).
    final breakdown = sri.getDetailedBreakdown();
    int trackedIn(String moduleId) => (breakdown[moduleId] ?? const {})
        .values
        .fold(0, (sum, s) => sum + s.tracked);
    final unlockedById = <String, bool>{};
    for (var i = 0; i < kLearningModules.length; i++) {
      final module = kLearningModules[i];
      unlockedById[module.id] = module.initiallyUnlocked ||
          (i > 0 &&
              trackedIn(kLearningModules[i - 1].id) >= kModuleUnlockTracked);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: l10n.progressTitle,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProgressScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l10n.settingsTitle,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                l10n.homeTagline,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            if (progress.currentStreak > 0)
              _StreakBar(progress: progress, l10n: l10n),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: dueCount > 0
                  ? Center(
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.replay),
                        label: Text(l10n.dueForReview(dueCount)),
                        onPressed: () => _startReview(context),
                      ),
                    )
                  : Text(
                      l10n.dueForReview(dueCount),
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.15,
                ),
                itemCount: kLearningModules.length,
                itemBuilder: (context, index) {
                  final module = kLearningModules[index];
                  return _ModuleCard(
                    module: module,
                    l10n: l10n,
                    unlocked: unlockedById[module.id] ?? true,
                    previousModule:
                        index > 0 ? kLearningModules[index - 1] : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StreakBar extends StatelessWidget {
  final ProgressService progress;
  final AppLocalizations l10n;

  const _StreakBar({required this.progress, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final today = progress.today;
    final days = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.local_fire_department,
                color: Colors.deepOrange,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.streakDays(progress.currentStreak),
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final d in days)
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: progress.practicedOn(d)
                        ? Colors.deepOrange
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final LearningModule module;
  final AppLocalizations l10n;
  final bool unlocked;
  final LearningModule? previousModule;

  const _ModuleCard({
    required this.module,
    required this.l10n,
    required this.unlocked,
    required this.previousModule,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (unlocked) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ModuleScreen(module: module),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  previousModule != null
                      ? l10n.unlockHint(previousModule!.title(l10n))
                      : l10n.locked,
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: module.color.withValues(
                  alpha: unlocked ? 1.0 : 0.3,
                ),
                child: Icon(
                  unlocked ? module.icon : Icons.lock,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const Spacer(),
              Text(
                module.title(l10n),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: unlocked ? null : Colors.grey,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                module.subtitle(l10n),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: unlocked ? null : Colors.grey,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
