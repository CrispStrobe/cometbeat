// lib/core/curriculum/curriculum.dart
//
// Curriculum alignment: a data model that maps a syllabus onto the games the app
// already has. It's generic — progress levels (tied to school years) are just a
// grouping over the same atomic skills:
//
//   Curriculum → Level → Topic → [gameIds]
//
// "Readiness" for a level/topic is derived from the child's best stars in the
// mapped games (0..1). Adding a level or a region is pure data.
//
// NOTE: the topic scope is a practice guide distilled (in our own words) from
// public school curricula — no badge/association branding, no verbatim text.
// See docs/PLAN.md.

import 'package:klang_universum/l10n/app_localizations.dart';

/// How a curriculum is framed. Only school Lehrpläne for now; the enum keeps the
/// model open to other framings without touching consumers.
enum CurriculumFramework { lehrplan }

/// A syllabus topic and the games that drill it.
class CurriculumTopic {
  const CurriculumTopic(this.title, this.gameIds);
  final String Function(AppLocalizations) title;
  final List<String> gameIds;
}

/// One level within a curriculum (a badge tier, or a Klassenstufe band).
class CurriculumLevel {
  const CurriculumLevel({
    required this.id,
    required this.name,
    required this.badge,
    required this.topics,
  });

  final String id;
  final String Function(AppLocalizations) name;

  /// A short badge/emoji shown on the level card.
  final String badge;
  final List<CurriculumTopic> topics;

  /// All distinct game IDs across this level's topics.
  List<String> get gameIds => {
        for (final t in topics) ...t.gameIds,
      }.toList();
}

/// A named syllabus (a badge system, or a school curriculum for a region).
class Curriculum {
  const Curriculum({
    required this.id,
    required this.framework,
    required this.name,
    required this.levels,
    this.region,
  });

  final String id;
  final CurriculumFramework framework;
  final String Function(AppLocalizations) name;

  /// Bundesland / school-type for a [CurriculumFramework.lehrplan]; null for
  /// the (national) Leistungsabzeichen.
  final String? region;
  final List<CurriculumLevel> levels;
}

// --- Readiness ---------------------------------------------------------------

/// Topic readiness in 0..1: the mean of best-stars/3 over the topic's games.
double topicReadiness(CurriculumTopic topic, int Function(String) starsFor) {
  if (topic.gameIds.isEmpty) return 0;
  final total = topic.gameIds.fold<int>(0, (sum, id) => sum + starsFor(id));
  return total / (topic.gameIds.length * 3);
}

/// Level readiness in 0..1: the mean of its topics' readiness.
double levelReadiness(CurriculumLevel level, int Function(String) starsFor) {
  if (level.topics.isEmpty) return 0;
  final total = level.topics
      .fold<double>(0, (sum, t) => sum + topicReadiness(t, starsFor));
  return total / level.topics.length;
}

/// A level counts as "reached" once the child is [_reachedAt] ready.
const _reachedAt = 0.66;

/// The level to point the child at next: the first not yet [_reachedAt] ready,
/// or the last level once everything is solid.
CurriculumLevel recommendedLevel(
  Curriculum curriculum,
  int Function(String) starsFor,
) {
  for (final level in curriculum.levels) {
    if (levelReadiness(level, starsFor) < _reachedAt) return level;
  }
  return curriculum.levels.last;
}

/// The topic within [level] with the lowest readiness (the best thing to drill
/// next). Null if the level has no topics.
CurriculumTopic? weakestTopic(
  CurriculumLevel level,
  int Function(String) starsFor,
) {
  if (level.topics.isEmpty) return null;
  return level.topics.reduce(
    (a, b) =>
        topicReadiness(a, starsFor) <= topicReadiness(b, starsFor) ? a : b,
  );
}

// --- Shared topic labels (reused across levels) ------------------------------

