// test/bowed_arranger_piece_test.dart
//
// The arranger on a real PEDAGOGICAL PIECE — the regime the app actually teaches —
// as opposed to the chamber repertoire of `cello_fingering_gold.json` and the scale
// tables of `cello_fingering_gold_becker.json`.
//
// Why this fixture is worth its own file:
//
//  * It is the ONLY double-keyed one we have. Two independent readings (the second
//    blind), then an arbiter for the 7 disputes. Reader A won 3, reader B won 2, and
//    on 2 the arbiter found a third answer neither had — so no single reading was
//    correct alone, and this is the only fixture where that has been established
//    rather than assumed.
//  * It is real music with both parts fingered, not a table of hand positions.
//  * It scores 95.2% / 83.3% where the other two score ~54% and ~56%. That is NOT a better
//    arranger: a beginner duet sits in first position with open strings, which is the
//    regime the model is built for. The three numbers mean different things and should
//    be quoted together or not at all.
import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/notation/bowed_arranger.dart';
import 'package:flutter_test/flutter_test.dart';

List<List<Map<String, dynamic>>> _runs(String staff) {
  final doc = jsonDecode(
    File('test/data/cello_fingering_gold_becker_p50.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final out = <List<Map<String, dynamic>>>[];
  final run = <Map<String, dynamic>>[];
  for (final n in (doc['notes'] as List).cast<Map<String, dynamic>>()) {
    if (n['staff'] != staff) continue;
    run.add(n);
  }
  if (run.isNotEmpty) out.add(run);
  return out;
}

({int hit, int total, int open, int openTotal}) _score(String staff) {
  var hit = 0, total = 0, open = 0, openTotal = 0;
  for (final seg in _runs(staff)) {
    final got = arrangeBowed(
      seg.map((n) => [n['midi'] as int]).toList(),
      skill: BowedSkill.advanced,
    );
    for (var i = 0; i < seg.length; i++) {
      final want = seg[i]['finger'];
      if (want is! int) continue;
      total++;
      if (got.columns[i].single.finger == want) hit++;
      if (want == 0) {
        openTotal++;
        if (got.columns[i].single.finger == 0) open++;
      }
    }
  }
  return (hit: hit, total: total, open: open, openTotal: openTotal);
}

void main() {
  test('the fixture is intact and double-keyed', () {
    final doc = jsonDecode(
      File('test/data/cello_fingering_gold_becker_p50.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final notes = (doc['notes'] as List).cast<Map<String, dynamic>>();
    expect(notes.length, 101);
    expect(notes.where((n) => n['finger'] is int).length, 66);
    // 7 notes were settled by arbitration; they are the ones two readers disputed.
    expect(notes.where((n) => n['arbitrated'] == true).length, 7);
    expect(doc['provenance'], contains('blind'));
  });

  test('every note of both parts gets a reachable fingering', () {
    for (final staff in ['upper', 'lower']) {
      for (final seg in _runs(staff)) {
        final got = arrangeBowed(
          seg.map((n) => [n['midi'] as int]).toList(),
          skill: BowedSkill.advanced,
        );
        expect(got.columns.length, seg.length, reason: '$staff lost a column');
        expect(got.columns.every((c) => c.length == 1), isTrue);
      }
    }
  });

  test('agreement on a pedagogical piece, per part', () {
    // Floors ~4 points under measured (95.2% upper / 83.3% lower). Per part,
    // because the parts are different problems: the upper is a fingered melody, the
    // lower an accompaniment that was the harder READ and may be the harder arrange.
    const floors = {'upper': 91.0, 'lower': 79.0};
    final report = StringBuffer('\nBecker p.50 no.9 (pedagogical duet)\n');
    for (final staff in ['upper', 'lower']) {
      final s = _score(staff);
      final pct = 100.0 * s.hit / s.total;
      report.writeln('  ${staff.padRight(6)} ${pct.toStringAsFixed(1)}% '
          '(${s.hit}/${s.total})  open strings ${s.open}/${s.openTotal}');
      expect(pct, greaterThan(floors[staff]!), reason: '$staff regressed');
    }
    // ignore: avoid_print
    print(report.toString());
  });

  test('open strings are exact — the determinate axis on easy music', () {
    for (final staff in ['upper', 'lower']) {
      final s = _score(staff);
      expect(
        s.open,
        s.openTotal,
        reason: '$staff: an open string the editor printed was not taken',
      );
    }
  });
}
