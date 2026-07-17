// lib/core/curriculum/coverage_gaps.dart
//
// Coverage gap analysis over the grade-1–10 concept inventory (concept_map.dart)
// and the game registry. Pure logic — it takes the registered game ids as a set,
// so it stays free of a features/games import and is trivially testable. The
// test (test/curriculum_coverage_test.dart) wires the real registry, prints the
// report, and guards the invariants (no dangling refs).
//
// It answers "where are the gaps in our covering?": concepts trained by no game,
// concepts trained by only one, games that sit in no concept, and — a real
// correctness guard — concepts that reference a game id that doesn't exist.

import 'package:comet_beat/core/curriculum/concept_map.dart';

/// A concept that names a game id which isn't in the registry (a real bug).
typedef DanglingRef = ({Concept concept, String gameId});

/// The result of running the analysis over [concepts] against [registeredGameIds].
class CoverageReport {
  CoverageReport({required this.concepts, required this.registeredGameIds});

  final List<Concept> concepts;
  final Set<String> registeredGameIds;

  /// Concepts that reference a game that isn't registered — these break the
  /// learning path and must be zero (asserted in the test).
  List<DanglingRef> get danglingRefs => [
        for (final c in concepts)
          for (final g in c.gameIds)
            if (!registeredGameIds.contains(g)) (concept: c, gameId: g),
      ];

  /// Concepts trained by no game at all — the true coverage gaps.
  List<Concept> get untrained =>
      concepts.where((c) => c.gameIds.isEmpty).toList();

  /// Concepts trained by exactly one game — thin, worth widening.
  List<Concept> get thin => concepts.where((c) => c.isThin).toList();

  /// Every game id a concept points at (that actually exists).
  Set<String> get placedGames => {
        for (final c in concepts)
          for (final g in c.gameIds)
            if (registeredGameIds.contains(g)) g,
      };

  /// Registered games not attached to any concept — content outside the path.
  List<String> get orphanGames =>
      (registeredGameIds.difference(placedGames).toList()..sort());

  double get placementRatio => registeredGameIds.isEmpty
      ? 0
      : placedGames.length / registeredGameIds.length;

  /// A human-readable gap report (printed by the test / a dev tool).
  String report() {
    final b = StringBuffer()
      ..writeln('=== Curriculum coverage gap report ===')
      ..writeln('concepts: ${concepts.length}   '
          'games placed: ${placedGames.length}/${registeredGameIds.length} '
          '(${(placementRatio * 100).toStringAsFixed(0)}%)')
      ..writeln();

    if (danglingRefs.isNotEmpty) {
      b.writeln('!! DANGLING game refs (bug): '
          '${danglingRefs.map((d) => '${d.concept.id}→${d.gameId}').join(', ')}');
      b.writeln();
    }

    b.writeln('UNTRAINED concepts (no game — real gaps):');
    for (final band in GradeBand.values) {
      final us = untrained.where((c) => c.band == band).toList();
      if (us.isEmpty) continue;
      b.writeln(
        '  ${band.label}: ${us.map((c) => '${c.title} [${c.area.name}]').join('; ')}',
      );
    }
    b
      ..writeln()
      ..writeln('THIN concepts (one game only):')
      ..writeln(
        '  ${thin.map((c) => '${c.title} (${c.gameIds.single})').join('; ')}',
      )
      ..writeln()
      ..writeln('ORPHAN games (registered but in no concept): '
          '${orphanGames.length}')
      ..writeln('  ${orphanGames.join(', ')}');
    return b.toString();
  }
}
