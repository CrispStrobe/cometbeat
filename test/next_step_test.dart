// The home screen's "what next?" — the curriculum's recommended level turned
// into a launchable programme, least-ready topic first.
import 'package:comet_beat/core/curriculum/curriculum.dart';
import 'package:comet_beat/features/curriculum/next_step.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final curriculum = kCurricula.first;

  test('a new learner is pointed at the first level', () {
    final step = nextStep(curriculum, (_) => 0, (_) => null)!;
    expect(step.level, curriculum.levels.first);
    expect(step.topic, step.level.topics.first);
    expect(step.program, isNotEmpty);
    expect(
      step.program.map((g) => g.id).toSet().length,
      step.program.length,
      reason: 'no game twice in one session',
    );
  });

  test('the programme opens on the least-ready topic', () {
    final level = curriculum.levels.first;
    final weak = level.topics.last;
    // Three stars everywhere except the last topic's games.
    int stars(String id) => weak.gameIds.contains(id) ? 0 : 3;
    final program = levelProgramByNeed(level, stars, (_) => null);
    expect(weak.gameIds, contains(program.first.id));
  });

  test('within a topic the game with the fewest stars is picked', () {
    final level = curriculum.levels.first;
    final topic = level.topics.firstWhere((t) => t.gameIds.length > 1);
    final played = topic.gameIds.first;
    int stars(String id) => id == played ? 2 : 0;
    final program = levelProgramByNeed(level, stars, (_) => null);
    expect(program.map((g) => g.id), isNot(contains(played)));
  });

  test('a solid first level moves the recommendation on', () {
    final first = curriculum.levels.first;
    int stars(String id) => first.gameIds.contains(id) ? 3 : 0;
    final step = nextStep(curriculum, stars, (_) => null)!;
    expect(step.level, isNot(first));
  });
}
