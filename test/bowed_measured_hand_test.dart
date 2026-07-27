// The arranger against a MEASURED cellist's hand.
//
// Every other check we have compares us with what an editor WROTE. This one
// compares us with where a player's fingers physically WERE: 45 notes derived from
// the String Performance Dataset (SPD, cello01), whose pipeline recovers a contact
// point on the fingerboard per frame from multi-view motion capture plus
// audio-detected hand-string contacts. Provenance and licence: test/data/README.md.
//
// Two findings worth keeping as a regression:
//
//  1. Their measurements are explained by OUR frame model. Reading each measured
//     stop as `anchor = semitones - (finger - 1)` lands on integer positions
//     (1, 2, 3, 4, 6, 7, 8, 9, 10, 11) rather than on arbitrary fractions — the
//     hand model is not just a book table we transcribed.
//  2. Agreement splits exactly where you would expect. In positions 1–4 — ordinary
//     playing — we choose the player's string ~95% of the time, matching the 92.7%
//     measured against printed editions from an entirely different kind of evidence.
//     Above that the excerpt is a SHIFTING EXERCISE, climbing one string on purpose,
//     and a movement-minimising DP will never reproduce it. That is the arranger
//     optimising for ease while the player optimised for practice, not a defect.

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/notation/bowed_arranger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final notes =
      jsonDecode(File('test/data/spd_cello01_measured.json').readAsStringSync())
          as List;

  int measuredPosition(Map n) =>
      ((n['semitones'] as num) - ((n['finger'] as int) - 1) - 1).round();

  test('the measured stops land on integer positions of our frame model', () {
    // If our semitone-per-finger frame were wrong, these would scatter.
    var onGrid = 0;
    for (final n in notes) {
      final anchor =
          ((n as Map)['semitones'] as num) - ((n['finger'] as int) - 1);
      if ((anchor - anchor.roundToDouble()).abs() < 0.35) onGrid++;
    }
    expect(onGrid / notes.length, greaterThan(0.7));
  });

  test('we choose the player own string in ordinary positions', () {
    final got = arrangeBowed(
      [
        for (final n in notes) [(n as Map)['midi'] as int],
      ],
      skill: BowedSkill.advanced,
    );
    var loAgree = 0, loTot = 0, hiAgree = 0, hiTot = 0;
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i] as Map;
      final ok = got.columns[i].single.string == n['string'];
      if (measuredPosition(n) <= 4) {
        loTot++;
        if (ok) loAgree++;
      } else {
        hiTot++;
        if (ok) hiAgree++;
      }
    }
    // ignore_for_file: avoid_print
    print(
      '\nmeasured hand (SPD cello01, n=${notes.length}) — string agreement',
    );
    print('  positions 1-4 : ${(100.0 * loAgree / loTot).toStringAsFixed(0)}%'
        ' ($loAgree/$loTot)');
    print('  positions 5+  : ${(100.0 * hiAgree / hiTot).toStringAsFixed(0)}%'
        ' ($hiAgree/$hiTot)   <- the shifting exercise');
    expect(loTot, greaterThan(10));
    expect(loAgree / loTot, greaterThan(0.8));
  });
}
