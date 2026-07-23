// A guitar-tablature arranger: assigns each note/chord of a pitch sequence to
// (string, fret) positions that are actually comfortable to play — minimising
// hand movement between columns and finger span within a chord — instead of the
// naive "lowest fret per note, independently" that makes a scale bounce across
// strings and picks unplayable chord voicings.
//
// The method is the classic Sayegh (1989) "optimum path" Viterbi: each column
// gets a set of candidate frettings, and we find the min-cost path through them
// where the transition cost penalises hand-position shifts and the local cost
// penalises chord span + high positions. Pure Dart (no Flutter) → unit-testable,
// patent-free, no model asset. It is the baseline every score→tab path uses
// (TabDocument.fromScore, MusicXML import, the MelodyBridge tab pull); a neural
// arranger can later slot in behind the same List<List<int>> → List<Fretting>
// shape without touching callers.

// Imports Tuning from crisp_notation_core (not the crisp_notation umbrella) so
// this stays Flutter-free and usable from headless CLIs (bin/tabconv.dart). The
// umbrella re-exports the same Tuning, so GUI callers are unaffected.
import 'package:crisp_notation_core/crisp_notation_core.dart' show Tuning;

/// One column's chosen fretting: string index (0 = top tab line) → fret (0 =
/// open). An empty map is a rest / silent column.
typedef Fretting = Map<int, int>;

/// How far a hand reaches across the fretboard, in frets, counting from the
/// lowest fretted note of a shape. [arrangeTab]'s hard span cap defaults to
/// this. It is deliberately a *constraint*, not a weight: span also exists as a
/// soft cost, but `cost.move` outbids it, so only a hard limit can stop an
/// impossible chord being chosen to keep the hand still.
const int kHandSpan = 5;

/// Scores candidate `(string, fret)` placements per column so a data-driven
/// arranger can supply the *local* term while [arrangeTab]'s Viterbi stays the
/// arbiter (hand-movement transition cost + the hard span cap remain ours, so
/// the model can bias *which* playable shape wins but can never introduce an
/// unplayable one — it only ever scores candidates that already passed the
/// cap). CrispASR would
/// implement this behind FFI/ONNX; a null return (whole or per-column) defers to
/// the heuristic cost, so callers keep working with no model present.
/// See docs/TAB_ARRANGER_NEURAL_HANDOFF.md.
abstract interface class TabPositionModel {
  /// For each input column, a `higher = more idiomatic` score per position, or
  /// null for that column to defer it to the heuristic. Positions map to the
  /// same MIDI pitches [arrangeTab] enumerates for the column.
  List<Map<(int string, int fret), double>?>? score(
    List<List<int>> columns,
    Tuning tuning, {
    int capo,
    int maxFret,
  });
}

/// Process-wide symbolic labeler that [arrangeTab] consults when no explicit
/// `model` is passed — so EVERY score→tab path (`TabDocument.fromScore`, file
/// imports, the GP plan, the MelodyBridge tab pull) fingers like the human-
/// trained model once it's loaded, without threading it through each caller. The
/// app sets it from `TabLabeler.load()` (null-on-offline); tests leave it null,
/// so the heuristic is the default + guaranteed fallback.
class TabArranger {
  TabArranger._();

  static TabPositionModel? shared;

  /// Span penalty re-applied on top of the app-loaded [shared] model's emission
  /// so arranged shapes stay as compact as a human's. The model alone picks the
  /// right position but slightly OVER-spans (1.68 vs human 1.43); the measured
  /// sweet spot 0.5 pulls span to 1.47 AND lifts agreement to 84% (they align —
  /// humans finger compact). Only used when [shared] drives the arrange; an
  /// explicit `arrangeTab(modelSpanCost:)` overrides it (e.g. benchmarks).
  static double sharedSpanCost = 0.5;
}

/// The weights of the arranger's cost function. Defaults are tuned so hand
/// movement dominates (keep the hand in one place), chord span matters, and a
/// tiny height term breaks ties toward the low neck.
class TabArrangeCost {
  /// Per fret of hand-position shift between adjacent columns.
  final double move;

  /// Per fret of spread between the lowest and highest fretted finger in a
  /// column (open strings are position-free and don't count).
  final double span;

  /// Per fret of mean fretted position — a small pull toward the nut so, all
  /// else equal, the low neck wins.
  final double height;

  const TabArrangeCost({
    this.move = 1.0,
    this.span = 0.6,
    this.height = 0.05,
  });
}

