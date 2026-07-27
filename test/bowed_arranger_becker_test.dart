// test/bowed_arranger_becker_test.dart
//
// Acceptance floor for the bowed arranger against BECKER'S printed fingerings —
// 24 three-octave scales, 1,056 notes, from `test/data/cello_fingering_gold_becker.json`.
//
// Why a second acceptance file rather than more rows in the first one:
//
//  • DIFFERENT PROVENANCE. The CC0/PDMX sets were extracted mechanically from
//    digital scores. These were SIGHT-READ from a 600 ppi scan by a vision model.
//    That is a different error profile — a misread digit is possible where a parsed
//    `<fingering>` element is not — so the two must stay separately reportable.
//  • DIFFERENT SCHOOL. Becker is explicitly frame-based in the neck and diatonic in
//    thumb position, and states both in prose. Mixing his numbers into a pool with
//    editors whose system we have not established would average across schools and
//    measure nothing.
//  • DIFFERENT AXIS COVERAGE. Unlike the PDMX sets, these carry the string (via the
//    open-string 0s) and, on p18, the position — the axes printed editions almost
//    never record.
//
// The floors are PER PAGE and deliberately not pooled: three different plates, read
// by different readers, and a pooled number would hide a regression on one behind a
// gain on another. They sit ~3 points under measured so that ordinary re-tuning does
// not trip them, and they are floors, not targets — see `scoring.not_a_ceiling` in
// the fixture.

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/notation/bowed_arranger.dart';
import 'package:flutter_test/flutter_test.dart';

class _Scale {
  _Scale(this.page, this.key, this.notes);
  final int page;
  final String key;
  final List<({int midi, int? target})> notes;
}

/// Loads the fixture, applying the scoring rule the source itself fixes: the upper
/// row is Becker's TWO-OCTAVE fingering, so the lower row is the intended target in
/// the third octave.
List<_Scale> _load() {
  final doc = jsonDecode(
    File('test/data/cello_fingering_gold_becker.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final out = <_Scale>[];
  for (final p in (doc['pages'] as List).cast<Map<String, dynamic>>()) {
    for (final s in (p['scales'] as List).cast<Map<String, dynamic>>()) {
      out.add(
        _Scale(
          p['page'] as int,
          s['key'] as String,
          [
            for (final n in (s['notes'] as List).cast<Map<String, dynamic>>())
              (
                midi: n['midi'] as int,
                target: (n['third_octave'] as bool)
                    ? n['alt'] as int?
                    : n['finger'] as int?,
              ),
          ],
        ),
      );
    }
  }
  return out;
}

/// One column per note. Written with `map` rather than a collection-for because
/// `dart format` splits the latter across lines and then the trailing-comma lint
/// fires on it.
List<List<int>> _columns(_Scale s) => s.notes.map((n) => [n.midi]).toList();

({int hit, int total}) _score(Iterable<_Scale> scales) {
  var hit = 0, total = 0;
  for (final s in scales) {
    final got = arrangeBowed(_columns(s), skill: BowedSkill.advanced);
    for (var i = 0; i < s.notes.length; i++) {
      final want = s.notes[i].target;
      if (want == null) continue; // absence in the SOURCE, not a miss
      total++;
      if (got.columns[i].single.finger == want) hit++;
    }
  }
  return (hit: hit, total: total);
}

void main() {
  final scales = _load();

  test('the fixture is intact', () {
    expect(scales.length, 24);
    expect(scales.fold<int>(0, (a, s) => a + s.notes.length), 1056);
    // Every scale is a 3-octave climb and return, summit notehead printed twice.
    expect(scales.every((s) => s.notes.length == 44), isTrue);
  });

  test('every note gets a reachable fingering', () {
    for (final s in scales) {
      final got = arrangeBowed(_columns(s), skill: BowedSkill.advanced);
      expect(
        got.columns.length,
        s.notes.length,
        reason: '${s.key} (p${s.page}) lost a column',
      );
      expect(
        got.columns.every((c) => c.length == 1),
        isTrue,
        reason: '${s.key} (p${s.page}) has an unassigned note',
      );
    }
  });

  test('agreement with Becker, per page', () {
    // Floors ~3 points under measured (56.0 / 53.4 / 56.1 at the time of writing).
    // Per page, never pooled. Three points is enough headroom that ordinary
    // re-weighting does not trip them, and small enough that a real regression does.
    const floors = {14: 53.0, 15: 50.0, 16: 53.0};
    final report = StringBuffer('\nBecker scale agreement (advanced)\n');
    for (final page in [14, 15, 16]) {
      final s = _score(scales.where((x) => x.page == page));
      final pct = 100.0 * s.hit / s.total;
      report.writeln('  p$page  ${pct.toStringAsFixed(1)}% '
          '(${s.hit}/${s.total})  floor ${floors[page]}');
      expect(
        pct,
        greaterThan(floors[page]!),
        reason: 'page $page regressed: ${pct.toStringAsFixed(1)}%',
      );
    }
    final all = _score(scales);
    report.writeln(
        '  all   ${(100.0 * all.hit / all.total).toStringAsFixed(1)}% '
        '(${all.hit}/${all.total}) — reported, NOT asserted; the per-page floors '
        'are the contract');
    // ignore: avoid_print
    print(report.toString());
  });

  test('open strings are the determinate axis and stay near-perfect', () {
    // Every printed 0 is an open string, so it pins the string with no room for
    // taste. This is the axis the literature finds nearly solved, and a drop here
    // means a real geometry bug rather than a difference of musical opinion.
    var hit = 0, total = 0;
    for (final s in scales) {
      final got = arrangeBowed(_columns(s), skill: BowedSkill.advanced);
      for (var i = 0; i < s.notes.length; i++) {
        if (s.notes[i].target != 0) continue;
        total++;
        if (got.columns[i].single.finger == 0) hit++;
      }
    }
    expect(
      total,
      greaterThan(50),
      reason: 'expected plenty of printed open strings',
    );
    expect(100.0 * hit / total, greaterThan(90.0));
  });
}
