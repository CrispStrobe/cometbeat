// Coverage gap analysis over the grade-1–10 concept inventory vs the real game
// registry. Prints the gap report (the planning artefact) and guards the hard
// invariants: no concept may reference a game that doesn't exist, and every
// concept's game ids must be real. The "untrained"/"thin"/"orphan" lists are
// informational — they are the map of where our coverage is thin.

import 'package:comet_beat/core/curriculum/concept_map.dart';
import 'package:comet_beat/core/curriculum/coverage_gaps.dart';
import 'package:comet_beat/features/games/game_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final report = CoverageReport(
    concepts: kConcepts,
    registeredGameIds: kGamesById.keys.toSet(),
  );

  test('the concept inventory names only real games (no dangling refs)', () {
    expect(
      report.danglingRefs,
      isEmpty,
      reason: 'concept(s) point at a missing game: '
          '${report.danglingRefs.map((d) => '${d.concept.id}→${d.gameId}').join(', ')}',
    );
  });

  test('every grade band carries at least one trained concept', () {
    for (final band in GradeBand.values) {
      final trained =
          kConcepts.where((c) => c.band == band && c.isTrained).length;
      expect(
        trained,
        greaterThan(0),
        reason: 'no trained concept in ${band.label}',
      );
    }
  });

  test('prints the coverage gap report', () {
    // Not an assertion on the gaps themselves — they are the deliverable. This
    // makes them visible in the test log and pins the shape of the analysis.
    // ignore: avoid_print
    print(report.report());
    expect(report.concepts, isNotEmpty);
    // Structural invariants only — we are actively closing gaps, so DON'T pin
    // which concepts are still untrained (that would break every time a gap is
    // filled). A concept marked untrained must genuinely have no games, and
    // every registered game must be placed.
    for (final c in report.untrained) {
      expect(c.gameIds, isEmpty, reason: '${c.id} is not really untrained');
    }
    expect(report.orphanGames, isEmpty, reason: 'every game should be placed');
  });

  test('report surfaces dangling refs and untrained concepts (synthetic)', () {
    // The real inventory has neither, so build a report that has both to cover
    // those report() branches.
    final synthetic = CoverageReport(
      concepts: const [
        Concept('c1', GradeBand.g12, ConceptArea.reading, 'Ghost ref', [
          'ghost_game',
        ]),
        Concept('c2', GradeBand.g34, ConceptArea.pulse, 'No game', []),
        Concept('c3', GradeBand.g12, ConceptArea.pulse, 'One game', [
          'real_game',
        ]),
      ],
      registeredGameIds: const {'real_game'},
    );

    expect(synthetic.danglingRefs, hasLength(1)); // c1 → ghost_game
    expect(synthetic.untrained.map((c) => c.id), ['c2']);
    // c1 and c3 each name exactly one game → both "thin".
    expect(synthetic.thin.map((c) => c.id), containsAll(['c1', 'c3']));

    final text = synthetic.report();
    expect(text, contains('DANGLING'));
    expect(text, contains('ghost_game'));
    expect(text, contains('UNTRAINED'));
    expect(text, contains('No game'));
  });
}
