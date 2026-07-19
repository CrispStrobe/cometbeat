// test/transcription/note_metrics.dart
//
// mir_eval-style note metrics — the SHARED "done" ruler for every transcription
// slice. Each worker's acceptance bar is a number from here (onset / note
// F-measure), not eyeballing. Greedy nearest-onset matching, each expected and
// detected note used at most once. Pure; imported by the per-worker tests.

import 'package:comet_beat/core/audio/transcription/contracts.dart';

/// Precision / recall / F-measure of one match count.
class Prf {
  const Prf(this.precision, this.recall, this.f);
  final double precision;
  final double recall;
  final double f;

  @override
  String toString() => 'P=${precision.toStringAsFixed(2)} '
      'R=${recall.toStringAsFixed(2)} F=${f.toStringAsFixed(2)}';
}

Prf _prf(int matched, int expected, int detected) {
  final precision = detected == 0 ? 0.0 : matched / detected;
  final recall = expected == 0 ? 0.0 : matched / expected;
  final f = (precision + recall) == 0
      ? 0.0
      : 2 * precision * recall / (precision + recall);
  return Prf(precision, recall, f);
}

// Greedy match: for each expected note (in time order) take the nearest unused
// detected note whose onset is within tol and [ok] holds. Returns the match
// count.
int _match(
  List<NoteEvent> expected,
  List<NoteEvent> detected,
  double onsetTolMs,
  bool Function(NoteEvent e, NoteEvent d) ok,
) {
  final exp = [...expected]..sort((a, b) => a.onMs.compareTo(b.onMs));
  final det = [...detected]..sort((a, b) => a.onMs.compareTo(b.onMs));
  final used = List<bool>.filled(det.length, false);
  var matched = 0;
  for (final e in exp) {
    var best = -1;
    var bestDist = double.infinity;
    for (var j = 0; j < det.length; j++) {
      if (used[j]) continue;
      final dist = (det[j].onMs - e.onMs).abs();
      if (dist <= onsetTolMs && dist < bestDist && ok(e, det[j])) {
        bestDist = dist;
        best = j;
      }
    }
    if (best >= 0) {
      used[best] = true;
      matched++;
    }
  }
  return matched;
}

/// Onset-only F-measure: a detected note matches an expected one if their
/// onsets are within [onsetTolMs] (pitch ignored).
Prf onsetPrf(
  List<NoteEvent> expected,
  List<NoteEvent> detected, {
  double onsetTolMs = 50,
}) =>
    _prf(
      _match(expected, detected, onsetTolMs, (_, __) => true),
      expected.length,
      detected.length,
    );

/// Note F-measure: onset within [onsetTolMs] AND MIDI within [pitchTol]
/// semitones. Set [pitchTol] > 0 to accept octave-agnostic or near matches.
Prf notePrf(
  List<NoteEvent> expected,
  List<NoteEvent> detected, {
  double onsetTolMs = 50,
  int pitchTol = 0,
}) =>
    _prf(
      _match(
        expected,
        detected,
        onsetTolMs,
        (e, d) => (e.midi - d.midi).abs() <= pitchTol,
      ),
      expected.length,
      detected.length,
    );

/// Convenience for tests: build ground-truth notes from a (midi, onMs, offMs)
/// list at full confidence.
List<NoteEvent> notes(List<(int, double, double)> spec) => [
      for (final (m, on, off) in spec)
        (midi: m, onMs: on, offMs: off, confidence: 1),
    ];
