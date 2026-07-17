// lib/core/audio/chord_progression.dart
//
// The scoring engine for chord-progression play-along — the chord analogue of
// play_along.dart. You strum/play a progression (C → G → Am → F) and it scores
// each chord against a moving chart, using the fuzzy ChordDetector: a chord
// counts as hit if the target appears among the detector's top candidates for
// enough of its beat. Pure Dart, no Flutter; unit-tested with fabricated
// ChordReadings in test/chord_progression_test.dart.

import 'dart:math';

import 'package:comet_beat/core/audio/chroma_analysis.dart';

/// One target chord positioned in musical time (beats from the chart start).
class TargetChord {
  const TargetChord({
    required this.rootPc,
    required this.suffix,
    required this.startBeat,
    required this.beats,
  });

  /// Root pitch class, 0 = C … 11 = B.
  final int rootPc;

  /// Chord-quality suffix as used by [ChordCandidate] ('', 'm', '7', 'maj7'…).
  final String suffix;

  final double startBeat;
  final double beats;

  double get endBeat => startBeat + beats;

  /// Does [c] name this same chord?
  bool matches(ChordCandidate c) => c.rootPc == rootPc && c.suffix == suffix;

  /// MIDI notes for playback/preview, voiced from [baseOctaveC].
  List<int> midis({int baseOctaveC = 48}) {
    final template =
        kChordTemplates.firstWhere((t) => t.suffix == suffix).intervals;
    return [for (final iv in template) baseOctaveC + rootPc + iv];
  }
}

/// A chord progression at a fixed tempo.
class ChordChart {
  const ChordChart({
    required this.name,
    required this.bpm,
    required this.chords,
  });

  final String name;
  final int bpm;
  final List<TargetChord> chords;

  double get beatMs => 60000.0 / bpm;
  double get totalBeats =>
      chords.isEmpty ? 0 : chords.map((c) => c.endBeat).reduce(max);
  double get totalMs => totalBeats * beatMs;
}

enum ChordResult { pending, hit, missed }

/// Mutable per-chord scoring state.
class ChordTargetState {
  ChordTargetState(this.target);

  final TargetChord target;
  ChordResult result = ChordResult.pending;

  int _good = 0;
  int _total = 0;

  /// Fraction of sampled frames (while active) where the target was detected.
  double get coverage => _total == 0 ? 0 : _good / _total;
}

/// Feed [update] elapsed time + the latest [ChordReading]; read [chords],
/// [activeChord], [hits], [accuracy], [finished] for the UI.
class ChordProgressionEngine {
  ChordProgressionEngine(
    this.chart, {
    this.topN = 2,
    this.hitCoverage = 0.35,
    this.leadInBeats = 4,
  }) : chords = chart.chords.map(ChordTargetState.new).toList();

  final ChordChart chart;

  /// Accept the target if it appears within the detector's top-[topN]
  /// candidates — chord detection is fuzzy, so being lenient here matters.
  final int topN;

  /// Fraction of a chord's active frames that must detect it to count as a hit.
  /// Lower than for single notes: a strum's attack/decay is only cleanly
  /// analysable for part of the beat.
  final double hitCoverage;

  final double leadInBeats;

  final List<ChordTargetState> chords;

  double _elapsedMs = 0;

  double get currentBeat => _elapsedMs / chart.beatMs - leadInBeats;
  bool get inCountIn => currentBeat < 0;
  bool get finished => currentBeat >= chart.totalBeats;

  int get hits => chords.where((c) => c.result == ChordResult.hit).length;
  double get accuracy => chords.isEmpty ? 0 : hits / chords.length;

  ChordTargetState? get activeChord {
    final b = currentBeat;
    for (final c in chords) {
      if (b >= c.target.startBeat && b < c.target.endBeat) return c;
    }
    return null;
  }

  void update({required double elapsedMs, required ChordReading reading}) {
    _elapsedMs = elapsedMs;
    final b = currentBeat;

    for (final c in chords) {
      if (c.result == ChordResult.pending && b >= c.target.endBeat) {
        c.result =
            c.coverage >= hitCoverage ? ChordResult.hit : ChordResult.missed;
      }
    }

    final active = activeChord;
    if (active != null && active.result == ChordResult.pending) {
      active._total++;
      final top = reading.candidates.take(topN);
      if (top.any(active.target.matches)) active._good++;
    }
  }

  void reset() {
    _elapsedMs = 0;
    for (final c in chords) {
      c.result = ChordResult.pending;
      c._good = 0;
      c._total = 0;
    }
  }
}

/// Built-in progressions.
class ChordCharts {
  /// I–IV–V7–I in C major (a cadence), slow.
  static const cadenceInC = ChordChart(
    name: 'Cadence in C',
    bpm: 60,
    chords: [
      TargetChord(rootPc: 0, suffix: '', startBeat: 0, beats: 2), // C
      TargetChord(rootPc: 5, suffix: '', startBeat: 2, beats: 2), // F
      TargetChord(rootPc: 7, suffix: '7', startBeat: 4, beats: 2), // G7
      TargetChord(rootPc: 0, suffix: '', startBeat: 6, beats: 2), // C
    ],
  );

  /// The I–V–vi–IV pop turnaround in C, a whole bar each.
  static const popTurnaround = ChordChart(
    name: 'Pop turnaround (C–G–Am–F)',
    bpm: 80,
    chords: [
      TargetChord(rootPc: 0, suffix: '', startBeat: 0, beats: 4), // C
      TargetChord(rootPc: 7, suffix: '', startBeat: 4, beats: 4), // G
      TargetChord(rootPc: 9, suffix: 'm', startBeat: 8, beats: 4), // Am
      TargetChord(rootPc: 5, suffix: '', startBeat: 12, beats: 4), // F
    ],
  );
}
