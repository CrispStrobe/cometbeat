// lib/core/models/learning_module.dart
//
// The module registry: one entry per learning topic. Each module bundles a
// set of minigames (features/games/...) and owns an ID namespace in the SRI
// database ('<module.id>.<skill>.<detail>', see sri_service.dart).
//
// To add a new module: add an entry here, add its title/subtitle keys to the
// ARB files, and register its games. Nothing else needs to change — the home
// screen renders from this list.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

class LearningModule {
  /// Stable ID, also the first segment of this module's SRI item IDs.
  final String id;
  final IconData icon;
  final Color color;

  /// Modules unlock in order as earlier ones reach mastery; the first
  /// [kInitiallyUnlocked] are always available.
  final bool initiallyUnlocked;

  final String Function(AppLocalizations) title;
  final String Function(AppLocalizations) subtitle;

  const LearningModule({
    required this.id,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.initiallyUnlocked = false,
  });
}

final List<LearningModule> kLearningModules = [
  LearningModule(
    id: 'note_values',
    icon: Icons.music_note,
    color: const Color(0xFF7C4DFF),
    initiallyUnlocked: true,
    title: (l) => l.moduleNoteValues,
    subtitle: (l) => l.moduleNoteValuesSubtitle,
  ),
  LearningModule(
    id: 'note_reading',
    icon: Icons.visibility,
    color: const Color(0xFF00B8D4),
    initiallyUnlocked: true,
    title: (l) => l.moduleNoteReading,
    subtitle: (l) => l.moduleNoteReadingSubtitle,
  ),
  LearningModule(
    id: 'measures',
    icon: Icons.straighten,
    color: const Color(0xFFFF6D00),
    title: (l) => l.moduleMeasures,
    subtitle: (l) => l.moduleMeasuresSubtitle,
  ),
  LearningModule(
    id: 'scales',
    icon: Icons.stairs,
    color: const Color(0xFF00C853),
    title: (l) => l.moduleScales,
    subtitle: (l) => l.moduleScalesSubtitle,
  ),
  LearningModule(
    id: 'chords',
    icon: Icons.library_music,
    color: const Color(0xFFD500F9),
    title: (l) => l.moduleChords,
    subtitle: (l) => l.moduleChordsSubtitle,
  ),
  LearningModule(
    id: 'harmony',
    icon: Icons.auto_awesome,
    color: const Color(0xFFFFAB00),
    title: (l) => l.moduleHarmony,
    subtitle: (l) => l.moduleHarmonySubtitle,
  ),
];