CurriculumTopic _reading(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicNoteReading, ids);
CurriculumTopic _values(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicNoteValues, ids);
CurriculumTopic _meter(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicMeter, ids);
CurriculumTopic _dynamics(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicDynamics, ids);
CurriculumTopic _scales(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicScales, ids);
CurriculumTopic _intervals(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicIntervals, ids);
CurriculumTopic _chords(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicChords, ids);
CurriculumTopic _harmony(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicHarmony, ids);
CurriculumTopic _transposition(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicTransposition, ids);
CurriculumTopic _ear(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicEar, ids);
CurriculumTopic _sight(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicSightReading, ids);

// --- Levels by school year (Klassenstufen) -----------------------------------
//
// Generic, un-branded progress levels tied to German school years. The topic
// scope per band is distilled (in our own words) from public state music
// curricula (e.g. NRW Grundschule — notation kept deliberately light — and
// Schleswig-Holstein Sek I, which itemises theory per grade band). No badge
// system, no association marks. The model still carries `region`, so a specific
// Bundesland's curriculum is a drop-in variant later.

final _bySchoolYear = Curriculum(
  id: 'school_years',
  framework: CurriculumFramework.lehrplan,
  name: (l) => l.curSchoolYears,
  levels: [
    // Grundschule, early: notation as a listening aid; pulse; loud/soft, fast/
    // slow, high/low.
    CurriculumLevel(
      id: 'g12',
      name: (l) => l.curLevelGrades12,
      badge: '🎒',
      topics: [
        _reading(['note_memory', 'note_order']),
        _values(['note_value_quiz', 'beat_sort']),
        _meter(['beat_runner', 'rhythm_tap']),
        _dynamics(['charades']),
        _ear(['major_minor_ear', 'echo_sequence']),
      ],
    ),
    // Grundschule, later: read simple treble notation; note values; simple
    // metre; dynamics/tempo.
    CurriculumLevel(
      id: 'g34',
      name: (l) => l.curLevelGrades34,
      badge: '📗',
      topics: [
        _reading(['note_reading_treble', 'line_space', 'ledger_leap']),
        _values(['note_value_quiz', 'duration_duel', 'beat_count']),
        _meter(['measure_fill', 'which_beat', 'time_signature']),
        _dynamics(['charades']),
        _ear(['major_minor_ear', 'melody_echo']),
      ],
    ),
    // Sek I 5/6: both clefs; metre; C/F/G major + accidentals; thirds; I/IV/V
    // triads.
    CurriculumLevel(
      id: 'g56',
      name: (l) => l.curLevelGrades56,
      badge: '🎼',
      topics: [
        _reading(['note_reading_treble', 'note_reading_bass', 'ledger_leap']),
        _meter(['time_signature', 'measure_fill', 'meter_detective']),
        _scales(['scale_detective', 'key_sig']),
        _intervals(['interval_ladder', 'interval_ear']),
        _chords(['chord_quiz', 'triad_builder']),
        _dynamics(['charades']),
      ],
    ),
    // Sek I 7/8: major/minor + circle of fifths; chord qualities; cadences;
    // syncopation.
    CurriculumLevel(
      id: 'g78',
      name: (l) => l.curLevelGrades78,
      badge: '🎵',
      topics: [
        _scales(['scale_detective', 'scale_builder', 'key_sig']),
        _intervals(['interval_ear', 'interval_ladder']),
        _chords(['chord_quiz', 'name_that_chord', 'chord_builder']),
        _harmony(['harmony_quiz', 'cadence_workshop', 'function_ear']),
        _values(['beat_runner', 'drum_read']),
        _ear(['melody_dictation']),
      ],
    ),
    // Sek I 9/10: inversions & 7ths; functions; transposition; score reading.
    CurriculumLevel(
      id: 'g910',
      name: (l) => l.curLevelGrades910,
      badge: '🎓',
      topics: [
        _chords(['chord_builder', 'name_that_chord', 'chord_grip_hero']),
        _harmony(['harmony_quiz', 'function_ear', 'cadence_workshop']),
        _transposition(['concert_pitch']),
        _sight(['staff_runner', 'duet', 'grand_staff_read']),
        _reading(['note_reading_tenor', 'duet']),
      ],
    ),
  ],
);

/// All curricula. One general school-year progression for now; the model holds
/// more (e.g. per-Bundesland variants) as pure data.
final List<Curriculum> kCurricula = [_bySchoolYear];
