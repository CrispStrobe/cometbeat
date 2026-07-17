// lib/features/textbook/textbook_screen.dart
//
// The read-through textbook: a learner can start at grade 1 and work down the
// whole music-theory syllabus, grade band by grade band. Each concept shows its
// LESSON (its game's zero-knowledge primer — words + engraved + heard examples)
// and links to the games that TRAIN it. Built directly on the grade-1–10 concept
// map (core/curriculum/concept_map.dart), so it stays in sync with coverage: a
// concept with no game yet is shown as "coming soon".
//
// Concept titles are the map's own-words English labels (dev-facing) for now;
// the lessons themselves are fully localised via their primers. Localising the
// concept titles is a follow-up.

import 'package:comet_beat/core/curriculum/concept_map.dart';
import 'package:comet_beat/features/games/game_registry.dart';
import 'package:comet_beat/features/games/tutorial_gate.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/tutorial/tutorial_sheet.dart';
import 'package:flutter/material.dart';

IconData _areaIcon(ConceptArea a) => switch (a) {
      ConceptArea.pulse => Icons.favorite,
      ConceptArea.reading => Icons.menu_book,
      ConceptArea.duration => Icons.timer,
      ConceptArea.meter => Icons.straighten,
      ConceptArea.dynamics => Icons.volume_up,
      ConceptArea.tempo => Icons.speed,
      ConceptArea.pitch => Icons.height,
      ConceptArea.scales => Icons.stairs,
      ConceptArea.intervals => Icons.swap_vert,
      ConceptArea.chords => Icons.layers,
      ConceptArea.harmony => Icons.account_tree,
      ConceptArea.articulation => Icons.gesture,
      ConceptArea.transpose => Icons.swap_horiz,
      ConceptArea.form => Icons.view_column,
      ConceptArea.timbre => Icons.music_note,
      ConceptArea.technique => Icons.piano,
      ConceptArea.aural => Icons.hearing,
      ConceptArea.creating => Icons.brush,
      ConceptArea.repertoire => Icons.library_music,
    };

class TextbookScreen extends StatelessWidget {
  const TextbookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.textbookTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              l10n.textbookIntro,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          for (final band in GradeBand.values) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
              child: Text(
                band.label,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            for (final c in kConcepts.where((c) => c.band == band))
              _ConceptTile(concept: c),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ConceptTile extends StatelessWidget {
  const _ConceptTile({required this.concept});

  final Concept concept;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final games = [
      for (final id in concept.gameIds)
        if (kGamesById[id] case final GameInfo g) g,
    ];

    if (games.isEmpty) {
      // A concept we don't train yet — shown so the path stays honest.
      return ListTile(
        leading: Icon(
          _areaIcon(concept.area),
          color: Theme.of(context).disabledColor,
        ),
        title: Text(concept.title),
        subtitle: Text(l10n.textbookComingSoon),
        enabled: false,
      );
    }

    // The lesson is the first game's primer (its own, or its module's fallback).
    final lesson = helpPrimerFor(games.first);

    return ExpansionTile(
      leading: Icon(
        _areaIcon(concept.area),
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(concept.title),
      subtitle: Text(l10n.textbookPractise),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        if (lesson != null)
          ListTile(
            leading: const Icon(Icons.auto_stories),
            title: Text(l10n.textbookReadLesson),
            onTap: () => showTutorial(context, lesson(l10n)),
          ),
        for (final g in games)
          ListTile(
            leading: Icon(g.icon),
            title: Text(g.title(l10n)),
            trailing: const Icon(Icons.play_arrow),
            onTap: () => Navigator.of(context).push(gameRoute(g)),
          ),
      ],
    );
  }
}
