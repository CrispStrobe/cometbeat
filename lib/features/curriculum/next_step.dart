// lib/features/curriculum/next_step.dart
//
// "What next?" — turns the curriculum's readiness maths into something a child
// can tap: the level to work on, the topic that needs it most, and a short
// programme of games to run. The home screen's Continue card is the consumer;
// the curriculum screens show the same levels as a browsable map.

import 'package:comet_beat/core/curriculum/curriculum.dart';
import 'package:comet_beat/features/games/game_registry.dart';

/// The recommended next thing to practise.
class NextStep {
  const NextStep({
    required this.level,
    required this.topic,
    required this.program,
  });

  /// The level the child is currently working towards.
  final CurriculumLevel level;

  /// The least-ready topic in [level] — what [program] opens with.
  final CurriculumTopic topic;

  /// One game per topic of [level], least-ready topic first. Never empty.
  final List<GameInfo> program;
}

/// One game per topic of [level], ordered least-ready topic first. Within a
/// topic the game with the fewest stars wins (ties keep the curriculum's own
/// order), so repeated sessions rotate through a topic's games instead of
/// replaying its first one. A game mapped under two topics appears once.
List<GameInfo> levelProgramByNeed(
  CurriculumLevel level,
  int Function(String) starsFor,
  double? Function(String) masteryUnder,
) {
  final readiness = {
    for (final t in level.topics) t: topicReadiness(t, starsFor, masteryUnder),
  };
  // Stable sort by readiness: List.sort is not guaranteed stable, so carry
  // the original index as the tie-break.
  final topics = [...level.topics];
  final order = {for (var i = 0; i < topics.length; i++) topics[i]: i};
  topics.sort((a, b) {
    final byNeed = readiness[a]!.compareTo(readiness[b]!);
    return byNeed != 0 ? byNeed : order[a]!.compareTo(order[b]!);
  });

  final seen = <String>{};
  final program = <GameInfo>[];
  for (final topic in topics) {
    GameInfo? pick;
    for (final id in topic.gameIds) {
      final game = gameInfoById(id);
      if (game == null || seen.contains(id)) continue;
      if (pick == null || starsFor(id) < starsFor(pick.id)) pick = game;
    }
    if (pick != null) {
      seen.add(pick.id);
      program.add(pick);
    }
  }
  return program;
}

/// The next step in [curriculum], or null when its recommended level maps to
/// no registered game (nothing to launch).
NextStep? nextStep(
  Curriculum curriculum,
  int Function(String) starsFor,
  double? Function(String) masteryUnder,
) {
  if (curriculum.levels.isEmpty) return null;
  final level = recommendedLevel(curriculum, starsFor, masteryUnder);
  final topic = weakestTopic(level, starsFor, masteryUnder);
  if (topic == null) return null;
  final program = levelProgramByNeed(level, starsFor, masteryUnder);
  if (program.isEmpty) return null;
  return NextStep(level: level, topic: topic, program: program);
}
