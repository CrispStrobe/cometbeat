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
  const MelodicMatch(this.id, this.score, this.distance, this.matched);
  final String id;

  /// 0..1, higher is better. 1.0 means the query's shape is contained exactly.
  final double score;
  final int distance;

  /// How many intervals the score is based on — the length of the common
  /// prefix that was actually compared.
  ///
  /// ⚠️ This is what stops a near-empty row from winning. Scoring on the common
  /// prefix means a candidate with a two-note incipit is judged on ONE interval,
  /// which anything matches perfectly; measured on the real catalog that alone
  /// took an 8-note query from 51% top-1 to 34%, because those rows flooded the
  /// top with 1.0s. Same score with less evidence behind it must rank lower.
  final int matched;

  @override
  int compareTo(MelodicMatch other) {
    final byScore = other.score.compareTo(score);
    return byScore != 0 ? byScore : other.matched.compareTo(matched);
  }
}

/// Finds the candidates whose opening most resembles [query].
///
/// [query] is absolute MIDI (sung, tapped, or lifted from a score) — the caller
/// does not have to transpose or normalise anything.
///
/// ⚠️ Query and candidate are compared over their **COMMON PREFIX** — both are
/// truncated to the shorter length. Both directions matter and each was a real
/// defect:
///   * a 4-note query against a full 16-note incipit is dominated by the twelve
///     notes the user never sang, so every short query scores equally badly.
///     This is what makes "I only remember the opening" work at all;
///   * and the reverse — a SUNG query easily runs past 16 notes while catalog
///     incipits stop there, so without truncating the query too, every note
///     beyond the incipit counts as an indel and a perfect match could not
///     score above ~0.7. That would have made sung search look broken while the
///     ranking was in fact correct.
///
/// Comparing only the common prefix does mean a row with a SHORT incipit can
/// tie a longer one. That is honest rather than a compromise: we genuinely know
/// no more about that row than its first few notes.
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
    final n = min(q.length, full.length);
    final query = q.length > n ? q.sublist(0, n) : q;
    final cand = full.length > n ? full.sublist(0, n) : full;
    final dist = melodicDistance(query, cand);
    // Normalise by the worst plausible cost over the compared span, so queries
    // and candidates of different lengths produce comparable scores.
    final worst = n * kIndelCost * 2;
    final score = worst == 0 ? 0.0 : (1.0 - dist / worst).clamp(0.0, 1.0);
    if (score >= minScore) out.add(MelodicMatch(c.id, score, dist, n));
  }
  out.sort();
  return out.length > limit ? out.sublist(0, limit) : out;
}

// ---------------------------------------------------------------------------
// Mode 2 — a SUNG query
// ---------------------------------------------------------------------------

/// The default ceiling on a sung query, in notes.
///
/// Catalog incipits stop at 16, so notes past that point can add no evidence —
/// [searchMelodies] compares the common prefix and simply ignores them. Capping
/// here instead makes that explicit and keeps the work proportional.
const int kMaxSungQueryNotes = 16;

/// Turns transcribed notes into a melodic query.
///
/// Takes `(midi, onMs, offMs, confidence)` records — structurally the
/// transcription pipeline's `NoteEvent`, but named structurally so this stays
/// in `core/music` without depending on the transcription contracts.
///
/// Three filters, each earning its place on real singing:
///   * **too short** — a hummed line is full of sub-100 ms artefacts as the
///     voice slides between pitches, and each one would insert a spurious
///     interval PAIR (in and out again), which is far more damaging than the
///     note is worth;
///   * **too quiet / unsure** — a low-confidence frame run is usually breath or
///     room noise that happened to have a pitch;
///   * **the tail** — see [kMaxSungQueryNotes].
///
/// ⚠️ Repeated pitches are KEPT. "C C G" and "C G" are different shapes
/// ([0, +7] vs [+7]), and a great many tunes open by repeating a note — Ode to
/// Joy and Twinkle both do. Deduplicating adjacent equal pitches would look
/// like a tidy-up and would quietly delete the opening of everything that
/// starts that way.
List<int> melodyQueryFromNotes(
  List<({int midi, double onMs, double offMs, double confidence})> notes, {
  double minDurationMs = 90,
  double minConfidence = 0.5,
  int maxNotes = kMaxSungQueryNotes,
}) {
  final out = <int>[];
  for (final n in notes) {
    if (n.offMs - n.onMs < minDurationMs) continue;
    if (n.confidence < minConfidence) continue;
    out.add(n.midi);
    if (out.length >= maxNotes) break;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Mode 3 — a query taken from music the user already has
// ---------------------------------------------------------------------------

/// The opening pitches of [pitchesInOrder] as a melodic query.
///
/// The caller supplies the notes in sounding order — from a score's melody
/// part, a loop's cells, a tab, a selection. This deliberately takes plain MIDI
/// rather than any editor's document type: every surface has its own, and a
/// query is just pitches.
///
/// ⚠️ Chords are the caller's problem, and the right answer is the TOP note.
/// A melody sits on top of its own harmonisation, so taking a chord's lowest or
/// average pitch searches for the accompaniment — the same trap that makes
/// note-count melody detection pick the left hand.
List<int> melodyQueryFromPitches(
  List<int> pitchesInOrder, {
  int maxNotes = kMaxSungQueryNotes,
}) =>
    pitchesInOrder.length > maxNotes
        ? pitchesInOrder.sublist(0, maxNotes)
        : List.of(pitchesInOrder);
