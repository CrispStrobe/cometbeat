// test/bowed_arranger_accept_test.dart
//
// Acceptance harness for the bowed arranger, against REAL printed cello
// fingerings — the bowed twin of `tab_labeler_accept_test.dart`.
//
// Gold set: `test/data/cello_fingering_gold.json`, extracted from the four
// **CC0-1.0** PDMX scores in our own music DB that carry `<fingering>` marks on a
// cello part (Boccherini Quintet in C, Vivaldi Cello Sonata RV 44, *Komm süsser
// Tod*, Bach Cello Suite No. 3 Bourrée I; source
// https://zenodo.org/records/15571083). 193 labelled notes across 2,303 columns —
// the entire dense cello-fingering supervision that exists in a 42k-score corpus,
// which is the honest measure of how scarce this data is.
//
// Three things to keep in mind when reading the number:
//
//  • **Fingers only.** Printed editions mark the finger, never the string — none
//    of the four files has a single `<string>` element. String and position are
//    hidden variables here, so this scores the one axis a human wrote down.
//  • **The labelled notes are the HARD ones.** An editor writes a fingering
//    exactly where the choice is not obvious and leaves the easy majority bare,
//    so this subset is adversarially selected against us.
//  • **One reference, not a consensus.** The violin literature scores against ten
//    annotators for good reason (professionals agree on the string, ~MRR .91, and
//    disagree on the position, F1 ≈ .24–.31). A single editor's fingering is one
//    valid answer among several, so this is a REGRESSION FLOOR, not a ceiling to
//    chase. Treat a drop as a bug and a rise as evidence, not as a score to
//    optimise into.

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/notation/bowed_arranger.dart';
import 'package:flutter_test/flutter_test.dart';

class _Piece {
  _Piece(Map<String, dynamic> json)
      : title = json['title'] as String,
        part = json['part'] as String,
        labelled = json['labelled'] as int,
        columns = [
          for (final c in json['columns'] as List)
            (
              pitches: [for (final p in c['pitches'] as List) p as int],
              fingers: [for (final f in c['fingers'] as List) f as int?],
              slur: c['slur'] as bool,
            ),
        ];

  final String title;
  final String part;
  final int labelled;
  final List<({List<int> pitches, List<int?> fingers, bool slur})> columns;
}

/// Agreement of [skill] with the printed fingers, plus the arranger's own stats.
({int hit, int total, int relaxed, double openShare}) _score(
  List<_Piece> pieces,
  BowedSkill skill,
) {
  var hit = 0, total = 0, relaxed = 0, open = 0, notes = 0;
  for (final piece in pieces) {
    final got = arrangeBowed(
      [for (final c in piece.columns) c.pitches],
      skill: skill,
      slurToNext: [for (final c in piece.columns) c.slur],
    );
    if (got.relaxed) relaxed++;
    for (var c = 0; c < piece.columns.length; c++) {
      final want = piece.columns[c].fingers;
      final mine = got.columns[c];
      for (var i = 0; i < want.length && i < mine.length; i++) {
        notes++;
        if (mine[i].isOpen) open++;
        final w = want[i];
        if (w == null) continue;
        total++;
        if (mine[i].finger == w) hit++;
      }
    }
  }
  return (
    hit: hit,
    total: total,
    relaxed: relaxed,
    openShare: notes == 0 ? 0 : open / notes,
  );
}

void main() {
  final file = File('test/data/cello_fingering_gold.json');
  final pieces = [
    for (final p in jsonDecode(file.readAsStringSync()) as List)
      _Piece(p as Map<String, dynamic>),
  ];

  test('gold set is the one we think it is', () {
    expect(pieces.length, 4);
    expect(pieces.fold<int>(0, (a, p) => a + p.labelled), 193);
  });

  test('agreement with printed cello fingerings (CC0 gold set)', () {
    final report = StringBuffer('\ncello fingering agreement '
        '(${pieces.fold<int>(0, (a, p) => a + p.labelled)} printed fingers)\n');
    final profiles = <String, BowedSkill>{
      'firstPosition': BowedSkill.firstPosition,
      'neckPositions': BowedSkill.neckPositions,
      'advanced': BowedSkill.advanced,
    };
    late ({int hit, int total, int relaxed, double openShare}) best;
    var bestPct = -1.0;
    for (final entry in profiles.entries) {
      final s = _score(pieces, entry.value);
      final pct = 100.0 * s.hit / s.total;
      report.writeln('  ${entry.key.padRight(14)} '
          '${pct.toStringAsFixed(1)}% (${s.hit}/${s.total}) · '
          'relaxed ${s.relaxed}/${pieces.length} · '
          'open ${(100 * s.openShare).toStringAsFixed(1)}%');
      if (pct > bestPct) {
        bestPct = pct;
        best = s;
      }
    }
    // Per-piece breakdown for the profile that repertoire like this calls for.
    for (final piece in pieces) {
      final s = _score([piece], BowedSkill.advanced);
      report.writeln('  · ${piece.title.padRight(46).substring(0, 46)} '
          '${(100.0 * s.hit / s.total).toStringAsFixed(1)}% '
          '(${s.hit}/${s.total})');
    }
    // ignore: avoid_print
    print(report);

    // Regression floor. Measured 2026-07-26: firstPosition 47.2% ·
    // neckPositions 43.5% · advanced 50.3% (the profile this repertoire calls
    // for, using BowedArrangeCost.professional). A coarse 135-point weight sweep
    // spans only 38.3–50.3%, so ~50% is the untrained ceiling on this gold set
    // and the floor sits below it with headroom. It exists to catch a regression
    // in the frame model, not to certify quality — see the header on why chasing
    // this number against a single editor would be a mistake.
    expect(best.total, 193);
    expect(bestPct, greaterThan(47.0));
  });

  test('the learner profile keeps the hand still, the professional one moves',
      () {
    // Not a quality claim — a check that the two profiles really are different
    // policies, since they share the same DP and it would be easy to wire the
    // per-skill weights up wrongly and never notice.
    expect(
      BowedArrangeCost.forSkill(BowedSkill.firstPosition).shift,
      BowedArrangeCost.learner.shift,
    );
    expect(
      BowedArrangeCost.forSkill(BowedSkill.advanced).shift,
      BowedArrangeCost.professional.shift,
    );
    expect(
      BowedArrangeCost.professional.shift,
      lessThan(BowedArrangeCost.learner.shift),
    );
    expect(BowedArrangeCost.professional.height, 0.0);
  });

  test('every gold note gets a reachable fingering', () {
    for (final piece in pieces) {
      final got = arrangeBowed(
        [for (final c in piece.columns) c.pitches],
        skill: BowedSkill.advanced,
      );
      for (var c = 0; c < piece.columns.length; c++) {
        expect(
          got.columns[c].length,
          piece.columns[c].pitches.length,
          reason: '${piece.title} column $c',
        );
        for (final f in got.columns[c]) {
          expect(f.semitones, greaterThanOrEqualTo(0));
          expect(f.finger, anyOf(0, 1, 2, 3, 4, kThumb));
        }
      }
    }
  });
}
