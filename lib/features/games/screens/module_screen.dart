// lib/features/games/screens/module_screen.dart
//
// Lists the minigames of one learning module (from the game registry).

import 'package:flutter/material.dart';

import '../../../core/models/learning_module.dart';
import '../../../l10n/app_localizations.dart';
import '../game_registry.dart';

class ModuleScreen extends StatelessWidget {
  final LearningModule module;

  const ModuleScreen({super.key, required this.module});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: module.color,
                      child: Icon(game.icon, color: Colors.white),
                    ),
                    title: Text(game.title(l10n)),
                    subtitle: Text(game.subtitle(l10n)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: game.builder),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
