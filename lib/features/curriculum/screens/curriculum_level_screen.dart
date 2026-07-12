// lib/features/curriculum/screens/curriculum_level_screen.dart
//
// One curriculum level: each topic with a readiness bar and the games that drill
// it (tap a game chip to play it). "Practise this level" opens a curated recital
// — one game per topic — so the child can run the level as a mixed set.

import 'package:flutter/material.dart';
import 'package:klang_universum/core/curriculum/curriculum.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/features/games/game_registry.dart';
import 'package:klang_universum/features/recital/recital_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

class CurriculumLevelScreen extends StatelessWidget {
  const CurriculumLevelScreen({super.key, required this.level});

  final CurriculumLevel level;

  /// One game per topic (the first that resolves) — a breadth sample to run.
  List<GameInfo> _program() {
    final seen = <String>{};
    final program = <GameInfo>[];
    for (final topic in level.topics) {
      for (final id in topic.gameIds) {
        final game = gameInfoById(id);
        if (game != null && seen.add(id)) {
          program.add(game);
          break;
        }
      }
    }
    return program;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress = context.watch<ProgressService>();
    int stars(String id) => progress.starsFor(id);
    final program = _program();

    // The lowest-readiness topic — the best thing to drill next.
    final weakest = weakestTopic(level, stars);
    final weakestGames = weakest == null
        ? <GameInfo>[]
        : [
            for (final id in weakest.gameIds)
              if (gameInfoById(id) case final game?) game,
          ];

    return Scaffold(
      appBar: AppBar(title: Text('${level.badge}  ${level.name(l10n)}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (program.isNotEmpty)
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RecitalScreen(program: program),
                  ),
                ),
                icon: const Icon(Icons.play_arrow),
                label: Text(l10n.curPracticeLevel),
              ),
            if (weakestGames.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RecitalScreen(program: weakestGames),
                  ),
                ),
                icon: const Icon(Icons.trending_up),
                label: Text(l10n.curPractiseWeakest),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              l10n.curTopicsHeader,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final topic in level.topics)
              _TopicTile(
                topic: topic,
                readiness: topicReadiness(topic, stars),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.topic, required this.readiness});

  final CurriculumTopic topic;
  final double readiness;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final games = [
      for (final id in topic.gameIds)
        if (gameInfoById(id) case final game?) game,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    topic.title(l10n),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  l10n.curReadiness((readiness * 100).round()),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: readiness,
                minHeight: 6,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 10),
            if (games.isEmpty)
              Text(
                l10n.curNoGames,
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final game in games)
                    ActionChip(
                      avatar: Icon(game.icon, size: 18),
                      label: Text(game.title(l10n)),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: game.builder),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
