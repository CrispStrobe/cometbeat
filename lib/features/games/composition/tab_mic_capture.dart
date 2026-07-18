// Turns the live microphone pitch stream into tab placements: play a note on
// your guitar and it lands on the fretboard. Pure Dart (no Flutter, no plugin)
// — it just consumes `PitchReading`s — so the debounce/mapping is fully
// unit-testable without a microphone.

import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart'
    show pitchFromMidi;
import 'package:crisp_notation/crisp_notation.dart' show Tuning;

/// Debounces a live pitch stream into committed `(string, fret)` placements for
/// a [tuning].
///
/// A note commits only after [framesToCommit] consecutive frames agree on the
/// same pitch (and clear the [minClarity]/[minRms] gates), which rejects the
/// noisy attack/decay edges. A held note commits once; **silence re-arms**, so
/// playing the same note twice with a gap gives two placements.
class TabMicCapture {
  final Tuning tuning;
  final int framesToCommit;
  final double minClarity;
  final double minRms;
  final int maxFret;

  int? _candidate;
  int _count = 0;
  int? _lastCommitted;

  TabMicCapture(
    this.tuning, {
    this.framesToCommit = 3,
    this.minClarity = 0.9,
    this.minRms = 0.01,
    this.maxFret = 24,
  });

  /// Forgets any in-flight candidate (e.g. on tuning change or restart).
  void reset() {
    _candidate = null;
    _count = 0;
    _lastCommitted = null;
  }

  /// Feeds one [reading]; returns the `(string, fret)` when a new note commits,
  /// else null. String index 0 = the top tab line, matching [Tuning].
  (int string, int fret)? accept(PitchReading reading) {
    // Silence / unreliable frame: drop the candidate AND re-arm, so the same
    // note played again after a gap counts as a new placement.
    if (!reading.hasPitch ||
        reading.clarity < minClarity ||
        reading.rms < minRms) {
      _candidate = null;
      _count = 0;
      _lastCommitted = null;
      return null;
    }

    final midi = reading.nearestMidi;
    if (midi == _candidate) {
      _count++;
    } else {
      _candidate = midi;
      _count = 1;
    }

    if (_count < framesToCommit || midi == _lastCommitted) return null;

    final placement = tuning.fretFor(pitchFromMidi(midi), maxFret: maxFret);
    if (placement == null) return null; // unreachable on this tuning
    _lastCommitted = midi;
    return (placement.$1, placement.$2);
  }
}
