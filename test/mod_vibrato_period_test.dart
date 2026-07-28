// Vibrato is a PERIOD wobble, not a pitch wobble.
//
// ProTracker adds `(vibratoTable[pos] * depth) >> 7` to the PERIOD each tick,
// the table peaking at 255 (`pt2_replayer.c` vibrato), so the peak period
// deviation is `255/128 · depth` units. Period and pitch are logarithmic, so a
// constant period wobble is NOT a constant semitone wobble: the same depth bends
// a high note further, and the up/down halves are asymmetric in pitch.
//
// Our default models a flat semitone depth (`kVibratoDepthSemitonesPerUnit`) —
// the vibrato twin of the portamento semitone approximation B3 fixed. It is
// ~1.6× too deep at the reference note and wrong in SHAPE everywhere, which is
// the residual PLAN.md §6 X1 left open (~0.02 spectral). `PORTA_PERIOD=1` turns
// on the period-accurate model for the whole pitch-effect family at once.
//
// These tests pin the ARITHMETIC, so they run everywhere — the audio A/B needs
// openmpt123/xmp/micromod and only runs opt-in on a developer machine.

import 'dart:math' as math;

import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:flutter_test/flutter_test.dart';

double _cents(double a, double b) => 1200 * math.log(b / a) / math.ln2;

/// The replayer's period-accurate vibrato apply-site formula for one sample:
/// a period offset of `depth · kVibratoPeriodPerDepthUnit · lfo`, applied in
/// period space. (`lfo` is the ±1 normalized waveform.)
double _vib(double pitch, int depth, double lfo) =>
    slidePitchByPeriod(pitch, depth * kVibratoPeriodPerDepthUnit * lfo);

void main() {
  group('period-accurate vibrato depth', () {
    test('peak wobble is 255/128 period units per depth-unit', () {
      expect(kVibratoPeriodPerDepthUnit, closeTo(1.9921875, 1e-9));
      // ProTracker's ~2·y peak: depth 8 ⇒ ~16 period units.
      expect(8 * kVibratoPeriodPerDepthUnit, closeTo(15.9375, 1e-9));
    });

    test(
        'a positive LFO LOWERS the pitch (period adds) and is shallower than '
        'the semitone model', () {
      // At the LFO peak, depth 8, from the reference note (period 428).
      final periodPeak = _vib(60, 8, 1);
      // Old model: pitch + 8·(1/8)·1 = +1.0 semitone, and UP.
      expect(60 + 8 * kVibratoDepthSemitonesPerUnit * 1, closeTo(61, 1e-9));
      // Period-accurate: adding ~15.94 to the period drops the pitch ~0.63 st
      // (a LONGER period is a LOWER pitch, hence minus).
      final expected = 60 - _cents(428, 428 + 15.9375) / 100;
      expect(periodPeak, closeTo(expected, 1e-9));
      expect(periodPeak - 60, closeTo(-0.633, 0.01));
    });

    test('the up and down halves are ASYMMETRIC in pitch (period space)', () {
      final down = 60 - _vib(60, 8, 1); // +period ⇒ pitch below 60
      final up = _vib(60, 8, -1) - 60; // −period ⇒ pitch above 60
      expect(down, greaterThan(0));
      expect(up, greaterThan(0));
      // A shorter period bends further per unit, so the UP half is the larger
      // excursion — a symmetry the flat semitone model cannot reproduce.
      expect(up, greaterThan(down));
    });

    test('the same depth bends a HIGH note further', () {
      final atMid = (60 - _vib(60, 8, 1)).abs(); // period 428
      final atHigh = (72 - _vib(72, 8, 1)).abs(); // period 214, an octave up
      expect(
        atHigh,
        greaterThan(atMid * 1.5),
        reason: 'a shorter period wobbles further in semitones: '
            'mid $atMid st, high $atHigh st',
      );
    });
  });

  test('vibrato follows the same per-format domain as portamento', () {
    // This used to assert the state of the shared `PORTA_PERIOD` switch. The
    // switch is gone; what matters now is that vibrato and portamento agree
    // about the domain, because they did NOT once — the two branches bent
    // opposite ways depending on the gate, which is why the sign lives inside
    // PitchDomain now.
    for (final profile in [
      ReplayProfile.protracker,
      ReplayProfile.screamTracker,
      ReplayProfile.fastTracker,
      ReplayProfile.impulse,
      ReplayProfile.native,
    ]) {
      final bent = profile.pitch.vibrato(60, 8, 1);
      expect(
        bent,
        lessThan(60),
        reason: '${profile.name}: a positive lobe must bend DOWN in every '
            'domain — that is what adding to the period does',
      );
    }
    expect(kVibratoDepthSemitonesPerUnit, 1 / 8);
  });
}
