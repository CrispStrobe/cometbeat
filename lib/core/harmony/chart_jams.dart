// lib/core/harmony/chart_jams.dart
//
// BB-D4b — a JAMS chord annotation becomes a chart.
//
// This is a CONVERTER, not a parser, and deliberately so.
// `songs/import/jams.dart` already reads chord annotations in five dialects and
// hands them back as ChordPro — dialect handling that took real work and that
// nothing here should duplicate. So the whole path is
// `jamsToChordPro` → `chartFromChordPro`, and this file's job is the seam and
// the honesty about what the seam costs.
//
// ⚠️ WHAT IT COSTS, and it is more than the ChordPro path costs:
//
//  1. TIMING. JAMS observations carry a time and a duration, in SECONDS, and
//     ChordPro has neither — so both are dropped. Bars are inferred one chord
//     to a bar, and `barsAreInferred` says so. Note that recovering real bar
//     lengths would take more than reading the durations: seconds only become
//     bars given a tempo and a meter, which a chord annotation alone does not
//     carry. The chord SEQUENCE is the part JAMS gives reliably on its own.
//
//  2. REPEATS. `_collapseRuns` keeps chord CHANGES, so a chord held over four
//     bars arrives as ONE bar. That is right for the chord-sheet pipeline it
//     was written for and surprising here, so it is pinned by a test.
//
// Using the timing would give REAL bar lengths — but `_observations` is private
// to `jams.dart`, so it would mean widening a shared file's API. That is worth
// doing when something needs the timing; it is not worth doing to make this
// slightly better, and inventing a second JAMS reader here to get at it would
// be worse than either.
library;

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_chordpro.dart';
import 'package:comet_beat/features/games/songs/import/jams.dart';

/// Reads a JAMS chord annotation as a chart. Never throws.
///
/// Returns an empty import when the file carries no chords — including when it
/// is not JAMS at all, since `jamsToChordPro` signals that by throwing and a
/// caller here wants an answer rather than an exception.
ChordProImport chartFromJams(String json) {
  final String chordPro;
  try {
    chordPro = jamsToChordPro(json);
  } on FormatException {
    return const ChordProImport(
      chart: Chart(),
      barsAreInferred: true,
    );
  } catch (_) {
    // Malformed JSON, a wrong shape, anything at all: a file the user picked
    // is arbitrary input, and a crash is never the right answer to it.
    return const ChordProImport(
      chart: Chart(),
      barsAreInferred: true,
    );
  }
  return chartFromChordPro(chordPro);
}
