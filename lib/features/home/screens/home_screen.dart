// lib/features/home/screens/home_screen.dart
//
// Module overview: one card per learning module from the registry.
// Tapping an unlocked module will navigate to its game selection screen
// (features/games, not yet implemented — shows a "coming soon" snackbar).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/learning_module.dart';
import '../../../core/services/sri_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../games/note_values/note_value_quiz_screen.dart';
import '../../games/screens/module_screen.dart';
import '../../progress/screens/progress_screen.dart';
import '../../settings/screens/settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// Starts a review session over due items. Currently only the note_values
  /// symbol items have a runner; other modules join as their games land.
  void _startReview(BuildContext context) {
    final sri = context.read<SriService>();
    final ids = sri
        .getItemsForReview(
          limit: 10,
          moduleId: 'note_values',
          resetSessionFirst: true,
        )
        .where((id) => id.startsWith('note_values.symbol.'))
        .toList();

    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.comingSoon),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteValueQuizScreen(reviewItemIds: ids),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sri = context.watch<SriService>();
    final dueCount = sri.getAvailableReviewCount();

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
                  return _ModuleCard(module: module, l10n: l10n);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final LearningModule module;
  final AppLocalizations l10n;

  const _ModuleCard({required this.module, required this.l10n});

  @override
  Widget build(BuildContext context) {
    // TODO: unlock progression — later modules open once earlier ones reach
    // mastery (SriService.getDetailedBreakdown). For now only the initial
    // modules are active.
    final unlocked = module.initiallyUnlocked;

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
                content: Text(l10n.locked),
                duration: const Duration(seconds: 1),
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
