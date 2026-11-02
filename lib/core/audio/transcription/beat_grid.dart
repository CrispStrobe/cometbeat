// lib/core/audio/transcription/beat_grid.dart
//
// A song's beat grid — beat times, which of them are downbeats, and the tempo.
// Pure Dart (web-safe); CrispASR's beat-this produces it natively
// (crispasr_ffi_beats_io.dart).

/// Beat times in milliseconds from the start of the audio.
class BeatGrid {
  const BeatGrid({
    required this.beatMs,
    required this.downbeatMs,
    required this.bpm,
  });

  /// Every beat, strictly increasing.
  final List<double> beatMs;

  /// The beats that start a bar (a subset of [beatMs]).
  final List<double> downbeatMs;

  /// The tempo, in beats per minute.
  final double bpm;

  bool get isEmpty => beatMs.isEmpty;

  /// Beats per bar — the commonest gap between downbeats, counted in beats.
  /// Null with fewer than two downbeats.
  int? get beatsPerBar {
    if (downbeatMs.length < 2) return null;
    final counts = <int, int>{};
    var b = 0;
    for (var d = 0; d + 1 < downbeatMs.length; d++) {
      while (b < beatMs.length && beatMs[b] < downbeatMs[d] - 1) {
        b++;
      }
      var n = 0;
      while (b + n < beatMs.length && beatMs[b + n] < downbeatMs[d + 1] - 1) {
        n++;
      }
      if (n > 0) counts[n] = (counts[n] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, c) => c.value > a.value ? c : a).key;
  }

  /// The first downbeat, or the first beat when no downbeat was found — the
  /// natural "beat 1" to align a chart or a count-in to.
  double? get firstDownbeatMs => downbeatMs.isNotEmpty
      ? downbeatMs.first
      : (beatMs.isEmpty ? null : beatMs.first);
}
