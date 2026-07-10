// lib/features/games/game_registry.dart
//
// Maps each learning module to its minigames. Adding a game = one GameInfo
// entry here plus its screen under features/games/<module>/ and, if it has
// scores, a bracket in core/tuning.dart's kStarThresholds.

import 'package:flutter/material.dart';
import 'package:partitura/partitura.dart';

import '../../l10n/app_localizations.dart';
import 'cello/cello_finger_quiz_screen.dart';
import 'cello/cello_string_quiz_screen.dart';
import 'chords/chord_quiz_screen.dart';
import 'chords/interval_ear_screen.dart';
import 'chords/triad_builder_screen.dart';
import 'harmony/harmony_quiz_screen.dart';
import 'measures/measure_fill_screen.dart';
import 'measures/meter_detective_screen.dart';
import 'note_reading/melody_echo_screen.dart';
import 'note_reading/note_reading_quiz_screen.dart';
import 'note_reading/place_note_screen.dart';
import 'note_values/beat_count_screen.dart';
import 'note_values/duration_duel_screen.dart';
import 'note_values/note_value_quiz_screen.dart';
import 'note_values/rhythm_tap_screen.dart';
import 'harmony/cadence_workshop_screen.dart';
import 'scales/major_minor_ear_screen.dart';
import 'scales/scale_builder_screen.dart';
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
    GameInfo(
      id: 'rhythm_tap',
      icon: Icons.touch_app,
      title: (l) => l.gameRhythmTap,
      subtitle: (l) => l.gameRhythmTapSubtitle,
      builder: (_) => const RhythmTapScreen(),
    ),
    GameInfo(
      id: 'beat_count',
      icon: Icons.filter_4,
      title: (l) => l.gameBeatCount,
      subtitle: (l) => l.gameBeatCountSubtitle,
      builder: (_) => const BeatCountScreen(),
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
    GameInfo(
      id: 'melody_echo',
      icon: Icons.graphic_eq,
      title: (l) => l.gameMelodyEcho,
      subtitle: (l) => l.gameMelodyEchoSubtitle,
      builder: (_) => const MelodyEchoScreen(),
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
    GameInfo(
      id: 'meter_detective',
      icon: Icons.hearing,
      title: (l) => l.gameMeterDetective,
      subtitle: (l) => l.gameMeterDetectiveSubtitle,
      builder: (_) => const MeterDetectiveScreen(),
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
    GameInfo(
      id: 'major_minor_ear',
      icon: Icons.hearing,
      title: (l) => l.gameMajorMinorEar,
      subtitle: (l) => l.gameMajorMinorEarSubtitle,
      builder: (_) => const MajorMinorEarScreen(),
    ),
    GameInfo(
      id: 'scale_builder',
      icon: Icons.construction,
      title: (l) => l.gameScaleBuilder,
      subtitle: (l) => l.gameScaleBuilderSubtitle,
      builder: (_) => const ScaleBuilderScreen(),
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
    GameInfo(
      id: 'triad_builder',
      icon: Icons.construction,
      title: (l) => l.gameTriadBuilder,
      subtitle: (l) => l.gameTriadBuilderSubtitle,
      builder: (_) => const TriadBuilderScreen(),
    ),
    GameInfo(
      id: 'interval_ear',
      icon: Icons.hearing,
      title: (l) => l.gameIntervalEar,
      subtitle: (l) => l.gameIntervalEarSubtitle,
      builder: (_) => const IntervalEarScreen(),
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
    GameInfo(
      id: 'cadence_workshop',
      icon: Icons.queue_music,
      title: (l) => l.gameCadenceWorkshop,
      subtitle: (l) => l.gameCadenceWorkshopSubtitle,
      builder: (_) => const CadenceWorkshopScreen(),
    ),
  ],
  'cello': [
    GameInfo(
      id: 'cello_string_quiz',
      icon: Icons.linear_scale,
      title: (l) => l.gameCelloStringQuiz,
      subtitle: (l) => l.gameCelloStringQuizSubtitle,
      builder: (_) => const CelloStringQuizScreen(),
    ),
    GameInfo(
      id: 'cello_finger_quiz',
      icon: Icons.back_hand,
      title: (l) => l.gameCelloFingerQuiz,
      subtitle: (l) => l.gameCelloFingerQuizSubtitle,
      builder: (_) => const CelloFingerQuizScreen(),
    ),
    GameInfo(
      id: 'note_reading_tenor',
      icon: Icons.music_note,
      title: (l) => l.gameNoteReadingTenor,
      subtitle: (l) => l.gameNoteReadingSubtitle,
      builder: (_) => const NoteReadingQuizScreen(clef: Clef.tenor),
    ),
  ],
};
