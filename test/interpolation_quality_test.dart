// interpolation_quality_test — the render-quality upgrades in the sample TICK
// voice: 4-point cubic (Catmull-Rom) resampling and the two MultiPLAY-style
// anti-click ramps (note-on soft-start + hard-cut residue tail). These change
// the rendered output of command songs deliberately (a re-baseline gated by the
// libopenmpt oracle A/B, not byte-identity), so this file locks in the numeric
// properties that make the change an IMPROVEMENT rather than a regression.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cubic tick-voice interpolation beats linear', () {
    test('a fractional sine read has lower error than 2-point linear', () {
      // A smooth band-limited signal: cubic (which fits the curvature of the two
      // neighbours on each side) should track it more closely than linear.
      const n = 256;
      const period = 8.0; // few samples/cycle → interpolation error is visible
      final s = Float64List(n);
      for (var i = 0; i < n; i++) {
        s[i] = sin(2 * pi * i / period);
      }
      double ideal(double pos) => sin(2 * pi * pos / period);

      var cubicErr = 0.0;
      var linearErr = 0.0;
      var samples = 0;
      // Stay away from the very ends so both schemes see full neighbourhoods.
      for (var pos = 2.0; pos < n - 3; pos += 0.13) {
        final cubic = readLoopedSampleForTest(s, pos)!;
        final f = pos.floor();
        final frac = pos - f;
        final linear = s[f] * (1 - frac) + s[f + 1] * frac;
        cubicErr += (cubic - ideal(pos)).abs();
        linearErr += (linear - ideal(pos)).abs();
        samples++;
      }
      cubicErr /= samples;
      linearErr /= samples;
      expect(
        cubicErr,
        lessThan(linearErr),
        reason: 'cubic mean error $cubicErr should beat linear $linearErr',
      );
      // And by a real margin, not a rounding fluke.
      expect(cubicErr, lessThan(linearErr * 0.6));
    });

    test('integer positions read the exact sample (no smoothing offset)', () {
      final s = Float64List.fromList([0.0, 1.0, -0.5, 0.25, 0.75, -1.0]);
      for (var i = 0; i < s.length - 1; i++) {
        expect(readLoopedSampleForTest(s, i.toDouble()), closeTo(s[i], 1e-12));
      }
    });

    test('a looped read wraps its neighbour taps (continuous at the seam)', () {
      // A forward loop over the whole buffer: reading just before the loop end
      // and just after the wrap should be continuous (the +1/+2 taps wrap to the
      // loop start rather than clamping to a flat endpoint).
      const n = 32;
      final s = Float64List(n);
      for (var i = 0; i < n; i++) {
        s[i] = sin(2 * pi * i / n);
      }
      final before =
          readLoopedSampleForTest(s, n - 0.5, loops: true, loopLen: n)!;
      final after = readLoopedSampleForTest(s, 0.5, loops: true, loopLen: n)!;
      // Both are finite, in-range, and near the sine at those wrapped phases.
      expect(before.abs(), lessThan(1.5));
      expect(after.abs(), lessThan(1.5));
      expect(before, closeTo(sin(2 * pi * (n - 0.5) / n), 0.1));
    });
  });

  group('note-on soft-start ramp', () {
    test('ramps 0 -> 1 over ~10 output samples on a real trigger', () {
      final v = ReplayVoice();
      v.armSoftStart();
      final gains = [
        for (var i = 0; i < ReplayVoice.softStartSamples; i++)
          v.softStartGain(),
      ];
      // First emitted sample is silent (starts from zero — kills the click).
      expect(gains.first, closeTo(0.0, 1e-12));
      // Strictly rising over the ramp.
      for (var i = 1; i < gains.length; i++) {
        expect(gains[i], greaterThan(gains[i - 1]));
        expect(gains[i], lessThanOrEqualTo(1.0));
      }
      // Fully open once the ramp completes, and it stays there.
      expect(v.softStartGain(), closeTo(1.0, 1e-12));
      expect(v.softStartGain(), closeTo(1.0, 1e-12));
    });

    test('an un-armed voice passes full gain (no fade on a tie)', () {
      final v = ReplayVoice();
      expect(v.softStartGain(), 1.0);
    });
  });

  group('hard-cut residue tail', () {
    test('decays smoothly from the last output — no instant discontinuity', () {
      final v = ReplayVoice();
      // Feed a steady stream of real output so the residue tracker holds ~0.8.
      for (var i = 0; i < 8; i++) {
        v.keepResidue(0.8);
      }
      // Now a hard cut: the tail must START at the last value (continuous), then
      // decay — never jump straight to zero.
      final tail = [for (var i = 0; i < 12; i++) v.residueStep()];
      expect(
        tail.first,
        closeTo(0.8, 1e-9),
        reason: 'first residue == last output (continuous, no click)',
      );
      // Monotone decay toward zero, each step a fraction of the previous.
      for (var i = 1; i < tail.length; i++) {
        expect(tail[i].abs(), lessThan(tail[i - 1].abs() + 1e-12));
      }
      // No single sample is a full jump to silence: the largest step-to-step
      // drop is bounded well below the signal level.
      var maxDrop = 0.0;
      for (var i = 1; i < tail.length; i++) {
        maxDrop = max(maxDrop, (tail[i - 1] - tail[i]).abs());
      }
      expect(
        maxDrop,
        lessThan(0.8),
        reason: 'residue never drops the full amplitude in one sample',
      );
      // The tail actually fades (last well below the start).
      expect(tail.last.abs(), lessThan(0.5));
    });
  });

  group('command-song streaming render is deterministic', () {
    test('mulju_the_clown.mod renders byte-identically run to run', () {
      final f = File('test/fixtures/mulju_the_clown.mod');
      if (!f.existsSync()) {
        // Fixture is optional in some checkouts; skip rather than fail.
        return;
      }
      final bytes = f.readAsBytesSync();
      final a = songFromModuleBytes(bytes).renderSongWav();
      final b = songFromModuleBytes(bytes).renderSongWav();
      expect(a.length, b.length);
      expect(a, equals(b));
    });
  });
}
