// lib/core/tuning.dart
//
// Centralized tuning constants for the progression / mastery / SRI systems.
// Mirrors the conventions of space_math_academy and voc so behavior is
// consistent across the app family. Everything here is A/B-testable:
// changing a value here should change behavior across the whole app.

/// Number of consecutive wins at the current level required before the
/// player advances to the next one.
const int kWinsRequiredForLevelUp = 3;

/// A locked module unlocks once the previous module (registry order) has
/// at least this many SRI-tracked items — i.e. the child has genuinely
/// played there. Soft engagement gate, not a mastery gate (docs/PLAN.md).
const int kModuleUnlockTracked = 6;

/// Default pass threshold (0.0 to 1.0) for ratio-based outcomes.
const double kDefaultPassThreshold = 0.7;

/// Minimum attempts at a (skill, difficulty) pair before we trust the
/// success ratio enough to claim mastery.
const int kMinAttemptsForMastery = 5;

// --- SM-2 spaced repetition constants ---
//
// Standard SM-2 (Piotr Wozniak, 1990). The defaults below reproduce the
// classic algorithm; identical to the values used in space_math_academy.

/// Starting easiness factor for a newly-introduced item. SM-2 default.
const double kSm2InitialEasiness = 2.5;

/// Floor on the easiness factor — anything below this means the item
/// is treated as "very hard" and reviewed frequently.
const double kSm2MinimumEasiness = 1.3;

/// Easiness above this threshold (plus enough repetitions) marks an item
/// as mastered.
const double kSm2MasteryEasinessThreshold = 4.0;

/// Repetitions required before mastery can even be considered.
const int kSm2MinimumRepetitionsForMastery = 3;

/// Max number of failure events tolerated when claiming mastery.
const int kSm2MaxFailuresForMastery = 1;

