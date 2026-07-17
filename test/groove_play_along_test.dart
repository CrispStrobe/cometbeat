// grooveChart — groove cells → PlayAlongChart (the "follow the melody" bridge).
// Pure model tests: beat placement, rests as gaps, chord top-voice, and that a
// real engine track maps to a gradable chart PlayAlongEngine accepts.

import 'dart:math';

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/play_along.dart';
import 'package:comet_beat/features/games/composition/groove_play_along.dart';
import 'package:flutter_test/flutter_test.dart';

/// The exact frequency of an equal-tempered [midi] (A4 = 440) — so a fed
/// reading lands dead-on the target note.
double _freq(int midi) => 440.0 * pow(2.0, (midi - 69) / 12.0);

void main() {
  test('cells map to target notes in musical time (2 steps = 1 beat)', () {
    final chart = grooveChart(
      const [
        (midis: [60], steps: 2), // C4, one beat at beat 0
        (midis: null, steps: 2), // a rest — a gap, no note
        (midis: [64], steps: 4), // E4, two beats at beat 2
      ],
      bpm: 100,
      name: 'test',
    );
    expect(chart.bpm, 100);
    expect(chart.notes.length, 2, reason: 'the rest is a gap, not a note');

    expect(chart.notes[0].midi, 60);
    expect(chart.notes[0].startBeat, 0);
    expect(chart.notes[0].beats, 1);

    expect(chart.notes[1].midi, 64);
    expect(chart.notes[1].startBeat, 2, reason: 'after a 1-beat note + 1 rest');
    expect(chart.notes[1].beats, 2);
    expect(chart.totalBeats, 4);
  });

  test('a chord/dyad collapses to its top voice', () {
    final chart = grooveChart(
      const [
        (midis: [60, 64, 67], steps: 2), // C major triad → top note G4
      ],
      bpm: 120,
      name: 'chord',
    );
    expect(chart.notes.single.midi, 67);
  });

  test('octaveAgnostic passes through for sung targets', () {
    final chart = grooveChart(
      const [
        (midis: [60], steps: 2),
      ],
      bpm: 100,
      name: 'sing',
      octaveAgnostic: true,
    );
    expect(chart.octaveAgnostic, isTrue);
  });

  test('a real engine track becomes a chart PlayAlongEngine can grade', () {
    final engine = LoopEngine();
    final cells = engine.cellsFor('melody')!;
    final chart = grooveChart(cells, bpm: engine.tempoBpm, name: 'melody');
    expect(chart.notes, isNotEmpty);

    // Grade a perfect pass: feed each target's own pitch during its window.
    final player = PlayAlongEngine(chart, leadInBeats: 0);
    for (final n in chart.notes) {
      final midMs = (n.startBeat + n.beats / 2) * chart.beatMs;
      player.update(
        elapsedMs: midMs,
        reading: PitchReading(
          frequency: _freq(n.midi),
          clarity: 1,
          a4: kDefaultA4,
        ),
      );
    }
    // Past the end, finalize the last note.
    player.update(
      elapsedMs: chart.totalMs + chart.beatMs,
      reading: PitchReading.silent(),
    );
    expect(
      player.hits,
      greaterThan(0),
      reason: 'playing the target line scores hits',
    );
  });
}
