// lib/features/curriculum/screens/curriculum_screen.dart
//
// Lists the curriculum's levels (generic progress levels tied to school years).
// Each shows a readiness bar (star coverage × SM-2 retention in the mapped
// games/skills); the recommended level is marked, and tapping one opens its
// topic breakdown.

import 'package:comet_beat/core/curriculum/curriculum.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/curriculum/screens/curriculum_level_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The standalone "Topics by grade" screen. Now a thin wrapper over
/// [CurriculumView] so the same body can be embedded as a Textbook tab.
class CurriculumScreen extends StatelessWidget {
  const CurriculumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.curriculumTitle)),
      body: const CurriculumView(),
    );
  }
}

/// The curriculum levels list (readiness bars + topic drill-down), without a
/// Scaffold — hosted standalone by [CurriculumScreen] and as the "Topics by
/// grade" tab inside the Textbook.
class CurriculumView extends StatelessWidget {
  const CurriculumView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress = context.watch<ProgressService>();
    final sri = context.watch<SriService>();
    int stars(String id) => progress.starsFor(id);
    double? mastery(String prefix) => sri.masteryUnder(prefix);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final curriculum in kCurricula) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: Text(
                curriculum.name(l10n),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final level in curriculum.levels)
              _LevelCard(
                level: level,
                readiness: levelReadiness(level, stars, mastery),
                recommended:
                    level == recommendedLevel(curriculum, stars, mastery),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CurriculumLevelScreen(level: level),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Text(
            l10n.curGuideNote,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.level,
    required this.readiness,
    required this.recommended,
    required this.onTap,
  });

  final CurriculumLevel level;
  final double readiness;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final pct = (readiness * 100).round();
    return Card(
      child: ListTile(
        leading: Text(level.badge, style: const TextStyle(fontSize: 30)),
        title: Row(
          children: [
            // Flexible so a long level name (or a longer locale) yields to the
            // "Continue here" badge instead of overflowing the ListTile title.
            Flexible(
              child: Text(level.name(l10n), overflow: TextOverflow.ellipsis),
            ),
            if (recommended) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  l10n.curContinueHere,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: readiness,
                  minHeight: 7,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.curReadiness(pct),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
