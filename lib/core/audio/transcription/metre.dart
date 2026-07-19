// lib/core/audio/transcription/metre.dart
//
// W-METRE (slice 1) — meter + downbeat estimation on top of Worker 2's beat grid
// (rhythm.dart's RhythmGrid). Our beat tracker finds the PULSE but not bar 1 or
// the time signature, so S5 assumed 4/4. This finds how the beats group into bars
// so the engraved score gets the RIGHT barlines and time signature — a 3/4 waltz
// reads as 3/4, not a mangled 4/4.
//
// Clean-room, patent-free, pure Dart (NOT madmom's DBN). The idea: real music
// puts more onset energy on downbeats. For each candidate bar length B ∈ {4,3,2}
// and phase, score how much stronger the onsets on the would-be downbeats are
// than on the other beats; the best (B, phase) wins, with a light prior toward
// common meters to break ties on ambiguous (uniform) input.

import 'package:comet_beat/core/audio/transcription/contracts.dart';

/// The estimated meter: [beatsPerBar]/[beatUnit] and the times of the downbeats.
typedef Meter = ({
  int beatsPerBar,
  int beatUnit,
  List<double> downbeatMs,
});

/// Estimate the meter of [grid]. [candidates] are the bar lengths to try (in
/// beats), most-preferred first. The default is `{4, 3}` because onset TIMES
/// alone can only resolve TRIPLE vs DUPLE — 4/4 and 2/4 are the same duple
/// pattern without onset strengths, so duple reads as the far more common 4/4.
/// (Pass `[4, 3, 2]` to allow 2/4, accepting that ambiguity.) Falls back to a
/// safe 4/4 when there aren't enough beats to judge.
Meter estimateMeter(
  RhythmGrid grid, {
  List<int> candidates = const [4, 3],
}) {
  final beats = grid.beatMs;
  if (beats.length < 4 || candidates.isEmpty) {
    return (beatsPerBar: 4, beatUnit: 4, downbeatMs: const []);
  }
  final period = (beats.last - beats.first) / (beats.length - 1);
  final tol = period * 0.3; // an onset within 30% of a beat "hits" it

  // Onset strength per beat: how close the nearest onset is (triangular kernel).
  final strength = [
    for (final t in beats) _onsetStrength(t, grid.onsetMs, tol),
  ];

  var bestB = candidates.first;
  var bestPhase = 0;
  var bestScore = double.negativeInfinity;
  for (var ci = 0; ci < candidates.length; ci++) {
    final b = candidates[ci];
    for (var phase = 0; phase < b; phase++) {
      var down = 0.0;
      var downN = 0;
      var off = 0.0;
      var offN = 0;
      for (var i = 0; i < strength.length; i++) {
        if ((i - phase) % b == 0) {
          down += strength[i];
          downN++;
        } else {
          off += strength[i];
          offN++;
        }
      }
      if (downN == 0) continue;
      final downMean = down / downN;
      final offMean = offN > 0 ? off / offN : 0.0;
      // Contrast (downbeats louder than the rest) + a small prior favouring the
      // earlier (more common) candidates so uniform input resolves to 4/4.
      final prior = (candidates.length - ci) * 1e-3;
      final score = (downMean - offMean) + prior;
      if (score > bestScore) {
        bestScore = score;
        bestB = b;
        bestPhase = phase;
      }
    }
  }

  final downbeatMs = [
    for (var i = 0; i < beats.length; i++)
      if ((i - bestPhase) % bestB == 0) beats[i],
  ];
  return (beatsPerBar: bestB, beatUnit: 4, downbeatMs: downbeatMs);
}

/// Strength of the onset nearest [t]: 1 when an onset lands exactly on the beat,
/// falling linearly to 0 at [tol] away, 0 beyond. Reads the closest onset only.
double _onsetStrength(double t, List<double> onsetMs, double tol) {
  if (onsetMs.isEmpty || tol <= 0) return 0;
  var best = 0.0;
  for (final o in onsetMs) {
    final d = (o - t).abs();
    if (d < tol) {
      final s = 1 - d / tol;
      if (s > best) best = s;
    }
  }
  return best;
}