/// The valid `(string, fret)` positions that sound [midi] on [tuning] behind a
/// [capo], within [maxFret]. String index 0 = top line (highest string).
List<(int string, int fret)> _positionsFor(
  int midi,
  Tuning tuning,
  int capo,
  int maxFret,
) {
  final out = <(int, int)>[];
  for (var s = 0; s < tuning.strings.length; s++) {
    final fret = midi - tuning.strings[s].midiNumber - capo;
    if (fret >= 0 && fret <= maxFret) out.add((s, fret));
  }
  return out;
}

/// The frets that need a finger (open strings are position-independent).
Iterable<int> _fretted(Fretting f) => f.values.where((v) => v > 0);

/// The stretch a hand must make for [f]: highest minus lowest *fretted* fret.
/// Open strings need no finger, so they don't widen the stretch.
int _spanOf(Fretting f) {
  final fretted = _fretted(f).toList();
  if (fretted.length < 2) return 0;
  var lo = fretted.first, hi = fretted.first;
  for (final v in fretted) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  return hi - lo;
}

/// The hand anchor of a fretting = its lowest fretted fret, or null when the
/// column is all-open / a rest (so it constrains nothing and moving to/from it
/// is free).
int? _anchor(Fretting f) {
  int? lo;
  for (final v in _fretted(f)) {
    if (lo == null || v < lo) lo = v;
  }
  return lo;
}

double _localCost(Fretting f, TabArrangeCost cost) {
  final fretted = _fretted(f).toList();
  if (fretted.isEmpty) return 0;
  var lo = fretted.first, hi = fretted.first, sum = 0;
  for (final v in fretted) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
    sum += v;
  }
  final span = (hi - lo) * cost.span;
  final height = (sum / fretted.length) * cost.height;
  return span + height;
}

double _transitionCost(Fretting prev, Fretting cur, TabArrangeCost cost) {
  final a = _anchor(prev), b = _anchor(cur);
  if (a == null || b == null) return 0; // an open column doesn't move the hand
  return (a - b).abs() * cost.move;
}

/// All ways to place [pitches] on distinct strings (a chord can't put two notes
/// on one string), each within reach. Prunes early; the result is capped to the
/// [limit] cheapest-by-[cost] frettings so a dense chord can't explode the DP.
/// A pitch with no reachable position is simply dropped from the column.
///
/// [maxSpan] (when non-null) is a HARD limit on the stretch of a single column,
/// applied before the DP ever sees the candidate. Span is otherwise only a soft
/// cost, and `move` outweighs it — so the Viterbi will happily buy a physically
/// impossible stretch to avoid shifting the hand. If no candidate satisfies the
/// cap, the narrowest available ones are kept rather than dropping the column:
/// a wide shape still beats no notes at all.
List<Fretting> _candidateFrettings(
  List<int> pitches,
  Tuning tuning,
  int capo,
  int maxFret,
  int limit,
  TabArrangeCost cost,
  int? maxSpan,
) {
  if (pitches.isEmpty) return const [<int, int>{}];
  // Reachable positions per pitch; drop unreachable pitches entirely.
  final perPitch = <List<(int, int)>>[];
  for (final m in pitches) {
    final pos = _positionsFor(m, tuning, capo, maxFret);
    if (pos.isNotEmpty) perPitch.add(pos);
  }
  if (perPitch.isEmpty) return const [<int, int>{}];

  final out = <Fretting>[];
  void recurse(int i, Map<int, int> acc, Set<int> usedStrings) {
    if (i == perPitch.length) {
      out.add(Map<int, int>.of(acc));
      return;
    }
    for (final (s, fret) in perPitch[i]) {
      if (usedStrings.contains(s)) continue;
      acc[s] = fret;
      usedStrings.add(s);
      recurse(i + 1, acc, usedStrings);
      usedStrings.remove(s);
      acc.remove(s);
    }
  }

  recurse(0, {}, {});
  if (out.isEmpty) return const [<int, int>{}]; // couldn't seat the chord

  var kept = out;
  if (maxSpan != null) {
    final within = [
      for (final f in out)
        if (_spanOf(f) <= maxSpan) f,
    ];
    if (within.isNotEmpty) {
      kept = within;
    } else {
      // Nothing reaches the cap: keep only the narrowest shapes, so the column
      // still sounds rather than vanishing.
      var best = _spanOf(out.first);
      for (final f in out) {
        final s = _spanOf(f);
        if (s < best) best = s;
      }
      kept = [
        for (final f in out)
          if (_spanOf(f) == best) f,
      ];
    }
  }

  if (kept.length > limit) {
    kept.sort((a, b) => _localCost(a, cost).compareTo(_localCost(b, cost)));
    return kept.sublist(0, limit);
  }
  return kept;
}

