// lib/features/games/game_registry.dart
//
// Maps each learning module to its minigames. Adding a game = one GameInfo
// entry here plus its screen under features/games/<module>/ and, if it has
// scores, a bracket in core/tuning.dart's kStarThresholds.

import 'package:flutter/material.dart';
import 'package:klang_universum/features/games/cello/cello_finger_quiz_screen.dart';
import 'package:klang_universum/features/games/cello/cello_string_quiz_screen.dart';
import 'package:klang_universum/features/games/chords/chord_quiz_screen.dart';
import 'package:klang_universum/features/games/chords/interval_ear_screen.dart';
import 'package:klang_universum/features/games/chords/triad_builder_screen.dart';
import 'package:klang_universum/features/games/composition/ending_detective_screen.dart';
import 'package:klang_universum/features/games/composition/my_melody_screen.dart';
import 'package:klang_universum/features/games/composition/question_answer_screen.dart';
import 'package:klang_universum/features/games/guitar/guitar_string_quiz_screen.dart';
import 'package:klang_universum/features/games/guitar/guitar_tab_read_screen.dart';
import 'package:klang_universum/features/games/harmony/cadence_workshop_screen.dart';
import 'package:klang_universum/features/games/harmony/function_ear_screen.dart';
import 'package:klang_universum/features/games/harmony/harmony_quiz_screen.dart';
import 'package:klang_universum/features/games/keyboard/grand_staff_read_screen.dart';
import 'package:klang_universum/features/games/keyboard/key_chord_screen.dart';
import 'package:klang_universum/features/games/keyboard/key_ear_screen.dart';
import 'package:klang_universum/features/games/keyboard/key_find_screen.dart';
import 'package:klang_universum/features/games/keyboard/key_melody_screen.dart';
import 'package:klang_universum/features/games/keyboard/key_name_screen.dart';
import 'package:klang_universum/features/games/measures/measure_fill_screen.dart';
import 'package:klang_universum/features/games/measures/meter_detective_screen.dart';
import 'package:klang_universum/features/games/note_reading/melody_dictation_screen.dart';
import 'package:klang_universum/features/games/note_reading/melody_echo_screen.dart';
import 'package:klang_universum/features/games/note_reading/note_memory_screen.dart';
import 'package:klang_universum/features/games/note_reading/note_order_screen.dart';
import 'package:klang_universum/features/games/note_reading/note_reading_quiz_screen.dart';
import 'package:klang_universum/features/games/note_reading/place_note_screen.dart';
import 'package:klang_universum/features/games/note_values/beat_count_screen.dart';
import 'package:klang_universum/features/games/note_values/duration_duel_screen.dart';
import 'package:klang_universum/features/games/note_values/note_value_quiz_screen.dart';
import 'package:klang_universum/features/games/note_values/rhythm_tap_screen.dart';
import 'package:klang_universum/features/games/scales/major_minor_ear_screen.dart';
import 'package:klang_universum/features/games/scales/scale_builder_screen.dart';
import 'package:klang_universum/features/games/scales/scale_detective_screen.dart';
import 'package:klang_universum/features/games/songs/song_screen.dart';
import 'package:klang_universum/features/games/songs/tune_quiz_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart';

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
    GameInfo(
      id: 'melody_dictation',
      icon: Icons.edit_note,
      title: (l) => l.gameMelodyDictation,
      subtitle: (l) => l.gameMelodyDictationSubtitle,
      builder: (_) => const MelodyDictationScreen(),
    ),
    GameInfo(
      id: 'note_memory',
      icon: Icons.grid_view,
      title: (l) => l.gameNoteMemory,
      subtitle: (l) => l.gameNoteMemorySubtitle,
      builder: (_) => const NoteMemoryScreen(),
    ),
    GameInfo(
      id: 'note_order',
      icon: Icons.sort,
      title: (l) => l.gameNoteOrder,
      subtitle: (l) => l.gameNoteOrderSubtitle,
      builder: (_) => const NoteOrderScreen(),
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
    GameInfo(
      id: 'function_ear',
      icon: Icons.hearing,
      title: (l) => l.gameFunctionEar,
      subtitle: (l) => l.gameFunctionEarSubtitle,
      builder: (_) => const FunctionEarScreen(),
    ),
  ],
  'composition': [
    GameInfo(
      id: 'ending_detective',
      icon: Icons.hearing,
      title: (l) => l.gameEndingDetective,
      subtitle: (l) => l.gameEndingDetectiveSubtitle,
      builder: (_) => const EndingDetectiveScreen(),
    ),
    GameInfo(
      id: 'question_answer',
      icon: Icons.question_answer,
      title: (l) => l.gameQuestionAnswer,
      subtitle: (l) => l.gameQuestionAnswerSubtitle,
      builder: (_) => const QuestionAnswerScreen(),
    ),
    GameInfo(
      id: 'my_melody',
      icon: Icons.edit_note,
      title: (l) => l.gameMyMelody,
      subtitle: (l) => l.gameMyMelodySubtitle,
      builder: (_) => const MyMelodyScreen(),
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
  'guitar': [
    GameInfo(
      id: 'guitar_string_quiz',
      icon: Icons.music_note,
      title: (l) => l.gameGuitarStringQuiz,
      subtitle: (l) => l.gameGuitarStringQuizSubtitle,
      builder: (_) => const GuitarStringQuizScreen(),
    ),
    GameInfo(
      id: 'guitar_tab_read',
      icon: Icons.grid_on,
      title: (l) => l.gameGuitarTabRead,
      subtitle: (l) => l.gameGuitarTabReadSubtitle,
      builder: (_) => const GuitarTabReadScreen(),
    ),
  ],
  'songs': [
    GameInfo(
      id: 'song_book',
      icon: Icons.menu_book,
      title: (l) => l.gameSongBook,
      subtitle: (l) => l.gameSongBookSubtitle,
      builder: (_) => const SongListScreen(),
    ),
    GameInfo(
      id: 'tune_quiz',
      icon: Icons.hearing,
      title: (l) => l.gameTuneQuiz,
      subtitle: (l) => l.gameTuneQuizSubtitle,
      builder: (_) => const TuneQuizScreen(),
    ),
  ],
  'keyboard': [
    GameInfo(
      id: 'key_find',
      icon: Icons.piano,
      title: (l) => l.gameKeyFind,
      subtitle: (l) => l.gameKeyFindSubtitle,
      builder: (_) => const KeyFindScreen(),
    ),
    GameInfo(
      id: 'key_name',
      icon: Icons.quiz,
      title: (l) => l.gameKeyName,
      subtitle: (l) => l.gameKeyNameSubtitle,
      builder: (_) => const KeyNameScreen(),
    ),
    GameInfo(
      id: 'key_ear',
      icon: Icons.hearing,
      title: (l) => l.gameKeyEar,
      subtitle: (l) => l.gameKeyEarSubtitle,
      builder: (_) => const KeyEarScreen(),
    ),
    GameInfo(
      id: 'key_melody',
      icon: Icons.queue_music,
      title: (l) => l.gameKeyMelody,
      subtitle: (l) => l.gameKeyMelodySubtitle,
      builder: (_) => const KeyMelodyScreen(),
    ),
    GameInfo(
      id: 'key_chord',
      icon: Icons.back_hand,
      title: (l) => l.gameKeyChord,
      subtitle: (l) => l.gameKeyChordSubtitle,
      builder: (_) => const KeyChordScreen(),
    ),
    GameInfo(
      id: 'grand_staff_read',
      icon: Icons.menu_book,
      title: (l) => l.gameGrandStaffRead,
      subtitle: (l) => l.gameGrandStaffReadSubtitle,
      builder: (_) => const GrandStaffReadScreen(),
    ),
  ],
};