// --- Star rating normalization ---
//
// Per-game expected-score brackets, format: gameType: [1-star, 2-star, 3-star
// minimum score]. Populated as minigames are implemented.
const Map<String, List<int>> kStarThresholds = {
  // 10 rounds x 100 points, first-try answers only.
  'note_value_quiz': [100, 600, 900],
  'duration_duel': [100, 600, 900],
  'tempo_duel': [100, 600, 900],
  'dynamics_duel': [100, 600, 900],
  'note_reading_quiz': [100, 600, 900],
  'place_note': [100, 600, 900],
  'measure_fill': [100, 600, 900],
  // 8 rounds: max 800.
  'scale_detective': [100, 500, 750],
  // In the Scale? (scale membership swipe): 10 rounds x 100.
  'in_scale': [100, 600, 900],
  'chord_quiz': [100, 600, 900],
  'harmony_quiz': [100, 600, 900],
  // Roman Numerals: 10 rounds × 100; clean run tops near 1000.
  'roman_numeral': [100, 600, 900],
  // Spot the Parallels: 10 rounds × 100 (binary clean/parallel).
  'spot_parallels': [100, 600, 900],
  'major_minor_ear': [100, 600, 900],
  // Which Mode? (Major / Minor / Dorian ear game): 10 rounds x 100.
  'mode_ear': [100, 600, 900],
  // Key Change? (modulation ear): 10 rounds x 100.
  'modulation_ear': [100, 600, 900],
  // Triad or Seventh? (hear the added 7th): 10 rounds x 100.
  'triad_seventh': [100, 600, 900],
  // Higher or Lower? (melodic-direction ear): 10 rounds x 100.
  'direction_ear': [100, 600, 900],
  'same_diff': [100, 600, 900],
  'run_direction': [100, 600, 900],
  'count_notes': [100, 600, 900],
  'function_ear': [100, 600, 900],
  'interval_ear': [100, 600, 900],
  // 8 rounds: max 800.
  'triad_builder': [100, 500, 750],
  'rhythm_tap': [100, 500, 750],
  // 6 rounds: max 600.
  'scale_builder': [100, 400, 550],
  // 4 rounds: max 400.
  'cadence_workshop': [100, 300, 400],
  'beat_count': [100, 600, 900],
  'beat_sort': [100, 400, 550],
  // 8 rounds: max 800.
  'meter_detective': [100, 500, 750],
  'melody_echo': [100, 500, 750],
  'melody_dictation': [100, 500, 750],
  // Note Match (6 pairs): 600 flawless; fewer moves = more stars.
  'note_memory': [100, 450, 560],
  'note_order': [100, 600, 900],
  // Longest First (order note values by length): 8 rounds x 100.
  'value_order': [100, 600, 900],
  'dynamics_order': [100, 600, 900],
  'tempo_order': [100, 600, 900],
  // Odd One Out: 8 rounds x 100, max 800; 3 stars rewards a flawless run.
  'odd_one_out': [100, 500, 800],
  // Note Whack: 12 whacks x 10 x combo multiplier (1..5); a flawless combo run
  // tops out near 300. 3 stars rewards clean, wrong-free whacking.
  'note_whack': [80, 200, 300],
  // Dynamics & Tempo Charades: 10 rounds x 100.
  'charades': [100, 600, 900],
  // Interval Ladder: 8 rounds x 100, max 800.
  'interval_ladder': [100, 500, 800],
  // Staff Runner: endless; score = notes read before three misses.
  'staff_runner': [6, 15, 25],
  // Chord Grip Hero: 10 chords; score = chords fully gripped.
  'chord_grip_hero': [3, 7, 10],
  // Note Snake: endless; score = notes eaten before a wrong bite.
  'note_snake': [3, 8, 15],
  // Name That Chord: 10 rounds x 100.
  'name_that_chord': [100, 600, 900],
  // Chord Chart (symbol → notation): 10 rounds x 100.
  'chord_chart': [100, 600, 900],
  // Chord Builder: 8 rounds x 100, max 800.
  'chord_builder': [100, 500, 800],
  // Major or Minor? (triad-quality sort): 6 rounds x 100.
  'major_minor_sort': [100, 400, 550],
  // Concert Pitch (transposing instruments): 10 rounds x 100.
  'concert_pitch': [100, 600, 900],
  // Write It for the Instrument (inverse: concert → written): 10 rounds x 100.
  'transpose_write': [100, 600, 900],
  // Bowing (string up/down-bow): 10 rounds x 100.
  'bowing': [100, 600, 900],
  // Which Beat? (rhythmic placement): 10 rounds x 100.
  'which_beat': [100, 600, 900],
  // Strong Beat? (metric accent, strong/weak): 10 rounds x 100.
  'strong_beat': [100, 600, 900],
  // Time Signatures (read C/cut/numeric): 10 rounds x 100.
  'time_signature': [100, 600, 900],
  // Duet (read the highlighted part of a two-staff system): 10 rounds x 100.
  'duet': [100, 600, 900],
  // Read the Voice (SATB voice reading): 10 rounds x 100.
  'read_voice': [100, 600, 900],
  // Which Voice? (identify S/A/T/B of a highlighted note): 10 rounds x 100.
  'which_voice': [100, 600, 900],
  // Hear the Voice (aural: identify the voice played alone): 10 rounds x 100.
  'hear_voice': [100, 600, 900],
  // Close or Open? (read SATB spacing): 10 rounds x 100.
  'spacing_read': [100, 600, 900],
  // Perform It (mic-graded reading): 8 notes x 10 performed; skips score 0.
  'perform_read': [30, 60, 80],
  // Sing Back (ear→voice): 8 notes x 10 sung back; skips score 0.
  'sing_back': [30, 60, 80],
  // Sing the Interval (ear→voice, mic-graded): 8 intervals x 10; skips score 0.
  'sing_interval': [30, 60, 80],
  // Cello Play It (mic-graded on the real cello): 8 notes x 10; skips score 0.
  'cello_play_it': [30, 60, 80],
  // Drum Read: ~12 notes x 10-20 (Perfect/Good); a clean run tops out near 200.
  'drum_read': [60, 140, 200],
  'line_space': [100, 600, 900],
  // High or Low? (pitch-direction sort): 6 rounds x 100, max 600.
  'pitch_sort': [100, 400, 550],
  // Sharp or Flat? (accidental-sign sort): 6 rounds x 100, max 600.
  'accidental_sort': [100, 400, 550],
  'dotted_sort': [100, 400, 550],
  // Step or Skip? (melodic-motion reading): 10 rounds x 100.
  'step_skip': [100, 600, 900],
  'tie_slur': [100, 600, 900],
  'sync_read': [100, 600, 900],
  'triplet_read': [100, 600, 900],
  'ornament_read': [100, 600, 900],
  'form_read': [100, 600, 900],
  // Enharmonic Twins (same-sound spelling vs different): 10 rounds x 100.
  'enharmonic': [100, 600, 900],
  // Read the Mark (articulation reading): 10 rounds x 100.
  'articulation_read': [100, 600, 900],
  // Beam or Flag? (beamed vs flagged eighths): 10 rounds x 100.
  'beam_flag': [100, 600, 900],
  // Spot the Upbeat (downbeat vs anacrusis reading): 10 rounds x 100.
  'spot_upbeat': [100, 600, 900],
  'which_clef': [100, 600, 900],
  'whole_half': [100, 600, 900],
  // Falling Notes: 15 notes, points = 10 x combo multiplier (1..5). A flawless
  // combo run tops out near 450; 3 stars rewards a near-perfect streak.
  'falling_notes': [50, 250, 400],
  // Falling Keys: same arcade engine, tapped on the piano.
  'falling_keys': [50, 250, 400],
  // Connect the Notes: 6 rounds x 100, max 600.
  'connect_line': [100, 400, 550],
  // Ledger Leap: 10 rounds x 100.
  'ledger_leap': [100, 600, 900],
  // Key Signature Detective: 10 rounds x 100.
  'key_sig': [100, 600, 900],
  // Echo Sequence: score = 100 × longest sequence echoed.
  'echo_sequence': [100, 400, 700],
  // Follow the Conductor (conducting patterns): 26 beats, Perfect 20 / Good 10.
  'command_caller': [120, 300, 460],
  // Beat Runner (rhythm patterns): ~14-22 notes, Perfect 20 / Good 10.
  'beat_runner': [100, 240, 400],
  'cello_string_quiz': [100, 600, 900],
  'cello_finger_quiz': [100, 600, 900],
  // Play/sing-along: score = notes hit. Cello walk 9, guitar riff 9,
  // keyboard scale 15, Twinkle 14.
  'cello_play_along': [1, 6, 9],
  'guitar_play_along': [1, 6, 9],
  'keyboard_play_along': [1, 10, 14],
  'keyboard_ode': [1, 10, 14],
  'sing_along': [1, 9, 13],
  'sing_mary': [1, 9, 12],
  // Chord-progression play-along: score = chords hit (4-chord progressions).
  'chord_play_along': [1, 3, 4],
  'guitar_string_quiz': [100, 600, 900],
  'guitar_tab_read': [100, 600, 900],
  'fretboard_find': [100, 600, 900],
  'capo_match': [100, 600, 900],
  'key_find': [100, 600, 900],
  'key_name': [100, 600, 900],
  'grand_staff_read': [100, 600, 900],
  // 8 rounds: max 800.
  'key_ear': [100, 500, 750],
  'key_chord': [100, 500, 750],
  // 6 rounds: max 600.
  'key_melody': [100, 400, 550],
  'ending_detective': [100, 600, 900],
  'tune_quiz': [100, 500, 750],
  // Which Family? (instrument → family reading quiz): 10 rounds x 100.
  'instrument_family': [100, 600, 900],
  // 8 rounds: max 800.
  'question_answer': [100, 500, 750],
};

/// Convert a raw game score to 1-3 stars. Returns 0 if the game was lost.
int scoreToStars(String gameType, int score, bool wasSuccessful) {
  if (!wasSuccessful) return 0;
  if (score <= 0) return 1;

  final thresholds = kStarThresholds[gameType];
  if (thresholds != null) {
    if (score >= thresholds[2]) return 3;
    if (score >= thresholds[1]) return 2;
    return 1;
  }

  // Fallback: generic rating, assuming an "average" score of ~500.
  if (score >= 800) return 3;
  if (score >= 400) return 2;
  return 1;
}
