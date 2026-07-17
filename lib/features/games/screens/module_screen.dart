// lib/features/games/screens/module_screen.dart
//
// Lists the minigames of one learning module (from the game registry).

import 'package:comet_beat/core/models/learning_module.dart';
import 'package:comet_beat/core/services/debug_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/features/games/game_registry.dart';
import 'package:comet_beat/features/games/tutorial_gate.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ModuleScreen extends StatelessWidget {
  final LearningModule module;

  const ModuleScreen({super.key, required this.module});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress = context.watch<ProgressService>();
    final unlockAll = context.watch<DebugService>().unlockAll;
    final games = kGamesByModule[module.id] ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(module.title(l10n))),
      body: games.isEmpty
          ? Center(child: Text(l10n.comingSoon))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: games.length,
              itemBuilder: (context, index) {
                final game = games[index];
                final locked = !unlockAll &&
                    game.unlockedWhen != null &&
                    !game.unlockedWhen!(progress);
                return Card(
                  child: Opacity(
                    opacity: locked ? 0.5 : 1.0,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: locked ? Colors.grey : module.color,
                        child: Icon(
                          locked ? Icons.lock : game.icon,
                          color: Colors.white,
                        ),
                      ),
                      title: Text(game.title(l10n)),
                      subtitle: Text(
                        locked
                            ? (game.lockedHint?.call(l10n) ?? l10n.locked)
                            : game.subtitle(l10n),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!locked)
                            for (var i = 0; i < 3; i++)
                              Icon(
                                i < progress.starsFor(game.id)
                                    ? Icons.star
                                    : Icons.star_border,
                                size: 18,
                                color: Colors.amber,
                              ),
                          const SizedBox(width: 4),
                          Icon(locked ? Icons.lock : Icons.chevron_right),
                        ],
                      ),
                      onTap: locked
                          ? () => ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    game.lockedHint?.call(l10n) ?? l10n.locked,
                                  ),
                                ),
                              )
                          : () => Navigator.of(context).push(gameRoute(game)),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
