// Our order-list walk and row timings, against an INDEPENDENT implementation.
//
// PLAN.md §6 X5. Everything else in the replay audit needs external renderers
// and runs opt-in: `openmpt123`, `xmp` and `mod2wav` are not on CI, so the
// numbers that found the vibrato rate and the IT break bug never guard a pull
// request. This one does. NodMOD (github.com/erodola/nodmod, MIT) walks a
// module's order list in Python and yields every visited row with its onset;
// `tool/nodmod_timeline_oracle.py` freezes that into
// `test/fixtures/flow/nodmod_timeline.json`, and this test compares it against
// `resolveTimingMap`. Pure arithmetic, no audio, no binaries.
//
// What it caught on its first run: our row-onset arithmetic accumulated
// rounding. A tracker row lasts `speed * 2.5 / bpm` seconds, whole milliseconds
// only at convenient tempos — 125 BPM at speed 6 is exactly 120 ms, but 160 BPM
// is 93.75 and 80 BPM is 187.5. We rounded EACH row and added the rounded
// values, so on `tempo_change_Fxx` our render ran 20.720 s where libopenmpt,
// libxmp and NodMOD all agree on 20.670. The error was unbounded — 0.5 ms per
// row at 80 BPM — and both the audio AND the playhead read it, so a long module
// at an awkward tempo drifted by seconds. See `rowOnsets`.
//
// ⚠️ The oracle is not ground truth everywhere, and `nodmod_timeline_oracle.py`
// records the two entries it deliberately omits: NodMOD's S3M walker does not
// model `SBx` pattern loop, and the two audio references disagree with EACH
// OTHER about FT2's loop counter on XM. Both were found by checking NodMOD's
// totals against libopenmpt and libxmp instead of assuming. IT has no NodMOD
// walker at all, which is exactly why the ladder calls it the highest-risk
// reader.

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

/// Onsets may differ by this many ms from the oracle.
///
/// One millisecond, not a percentage: the point of `rowOnsets` is that the error
/// does NOT grow with the row count, so a tolerance that scaled with position
/// would defeat the test it exists to make possible. Both sides round exact
/// seconds to whole milliseconds independently, so ±1 is the honest floor.
const int _kToleranceMs = 1;

void main() {
  final oracleFile = File('test/fixtures/flow/nodmod_timeline.json');

  test('the frozen oracle is present and non-trivial', () {
    expect(
      oracleFile.existsSync(),
      isTrue,
      reason: 'regenerate with tool/nodmod_timeline_oracle.py',
    );
    final songs =
        (jsonDecode(oracleFile.readAsStringSync()) as Map)['songs'] as Map;
    expect(songs.length, greaterThanOrEqualTo(12));
  });

  group('flow walk matches NodMOD', () {
    final decoded = jsonDecode(oracleFile.readAsStringSync()) as Map;
    final songs = (decoded['songs'] as Map).cast<String, dynamic>();

    for (final name in songs.keys.toList()..sort()) {
      test(name, () {
        final entry = (songs[name] as Map).cast<String, dynamic>();
        final quads = (entry['quads'] as List).cast<int>();
        final expectedRows = entry['rows'] as int;

        final song = songFromModuleBytes(
          File('test/fixtures/flow/$name').readAsBytesSync(),
        );
        final ours = resolveTimingMap(song);

        expect(
          ours.length,
          expectedRows,
          reason: 'we played a different number of rows than NodMOD — a flow '
              'command fired, failed to fire, or landed on the wrong row',
        );

        // Walk every row rather than spot-checking the ends: a jump that lands
        // one row off and a break that compensates for it would cancel out in
        // the totals.
        for (var i = 0; i < expectedRows; i++) {
          final o = ours[i];
          final base = i * 4;
          expect(
            [o.orderIndex, o.patternIndex, o.row],
            [quads[base], quads[base + 1], quads[base + 2]],
            reason: 'row $i of $name: we were at order ${o.orderIndex} '
                'pattern ${o.patternIndex} row ${o.row}, NodMOD at order '
                '${quads[base]} pattern ${quads[base + 1]} row '
                '${quads[base + 2]}',
          );
          expect(
            (o.startMs - quads[base + 3]).abs(),
            lessThanOrEqualTo(_kToleranceMs),
            reason: 'row $i of $name starts at ${o.startMs} ms, NodMOD says '
                '${quads[base + 3]} ms. A drift that GROWS with the row index '
                'is per-row rounding being accumulated (see rowOnsets); a '
                'constant offset is a different bug.',
          );
        }
      });
    }
  });

  test('row onsets do not accumulate rounding error', () {
    // The regression in isolation, independent of any fixture. 160 BPM at speed
    // 6 is 93.75 ms — a row length that cannot be represented in whole
    // milliseconds — so rounding per row and summing drifts by a quarter of a
    // millisecond every row.
    final played = [
      for (var i = 0; i < 4000; i++) const PlayedRow(0, 0, 0, 6, 160),
    ];
    final onsets = rowOnsets(played, 125, 1000);
    // 4000 rows x 93.75 ms = 375000 ms exactly.
    expect(onsets.last, closeTo(375000, 1));
    // Per-row accumulation would land 1000 ms long here — a full second.
    expect((onsets.last - 375000).abs(), lessThan(2));
  });
}
