// W-METRE — meter + downbeat estimation. Built from RhythmGrids directly (no
// audio): a waltz (onset every 3rd beat) reads as 3/4, a common-time pattern
// (strong beats 1 & 3) reads as 4/4, and the downbeat phase follows a pickup.

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/metre.dart';
import 'package:flutter_test/flutter_test.dart';

// A grid of [nBeats] beats at [bpm]; onsets are placed on the beat indices in
// [onBeats] (repeating every [group] beats), each nudged by 0 ms (dead on).
RhythmGrid _grid({
  required int nBeats,
  double bpm = 120,
  required int group,
  required Set<int> onBeats,
}) {
  final beatMs = <double>[];
  final onsetMs = <double>[];
  final period = 60000 / bpm;
  for (var i = 0; i < nBeats; i++) {
    final t = i * period;
    beatMs.add(t);
    if (onBeats.contains(i % group)) onsetMs.add(t);
  }
  return (bpm: bpm, beatMs: beatMs, onsetMs: onsetMs);
}

void main() {
  test('a waltz (onset every 3rd beat) is 3/4', () {
    final m = estimateMeter(
      _grid(nBeats: 24, group: 3, onBeats: {0}),
    );
    expect(m.beatsPerBar, 3);
    expect(m.beatUnit, 4);
    // Downbeats land on beats 0, 3, 6, … (every 3rd beat time).
    expect(m.downbeatMs.length, 8);
    expect(m.downbeatMs.first, 0.0);
  });

  test('a duple pattern (onset every 2nd beat) reads as 4/4, not 3/4', () {
    // Onsets on beats 0, 2, 4, … — a duple feel. With the default {4, 3}
    // candidates it resolves to the common 4/4 (2/4 is only offered explicitly).
    final m = estimateMeter(
      _grid(nBeats: 32, group: 2, onBeats: {0}),
    );
    expect(m.beatsPerBar, 4);
  });

  test('with 2/4 explicitly allowed, a duple pattern can read as 2/4', () {
    final m = estimateMeter(
      _grid(nBeats: 32, group: 2, onBeats: {0}),
      candidates: const [4, 3, 2],
    );
    // Onset every 2nd beat fits a bar of 2 perfectly → 2 wins once offered.
    expect(m.beatsPerBar, 2);
  });

  test('the downbeat phase follows a pickup (anacrusis)', () {
    // Onset on beats 1, 4, 7, … → downbeats are phase 1 in a 3/4 meter.
    final beatMs = [for (var i = 0; i < 24; i++) i * 500.0];
    final onsetMs = [for (var i = 1; i < 24; i += 3) i * 500.0];
    final m = estimateMeter(
      (bpm: 120, beatMs: beatMs, onsetMs: onsetMs),
    );
    expect(m.beatsPerBar, 3);
    // First downbeat is beat index 1 → 500 ms, not 0.
    expect(m.downbeatMs.first, 500.0);
  });

  test('uniform onsets (no accent) resolve to a safe 4/4', () {
    final m = estimateMeter(
      _grid(nBeats: 16, group: 1, onBeats: {0}), // an onset on every beat
    );
    expect(m.beatsPerBar, 4);
  });

  test('too few beats falls back to 4/4', () {
    final m = estimateMeter((bpm: 120, beatMs: [0, 500], onsetMs: [0]));
    expect(m.beatsPerBar, 4);
    expect(m.downbeatMs, isEmpty);
  });
}
