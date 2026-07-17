// lib/core/models/learning_module.dart
//
// The module registry: one entry per learning topic. Each module bundles a
// set of minigames (features/games/...) and owns an ID namespace in the SRI
// database ('<module.id>.<skill>.<detail>', see sri_service.dart).
//
// To add a new module: add an entry here, add its title/subtitle keys to the
// ARB files, and register its games. Nothing else needs to change — the home
// screen renders from this list.

import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class LearningModule {
  /// Stable ID, also the first segment of this module's SRI item IDs.
  final String id;
  final IconData icon;
  final Color color;

  /// Whether the module is available from the start. All modules with games
  /// are currently unlocked (testing phase); planned gating: unlock when the
  /// previous module reaches >=50% SRI mastery — see docs/PLAN.md.
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
  LearningModule(
    id: 'composition',
    icon: Icons.edit_note,
    color: const Color(0xFF5C6BC0),
    title: (l) => l.moduleComposition,
    subtitle: (l) => l.moduleCompositionSubtitle,
  ),
  // Instrument corner — unlocked from the start (special interest beats
  // curriculum order; see docs/PLAN.md).
  LearningModule(
    id: 'cello',
    icon: Icons.audiotrack,
    color: const Color(0xFF8D6E63),
    initiallyUnlocked: true,
    title: (l) => l.moduleCello,
    subtitle: (l) => l.moduleCelloSubtitle,
  ),
  // Guitar corner — a second instrument corner (tablature), unlocked from the
  // start like the cello corner (special interest beats curriculum order).
  LearningModule(
    id: 'guitar',
    icon: Icons.music_note,
    color: const Color(0xFF6D4C41),
    initiallyUnlocked: true,
    title: (l) => l.moduleGuitar,
    subtitle: (l) => l.moduleGuitarSubtitle,
  ),
  LearningModule(
    id: 'songs',
    icon: Icons.library_music,
    color: const Color(0xFFEC407A),
    initiallyUnlocked: true,
    title: (l) => l.moduleSongs,
    subtitle: (l) => l.moduleSongsSubtitle,
  ),
  LearningModule(
    id: 'keyboard',
    icon: Icons.piano,
    color: const Color(0xFF26A69A),
    initiallyUnlocked: true,
    title: (l) => l.moduleKeyboard,
    subtitle: (l) => l.moduleKeyboardSubtitle,
  ),
  // Transposing-instrument corner — advanced, unlocked from the start like the
  // other instrument corners (special interest beats curriculum order).
  LearningModule(
    id: 'transpose',
    icon: Icons.swap_vert,
    color: const Color(0xFF00897B),
    initiallyUnlocked: true,
    title: (l) => l.moduleTranspose,
    subtitle: (l) => l.moduleTransposeSubtitle,
  ),
  // Drum/percussion corner — read rhythms on the neutral percussion staff.
  LearningModule(
    id: 'drums',
    icon: Icons.album,
    color: const Color(0xFF455A64),
    initiallyUnlocked: true,
    title: (l) => l.moduleDrums,
    subtitle: (l) => l.moduleDrumsSubtitle,
  ),
];
