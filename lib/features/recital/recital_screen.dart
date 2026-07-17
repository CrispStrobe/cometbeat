// lib/features/recital/recital_screen.dart
//
// "Recital Mode" — a progression meta (docs/PLAN.md original concepts): string a
// handful of games into one themed programme, play them in order, and end on a
// curtain call that tallies the stars earned across the set. It wraps the SM-2
// review in a set-piece — the games it picks lean toward ones the child has
// already practised, so a recital is a showcase of learned skills.
//
// It doesn't replace the games' own scoring; each piece records its result as
// usual. The recital just tracks which pieces were performed and sums the stars.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/tuning.dart';
import 'package:comet_beat/features/games/game_registry.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Picks a 3–5 piece programme, favouring scored games the child has already
/// played (a showcase), padding with other scored games if needed.
List<GameInfo> buildRecitalProgram(BuildContext context) {
  final progress = context.read<ProgressService>();
  final all = kGamesByModule.values
      .expand((games) => games)
      .where((g) => kStarThresholds.containsKey(g.id))
      .toList();
  final played =
      all.where((g) => progress.progressFor(g.id).plays > 0).toList();
  final pool = (played.length >= 3 ? played : all)..shuffle(Random());
  return pool.take(5).toList();
}

class RecitalScreen extends StatefulWidget {
  const RecitalScreen({super.key, required this.program});

  final List<GameInfo> program;

  @override
  State<RecitalScreen> createState() => _RecitalScreenState();
}

class _RecitalScreenState extends State<RecitalScreen> {
  final Set<String> _performed = {};
  bool _celebrated = false;

  bool get _complete =>
      widget.program.isNotEmpty && _performed.length >= widget.program.length;

  Future<void> _play(GameInfo game) async {
    // Plain route (no first-run tutorial): a recital is a showcase of games the
    // child already knows — tutorials belong on the module browse, not here.
    await Navigator.of(context).push(
      MaterialPageRoute(builder: game.builder),
    );
    if (!mounted) return;
    setState(() => _performed.add(game.id));
  }

  int get _starsEarned {
    final progress = context.read<ProgressService>();
    return widget.program.fold(0, (sum, g) => sum + progress.starsFor(g.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress = context.watch<ProgressService>();

    if (_complete) {
      // Play the fanfare once when the curtain falls.
      if (!_celebrated) {
        _celebrated = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => context.read<AudioService>().playFanfare(),
        );
      }
      return _CurtainCall(
        starsEarned: _starsEarned,
        maxStars: widget.program.length * 3,
        onHome: () => Navigator.of(context).pop(),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.recitalTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.recitalProgress(_performed.length, widget.program.length),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.program.length,
                itemBuilder: (context, i) {
                  final game = widget.program[i];
                  final done = _performed.contains(game.id);
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: done
                            ? Colors.green
                            : Theme.of(context).colorScheme.primary,
                        child: done
                            ? const Icon(Icons.check, color: Colors.white)
                            : Text(
                                '${i + 1}',
                                style: const TextStyle(color: Colors.white),
                              ),
                      ),
                      title: Text(game.title(l10n)),
                      subtitle: Text(game.subtitle(l10n)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var s = 0; s < 3; s++)
                            Icon(
                              s < progress.starsFor(game.id)
                                  ? Icons.star
                                  : Icons.star_border,
                              size: 16,
                              color: Colors.amber,
                            ),
                          const SizedBox(width: 6),
                          Icon(done ? Icons.replay : Icons.play_arrow),
                        ],
                      ),
                      onTap: () => _play(game),
                    ),
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

class _CurtainCall extends StatelessWidget {
  const _CurtainCall({
    required this.starsEarned,
    required this.maxStars,
    required this.onHome,
  });

  final int starsEarned;
  final int maxStars;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.recitalTitle)),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎭', style: TextStyle(fontSize: 88)),
              const SizedBox(height: 12),
              Text(
                l10n.recitalCurtainCall,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 40),
                  const SizedBox(width: 8),
                  Text(
                    '$starsEarned / $maxStars',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onHome,
                icon: const Icon(Icons.home),
                label: Text(l10n.recitalDone),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
