// test/metronome_test.dart
//
// The count-in metronome clicks the "1-2-3-4" plus the downbeat, accents the
// downbeat, then stays silent once the notes start (so it never plays over the
// audio the mic is scoring).

import 'package:comet_beat/core/audio/metronome.dart';
import 'package:flutter_test/flutter_test.dart';

/// Step the clicker from [start] beats through [end] and collect the beats it
/// clicked (and which were accented).
List<({int beat, bool accent})> _clicks(
  double start,
  double end, {
  double step = 0.1,
}) {
  final clicker = CountInClicker();
  final out = <({int beat, bool accent})>[];
  for (var beat = start; beat <= end; beat += step) {
    final r = clicker.update(beat);
    if (r.click) out.add((beat: beat.floor(), accent: r.accent));
  }
  return out;
}

void main() {
  test('clicks a 4-beat count-in plus the downbeat, then stops', () {
    // Lead-in of 4 beats: the clock runs from -4 to past 0.
    final clicks = _clicks(-4.0, 3.0);
    expect(clicks.map((c) => c.beat).toList(), [-4, -3, -2, -1, 0]);
    // No clicks once real notes begin (beat >= 1).
    expect(clicks.every((c) => c.beat <= 0), isTrue);
  });

  test('accents the first count beat and the downbeat', () {
    final clicks = _clicks(-4.0, 1.0);
    final accents = clicks.where((c) => c.accent).map((c) => c.beat).toList();
    expect(accents, [-4, 0]); // "1" of the count-in and the downbeat
  });

  test('reset lets the count-in play again', () {
    final clicker = CountInClicker();
    for (var b = -4.0; b <= 1.0; b += 0.1) {
      clicker.update(b);
    }
    clicker.reset();
    // After reset, the first crossed count-in beat clicks again.
    var clicked = false;
    for (var b = -4.0; b <= 0.0; b += 0.1) {
      if (clicker.update(b).click) clicked = true;
    }
    expect(clicked, isTrue);
  });
}
