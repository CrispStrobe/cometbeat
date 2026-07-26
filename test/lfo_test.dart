// The shared LFO shape ([lfoValue] in crisp_dsp/lfo.dart) — extracted from the
// replayer so the FX rack's auto-wah can reuse the exact same waveform.
//
// Two properties:
//  1. SHAPES — sine/ramp/square are the values the tracker's E4x/E7x/S5x
//     waveform selects assert against, and out-of-range selectors fall back to
//     sine.
//  2. DELEGATION — the replayer's public `trackerLfo` now forwards to
//     `lfoValue`, so the two are bit-identical for every waveform/phase (the
//     vibrato/tremolo trajectory is unchanged by the extraction).

import 'dart:math';

import 'package:comet_beat/core/audio/crisp_dsp/lfo.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart' show trackerLfo;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lfoValue shapes', () {
    test('sine (waveform 0)', () {
      expect(lfoValue(0, 0), closeTo(0, 1e-12));
      expect(lfoValue(0, pi / 2), closeTo(1, 1e-12));
      expect(lfoValue(0, pi), closeTo(0, 1e-12));
      expect(lfoValue(0, 3 * pi / 2), closeTo(-1, 1e-12));
    });

    test('ramp-down (waveform 1): +1 at cycle start, sloping to −1', () {
      expect(lfoValue(1, 0), closeTo(1, 1e-12));
      expect(lfoValue(1, pi), closeTo(0, 1e-12)); // half cycle
      expect(lfoValue(1, 2 * pi - 1e-9), closeTo(-1, 1e-6)); // end of cycle
    });

    test('square (waveform 2): ±1 by the sign of sin', () {
      expect(lfoValue(2, pi / 2), 1.0);
      expect(lfoValue(2, 3 * pi / 2), -1.0);
      expect(lfoValue(2, 0), 1.0); // sin(0) == 0 → ≥ 0 branch
    });

    test('out-of-range selector (3, "random") falls back to sine', () {
      for (final phase in [0.0, 0.7, pi, 4.2, 6.0]) {
        expect(lfoValue(3, phase), closeTo(sin(phase), 1e-12));
        expect(lfoValue(7, phase), closeTo(sin(phase), 1e-12)); // & 3 == 3
      }
    });

    test('output always in [-1, 1]', () {
      for (var w = 0; w < 4; w++) {
        for (var i = 0; i < 500; i++) {
          final v = lfoValue(w, i * 0.137);
          expect(v, inInclusiveRange(-1.0, 1.0));
        }
      }
    });
  });

  test('trackerLfo delegates to lfoValue bit-for-bit', () {
    for (var w = 0; w < 8; w++) {
      for (var i = 0; i < 1000; i++) {
        final phase = i * 0.0193 * pi;
        expect(trackerLfo(w, phase), lfoValue(w, phase));
      }
    }
  });
}
