// lib/features/games/game_registry.dart
//
// Maps each learning module to its minigames. Adding a game = one GameInfo
// entry here plus its screen under features/games/<module>/ and, if it has
// scores, a bracket in core/tuning.dart's kStarThresholds.

import 'package:comet_beat/core/audio/chord_progression.dart';
import 'package:comet_beat/core/audio/play_along.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/features/games/cello/bowing_screen.dart';
import 'package:comet_beat/features/games/cello/cello_finger_quiz_screen.dart';
import 'package:comet_beat/features/games/cello/cello_play_it_screen.dart';
import 'package:comet_beat/features/games/cello/cello_string_quiz_screen.dart';
import 'package:comet_beat/features/games/cello/tuner_spike_screen.dart';
import 'package:comet_beat/features/games/chords/chord_builder_screen.dart';
import 'package:comet_beat/features/games/chords/chord_chart_screen.dart';
import 'package:comet_beat/features/games/chords/chord_listen_spike_screen.dart';
import 'package:comet_beat/features/games/chords/chord_progression_screen.dart';
import 'package:comet_beat/features/games/chords/chord_quiz_screen.dart';
import 'package:comet_beat/features/games/chords/interval_ear_screen.dart';
import 'package:comet_beat/features/games/chords/interval_ladder_screen.dart';
import 'package:comet_beat/features/games/chords/major_minor_sort_screen.dart';
import 'package:comet_beat/features/games/chords/name_that_chord_screen.dart';
import 'package:comet_beat/features/games/chords/sing_interval_screen.dart';
import 'package:comet_beat/features/games/chords/triad_builder_screen.dart';
import 'package:comet_beat/features/games/chords/triad_seventh_screen.dart';
import 'package:comet_beat/features/games/composition/ending_detective_screen.dart';
import 'package:comet_beat/features/games/composition/free_sing_screen.dart';
import 'package:comet_beat/features/games/composition/grid_composer_screen.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:comet_beat/features/games/composition/melody_doodle_screen.dart';
import 'package:comet_beat/features/games/composition/my_melody_screen.dart';
import 'package:comet_beat/features/games/composition/question_answer_screen.dart';
import 'package:comet_beat/features/games/composition/tracker_screen.dart';
import 'package:comet_beat/features/games/drums/drum_read_screen.dart';
import 'package:comet_beat/features/games/expression/charades_screen.dart';
import 'package:comet_beat/features/games/guitar/guitar_string_quiz_screen.dart';
import 'package:comet_beat/features/games/guitar/guitar_tab_read_screen.dart';
import 'package:comet_beat/features/games/guitar/strum_toy_screen.dart';
import 'package:comet_beat/features/games/harmony/cadence_workshop_screen.dart';
import 'package:comet_beat/features/games/harmony/function_ear_screen.dart';
import 'package:comet_beat/features/games/harmony/harmony_quiz_screen.dart';
import 'package:comet_beat/features/games/harmony/roman_numeral_screen.dart';
import 'package:comet_beat/features/games/keyboard/chord_grip_hero_screen.dart';
import 'package:comet_beat/features/games/keyboard/grand_staff_read_screen.dart';
import 'package:comet_beat/features/games/keyboard/key_chord_screen.dart';
import 'package:comet_beat/features/games/keyboard/key_ear_screen.dart';
import 'package:comet_beat/features/games/keyboard/key_find_screen.dart';
import 'package:comet_beat/features/games/keyboard/key_melody_screen.dart';
import 'package:comet_beat/features/games/keyboard/key_name_screen.dart';
import 'package:comet_beat/features/games/measures/beat_runner_screen.dart';
import 'package:comet_beat/features/games/measures/measure_fill_screen.dart';
import 'package:comet_beat/features/games/measures/meter_detective_screen.dart';
import 'package:comet_beat/features/games/measures/spot_upbeat_screen.dart';
import 'package:comet_beat/features/games/measures/strong_beat_screen.dart';
import 'package:comet_beat/features/games/measures/time_signature_screen.dart';
import 'package:comet_beat/features/games/measures/which_beat_screen.dart';
import 'package:comet_beat/features/games/note_reading/accidental_sort_screen.dart';
import 'package:comet_beat/features/games/note_reading/articulation_read_screen.dart';
import 'package:comet_beat/features/games/note_reading/beam_flag_screen.dart';
import 'package:comet_beat/features/games/note_reading/connect_line_screen.dart';
import 'package:comet_beat/features/games/note_reading/duet_screen.dart';
import 'package:comet_beat/features/games/note_reading/enharmonic_screen.dart';
import 'package:comet_beat/features/games/note_reading/falling_notes_screen.dart';
import 'package:comet_beat/features/games/note_reading/hear_voice_screen.dart';
import 'package:comet_beat/features/games/note_reading/ledger_leap_screen.dart';
import 'package:comet_beat/features/games/note_reading/line_space_screen.dart';
import 'package:comet_beat/features/games/note_reading/melody_dictation_screen.dart';
import 'package:comet_beat/features/games/note_reading/melody_echo_screen.dart';
import 'package:comet_beat/features/games/note_reading/note_memory_screen.dart';
import 'package:comet_beat/features/games/note_reading/note_order_screen.dart';
import 'package:comet_beat/features/games/note_reading/note_reading_quiz_screen.dart';
import 'package:comet_beat/features/games/note_reading/note_snake_screen.dart';
import 'package:comet_beat/features/games/note_reading/note_whack_screen.dart';
import 'package:comet_beat/features/games/note_reading/odd_one_out_screen.dart';
import 'package:comet_beat/features/games/note_reading/perform_it_screen.dart';
import 'package:comet_beat/features/games/note_reading/pitch_sort_screen.dart';
import 'package:comet_beat/features/games/note_reading/place_note_screen.dart';
import 'package:comet_beat/features/games/note_reading/read_voice_screen.dart';
import 'package:comet_beat/features/games/note_reading/spacing_read_screen.dart';
import 'package:comet_beat/features/games/note_reading/staff_runner_screen.dart';
import 'package:comet_beat/features/games/note_reading/step_skip_screen.dart';
import 'package:comet_beat/features/games/note_reading/tie_slur_screen.dart';
import 'package:comet_beat/features/games/note_reading/which_clef_screen.dart';
import 'package:comet_beat/features/games/note_reading/which_voice_screen.dart';
import 'package:comet_beat/features/games/note_reading/whole_half_screen.dart';
import 'package:comet_beat/features/games/note_values/beat_count_screen.dart';
import 'package:comet_beat/features/games/note_values/beat_sort_screen.dart';
import 'package:comet_beat/features/games/note_values/dotted_sort_screen.dart';
import 'package:comet_beat/features/games/note_values/duration_duel_screen.dart';
import 'package:comet_beat/features/games/note_values/dynamics_duel_screen.dart';
import 'package:comet_beat/features/games/note_values/note_value_quiz_screen.dart';
import 'package:comet_beat/features/games/note_values/rhythm_tap_screen.dart';
import 'package:comet_beat/features/games/note_values/tempo_duel_screen.dart';
import 'package:comet_beat/features/games/note_values/value_order_screen.dart';
import 'package:comet_beat/features/games/playalong/play_along_screen.dart';
import 'package:comet_beat/features/games/scales/command_caller_screen.dart';
import 'package:comet_beat/features/games/scales/count_notes_screen.dart';
import 'package:comet_beat/features/games/scales/direction_ear_screen.dart';
import 'package:comet_beat/features/games/scales/echo_sequence_screen.dart';
import 'package:comet_beat/features/games/scales/in_scale_screen.dart';
import 'package:comet_beat/features/games/scales/key_signature_screen.dart';
import 'package:comet_beat/features/games/scales/major_minor_ear_screen.dart';
import 'package:comet_beat/features/games/scales/run_direction_screen.dart';
import 'package:comet_beat/features/games/scales/same_diff_screen.dart';
import 'package:comet_beat/features/games/scales/scale_builder_screen.dart';
import 'package:comet_beat/features/games/scales/scale_detective_screen.dart';
import 'package:comet_beat/features/games/scales/sing_back_screen.dart';
import 'package:comet_beat/features/games/songs/song_screen.dart';
import 'package:comet_beat/features/games/songs/tune_quiz_screen.dart';
import 'package:comet_beat/features/games/transpose/concert_pitch_screen.dart';
import 'package:comet_beat/features/games/transpose/transpose_write_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/tutorial/primers.dart';
import 'package:comet_beat/shared/tutorial/tutorial.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart';

