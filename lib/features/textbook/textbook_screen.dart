// lib/features/textbook/textbook_screen.dart
//
// The read-through textbook: a learner can start at grade 1 and work down the
// whole music-theory syllabus, grade band by grade band. Each concept shows its
// LESSON (its game's zero-knowledge primer — words + engraved + heard examples)
// and links to the games that TRAIN it. Built directly on the grade-1–10 concept
// map (core/curriculum/concept_map.dart), so it stays in sync with coverage: a
// concept with no game yet is shown as "coming soon".
//
// Everything shown here is localised (de/en): the grade-band labels + narrative
// intros, the concept-area sub-headers, the concept titles (textbook_i18n.dart,
// ARB-backed), and the lessons themselves (their primers). Within a band the
// concepts are grouped by area with a sub-header, so it reads like a book.

import 'package:comet_beat/core/curriculum/concept_map.dart';
import 'package:comet_beat/features/curriculum/screens/curriculum_screen.dart'
    show CurriculumView;
import 'package:comet_beat/features/games/composition/form_analysis_view.dart';
import 'package:comet_beat/features/games/game_registry.dart';
import 'package:comet_beat/features/games/tutorial_gate.dart';
import 'package:comet_beat/features/textbook/textbook_i18n.dart';
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

/// The concept areas present in a band, in the order they first appear in the
/// concept map (so the reader keeps the map's deliberate teaching sequence).
List<ConceptArea> _areasInBand(GradeBand band) {
  final seen = <ConceptArea>[];
  for (final c in kConcepts.where((c) => c.band == band)) {
    if (!seen.contains(c.area)) seen.add(c.area);
  }
  return seen;
}

/// The Textbook hub: the read-through lessons ("Read") and the curriculum
/// levels ("Topics by grade"), united under one screen with two tabs. Topics by
/// grade used to be its own home tile; it now lives here as a view mode.
class TextbookScreen extends StatelessWidget {
  const TextbookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.textbookTitle),
          bottom: TabBar(
            tabs: [
              Tab(
                icon: const Icon(Icons.menu_book),
                text: l10n.textbookTabRead,
              ),
              Tab(icon: const Icon(Icons.school), text: l10n.curriculumTitle),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_ReadTab(), CurriculumView()],
        ),
      ),
    );
  }
}

/// The read-through lessons tab (the original Textbook body).
class _ReadTab extends StatelessWidget {
  const _ReadTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
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
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
            child: Text(
              bandLabel(l10n, band),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              bandIntro(l10n, band),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          // Group the band's concepts by area, in first-appearance order, with
          // a small area sub-header before each run.
          for (final area in _areasInBand(band)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
              child: Row(
                children: [
                  Icon(
                    _areaIcon(area),
                    size: 16,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    areaName(l10n, area).toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                        ),
                  ),
                ],
              ),
            ),
            for (final c
                in kConcepts.where((c) => c.band == band && c.area == area))
              _ConceptTile(concept: c),
          ],
        ],
        const SizedBox(height: 24),
      ],
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
        title: Text(conceptTitle(l10n, concept.id)),
        subtitle: Text(l10n.textbookComingSoon),
        enabled: false,
      );
    }

    // The lesson is the first game's primer (its own, or its module's fallback).
    final lesson = helpPrimerFor(games.first);
    // The textbook's own teaching paragraph (null where not yet authored).
    final prose = conceptProse(l10n, concept.id);
    // Worked AnaVis-style form / harmony examples, if this concept has any.
    final formExamples = kFormExamples[concept.id];
    final harmonyExamples = kHarmonyExamples[concept.id];

    return ExpansionTile(
      leading: Icon(
        _areaIcon(concept.area),
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(conceptTitle(l10n, concept.id)),
      subtitle: Text(l10n.textbookPractise),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        if (prose != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              prose,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        if (lesson != null)
          ListTile(
            leading: const Icon(Icons.auto_stories),
            title: Text(l10n.textbookReadLesson),
            onTap: () => showTutorial(context, lesson(l10n)),
          ),
        if (formExamples != null && formExamples.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.view_column),
            title: Text(l10n.formAnalysisTitle),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FormAnalysisScreen(examples: formExamples),
              ),
            ),
          ),
        if (harmonyExamples != null && harmonyExamples.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.account_tree),
            title: Text(l10n.harmonyAnalysisTitle),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    HarmonyAnalysisScreen(examples: harmonyExamples),
              ),
            ),
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
