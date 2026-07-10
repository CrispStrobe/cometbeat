// lib/features/games/game_registry.dart
//
// Maps each learning module to its minigames. Adding a game = one GameInfo
// entry here plus its screen under features/games/<module>/ and, if it has
// scores, a bracket in core/tuning.dart's kStarThresholds.

import 'package:flutter/material.dart';
import 'package:partitura/partitura.dart';

import '../../l10n/app_localizations.dart';
import 'note_reading/note_reading_quiz_screen.dart';
import 'note_values/duration_duel_screen.dart';
import 'note_values/note_value_quiz_screen.dart';

class GameInfo {
  /// Stable ID, used for star thresholds and analytics.
  final String id;
  final IconData icon;
  final String Function(AppLocalizations) title;
  final String Function(AppLocalizations) subtitle;
  final WidgetBuilder builder;

  const GameInfo({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
  });
}

final Map<String, List<GameInfo>> kGamesByModule = {
  'note_values': [
    GameInfo(
      id: 'note_value_quiz',
      icon: Icons.quiz,
      title: (l) => l.gameNoteValueQuiz,
      subtitle: (l) => l.gameNoteValueQuizSubtitle,
      builder: (_) => const NoteValueQuizScreen(),
    ),
    GameInfo(
      id: 'duration_duel',
      icon: Icons.compare_arrows,
      title: (l) => l.gameDurationDuel,
      subtitle: (l) => l.gameDurationDuelSubtitle,
      builder: (_) => const DurationDuelScreen(),
    ),
  ],
  'note_reading': [
    GameInfo(
      id: 'note_reading_treble',
      icon: Icons.music_note,
      title: (l) => l.gameNoteReadingTreble,
      subtitle: (l) => l.gameNoteReadingSubtitle,
      builder: (_) => const NoteReadingQuizScreen(clef: Clef.treble),
    ),
    GameInfo(
      id: 'note_reading_bass',
      icon: Icons.music_note_outlined,
      title: (l) => l.gameNoteReadingBass,
      subtitle: (l) => l.gameNoteReadingSubtitle,
      builder: (_) => const NoteReadingQuizScreen(clef: Clef.bass),
    ),
  ],
};