/// Every game by ID, across all modules — for curriculum/recital lookups.
final Map<String, GameInfo> kGamesById = {
  for (final games in kGamesByModule.values)
    for (final game in games) game.id: game,
};

/// The [GameInfo] for [id], or null if no such game is registered.
GameInfo? gameInfoById(String id) => kGamesById[id];

/// The module key for each game id — the inverse of [kGamesByModule].
final Map<String, String> kModuleByGameId = {
  for (final entry in kGamesByModule.entries)
    for (final game in entry.value) game.id: entry.key,
};

/// The general "how this corner works" primer for each module (its entry
/// game's), keyed like [kGamesByModule]. Used as the **fallback** help for any
/// game that has no primer of its own, so every game can offer a "?".
const Map<String, Tutorial Function(AppLocalizations)> kModulePrimers = {
  'note_values': noteValuesPrimer,
  'note_reading': readingPrimer,
  'measures': measuresPrimer,
  'scales': scalesPrimer,
  'chords': chordsPrimer,
  'harmony': harmonyPrimer,
  'composition': compositionPrimer,
  'cello': celloPrimer,
  'guitar': guitarPrimer,
  'songs': songsPrimer,
  'keyboard': keyboardPrimer,
  'transpose': transposePrimer,
  'drums': drumsPrimer,
};

/// The tutorial to open from a game's "?" help button: its own [GameInfo.tutorial]
/// if it has one, else its module's general primer. The first-run **auto-show**
/// deliberately uses only [GameInfo.tutorial] (curated to entry/★ games) so a
/// module intro doesn't re-pop on every game — but the on-demand "?" should be
/// available everywhere, which this fallback provides.
Tutorial Function(AppLocalizations)? helpPrimerFor(GameInfo game) =>
    game.tutorial ?? kModulePrimers[kModuleByGameId[game.id]];

class GameInfo {
  /// Stable ID, used for star thresholds and analytics.
  final String id;
  final IconData icon;
  final String Function(AppLocalizations) title;
  final String Function(AppLocalizations) subtitle;
  final WidgetBuilder builder;

  /// Optional advanced gate. When set and it returns `false`, the tile is
  /// locked (dimmed, with a lock icon) until the child has progressed enough
  /// in the prerequisite games. Null means always available.
  final bool Function(ProgressService)? unlockedWhen;

  /// Hint shown when [unlockedWhen] keeps the tile locked.
  final String Function(AppLocalizations)? lockedHint;

  /// Optional zero-knowledge tutorial for this game — the musical facts it
  /// drills, explained with a seen example (notation) and a heard example
  /// (audio). Shown automatically the first time the game is opened (via the
  /// [gameRoute] wrapper) and reopenable from the "?" button. Null = none yet.
  final Tutorial Function(AppLocalizations)? tutorial;

