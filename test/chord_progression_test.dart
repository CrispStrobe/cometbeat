// test/chord_progression_test.dart
//
// Drives ChordProgressionEngine with fabricated ChordReadings to prove the
// scoring: a perfect performance hits every chord, silence/wrong chords miss,
// and a target found only as the 2nd candidate still counts (fuzzy tolerance).

import 'package:comet_beat/core/audio/chord_progression.dart';
import 'package:comet_beat/core/audio/chroma_analysis.dart';
import 'package:comet_beat/core/tuning.dart';
import 'package:comet_beat/features/games/chords/chord_progression_screen.dart'
    show chordProgressionSriId;
import 'package:flutter_test/flutter_test.dart';

ChordReading _reading(List<ChordCandidate> candidates) =>
    ChordReading(candidates: candidates, chroma: List.filled(12, 0), energy: 1);

ChordCandidate _cand(int rootPc, String suffix, double score) =>
    ChordCandidate(rootPc: rootPc, suffix: suffix, score: score);

ChordProgressionEngine _run(
  ChordChart chart,
  ChordReading Function(ChordTargetState? active) readingFor, {
  double frameMs = 20,
}) {
  final engine = ChordProgressionEngine(chart);
  final totalMs = chart.totalMs + engine.leadInBeats * chart.beatMs + frameMs;
  for (var t = 0.0; t <= totalMs; t += frameMs) {
    engine.update(elapsedMs: t, reading: readingFor(engine.activeChord));
  }
  return engine;
}

void main() {
  test('perfect performance hits every chord', () {
    final engine = _run(
      ChordCharts.popTurnaround,
      (active) => active == null
          ? ChordReading.silent()
          : _reading([_cand(active.target.rootPc, active.target.suffix, 0.95)]),
    );
    expect(engine.finished, isTrue);
    expect(engine.hits, engine.chords.length);
    expect(engine.accuracy, 1.0);
  });

  test('a target found only as the 2nd candidate still counts (fuzzy)', () {
    final engine = _run(
      ChordCharts.popTurnaround,
      (active) => active == null
          ? ChordReading.silent()
          : _reading([
              _cand((active.target.rootPc + 5) % 12, 'm7', 0.8), // wrong best
              _cand(active.target.rootPc, active.target.suffix, 0.78), // right
            ]),
    );
    expect(engine.hits, engine.chords.length);
  });

  test('silence misses every chord', () {
    final engine =
        _run(ChordCharts.popTurnaround, (_) => ChordReading.silent());
    expect(engine.hits, 0);
  });

  test('the wrong chord misses', () {
    final engine = _run(
      ChordCharts.cadenceInC,
      (active) => active == null
          ? ChordReading.silent()
          // Always report D minor, regardless of the target.
          : _reading([_cand(2, 'm', 0.9)]),
    );
    expect(engine.hits, lessThan(engine.chords.length));
  });

  test('a perfect run earns 3 stars via the thresholds', () {
    final engine = _run(
      ChordCharts.popTurnaround,
      (active) => active == null
          ? ChordReading.silent()
          : _reading([_cand(active.target.rootPc, active.target.suffix, 0.95)]),
    );
    expect(scoreToStars('chord_play_along', engine.hits, engine.hits > 0), 3);
  });

  test('chordProgressionSriId spells root + quality', () {
    String id(int pc, String s) => chordProgressionSriId('cp', pc, s);
    expect(id(0, ''), 'cp.c');
    expect(id(9, 'm'), 'cp.am');
    expect(id(7, '7'), 'cp.g7');
    expect(id(6, 'dim'), 'cp.fsdim'); // F#dim
  });

  test('TargetChord.midis voices the right notes', () {
    // Am at base C3 (48): A(57) C(60) E(64).
    const am = TargetChord(rootPc: 9, suffix: 'm', startBeat: 0, beats: 1);
    expect(am.midis(), [57, 60, 64]);
  });
}
