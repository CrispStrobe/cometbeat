// test/bowed_shift_agreement_test.dart
//
// WHERE THE HAND MOVES — the axis this project had no measurement for at all until
// `shiftBase` was added, and the reason three earlier attempts at the same defect
// each traded one axis for another: they were judged through frame agreement on a
// single page, which is a proxy, not the thing.
//
// Ground truth is `test/data/cello_shift_gold_danbe.json`: Danbé's «Étude des cinq
// positions», where every note carries the position label printed above its bar, so
// a change of label between adjacent notes is a labelled shift.
//
// ⚠ The comparison is on SHIFT POINTS, never on position numbers. Danbé's numbering
// is a French scheme we have not mapped to ours, and assuming such a mapping has
// already produced two errors in this arc (our own numbering turned out semitone-
// counted where the convention is diatonic; and «Einsatz» turned out to mean thumb
// position, not shifting). Asking only "does the hand move HERE?" needs no mapping.
//
// These are floors on a SMALL set — 15 labelled shifts. Treat a fall as a real
// regression and a rise as weak evidence; the set is too small to optimise into.

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/notation/bowed_arranger.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Note = ({int midi, String? position});

List<List<_Note>> _load() {
  final doc = jsonDecode(
    File('test/data/cello_shift_gold_danbe.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return [
    for (final l in (doc['lines'] as List).cast<Map<String, dynamic>>())
      [
        for (final n in (l['notes'] as List).cast<Map<String, dynamic>>())
          (midi: n['midi'] as int, position: n['position'] as String?),
      ],
  ];
}

({int tp, int fp, int fn, int gold, int ours}) _score(BowedSkill skill) {
  var tp = 0, fp = 0, fn = 0, gold = 0, ours = 0;
  for (final line in _load()) {
    final got = arrangeBowed(
      line.map((n) => [n.midi]).toList(),
      skill: skill,
    );
    for (var i = 1; i < line.length; i++) {
      final a = line[i - 1].position, b = line[i].position;
      if (a == null || b == null) continue;
      final goldShift = a != b;
      final ourShift =
          got.columns[i].single.anchor != got.columns[i - 1].single.anchor;
      if (goldShift) gold++;
      if (ourShift) ours++;
      if (goldShift && ourShift) {
        tp++;
      } else if (ourShift) {
        fp++;
      } else if (goldShift) {
        fn++;
      }
    }
  }
  return (tp: tp, fp: fp, fn: fn, gold: gold, ours: ours);
}

void main() {
  test('the fixture is intact', () {
    final lines = _load();
    expect(lines.length, 3);
    expect(lines.fold<int>(0, (a, l) => a + l.length), 60);
    final gold = _score(BowedSkill.advanced).gold;
    expect(gold, 15, reason: '15 labelled position changes');
  });

  test('the hand does not move wildly more often than the source moves it', () {
    // The defect `shiftBase` fixed was the hand creeping a semitone mid-figure.
    // Before it, `advanced` made 21 anchor changes against the source's 15.
    final r = _score(BowedSkill.advanced);
    expect(
      r.ours,
      lessThanOrEqualTo(20),
      reason: 'we made ${r.ours} shifts against a printed 15 — the hand is '
          'creeping again; check BowedArrangeCost.shiftBase',
    );
  });

  test('shift-point agreement holds its floor', () {
    final r = _score(BowedSkill.advanced);
    final precision = r.tp + r.fp == 0 ? 0.0 : 100.0 * r.tp / (r.tp + r.fp);
    final recall = r.tp + r.fn == 0 ? 0.0 : 100.0 * r.tp / (r.tp + r.fn);
    // ignore: avoid_print
    print('\nshift points (advanced): gold ${r.gold} · ours ${r.ours} · '
        'TP ${r.tp} FP ${r.fp} FN ${r.fn} · '
        'precision ${precision.toStringAsFixed(1)}% · '
        'recall ${recall.toStringAsFixed(1)}%');
    // Deliberately loose: this axis is the hardest in the literature (position
    // F1 ≈ .24–.31 across ten professional annotators) and the set is small.
    expect(precision, greaterThan(25.0));
    expect(recall, greaterThan(30.0));
  });

  test('a stationary passage produces no shifts at all', () {
    // Sanity that the metric can read zero: four notes inside one first-position
    // frame on the D string must not move the hand.
    final got = arrangeBowed(
      const [
        [50],
        [52],
        [53],
        [54],
      ],
      skill: BowedSkill.advanced,
    );
    expect(got.columns.map((c) => c.single.anchor).toSet().length, 1);
  });
}