  const GameInfo({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
    this.unlockedWhen,
    this.lockedHint,
    this.tutorial,
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
      tutorial: noteValuesPrimer,
    ),
    // Read the augmentation dot — sort notes into Dotted vs Plain baskets.
    GameInfo(
      id: 'dotted_sort',
      icon: Icons.fiber_manual_record,
      title: (l) => l.gameDottedSort,
      subtitle: (l) => l.gameDottedSortSubtitle,
      builder: (_) => const DottedSortScreen(),
      tutorial: dottedNotePrimer,
    ),
    GameInfo(
      id: 'duration_duel',
      icon: Icons.compare_arrows,
      title: (l) => l.gameDurationDuel,
      subtitle: (l) => l.gameDurationDuelSubtitle,
      builder: (_) => const DurationDuelScreen(),
    ),
    // Faster or Slower? — read two Italian tempo terms, tap the faster.
    GameInfo(
      id: 'tempo_duel',
      icon: Icons.speed,
      title: (l) => l.gameTempoDuel,
      subtitle: (l) => l.gameTempoDuelSubtitle,
      builder: (_) => const TempoDuelScreen(),
      tutorial: tempoTermsPrimer,
    ),
    // Louder or Softer? — read two dynamic marks, tap the louder.
    GameInfo(
      id: 'dynamics_duel',
      icon: Icons.volume_up,
      title: (l) => l.gameDynamicsDuel,
      subtitle: (l) => l.gameDynamicsDuelSubtitle,
      builder: (_) => const DynamicsDuelScreen(),
      tutorial: dynamicsPrimer,
    ),
    // Match each dynamic mark to its meaning (pp ↔ very soft) — the Connect
    // board with a dynamics mode; the reading side of Louder or Softer?.
    GameInfo(
      id: 'connect_dynamics',
      icon: Icons.graphic_eq,
      title: (l) => l.gameConnectDynamics,
      subtitle: (l) => l.gameConnectDynamicsSubtitle,
      builder: (_) => const ConnectLineScreen(mode: ConnectMode.dynamics),
      tutorial: dynamicsPrimer,
    ),
    // Match each rest to the note it equals in length (quarter rest ↔ quarter
    // note) — the Connect board with a rests mode; reads the silent side.
    GameInfo(
      id: 'connect_rests',
      icon: Icons.hourglass_empty,
      title: (l) => l.gameConnectRests,
      subtitle: (l) => l.gameConnectRestsSubtitle,
      builder: (_) => const ConnectLineScreen(mode: ConnectMode.rests),
      tutorial: restsPrimer,
    ),
    // Match each Italian tempo word to its meaning (Largo ↔ very slow) — the
    // Connect board with a tempo mode; the reading vocabulary drill.
    GameInfo(
      id: 'connect_tempo',
      icon: Icons.speed,
      title: (l) => l.gameConnectTempo,
      subtitle: (l) => l.gameConnectTempoSubtitle,
      builder: (_) => const ConnectLineScreen(mode: ConnectMode.tempo),
      tutorial: tempoTermsPrimer,
    ),
    // Match each note value to how many beats it lasts in 4/4 (half ↔ 2 beats)
    // — the Connect board with a beats mode; core rhythm-reading.
    GameInfo(
      id: 'connect_beats',
      icon: Icons.timer_outlined,
      title: (l) => l.gameConnectBeats,
      subtitle: (l) => l.gameConnectBeatsSubtitle,
      builder: (_) => const ConnectLineScreen(mode: ConnectMode.beats),
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
    GameInfo(
      id: 'beat_sort',
      icon: Icons.drag_indicator,
      title: (l) => l.gameBeatSort,
      subtitle: (l) => l.gameBeatSortSubtitle,
      builder: (_) => const BeatSortScreen(),
    ),
    // Ordering format on note values: tap longest → shortest.
    GameInfo(
      id: 'value_order',
      icon: Icons.sort,
      title: (l) => l.gameValueOrder,
      subtitle: (l) => l.gameValueOrderSubtitle,
      builder: (_) => const ValueOrderScreen(),
    ),
    GameInfo(
      id: 'connect_symbols',
      icon: Icons.polyline,
      title: (l) => l.gameConnectSymbols,
      subtitle: (l) => l.gameConnectSymbolsSubtitle,
      builder: (_) => const ConnectLineScreen(mode: ConnectMode.symbols),
    ),
  ],
  'note_reading': [
    GameInfo(
      id: 'note_reading_treble',
      icon: Icons.music_note,
      title: (l) => l.gameNoteReadingTreble,
      subtitle: (l) => l.gameNoteReadingSubtitle,
      builder: (_) => const NoteReadingQuizScreen(clef: Clef.treble),
      tutorial: readingPrimer,
    ),
    GameInfo(
      id: 'note_reading_bass',
      icon: Icons.music_note_outlined,
      title: (l) => l.gameNoteReadingBass,
      subtitle: (l) => l.gameNoteReadingSubtitle,
      builder: (_) => const NoteReadingQuizScreen(clef: Clef.bass),
      tutorial: readingBassPrimer,
    ),
    // High/low pitch-direction sort (drag-into-baskets format).
    GameInfo(
      id: 'pitch_sort',
      icon: Icons.height,
      title: (l) => l.gamePitchSort,
      subtitle: (l) => l.gamePitchSortSubtitle,
      builder: (_) => const PitchSortScreen(),
      tutorial: directionPrimer,
    ),
    // Same sort in the bass clef — bass-clef reading practice.
    GameInfo(
      id: 'pitch_sort_bass',
      icon: Icons.height,
      title: (l) => l.gamePitchSortBass,
      subtitle: (l) => l.gamePitchSortSubtitle,
      builder: (_) => const PitchSortScreen(clef: Clef.bass),
      tutorial: directionPrimer,
    ),
    // Sharp/flat accidental-reading sort (same baskets format).
    GameInfo(
      id: 'accidental_sort',
      icon: Icons.sort_by_alpha,
      title: (l) => l.gameAccidentalSort,
      subtitle: (l) => l.gameAccidentalSortSubtitle,
      builder: (_) => const AccidentalSortScreen(),
      tutorial: accidentalsPrimer,
    ),
    // Same sharp/flat sort in the bass clef — bass-clef reading practice.
    GameInfo(
      id: 'accidental_sort_bass',
      icon: Icons.sort_by_alpha,
      title: (l) => l.gameAccidentalSortBass,
      subtitle: (l) => l.gameAccidentalSortSubtitle,
      builder: (_) => const AccidentalSortScreen(clef: Clef.bass),
      tutorial: accidentalsPrimer,
    ),
    // Step-vs-skip melodic-motion reading (before naming exact intervals).
    GameInfo(
      id: 'step_skip',
      icon: Icons.moving,
      title: (l) => l.gameStepSkip,
      subtitle: (l) => l.gameStepSkipSubtitle,
      builder: (_) => const StepSkipScreen(),
      tutorial: stepSkipPrimer,
    ),
    // Same drill in the bass clef — bass-clef reading practice.
    GameInfo(
      id: 'step_skip_bass',
      icon: Icons.moving,
      title: (l) => l.gameStepSkipBass,
      subtitle: (l) => l.gameStepSkipSubtitle,
      builder: (_) => const StepSkipScreen(clef: Clef.bass),
      tutorial: stepSkipPrimer,
    ),
    // Tie or Slur? — read the curve: same pitch (tie) vs different (slur).
    GameInfo(
      id: 'tie_slur',
      icon: Icons.link,
      title: (l) => l.gameTieSlur,
      subtitle: (l) => l.gameTieSlurSubtitle,
      builder: (_) => const TieSlurScreen(),
      tutorial: tieSlurPrimer,
    ),
    // Read the Mark — match a note's articulation glyph (staccato / accent, and
    // tenuto / marcato at 2★) to its name.
    GameInfo(
      id: 'articulation_read',
      icon: Icons.fiber_manual_record,
      title: (l) => l.gameArticulation,
      subtitle: (l) => l.gameArticulationSubtitle,
      builder: (_) => const ArticulationReadScreen(),
      tutorial: articulationPrimer,
    ),
    // Beam or Flag? — the two looks of eighth notes: joined by a beam vs each
    // keeping its flag. Same rhythm, different engraving.
    GameInfo(
      id: 'beam_flag',
      icon: Icons.horizontal_rule,
      title: (l) => l.gameBeamFlag,
      subtitle: (l) => l.gameBeamFlagSubtitle,
      builder: (_) => const BeamFlagScreen(),
      tutorial: beamPrimer,
    ),
    // Enharmonic Twins — same sound spelled two ways (F♯/G♭) or different?
    GameInfo(
      id: 'enharmonic',
      icon: Icons.swap_horiz,
      title: (l) => l.gameEnharmonic,
      subtitle: (l) => l.gameEnharmonicSubtitle,
      builder: (_) => const EnharmonicScreen(),
      tutorial: enharmonicPrimer,
    ),
    // Read the clef sign itself — Treble vs Bass (Alto/Tenor at 2★).
    GameInfo(
      id: 'which_clef',
      icon: Icons.vpn_key_outlined,
      title: (l) => l.gameWhichClef,
      subtitle: (l) => l.gameWhichClefSubtitle,
      builder: (_) => const WhichClefScreen(),
      tutorial: clefsPrimer,
    ),
    // Tone vs semitone — read a 2nd's real size (half steps hide at E–F, B–C).
    GameInfo(
      id: 'whole_half',
      icon: Icons.height,
      title: (l) => l.gameWholeHalf,
      subtitle: (l) => l.gameWholeHalfSubtitle,
      builder: (_) => const WholeHalfScreen(),
      tutorial: wholeHalfPrimer,
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
    GameInfo(
      id: 'line_space',
      icon: Icons.swipe,
      title: (l) => l.gameLineSpace,
      subtitle: (l) => l.gameLineSpaceSubtitle,
      builder: (_) => const LineSpaceScreen(),
    ),
    GameInfo(
      id: 'falling_notes',
      icon: Icons.bolt,
      title: (l) => l.gameFallingNotes,
      subtitle: (l) => l.gameFallingNotesSubtitle,
      builder: (_) => const FallingNotesScreen(),
    ),
    GameInfo(
      id: 'connect_line',
      icon: Icons.polyline,
      title: (l) => l.gameConnectLine,
      subtitle: (l) => l.gameConnectLineSubtitle,
      builder: (_) => const ConnectLineScreen(),
    ),
    GameInfo(
      id: 'ledger_leap',
      icon: Icons.stacked_line_chart,
      title: (l) => l.gameLedgerLeap,
      subtitle: (l) => l.gameLedgerLeapSubtitle,
      builder: (_) => const LedgerLeapScreen(),
      tutorial: ledgerPrimer,
    ),
    GameInfo(
      id: 'odd_one_out',
      icon: Icons.filter_2,
      title: (l) => l.gameOddOneOut,
      subtitle: (l) => l.gameOddOneOutSubtitle,
      builder: (_) => const OddOneOutScreen(),
    ),
    GameInfo(
      id: 'note_whack',
      icon: Icons.sports_kabaddi,
      title: (l) => l.gameNoteWhack,
      subtitle: (l) => l.gameNoteWhackSubtitle,
      builder: (_) => const NoteWhackScreen(),
    ),
    GameInfo(
      id: 'staff_runner',
      icon: Icons.directions_run,
      title: (l) => l.gameStaffRunner,
      subtitle: (l) => l.gameStaffRunnerSubtitle,
      builder: (_) => const StaffRunnerScreen(),
    ),
    GameInfo(
      id: 'perform_read',
      icon: Icons.mic,
      title: (l) => l.gamePerformIt,
      subtitle: (l) => l.gamePerformItSubtitle,
      builder: (_) => const PerformItScreen(),
    ),
    GameInfo(
      id: 'note_snake',
      icon: Icons.gesture,
      title: (l) => l.gameNoteSnake,
      subtitle: (l) => l.gameNoteSnakeSubtitle,
      builder: (_) => const NoteSnakeScreen(),
    ),
    GameInfo(
      id: 'duet',
      icon: Icons.splitscreen,
      title: (l) => l.gameDuet,
      subtitle: (l) => l.gameDuetSubtitle,
      builder: (_) => const DuetScreen(),
      tutorial: voicesPrimer,
    ),
    // Read one voice out of a chord (2 voices → SATB). Advanced: builds on Duet.
    GameInfo(
      id: 'read_voice',
      icon: Icons.groups,
      title: (l) => l.gameReadVoice,
      subtitle: (l) => l.gameReadVoiceSubtitle,
      builder: (_) => const ReadVoiceScreen(),
      unlockedWhen: (p) => p.starsFor('duet') >= 2,
      lockedHint: (l) => l.advancedGameHint,
      tutorial: voicesPrimer,
    ),
    // Inverse of Read the Voice: which voice is the highlighted note?
    GameInfo(
      id: 'which_voice',
      icon: Icons.record_voice_over,
      title: (l) => l.gameWhichVoice,
      subtitle: (l) => l.gameWhichVoiceSubtitle,
      builder: (_) => const WhichVoiceScreen(),
      unlockedWhen: (p) => p.starsFor('duet') >= 2,
      lockedHint: (l) => l.advancedGameHint,
      tutorial: voicesPrimer,
    ),
    // Aural SATB: hear the chord then one voice — which voice was it?
    GameInfo(
      id: 'hear_voice',
      icon: Icons.hearing,
      title: (l) => l.gameHearVoice,
      subtitle: (l) => l.gameHearVoiceSubtitle,
      builder: (_) => const HearVoiceScreen(),
      unlockedWhen: (p) => p.starsFor('duet') >= 2,
      lockedHint: (l) => l.advancedGameHint,
      tutorial: voicesPrimer,
    ),
    // Read SATB spacing: are the upper voices close or open position?
    GameInfo(
      id: 'spacing_read',
      icon: Icons.unfold_more,
      title: (l) => l.gameSpacingRead,
      subtitle: (l) => l.gameSpacingReadSubtitle,
      builder: (_) => const SpacingReadScreen(),
      tutorial: spacingPrimer,
      unlockedWhen: (p) => p.starsFor('duet') >= 2,
      lockedHint: (l) => l.advancedGameHint,
    ),
    // Bass-clef variants of the reading games (violin/treble + bass).
    GameInfo(
      id: 'line_space_bass',
      icon: Icons.swipe,
      title: (l) => '${l.gameLineSpace} — ${l.clefBass}',
      subtitle: (l) => l.gameLineSpaceSubtitle,
      builder: (_) => const LineSpaceScreen(clef: Clef.bass),
      tutorial: readingBassPrimer,
    ),
    GameInfo(
      id: 'note_order_bass',
      icon: Icons.sort,
      title: (l) => '${l.gameNoteOrder} — ${l.clefBass}',
      subtitle: (l) => l.gameNoteOrderSubtitle,
      builder: (_) => const NoteOrderScreen(clef: Clef.bass),
      tutorial: readingBassPrimer,
    ),
    GameInfo(
      id: 'falling_notes_bass',
      icon: Icons.bolt,
      title: (l) => '${l.gameFallingNotes} — ${l.clefBass}',
      subtitle: (l) => l.gameFallingNotesSubtitle,
      builder: (_) => const FallingNotesScreen(clef: Clef.bass),
      tutorial: readingBassPrimer,
    ),
    GameInfo(
      id: 'connect_line_bass',
      icon: Icons.polyline,
      title: (l) => '${l.gameConnectLine} — ${l.clefBass}',
      subtitle: (l) => l.gameConnectLineSubtitle,
      builder: (_) => const ConnectLineScreen(clef: Clef.bass),
      tutorial: readingBassPrimer,
    ),
    GameInfo(
      id: 'odd_one_out_bass',
      icon: Icons.filter_2,
      title: (l) => '${l.gameOddOneOut} — ${l.clefBass}',
      subtitle: (l) => l.gameOddOneOutSubtitle,
      builder: (_) => const OddOneOutScreen(clef: Clef.bass),
      tutorial: readingBassPrimer,
    ),
    GameInfo(
      id: 'note_whack_bass',
      icon: Icons.sports_kabaddi,
      title: (l) => '${l.gameNoteWhack} — ${l.clefBass}',
      subtitle: (l) => l.gameNoteWhackSubtitle,
      builder: (_) => const NoteWhackScreen(clef: Clef.bass),
      tutorial: readingBassPrimer,
    ),
    GameInfo(
      id: 'staff_runner_bass',
      icon: Icons.directions_run,
      title: (l) => '${l.gameStaffRunner} — ${l.clefBass}',
      subtitle: (l) => l.gameStaffRunnerSubtitle,
      builder: (_) => const StaffRunnerScreen(clef: Clef.bass),
      tutorial: readingBassPrimer,
    ),
    GameInfo(
      id: 'note_snake_bass',
      icon: Icons.gesture,
      title: (l) => '${l.gameNoteSnake} — ${l.clefBass}',
      subtitle: (l) => l.gameNoteSnakeSubtitle,
      builder: (_) => const NoteSnakeScreen(clef: Clef.bass),
      tutorial: readingBassPrimer,
    ),
  ],
  'measures': [
    GameInfo(
      id: 'measure_fill',
      icon: Icons.check_box_outline_blank,
      title: (l) => l.gameMeasureFill,
      subtitle: (l) => l.gameMeasureFillSubtitle,
      builder: (_) => const MeasureFillScreen(),
      tutorial: measuresPrimer,
    ),
    GameInfo(
      id: 'meter_detective',
      icon: Icons.hearing,
      title: (l) => l.gameMeterDetective,
      subtitle: (l) => l.gameMeterDetectiveSubtitle,
      builder: (_) => const MeterDetectiveScreen(),
    ),
    GameInfo(
      id: 'beat_runner',
      icon: Icons.sports_esports,
      title: (l) => l.gameBeatRunner,
      subtitle: (l) => l.gameBeatRunnerSubtitle,
      builder: (_) => const BeatRunnerScreen(),
    ),
    GameInfo(
      id: 'charades',
      icon: Icons.speed,
      title: (l) => l.gameCharades,
      subtitle: (l) => l.gameCharadesSubtitle,
      builder: (_) => const CharadesScreen(),
    ),
    GameInfo(
      id: 'which_beat',
      icon: Icons.pin,
      title: (l) => l.gameWhichBeat,
      subtitle: (l) => l.gameWhichBeatSubtitle,
      builder: (_) => const WhichBeatScreen(),
    ),
    // Metric-accent training — strong vs weak beats via crisp_notation's beatStrength.
    GameInfo(
      id: 'strong_beat',
      icon: Icons.graphic_eq,
      title: (l) => l.gameStrongBeat,
      subtitle: (l) => l.gameStrongBeatSubtitle,
      builder: (_) => const StrongBeatScreen(),
      tutorial: strongBeatPrimer,
    ),
    GameInfo(
      id: 'time_signature',
      icon: Icons.timer_outlined,
      title: (l) => l.gameTimeSignature,
      subtitle: (l) => l.gameTimeSignatureSubtitle,
      builder: (_) => const TimeSignatureScreen(),
      tutorial: timeSignaturePrimer,
    ),
    // Spot the Upbeat — read whether a tune starts on the downbeat or with a
    // pickup (anacrusis); the incomplete first measure is the cue.
    GameInfo(
      id: 'spot_upbeat',
      icon: Icons.call_made,
      title: (l) => l.gameSpotUpbeat,
      subtitle: (l) => l.gameSpotUpbeatSubtitle,
      builder: (_) => const SpotUpbeatScreen(),
      tutorial: upbeatPrimer,
    ),
  ],
  'scales': [
    GameInfo(
      id: 'scale_detective',
      icon: Icons.search,
      title: (l) => l.gameScaleDetective,
      subtitle: (l) => l.gameScaleDetectiveSubtitle,
      builder: (_) => const ScaleDetectiveScreen(),
      tutorial: scalesPrimer,
    ),
    // Swipe drill: is this note in the C major scale?
    GameInfo(
      id: 'in_scale',
      icon: Icons.rule,
      title: (l) => l.gameInScale,
      subtitle: (l) => l.gameInScaleSubtitle,
      builder: (_) => const InScaleScreen(),
    ),
    GameInfo(
      id: 'major_minor_ear',
      icon: Icons.hearing,
      title: (l) => l.gameMajorMinorEar,
      subtitle: (l) => l.gameMajorMinorEarSubtitle,
      builder: (_) => const MajorMinorEarScreen(),
    ),
    // Melodic-direction ear game (aural twin of the High or Low? sort).
    GameInfo(
      id: 'direction_ear',
      icon: Icons.swap_vert,
      title: (l) => l.gameDirectionEar,
      subtitle: (l) => l.gameDirectionEarSubtitle,
      builder: (_) => const DirectionEarScreen(),
      tutorial: directionPrimer,
    ),
    // Same-or-different pitch discrimination — the youngest ear skill.
    GameInfo(
      id: 'same_diff',
      icon: Icons.compare_arrows,
      title: (l) => l.gameSameDiff,
      subtitle: (l) => l.gameSameDiffSubtitle,
      builder: (_) => const SameDiffScreen(),
      tutorial: sameDiffPrimer,
    ),
    // Direction of a short run — a step past Higher or Lower? (more notes).
    GameInfo(
      id: 'run_direction',
      icon: Icons.show_chart,
      title: (l) => l.gameRunDirection,
      subtitle: (l) => l.gameRunDirectionSubtitle,
      builder: (_) => const RunDirectionScreen(),
      tutorial: directionPrimer,
    ),
    // Count the notes — aural attention: how many notes did you just hear?
    GameInfo(
      id: 'count_notes',
      icon: Icons.filter_2,
      title: (l) => l.gameCountNotes,
      subtitle: (l) => l.gameCountNotesSubtitle,
      builder: (_) => const CountNotesScreen(),
      tutorial: countNotesPrimer,
    ),
    GameInfo(
      id: 'sing_back',
      icon: Icons.record_voice_over,
      title: (l) => l.gameSingBack,
      subtitle: (l) => l.gameSingBackSubtitle,
      builder: (_) => const SingBackScreen(),
    ),
    GameInfo(
      id: 'scale_builder',
      icon: Icons.construction,
      title: (l) => l.gameScaleBuilder,
      subtitle: (l) => l.gameScaleBuilderSubtitle,
      builder: (_) => const ScaleBuilderScreen(),
    ),
    GameInfo(
      id: 'echo_sequence',
      icon: Icons.touch_app,
      title: (l) => l.gameEchoSequence,
      subtitle: (l) => l.gameEchoSequenceSubtitle,
      builder: (_) => const EchoSequenceScreen(),
    ),
    GameInfo(
      id: 'command_caller',
      icon: Icons.gesture,
      title: (l) => l.gameCommandCaller,
      subtitle: (l) => l.gameCommandCallerSubtitle,
      builder: (_) => const CommandCallerScreen(),
    ),
    GameInfo(
      id: 'key_sig',
      icon: Icons.vpn_key,
      title: (l) => l.gameKeySignature,
      subtitle: (l) => l.gameKeySignatureSubtitle,
      builder: (_) => const KeySignatureScreen(),
      tutorial: keySignaturePrimer,
    ),
  ],
  'chords': [
    // Fuzzy chord recognition from the live mic.
    GameInfo(
      id: 'chord_listen_spike',
      icon: Icons.hearing,
      title: (l) => l.gameChordListener,
      subtitle: (l) => l.gameChordListenerSubtitle,
      builder: (_) => const ChordListenSpikeScreen(),
    ),
    // Chord-progression play-along with a moving chart.
    GameInfo(
      id: 'chord_play_along',
      icon: Icons.moving,
      title: (l) => l.gameChordProgression,
      subtitle: (l) => l.gameChordProgressionSubtitle,
      builder: (ctx) => ChordProgressionScreen(
        chart: ChordCharts.popTurnaround,
        title: AppLocalizations.of(ctx)!.gameChordProgression,
        gameId: 'chord_play_along',
      ),
    ),
    GameInfo(
      id: 'chord_quiz',
      icon: Icons.library_music,
      title: (l) => l.gameChordQuiz,
      subtitle: (l) => l.gameChordQuizSubtitle,
      builder: (_) => const ChordQuizScreen(),
    ),
    // Major or Minor? — read the triad's quality and sort it into a basket
    // (Diminished joins at 2★). The reading twin of the aural Dur oder Moll?.
    GameInfo(
      id: 'major_minor_sort',
      icon: Icons.sort,
      title: (l) => l.gameMajorMinorSort,
      subtitle: (l) => l.gameMajorMinorSortSubtitle,
      builder: (_) => const MajorMinorSortScreen(),
      tutorial: chordsPrimer,
    ),
    GameInfo(
      id: 'triad_builder',
      icon: Icons.construction,
      title: (l) => l.gameTriadBuilder,
      subtitle: (l) => l.gameTriadBuilderSubtitle,
      builder: (_) => const TriadBuilderScreen(),
      tutorial: chordsPrimer,
    ),
    GameInfo(
      id: 'interval_ear',
      icon: Icons.hearing,
      title: (l) => l.gameIntervalEar,
      subtitle: (l) => l.gameIntervalEarSubtitle,
      builder: (_) => const IntervalEarScreen(),
      tutorial: intervalsPrimer,
    ),
    // Sing the Interval — hear an interval, sing the top note back (mic-graded,
    // octave-agnostic). The sung twin of Interval Ear.
    GameInfo(
      id: 'sing_interval',
      icon: Icons.mic,
      title: (l) => l.gameSingInterval,
      subtitle: (l) => l.gameSingIntervalSubtitle,
      builder: (_) => const SingIntervalScreen(),
      tutorial: intervalsPrimer,
    ),
    // Triad or Seventh? — hear a major triad vs a dominant-7 (triad + a minor
    // 7th), tap which; trains the ear to notice the added seventh.
    GameInfo(
      id: 'triad_seventh',
      icon: Icons.hearing,
      title: (l) => l.gameTriadSeventh,
      subtitle: (l) => l.gameTriadSeventhSubtitle,
      builder: (_) => const TriadSeventhScreen(),
    ),
    GameInfo(
      id: 'interval_ladder',
      icon: Icons.stairs,
      title: (l) => l.gameIntervalLadder,
      subtitle: (l) => l.gameIntervalLadderSubtitle,
      builder: (_) => const IntervalLadderScreen(),
    ),
    // Count-the-note-names interval drill, connect-a-line format (reuses the
    // Connect the Notes board with a third mode).
    GameInfo(
      id: 'connect_intervals',
      icon: Icons.straighten,
      title: (l) => l.gameConnectIntervals,
      subtitle: (l) => l.gameConnectIntervalsSubtitle,
      builder: (_) => const ConnectLineScreen(mode: ConnectMode.intervals),
    ),
    GameInfo(
      id: 'name_that_chord',
      icon: Icons.abc,
      title: (l) => l.gameNameThatChord,
      subtitle: (l) => l.gameNameThatChordSubtitle,
      builder: (_) => const NameThatChordScreen(),
    ),
    // Lead-sheet reading: symbol → notation (inverse of Name That Chord).
    GameInfo(
      id: 'chord_chart',
      icon: Icons.grid_view,
      title: (l) => l.gameChordChart,
      subtitle: (l) => l.gameChordChartSubtitle,
      builder: (_) => const ChordChartScreen(),
      tutorial: chordChartPrimer,
    ),
    GameInfo(
      id: 'chord_builder',
      icon: Icons.construction,
      title: (l) => l.gameChordBuilder,
      subtitle: (l) => l.gameChordBuilderSubtitle,
      builder: (_) => const ChordBuilderScreen(),
    ),
  ],
  'harmony': [
    GameInfo(
      id: 'harmony_quiz',
      icon: Icons.auto_awesome,
      title: (l) => l.gameHarmonyQuiz,
      subtitle: (l) => l.gameHarmonyQuizSubtitle,
      builder: (_) => const HarmonyQuizScreen(),
      tutorial: harmonyPrimer,
    ),
    // Roman numerals — every diatonic degree, named by crisp_notation's analyser.
    GameInfo(
      id: 'roman_numeral',
      icon: Icons.stairs,
      title: (l) => l.gameRomanNumeral,
      subtitle: (l) => l.gameRomanNumeralSubtitle,
      builder: (_) => const RomanNumeralScreen(),
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
    // Free Sing — sing any tune, hear it back on the synth (a creative toy).
    GameInfo(
      id: 'free_sing',
      icon: Icons.graphic_eq,
      title: (l) => l.gameFreeSing,
      subtitle: (l) => l.gameFreeSingSubtitle,
      builder: (_) => const FreeSingScreen(),
      tutorial: compositionPrimer,
    ),
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
    // Colour-grid composing for pre-readers — tap coloured cells (a consonant
    // pentatonic) that render to a real Score. A sandbox, no stars.
    GameInfo(
      id: 'grid_composer',
      icon: Icons.grid_on,
      title: (l) => l.gameGridComposer,
      subtitle: (l) => l.gameGridComposerSubtitle,
      builder: (_) => const GridComposerScreen(),
    ),
    // Its gesture twin — draw a contour, it quantises to the same C-pentatonic
    // beats and renders to a real Score. A sandbox, no stars.
    GameInfo(
      id: 'melody_doodle',
      icon: Icons.gesture,
      title: (l) => l.gameMelodyDoodle,
      subtitle: (l) => l.gameMelodyDoodleSubtitle,
      builder: (_) => const MelodyDoodleScreen(),
    ),
    // Loop-mixer toy — cards layer synced 2-bar loops (drums/bass/chords/
    // melody/sparkle, all C-pentatonic so any combo grooves). A sandbox,
    // no stars.
    GameInfo(
      id: 'loop_mixer',
      icon: Icons.queue_music,
      title: (l) => l.gameLoopMixer,
      subtitle: (l) => l.gameLoopMixerSubtitle,
      builder: (_) => const LoopMixerScreen(),
    ),
    // Touch-first pattern sequencer (a kid-friendly tracker): pick an
    // instrument, tap a pentatonic grid, layers loop together. A sandbox,
    // no stars.
    GameInfo(
      id: 'tracker',
      icon: Icons.grid_view,
      title: (l) => l.gameTracker,
      subtitle: (l) => l.gameTrackerSubtitle,
      builder: (_) => const TrackerScreen(),
    ),
  ],
  'cello': [
    // Live-mic tuner.
    GameInfo(
      id: 'cello_tuner',
      icon: Icons.graphic_eq,
      title: (l) => l.gameTuner,
      subtitle: (l) => l.gameTunerSubtitle,
      builder: (_) => const TunerSpikeScreen(),
      tutorial: celloPrimer,
    ),
    // Play-along with a moving score.
    GameInfo(
      id: 'cello_play_along',
      icon: Icons.moving,
      title: (l) => l.gamePlayAlong,
      subtitle: (l) => l.gamePlayAlongSubtitle,
      builder: (ctx) => PlayAlongScreen(
        chart: PlayAlongCharts.celloFirstPosition,
        title: AppLocalizations.of(ctx)!.gamePlayAlong,
        gameId: 'cello_play_along',
        sriPrefix: 'cello.play_along',
      ),
    ),
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
    // Mic grading on the real cello: play the shown first-position note.
    GameInfo(
      id: 'cello_play_it',
      icon: Icons.mic,
      title: (l) => l.gameCelloPlayIt,
      subtitle: (l) => l.gameCelloPlayItSubtitle,
      builder: (_) => const CelloPlayItScreen(),
    ),
    GameInfo(
      id: 'bowing',
      icon: Icons.gesture,
      title: (l) => l.gameBowing,
      subtitle: (l) => l.gameBowingSubtitle,
      builder: (_) => const BowingScreen(),
    ),
    GameInfo(
      id: 'note_reading_tenor',
      icon: Icons.music_note,
      title: (l) => l.gameNoteReadingTenor,
      subtitle: (l) => l.gameNoteReadingSubtitle,
      builder: (_) => const NoteReadingQuizScreen(clef: Clef.tenor),
      // Tenor clef is advanced for a young cellist — open it only once the
      // string and finger basics are solid (upper levels only).
      unlockedWhen: (p) =>
          p.starsFor('cello_string_quiz') >= 2 &&
          p.starsFor('cello_finger_quiz') >= 2,
      lockedHint: (l) => l.advancedGameHint,
    ),
  ],
  'guitar': [
    // Play-along riff with a moving score.
    GameInfo(
      id: 'guitar_play_along',
      icon: Icons.moving,
      title: (l) => l.gamePlayAlong,
      subtitle: (l) => l.gamePlayAlongGuitarSubtitle,
      builder: (ctx) => PlayAlongScreen(
        chart: PlayAlongCharts.guitarRiff,
        title: AppLocalizations.of(ctx)!.gamePlayAlong,
        gameId: 'guitar_play_along',
        sriPrefix: 'guitar.play_along',
      ),
      tutorial: guitarPrimer,
    ),
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
    GameInfo(
      id: 'strum_toy',
      icon: Icons.music_note,
      title: (l) => l.gameStrumToy,
      subtitle: (l) => l.gameStrumToySubtitle,
      builder: (_) => const StrumToyScreen(),
    ),
  ],
  'songs': [
    GameInfo(
      id: 'song_book',
      icon: Icons.menu_book,
      title: (l) => l.gameSongBook,
      subtitle: (l) => l.gameSongBookSubtitle,
      builder: (_) => const SongListScreen(),
      tutorial: songsPrimer,
    ),
    // Sing-along with a moving score (octave-agnostic).
    GameInfo(
      id: 'sing_along',
      icon: Icons.mic_external_on,
      title: (l) => l.gameSingAlong,
      subtitle: (l) => l.gameSingAlongSubtitle,
      builder: (ctx) => PlayAlongScreen(
        chart: PlayAlongCharts.twinkleSing,
        title: AppLocalizations.of(ctx)!.gameSingAlong,
        gameId: 'sing_along',
        sriPrefix: 'voice.sing_along',
      ),
    ),
    // Sing-along: Mary Had a Little Lamb.
    GameInfo(
      id: 'sing_mary',
      icon: Icons.mic_external_on,
      title: (l) => l.gameMaryLamb,
      subtitle: (l) => l.gameSingAlongSubtitle,
      builder: (ctx) => PlayAlongScreen(
        chart: PlayAlongCharts.marySing,
        title: AppLocalizations.of(ctx)!.gameMaryLamb,
        gameId: 'sing_mary',
        sriPrefix: 'voice.sing_along',
      ),
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
    // Play-along scale with a moving score.
    GameInfo(
      id: 'keyboard_play_along',
      icon: Icons.moving,
      title: (l) => l.gamePlayAlong,
      subtitle: (l) => l.gamePlayAlongKeyboardSubtitle,
      builder: (ctx) => PlayAlongScreen(
        chart: PlayAlongCharts.keyboardScale,
        title: AppLocalizations.of(ctx)!.gamePlayAlong,
        gameId: 'keyboard_play_along',
        sriPrefix: 'keyboard.play_along',
      ),
      tutorial: keyboardPrimer,
    ),
    // Ode to Joy — a real tune to play along on the keys.
    GameInfo(
      id: 'keyboard_ode',
      icon: Icons.piano,
      title: (l) => l.gameOdeToJoy,
      subtitle: (l) => l.gamePlayAlongKeyboardSubtitle,
      builder: (ctx) => PlayAlongScreen(
        chart: PlayAlongCharts.odeToJoy,
        title: AppLocalizations.of(ctx)!.gameOdeToJoy,
        gameId: 'keyboard_ode',
        sriPrefix: 'keyboard.play_along',
      ),
    ),
    GameInfo(
      id: 'key_find',
      icon: Icons.piano,
      title: (l) => l.gameKeyFind,
      subtitle: (l) => l.gameKeyFindSubtitle,
      builder: (_) => const KeyFindScreen(),
    ),
    // Same bridge, bass clef: the keyboard drops two octaves so the low staff
    // notes (G2..A3) land on real keys. Own progress id.
    GameInfo(
      id: 'key_find_bass',
      icon: Icons.piano,
      title: (l) => l.gameKeyFindBass,
      subtitle: (l) => l.gameKeyFindSubtitle,
      builder: (_) => const KeyFindScreen(clef: Clef.bass),
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
    GameInfo(
      id: 'falling_keys',
      icon: Icons.bolt,
      title: (l) => l.gameFallingKeys,
      subtitle: (l) => l.gameFallingKeysSubtitle,
      builder: (_) => const FallingNotesScreen(mode: FallingMode.play),
    ),
    GameInfo(
      id: 'chord_grip_hero',
      icon: Icons.piano,
      title: (l) => l.gameChordGripHero,
      subtitle: (l) => l.gameChordGripHeroSubtitle,
      builder: (_) => const ChordGripHeroScreen(),
    ),
  ],
  'transpose': [
    GameInfo(
      id: 'concert_pitch',
      icon: Icons.swap_vert,
      title: (l) => l.gameConcertPitch,
      subtitle: (l) => l.gameConcertPitchSubtitle,
      builder: (_) => const ConcertPitchScreen(),
      tutorial: transposePrimer,
    ),
    // The inverse of Concert Pitch: name the note the instrument must read to
    // sound a given concert pitch.
    GameInfo(
      id: 'transpose_write',
      icon: Icons.edit_note,
      title: (l) => l.gameTransposeWrite,
      subtitle: (l) => l.gameTransposeWriteSubtitle,
      builder: (_) => const TransposeWriteScreen(),
      tutorial: transposePrimer,
    ),
  ],
  'drums': [
    GameInfo(
      id: 'drum_read',
      icon: Icons.album,
      title: (l) => l.gameDrumRead,
      subtitle: (l) => l.gameDrumReadSubtitle,
      builder: (_) => const DrumReadScreen(),
      tutorial: drumsPrimer,
    ),
  ],
};
