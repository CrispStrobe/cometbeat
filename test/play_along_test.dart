// test/play_along_test.dart
//
// Drives PlayAlongEngine with fabricated readings to prove the scoring logic:
// a perfect performance hits every note, silence misses every note, a wrong
// pitch misses, and octave-agnostic charts accept octave-shifted singing.

import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/play_along.dart';
import 'package:comet_beat/core/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

/// A reading exactly on [midi], [cents] off.
PitchReading _reading(int midi, {double cents = 0}) {
  final freq = 440.0 * _pow2((midi - 69 + cents / 100) / 12);
  return PitchReading(frequency: freq, clarity: 0.99, a4: 440);
}

double _pow2(double x) => _exp(x * 0.6931471805599453);
double _exp(double x) {
  // Small local exp to avoid importing dart:math for one call in the helper.
  var term = 1.0, sum = 1.0;
  for (var i = 1; i < 30; i++) {
    term *= x / i;
    sum += term;
  }
  return sum;
}

/// Play [chart] end-to-end, feeding [readingFor] at each simulated frame.
PlayAlongEngine _run(
  PlayAlongChart chart,
  PitchReading Function(NoteState? active) readingFor, {
  double frameMs = 20,
}) {
  final engine = PlayAlongEngine(chart);
  final totalMs = chart.totalMs + engine.leadInBeats * chart.beatMs + frameMs;
  for (var t = 0.0; t <= totalMs; t += frameMs) {
    engine.update(elapsedMs: t, reading: readingFor(engine.activeNote));
  }
  return engine;
}

void main() {
  test('perfect performance hits every note', () {
    final engine = _run(
      PlayAlongCharts.celloFirstPosition,
      (active) =>
          active == null ? PitchReading.silent() : _reading(active.note.midi),
    );
    expect(engine.finished, isTrue);
    expect(engine.hits, engine.notes.length);
    expect(engine.accuracy, 1.0);
    // avgCents ~ 0 on every hit note.
    for (final n in engine.notes) {
      expect(n.result, NoteResult.hit);
      expect(n.avgCents ?? 0, closeTo(0, 1));
    }
  });

  test('slightly flat but within tolerance still counts', () {
    final engine = _run(
      PlayAlongCharts.celloFirstPosition,
      (active) => active == null
          ? PitchReading.silent()
          : _reading(active.note.midi, cents: -20),
    );
    expect(engine.hits, engine.notes.length);
  });

  test('silence misses every note', () {
    final engine = _run(
      PlayAlongCharts.celloFirstPosition,
      (_) => PitchReading.silent(),
    );
    expect(engine.hits, 0);
    for (final n in engine.notes) {
      expect(n.result, NoteResult.missed);
    }
  });

  test('a wrong pitch (a third off) misses', () {
    final engine = _run(
      PlayAlongCharts.celloFirstPosition,
      (active) => active == null
          ? PitchReading.silent()
          : _reading(active.note.midi + 4),
    );
    expect(engine.hits, 0);
  });

  test('octave-agnostic sing chart accepts an octave-shifted voice', () {
    final engine = _run(
      PlayAlongCharts.twinkleSing,
      (active) => active == null
          ? PitchReading.silent()
          : _reading(active.note.midi - 12), // sung an octave low
    );
    expect(engine.hits, engine.notes.length);
  });

  test('exact-octave chart rejects an octave-shifted performance', () {
    final engine = _run(
      PlayAlongCharts.celloFirstPosition,
      (active) => active == null
          ? PitchReading.silent()
          : _reading(active.note.midi - 12),
    );
    expect(engine.hits, 0);
  });

  test('a perfect run earns 3 stars, a total miss earns 0', () {
    final perfect = _run(
      PlayAlongCharts.celloFirstPosition,
      (active) =>
          active == null ? PitchReading.silent() : _reading(active.note.midi),
    );
    expect(scoreToStars('cello_play_along', perfect.hits, perfect.hits > 0), 3);

    final silent = _run(
      PlayAlongCharts.celloFirstPosition,
      (_) => PitchReading.silent(),
    );
    expect(scoreToStars('cello_play_along', silent.hits, silent.hits > 0), 0);
  });

  test('slowing the tempo lengthens the chart but keeps the notes/hits', () {
    const base = PlayAlongCharts.celloFirstPosition;
    final slow = base.copyWith(bpm: (base.bpm * 0.5).round());
    expect(slow.notes, same(base.notes));
    expect(slow.totalMs, closeTo(base.totalMs * 2, base.totalMs * 0.02));
    // A perfect run at half tempo still hits every note.
    final engine = _run(
      slow,
      (active) =>
          active == null ? PitchReading.silent() : _reading(active.note.midi),
    );
    expect(engine.hits, engine.notes.length);
  });

  test('counts in before the first note', () {
    final engine = PlayAlongEngine(PlayAlongCharts.twinkleSing);
    expect(engine.inCountIn, isTrue);
    expect(engine.activeNote, isNull);
    engine.update(
      elapsedMs: engine.leadInBeats * engine.chart.beatMs + 1,
      reading: PitchReading.silent(),
    );
    expect(engine.inCountIn, isFalse);
  });

  group('practice loop', () {
    const loopChart = PlayAlongChart(
      name: 'loop',
      bpm: 60,
      notes: [
        TargetNote(midi: 60, startBeat: 0, beats: 1),
        TargetNote(midi: 62, startBeat: 1, beats: 1),
        TargetNote(midi: 64, startBeat: 2, beats: 1),
        TargetNote(midi: 65, startBeat: 3, beats: 1),
      ],
    );

    test('keeps musical time inside the loop and never finishes', () {
      final e = PlayAlongEngine(loopChart, leadInBeats: 0);
      final ms = loopChart.beatMs;
      e.setLoop(1, 3); // loop notes 1 and 2
      // Far past the loop end — time must have wrapped back into [1, 3).
      e.update(elapsedMs: 10 * ms, reading: PitchReading.silent());
      expect(e.currentBeat, greaterThanOrEqualTo(1.0));
      expect(e.currentBeat, lessThan(3.0));
      expect(e.finished, isFalse);
      // The note after the loop is never reached — stays pending.
      expect(e.notes[3].result, NoteResult.pending);
    });

    test('re-arms a hit note on the next pass', () {
      final e = PlayAlongEngine(loopChart, leadInBeats: 0);
      final ms = loopChart.beatMs;
      e.setLoop(1, 3);
      // Sample note 1 on-pitch across its beat so it registers as a hit...
      for (var t = 1.0; t < 2.0; t += 0.1) {
        e.update(elapsedMs: t * ms, reading: _reading(62));
      }
      // ...cross the loop end so note 1 finalizes, then wraps + re-arms.
      e.update(elapsedMs: 3.1 * ms, reading: PitchReading.silent());
      expect(e.notes[1].result, NoteResult.pending, reason: 're-armed');
    });

    test('clearing the loop lets playback finish', () {
      final e = PlayAlongEngine(loopChart, leadInBeats: 0);
      final ms = loopChart.beatMs;
      e.setLoop(1, 3);
      e.update(elapsedMs: 10 * ms, reading: PitchReading.silent());
      e.setLoop(null, null);
      e.update(elapsedMs: 20 * ms, reading: PitchReading.silent());
      expect(e.finished, isTrue);
    });
  });
}