/// Arranges [columns] (each a list of simultaneous MIDI pitches — a single note
/// is a one-element list, a rest an empty list) into a comfortable [Fretting]
/// per column on [tuning] behind a [capo], via a Viterbi over candidate
/// frettings. Notes unreachable within [maxFret] are dropped; column count and
/// order are preserved 1:1, so callers can zip the result back with durations.
///
/// [maxSpan] hard-caps the stretch of any single column (highest minus lowest
/// fretted fret) — a hand's reach, so a shape that no hand can make is never a
/// candidate. It defaults to [kHandSpan] because span is otherwise only a *soft*
/// cost that `cost.move` outbids: at the default weights, dodging an 8-fret hand
/// shift (8.0) is cheaper than 11 extra frets of stretch (6.6), so the Viterbi
/// would buy a physically impossible chord to keep the hand still. Measured over
/// 337 Mutopia guitar works (116k notes), the cap removed 83% of >5-fret spans
/// for 1.5% more hand travel and no extra dropped notes; every span left over
/// was one no fretting of those pitches could avoid. Pass null to disable.
/// Columns with no shape inside the cap fall back to their narrowest, never to
/// silence.
List<Fretting> arrangeTab(
  List<List<int>> columns,
  Tuning tuning, {
  int capo = 0,
  int maxFret = 20,
  int maxCandidatesPerColumn = 64,
  TabArrangeCost cost = const TabArrangeCost(),
  TabPositionModel? model,
  int? maxSpan = kHandSpan,
  // When >0 AND a model is supplied, re-adds a span penalty on TOP of the model
  // emission (which otherwise replaces the local cost, dropping span). Lets the
  // arranger prefer the compact shape among the model's high-scoring options —
  // pulls arranged span toward the human's without retraining. 0 = unchanged.
  double modelSpanCost = 0,
}) {
  if (columns.isEmpty) return [];
  final cands = [
    for (final col in columns)
      _candidateFrettings(
        col,
        tuning,
        capo,
        maxFret,
        maxCandidatesPerColumn,
        cost,
        maxSpan,
      ),
  ];

  // When a model is supplied (explicitly or via the app-loaded [TabArranger]
  // global), its per-position scores replace the heuristic LOCAL term
  // (transition/hand-movement stays ours). A missing score for a candidate's
  // position falls back to the heuristic, so partial models work.
  final m = model ?? TabArranger.shared;
  // An explicit modelSpanCost wins; otherwise the app-loaded shared model brings
  // its tuned default so the in-app arrange matches the 84%/span-1.47 benchmark.
  final effModelSpanCost = modelSpanCost > 0
      ? modelSpanCost
      : (model == null && m != null ? TabArranger.sharedSpanCost : 0.0);
  final scores = m?.score(columns, tuning, capo: capo, maxFret: maxFret);
  double local(int i, Fretting f) {
    final col = (scores != null && i < scores.length) ? scores[i] : null;
    if (col != null && f.isNotEmpty) {
      var sum = 0.0;
      var any = false;
      for (final e in f.entries) {
        final v = col[(e.key, e.value)];
        if (v != null) {
          sum += v;
          any = true;
        }
      }
      if (any) {
        // higher model score → lower cost; + span penalty (explicit, or the
        // shared model's tuned default) to keep shapes human-compact.
        return -sum +
            (effModelSpanCost > 0 ? _spanOf(f) * effModelSpanCost : 0);
      }
    }
    return _localCost(f, cost);
  }

  // Viterbi: dp[c] = best total cost of ending column i at candidate c.
  var dp = [for (final f in cands[0]) local(0, f)];
  final back = <List<int>>[]; // back[i][c] = chosen candidate index in col i-1
  for (var i = 1; i < cands.length; i++) {
    final prev = cands[i - 1];
    final cur = cands[i];
    final next = List<double>.filled(cur.length, double.infinity);
    final bp = List<int>.filled(cur.length, 0);
    for (var c = 0; c < cur.length; c++) {
      final loc = local(i, cur[c]);
      for (var p = 0; p < prev.length; p++) {
        final total = dp[p] + loc + _transitionCost(prev[p], cur[c], cost);
        if (total < next[c]) {
          next[c] = total;
          bp[c] = p;
        }
      }
    }
    dp = next;
    back.add(bp);
  }

  // Reconstruct the min-cost path.
  var best = 0;
  for (var c = 1; c < dp.length; c++) {
    if (dp[c] < dp[best]) best = c;
  }
  final chosen = List<int>.filled(cands.length, 0);
  chosen[cands.length - 1] = best;
  for (var i = cands.length - 1; i > 0; i--) {
    chosen[i - 1] = back[i - 1][chosen[i]];
  }
  return [for (var i = 0; i < cands.length; i++) cands[i][chosen[i]]];
}
