// Where the disagreements actually live — the metric that makes the headline
// number interpretable.
//
// Exact-finger agreement against a single editor conflates two axes that behave
// completely differently, and the violin literature measures them separately for
// exactly that reason: string choice is nearly determinate (Jen et al. report F1
// .83 / MRR .91) while HAND POSITION is subjective (F1 .24–.31 — ten professionals
// disagree with each other). So a low exact-finger number is not evidence of a bad
// arranger; it is mostly evidence that position is a choice.
//
// Measured here: exact finger 52.0%, but **string agreement 92.7%** — i.e. on the
// determinate axis we already agree with the editors, and nearly all the residual
// is position-on-the-same-string. Chasing exact-finger 90% against one editor is
// not a reachable target; the published SOTA does not approach it either, with
// 1000x the labels.
//
// ⚠ Do not "fix" the residual with weights on this data. The one lever the errors
// suggested (raise the open-string cost, since 19 disagreements are open-vs-stopped)
// was tested with a leave-one-piece-out sweep and does NOTHING: 52.0% at open costs
// 0.0/0.4/1.0 and WORSE at 2.0/4.0. 248 labels across 8 parts cannot support weight
// tuning; that is what the LOPO was for.
import 'dart:convert';
import 'dart:io';
import 'package:comet_beat/core/notation/bowed_arranger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('agreement decomposes into a determinate axis and a subjective one', () {
    final inst = BowedInstrument.cello;
    var total = 0, exact = 0, stringOk = 0, impossible = 0, openDiff = 0;
    for (final path in [
      'test/data/cello_fingering_gold.json',
      'test/data/cello_fingering_gold_pd.json',
    ]) {
      for (final piece in jsonDecode(File(path).readAsStringSync()) as List) {
        final cols = (piece as Map)['columns'] as List;
        final pitches = [
          for (final c in cols)
            [for (final p in (c as Map)['pitches'] as List) p as int],
        ];
        final got = arrangeBowed(
          pitches,
          skill: BowedSkill.advanced,
          slurToNext: [for (final c in cols) (c as Map)['slur'] as bool],
        );
        for (var i = 0; i < cols.length; i++) {
          final fingers = (cols[i] as Map)['fingers'] as List;
          for (var j = 0;
              j < fingers.length && j < got.columns[i].length;
              j++) {
            final want = fingers[j] as int?;
            if (want == null) continue;
            total++;
            final mine = got.columns[i][j];
            if (mine.finger == want) {
              exact++;
              continue;
            }
            // Which strings COULD produce this pitch with the printed finger?
            final midi = pitches[i][j];
            final strings = <int>{};
            for (var s = 0; s < inst.tuning.strings.length; s++) {
              final semis = midi - inst.tuning.strings[s].midiNumber;
              if (semis < 0) continue;
              if (want == 0) {
                if (semis == 0) strings.add(s);
                continue;
              }
              for (final mode in BowedHandMode.values) {
                for (var anchor = 0; anchor <= 24; anchor++) {
                  final f = frameOf(inst, mode, anchor);
                  if (f[want] == semis) strings.add(s);
                }
              }
            }
            if (strings.isEmpty) {
              impossible++;
              continue;
            }
            if (strings.contains(mine.string)) stringOk++;
            if (mine.isOpen != (want == 0)) openDiff++;
          }
        }
      }
    }
    final agree = 100.0 * exact / total;
    final sameString = 100.0 * (exact + stringOk) / total;
    expect(total, 248);
    // The determinate axis. This is the floor worth defending: a regression here
    // means the frame model picked an unreachable or wrong string, which is a bug
    // rather than a difference of opinion.
    expect(sameString, greaterThan(85.0));
    // No label should be physically impossible — if one is, either the fixture or
    // the frame model is wrong.
    expect(impossible, 0);
    // ignore_for_file: avoid_print
    print('\nlabels $total');
    print('  exact finger            ${agree.toStringAsFixed(1)}%  ($exact)');
    print('  + same STRING, different position/finger  (+$stringOk) '
        '=> string agreement ${sameString.toStringAsFixed(1)}%');
    print('  label physically impossible for any string: $impossible');
    print('  disagreements that are open-vs-stopped: $openDiff');
  });
}
