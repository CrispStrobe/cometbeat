// renderCellsWithInstrument — voice a Loop Mixer pitched track with an arbitrary
// TrackerInstrument, proving the looper's grid cells are the same notes-on-a-grid
// model the tracker plays. Locks: a stem of the loop length, non-silent, chords
// sum, transpose shifts.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_engine.dart'
    show LoopTiming, PatternCell;
import 'package:comet_beat/core/audio/loop_instrument_render.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

SampleInstrument _voice() {
  final pcm = Float64List(2048);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = 0.4 * math.sin(2 * math.pi * 220 * i / 44100);
  }
  return SampleInstrument('v', pcm);
}

double _peak(Float64List x) {
  var p = 0.0;
  for (final s in x) {
    if (s.abs() > p) p = s.abs();
  }
  return p;
}

const _melody = <PatternCell>[
  PatternCell(midis: [60], steps: 4),
  PatternCell(midis: [64], steps: 4),
  PatternCell(midis: [67], steps: 4),
  PatternCell(midis: [72], steps: 4),
];

void main() {
  const timing = LoopTiming(tempoBpm: 120); // 2 bars = 16 steps

  test('renders a stem of the loop length, non-silent', () {
    final pcm = renderCellsWithInstrument(_melody, _voice(), timing);
    expect(pcm.length, timing.totalSamples);
    expect(_peak(pcm), greaterThan(0.01));
  });

  test('a rest cell (no midis) leaves that span quieter than a played span',
      () {
    final withRest = <PatternCell>[
      const PatternCell(midis: [60], steps: 8),
      const PatternCell(steps: 8), // second half is a rest
    ];
    final pcm = renderCellsWithInstrument(withRest, _voice(), timing);
    // energy in the first half (played) exceeds the second (rest) — allowing
    // for the note ringing a little into the rest.
    var a = 0.0, b = 0.0;
    final half = pcm.length ~/ 2;
    for (var i = 0; i < half; i++) {
      a += pcm[i] * pcm[i];
    }
    for (var i = half; i < pcm.length; i++) {
      b += pcm[i] * pcm[i];
    }
    expect(a, greaterThan(b));
  });

  test('transpose shifts every note (different audio)', () {
    final base = renderCellsWithInstrument(_melody, _voice(), timing);
    final up =
        renderCellsWithInstrument(_melody, _voice(), timing, transpose: 5);
    expect(up.length, base.length);
    expect(up, isNot(base));
  });

  test('a chord cell sums its tones (louder than a single note)', () {
    const single = <PatternCell>[
      PatternCell(midis: [60], steps: 16),
    ];
    const chord = <PatternCell>[
      PatternCell(midis: [60, 64, 67], steps: 16),
    ];
    final one = renderCellsWithInstrument(single, _voice(), timing);
    final three = renderCellsWithInstrument(chord, _voice(), timing);
    expect(_peak(three), greaterThan(_peak(one)));
  });
}
