// lib/core/music/melodic_search.dart
//
// "What is this tune?" — melodic search over the corpus's incipits.
//
// The corpus feature index put an `incipit` (the opening notes, as absolute
// MIDI) on **38,417 of the catalog's 38,427 score rows**, and nothing in the app
// has ever read it. This is the search half: give it a few notes and it finds
// the pieces that start that way.
//
// THREE DECISIONS DECIDE WHETHER THIS WORKS ON REAL INPUT, and all three are
// easy to get wrong in a way that still passes a naive test:
//
//   1. **Match INTERVALS, not pitches.** Someone humming a tune starts wherever
//      their voice sits, and a corpus row is in whatever key it was written in.
//      Comparing absolute pitch would only ever find transpositions by accident.
//      An interval sequence is transposition-proof, which is exactly why the
//      feature index computes one.
//
//   2. **Edit distance, not equality.** A hum drops a note, doubles a note, or
//      adds a turn; and one *setting* of a traditional tune differs from another
//      by precisely that kind of small edit. Exact matching looks broken the
//      moment it meets a human.
//
//   3. **A near-miss is cheaper than a wrong note.** Being a semitone out (a
//      mis-sung third, a modal variant) is a much smaller error than jumping the
//      wrong direction, so substitution cost scales with how far off the
//      interval is rather than being a flat penalty. Without this, "close but
//      slightly flat" ranks the same as "unrelated".
//
// Pure Dart — no Flutter, no I/O — so it is testable headlessly and can run
// against either the shipped catalog or a local corpus.

import 'dart:math';

/// The interval sequence of [pitches] — the transposition-proof fingerprint.
///
/// One shorter than the input, and empty for a single note (a lone note has no
/// shape, and pretending otherwise would make every one-note row match
/// everything).
List<int> intervalsOf(List<int> pitches) => [
      for (var i = 1; i < pitches.length; i++) pitches[i] - pitches[i - 1],
    ];

/// What one interval being wrong costs, in the same units as an insert/delete.
///
/// 0 when identical; small when nearly right; capped so that a wildly wrong
/// interval never costs more than deleting the note and inserting another —
/// beyond that cap the difference is meaningless and letting it grow would let
/// one bad note dominate an otherwise good match.
int substitutionCost(int a, int b) {
  final d = (a - b).abs();
  if (d == 0) return 0;
  return min(1 + d, kIndelCost * 2);
}

/// Cost of an inserted or dropped note.
///
/// Deliberately > 1: a dropped note is a normal artefact of humming, so it must
/// be affordable, but not so cheap that deleting everything becomes a good
/// match for anything.
const int kIndelCost = 3;

/// Weighted edit distance between two interval sequences.
int melodicDistance(List<int> a, List<int> b) {
  if (a.isEmpty) return b.length * kIndelCost;
  if (b.isEmpty) return a.length * kIndelCost;
  // Two rows is all the algorithm needs, and the pool is tens of thousands of
  // candidates — allocating a full matrix per candidate would dominate.
  var prev = List<int>.generate(b.length + 1, (j) => j * kIndelCost);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i * kIndelCost;
    for (var j = 1; j <= b.length; j++) {
      final sub = prev[j - 1] + substitutionCost(a[i - 1], b[j - 1]);
      final del = prev[j] + kIndelCost;
      final ins = cur[j - 1] + kIndelCost;
      cur[j] = min(sub, min(del, ins));
    }
    final swap = prev;
    prev = cur;
    cur = swap;
  }
  return prev[b.length];
}

/// One candidate to search: an id and the opening pitches the index recorded.
class MelodicCandidate {
  const MelodicCandidate(this.id, this.incipit);
  final String id;

  /// Absolute MIDI pitches. Intervals are derived, so a caller can hand over
  /// exactly what the catalog stores without preprocessing it.
  final List<int> incipit;
}

/// A scored hit.
class MelodicMatch implements Comparable<MelodicMatch> {
  const MelodicMatch(this.id, this.score, this.distance);
  final String id;

  /// 0..1, higher is better. 1.0 means the query's shape is contained exactly.
  final double score;
  final int distance;

  @override
  int compareTo(MelodicMatch other) => other.score.compareTo(score);
}

/// Finds the candidates whose opening most resembles [query].
///
/// [query] is absolute MIDI (sung, tapped, or lifted from a score) — the caller
/// does not have to transpose or normalise anything.
///
/// ⚠️ The query is matched against the candidate's opening **PREFIX of the same
/// length**, not against its whole incipit. Catalog incipits are a fixed 16
/// notes; a 4-note query compared to all 16 would be dominated by the 12 notes
/// the user never sang, and every short query would score equally badly. This
/// is what makes "I only remember the first few notes" work at all.
List<MelodicMatch> searchMelodies(
  List<int> query,
  Iterable<MelodicCandidate> pool, {
  int limit = 20,
  double minScore = 0.0,
}) {
  final q = intervalsOf(query);
  if (q.isEmpty) return const [];
  final out = <MelodicMatch>[];
  for (final c in pool) {
    final full = intervalsOf(c.incipit);
    if (full.isEmpty) continue;
    final cand = full.length > q.length ? full.sublist(0, q.length) : full;
    final dist = melodicDistance(q, cand);
    // Normalise by the worst plausible cost for this comparison so that short
    // and long queries produce comparable scores.
    final worst = max(q.length, cand.length) * kIndelCost * 2;
    final score = worst == 0 ? 0.0 : (1.0 - dist / worst).clamp(0.0, 1.0);
    if (score >= minScore) out.add(MelodicMatch(c.id, score, dist));
  }
  out.sort();
  return out.length > limit ? out.sublist(0, limit) : out;
}
