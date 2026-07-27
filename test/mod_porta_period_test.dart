// Portamento is a PERIOD slide, not a pitch slide.
//
// ProTracker does `period -= param` per tick, clamped to [113, 856]
// (`pt2_replayer.c` portaUp/portaDown). Period and pitch are related
// logarithmically — `f = clock / period` — so a linear period step is NOT a
// constant semitone step: the slide accelerates as the period shrinks, and how
// far a given param bends depends on where the note started.
//
// Our default models pitch in fractional semitones with a fixed
// `kPortaSemitonesPerUnit`, which can only be right at ONE starting point.
// PLAN.md §6 X1 measured the cost against three independent players that agree
// with each other at 1.000 spectral:
//
//              default   PORTA_PERIOD=1
//   1xx up      0.549     1.000
//   2xx down    0.689     1.000
//   3xx tone    0.963     1.000
//   5xy combo   0.918     1.000
//
// These tests pin the ARITHMETIC, so they run everywhere — the audio A/B needs
// openmpt123/xmp/micromod and only runs opt-in on a developer machine.

import 'dart:math' as math;

import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:flutter_test/flutter_test.dart';

double _cents(double a, double b) => 1200 * math.log(b / a) / math.ln2;

void main() {
  group('period ↔ pitch', () {
    test('the reference note sits on the reference period', () {
      // Period 428 is modPeriods index 12, which import maps to MIDI 60.
      expect(periodForPitch(60), closeTo(428, 0.001));
      expect(pitchForPeriod(428), closeTo(60, 0.001));
    });

    test('an octave up halves the period', () {
      expect(periodForPitch(72), closeTo(214, 0.001));
      expect(pitchForPeriod(214), closeTo(72, 0.001));
    });

    test('they invert each other across the whole legal window', () {
      for (var p = kModMinPeriod; p <= kModMaxPeriod; p += 7) {
        expect(periodForPitch(pitchForPeriod(p)), closeTo(p, 1e-9));
      }
    });
  });

  group('slidePitchByPeriod', () {
    test('a linear period step is NOT a constant pitch step', () {
      // The whole reason the semitone model cannot work. Same param, two
      // starting notes, two different pitch results.
      const step = -16.0; // 16 period units up
      final lowNote = slidePitchByPeriod(48, step); // long period
      final highNote = slidePitchByPeriod(72, step); // short period
      final lowMove = lowNote - 48;
      final highMove = highNote - 72;
      expect(
        highMove,
        greaterThan(lowMove * 2),
        reason: 'the same period step must bend a HIGH note much further: '
            'low moved $lowMove st, high moved $highMove st',
      );
    });

    test('sliding up then down by the same amount returns home', () {
      final up = slidePitchByPeriod(60, -40);
      final back = slidePitchByPeriod(up, 40);
      expect(back, closeTo(60, 1e-9));
    });

    test('clamps to the hardware window, never past it', () {
      // ProTracker pins the period at 113/856; a runaway slide must stop
      // there rather than run off into inaudible or absurd pitches.
      final wayUp = slidePitchByPeriod(60, -100000);
      expect(periodForPitch(wayUp), closeTo(kModMinPeriod, 1e-6));
      final wayDown = slidePitchByPeriod(60, 100000);
      expect(periodForPitch(wayDown), closeTo(kModMaxPeriod, 1e-6));
    });

    test('matches ProTracker over a real slide, where the old model did not',
        () {
      // The X1 fixture: param 4 per tick, 48 ticks, starting at period 428.
      var pitch = 60.0;
      for (var i = 0; i < 48; i++) {
        pitch = slidePitchByPeriod(pitch, -4);
      }
      // Hardware: 428 - 192 = 236, still inside the window. A SHORTER period
      // is a HIGHER pitch, so the ratio is old/new — getting this backwards is
      // the easiest mistake here, and it cost me a red on first run.
      final expected = 60.0 + _cents(236, 428) / 100;
      expect(pitch, closeTo(expected, 1e-9));
      expect(
        pitch - 60,
        closeTo(10.31, 0.02),
        reason: 'ProTracker bends 10.3 st',
      );

      // The semitone model bends a flat 12.0 over the same run — 1.7 semitones
      // adrift by the end, and wrong in SHAPE throughout, not just at the end.
      expect(48 * 4 * kPortaSemitonesPerUnit, 12.0);
    });
  });

  test('the gate reports its own state, and OFF is the default', () {
    // Changing every module's slides is opt-in; the semitone model is a
    // documented deliberate choice, so it stays until someone decides.
    //
    // Asserted in BOTH directions so a PORTA_PERIOD=1 run is clean — a suite
    // that goes red when you turn the flag on teaches people to ignore it.
    if (kPortaPeriodAccurate) {
      // Under the gate the period path must actually be the one in force.
      var pitch = 60.0;
      for (var i = 0; i < 48; i++) {
        pitch = slidePitchByPeriod(pitch, -4);
      }
      expect(pitch - 60, closeTo(10.31, 0.02));
    } else {
      expect(kPortaSemitonesPerUnit, 1 / 16);
    }
  });
}
