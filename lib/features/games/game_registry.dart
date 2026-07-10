// lib/features/games/game_registry.dart
//
// Maps each learning module to its minigames. Adding a game = one GameInfo
// entry here plus its screen under features/games/<module>/ and, if it has
// scores, a bracket in core/tuning.dart's kStarThresholds.

import 'package:flutter/material.dart';
import 'package:partitura/partitura.dart';

import '../../l10n/app_localizations.dart';
import 'chords/chord_quiz_screen.dart';
import 'harmony/harmony_quiz_screen.dart';
import 'measures/measure_fill_screen.dart';
import 'note_reading/note_reading_quiz_screen.dart';
import 'note_reading/place_note_screen.dart';
import 'note_values/duration_duel_screen.dart';
import 'note_values/note_value_quiz_screen.dart';
import 'scales/scale_detective_screen.dart';

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
    GameInfo(
      id: 'place_note_treble',
      icon: Icons.touch_app,
      title: (l) => l.gamePlaceNoteTreble,
      subtitle: (l) => l.gamePlaceNoteSubtitle,
      builder: (_) => const PlaceNoteScreen(clef: Clef.treble),
    ),
    GameInfo(
      id: 'place_note_bass',
      icon: Icons.touch_app_outlined,
      title: (l) => l.gamePlaceNoteBass,
      subtitle: (l) => l.gamePlaceNoteSubtitle,
      builder: (_) => const PlaceNoteScreen(clef: Clef.bass),
    ),
  ],
  'measures': [
    GameInfo(
      id: 'measure_fill',
      icon: Icons.check_box_outline_blank,
      title: (l) => l.gameMeasureFill,
      subtitle: (l) => l.gameMeasureFillSubtitle,
      builder: (_) => const MeasureFillScreen(),
    ),
  ],
  'scales': [
    GameInfo(
      id: 'scale_detective',
      icon: Icons.search,
      title: (l) => l.gameScaleDetective,
      subtitle: (l) => l.gameScaleDetectiveSubtitle,
      builder: (_) => const ScaleDetectiveScreen(),
    ),
  ],
  'chords': [
    GameInfo(
      id: 'chord_quiz',
      icon: Icons.library_music,
      title: (l) => l.gameChordQuiz,
      subtitle: (l) => l.gameChordQuizSubtitle,
      builder: (_) => const ChordQuizScreen(),
    ),
  ],
  'harmony': [
    GameInfo(
      id: 'harmony_quiz',
      icon: Icons.auto_awesome,
      title: (l) => l.gameHarmonyQuiz,
      subtitle: (l) => l.gameHarmonyQuizSubtitle,
      builder: (_) => const HarmonyQuizScreen(),
    ),
  ],
};
