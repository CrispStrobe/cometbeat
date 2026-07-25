import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/envelope.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Tracker Envelope and KeyOff Behavior', () {
    test('applyEnvelope with sustainSamples correctly delays release', () {
      final buf = Float64List(44100); // 1 second buffer
      for (var i = 0; i < buf.length; i++) {
        buf[i] = 1.0; // DC signal
      }

      const env = Envelope(attack: 0.1, release: 0.2);

      // Sustain for 0.5 seconds, then release for 0.2 seconds
      const sustainSamples = 22050; // 0.5 seconds

      final voiced = applyEnvelope(buf, env, sustainSamples: sustainSamples);

      // Attack check
      expect(voiced[0], 0.0);
      expect(voiced[4410], 1.0); // 0.1s attack finishes

      // Sustain check
      expect(voiced[10000], 1.0);
      expect(voiced[22050], 1.0); // 0.5s sustain finishes

      // Release check
      expect(
        voiced[26460],
        closeTo(0.5, 0.01),
      ); // 0.6s (0.5 + 0.1 half release), approx 0.5
      expect(voiced[30870], 0.0); // 0.7s (0.5 + 0.2 release), reaches 0
    });

    test('noteRuns correctly identifies sustain and release steps', () {
      final cells = [
        const TrackerCell(midi: 60), // Row 0
        const TrackerCell(), // Row 1
        TrackerCell.noteCut, // Row 2
        const TrackerCell(), // Row 3
        const TrackerCell(midi: 62), // Row 4
        const TrackerCell(), // Row 5
      ];

      final runs = noteRuns(cells);

      expect(runs.length, 2);
      // First run: C-4, sustains for 2 steps (0, 1), releases for 2 steps (2, 3)
      expect(runs[0].$1, 60);
      expect(runs[0].$2, 2); // Sustain
      expect(runs[0].$3, 2); // Release

      // Second run: D-4, sustains for 2 steps (4, 5), cut by end of pattern
      expect(runs[1].$1, 62);
      expect(runs[1].$2, 2); // Sustain
      expect(runs[1].$3, 0); // Release
    });

    test('noteRuns handles same-cell note and keyOff correctly', () {
      final cells = [
        const TrackerCell(
          midi: 60,
          keyOff: true,
        ), // Trigger and cut immediately
        const TrackerCell(), // Release continues
      ];

      final runs = noteRuns(cells);

      expect(runs.length, 1);
      // Run: C-4, sustains for 0 steps, releases for 2 steps
      expect(runs[0].$1, 60);
      expect(runs[0].$2, 0); // Sustain (0 steps)
      expect(runs[0].$3, 2); // Release (cell 0 and 1)
    });
  });
}
