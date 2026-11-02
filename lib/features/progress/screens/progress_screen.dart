// lib/features/progress/screens/progress_screen.dart
//
// Learning progress: the Karteikasten (Leitner boxes projected from the
// SM-2 state, as in space_math_academy) and per-module mastery bars.

import 'package:comet_beat/core/models/learning_module.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/progress/sri_item_label.dart';
import 'package:comet_beat/features/recital/recital_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The learning-progress hub: cumulative stats (Karteikasten + mastery) and the
/// Recital showcase, united under one screen with two tabs.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.progressTitle),
          bottom: TabBar(
            tabs: [
              Tab(icon: const Icon(Icons.bar_chart), text: l10n.progressTitle),
              Tab(
                icon: const Icon(Icons.theater_comedy),
                text: l10n.recitalTitle,
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_ProgressTab(), _RecitalsTab()],
        ),
      ),
    );
  }
}

/// The Recital showcase entry point (its own tab in the Progress hub). A recital
/// is a focused performance session, so this launches [RecitalScreen] rather
/// than embedding it.
class _RecitalsTab extends StatelessWidget {
  const _RecitalsTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎭', style: TextStyle(fontSize: 72)),
            const SizedBox(height: 16),
            Text(
              l10n.recitalIntro,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.recitalStart),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      RecitalScreen(program: buildRecitalProgram(context)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cumulative learning stats: the Karteikasten (Leitner boxes) and per-module
/// mastery bars.
class _ProgressTab extends StatelessWidget {
  const _ProgressTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sri = context.watch<SriService>();
    final boxCounts = sri.getBoxCounts();
    final breakdown = sri.getDetailedBreakdown();
    final tricky = sri.weakestItems();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.karteikastenTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Row(
              children: [
                for (var box = 1; box <= 5; box++)
                  Expanded(
                    child: _BoxColumn(
                      count: boxCounts[box] ?? 0,
                      label: switch (box) {
                        1 => l10n.boxNew,
                        5 => l10n.boxMastered,
                        _ => 'Box $box',
                      },
                      emphasized: box == 5,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (tricky.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            l10n.trickyNotesTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.trickyNotesHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final item in tricky)
                  _TrickyTile(
                    module: _moduleForSriId(item.itemId),
                    label: describeSriItem(l10n, item.itemId),
                    missed: l10n.trickyMissed(item.failureCount),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          l10n.moduleProgressTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final module in kLearningModules)
          _ModuleProgressCard(
            module: module,
            skills: moduleSkills(breakdown, module.id),
            l10n: l10n,
          ),
      ],
    );
  }
}

/// All skill stats that belong to [moduleId], merging SRI namespaces that
/// alias onto it (see [kSriNamespaceModule]).
@visibleForTesting
Map<String, SkillStat> moduleSkills(
  Map<String, Map<String, SkillStat>> breakdown,
  String moduleId,
) {
  final out = <String, SkillStat>{};
  breakdown.forEach((ns, skills) {
    if (moduleIdForSriNamespace(ns) != moduleId) return;
    skills.forEach((skill, stat) {
      final key = ns == moduleId ? skill : '$ns.$skill';
      out[key] = stat;
    });
  });
  return out;
}

class _BoxColumn extends StatelessWidget {
  final int count;
  final String label;
  final bool emphasized;

  const _BoxColumn({
    required this.count,
    required this.label,
    required this.emphasized,
  });

  @override
  Widget build(BuildContext context) {
    final color = emphasized
        ? Colors.amber.shade700
        : Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Text(
          '$count',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(color: color, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ModuleProgressCard extends StatelessWidget {
  final LearningModule module;
  final Map<String, SkillStat> skills;
  final AppLocalizations l10n;

  const _ModuleProgressCard({
    required this.module,
    required this.skills,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final tracked = skills.values.fold<int>(0, (sum, s) => sum + s.tracked);
    final mastered = skills.values.fold<int>(0, (sum, s) => sum + s.mastered);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: module.color,
              child: Icon(module.icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    module.title(l10n),
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: tracked > 0 ? mastered / tracked : 0,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                    color: module.color,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    // Nothing tracked yet: "0 von 0" says nothing, so show
                    // what the module is about instead.
                    tracked > 0
                        ? l10n.masteredOfTracked(mastered, tracked)
                        : module.subtitle(l10n),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The learning module an SRI item belongs to (its first segment), for the
/// coloured icon in the tricky-spots list. Key signatures live in the scales
/// corner. Null when nothing matches.
LearningModule? _moduleForSriId(String id) {
  final mapped = moduleIdForSriNamespace(id.split('.').first);
  for (final module in kLearningModules) {
    if (module.id == mapped) return module;
  }
  return null;
}

/// One weak SRI item: a coloured module icon (so the list obviously spans
/// reading, rhythm, chords, harmony, keyboard, …), a readable label, and how
/// many times it was missed.
class _TrickyTile extends StatelessWidget {
  const _TrickyTile({
    required this.module,
    required this.label,
    required this.missed,
  });

  final LearningModule? module;
  final String label;
  final String missed;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 15,
        backgroundColor: module?.color ?? Colors.redAccent,
        child: Icon(
          module?.icon ?? Icons.priority_high,
          size: 17,
          color: Colors.white,
        ),
      ),
      title: Text(label),
      trailing: Text(missed, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
