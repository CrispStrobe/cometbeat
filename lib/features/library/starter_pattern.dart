// A tiny "starter module" generator: given a channel count and a pattern length,
// it returns which (channel, row) cells to trigger for a simple, generic
// backbeat. Pure Dart (no Tracker model dependency) so it is unit-testable and
// collision-free — the Tracker applies the hits via its existing per-cell note
// API. Pairs with "Browse free sounds": assign CC0 samples to a few channels,
// then lay down a starter groove in one tap.

/// A hit to place in the pattern grid.
typedef PatternHit = ({int channel, int row});

/// A simple backbeat over [channels] channels and [rows] rows:
/// - **channel 0** — a steady pulse on every beat (a kick-ish downbeat);
/// - **channel 1** — the backbeat (beats 2 & 4);
/// - **channels ≥ 2** — eighth-note pulses (a hat-ish layer).
///
/// Beat length is `rows/4` (so a classic 16-row pattern = 4 beats), clamped to
/// at least one row. Channels beyond what exist are simply skipped, so it adapts
/// to however many instruments the user has set up.
List<PatternHit> starterBeatHits({required int channels, required int rows}) {
  if (channels <= 0 || rows <= 0) return const [];
  final quarter = (rows / 4).round().clamp(1, rows); // rows per beat
  final eighth = (quarter ~/ 2).clamp(1, rows); // rows per eighth
  final hits = <PatternHit>[];
  for (var r = 0; r < rows; r++) {
    if (r % quarter == 0) hits.add((channel: 0, row: r)); // downbeat pulse
    if (channels > 1 && r % (quarter * 2) == quarter) {
      hits.add((channel: 1, row: r)); // backbeat
    }
    if (channels > 2 && r % eighth == 0) {
      hits.add((channel: 2, row: r)); // hats
    }
  }
  return hits;
}
