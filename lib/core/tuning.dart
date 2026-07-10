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
  'note_reading_quiz': [100, 600, 900],
  'place_note': [100, 600, 900],
  'measure_fill': [100, 600, 900],
  // 8 rounds: max 800.
  'scale_detective': [100, 500, 750],
  'chord_quiz': [100, 600, 900],
  'harmony_quiz': [100, 600, 900],
  'major_minor_ear': [100, 600, 900],
  'interval_ear': [100, 600, 900],
  // 8 rounds: max 800.
  'triad_builder': [100, 500, 750],
  'rhythm_tap': [100, 500, 750],
  // 6 rounds: max 600.
  'scale_builder': [100, 400, 550],
  // 4 rounds: max 400.
  'cadence_workshop': [100, 300, 400],
  'beat_count': [100, 600, 900],
  // 8 rounds: max 800.
  'meter_detective': [100, 500, 750],
  'melody_echo': [100, 500, 750],
  'cello_string_quiz': [100, 600, 900],
  'cello_finger_quiz': [100, 600, 900],
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
