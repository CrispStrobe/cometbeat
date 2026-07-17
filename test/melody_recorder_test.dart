// test/melody_recorder_test.dart
//
// Feeds simulated PitchReadings to MelodyRecorder and checks it transcribes the
// sung pitch stream into the right notes, filtering blips and rests.

import 'package:comet_beat/core/audio/melody_recorder.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

PitchReading _r(int midi) => PitchReading(
      frequency: 440.0 * _pow2((midi - 69) / 12),
      clarity: 0.99,
      a4: 440,
    );
double _pow2(double x) {
  var t = 1.0, s = 1.0;
  final xl = x * 0.6931471805599453;
  for (var i = 1; i < 30; i++) {
    t *= xl / i;
    s += t;
  }
  return s;
}

/// Feed [segments] (midi or null for silence, each lasting ms) at [frameMs].
MelodyRecorder _record(
  List<(int?, int)> segments, {
  double frameMs = 20,
}) {
  final rec = MelodyRecorder();
  var t = 0.0;
  for (final (midi, ms) in segments) {
    final end = t + ms;
    while (t < end) {
      rec.update(
        elapsedMs: t,
        reading: midi == null ? PitchReading.silent() : _r(midi),
      );
      t += frameMs;
    }
  }
  rec.finish();
  return rec;
}

void main() {
  test('transcribes a three-note melody with rests', () {
    final rec = _record([
      (60, 300), // C4
      (null, 200), // rest
      (62, 300), // D4
      (64, 400), // E4
    ]);
    expect(rec.notes.map((n) => n.$1).toList(), [60, 62, 64]);
    for (final n in rec.notes) {
      expect(n.$2, greaterThan(200)); // roughly the held duration
    }
  });

  test('re-attacking the same note yields two notes (gap between)', () {
    final rec = _record([
      (67, 250),
      (null, 200),
      (67, 250),
    ]);
    expect(rec.notes.map((n) => n.$1).toList(), [67, 67]);
  });

  test('a too-short blip is dropped', () {
    final rec = _record([
      (60, 300),
      (61, 40), // 40 ms < minNoteMs → dropped
      (60, 300),
    ]);
    expect(rec.notes.map((n) => n.$1).toList(), [60, 60]);
  });

  test('reset clears the capture', () {
    final rec = _record([(60, 300)]);
    expect(rec.notes, isNotEmpty);
    rec.reset();
    expect(rec.notes, isEmpty);
  });
}
