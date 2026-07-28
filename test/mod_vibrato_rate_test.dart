// Vibrato and tremolo: rate, depth, shape, and when the LFO runs.
//
// PLAN.md §6 X1 closed every effect fixture except vibrato, which sat at 0.979
// against references that agreed at 0.999, with `6xy` tracking it exactly
// (0.977) — one shared LFO, not two faults. The PLAN guessed the depth scale
// and the period-vs-pitch question, by analogy with portamento. Both guesses
// were wrong. The fault was the RATE.
//
// ProTracker adds `x*4` to an 8-bit position each tick and indexes a 32-entry
// table with `(pos >> 2) & 0x1F`, taking the sign from `pos < 128`. The
// position therefore wraps every 256 units, so a full cycle takes 256/(4x) =
// **64/x ticks**. We used 32/x — every vibrato in every module ran at exactly
// twice its intended rate. No reading of the format produces 32/x; this was a
// plain bug, not one of the deliberate musical approximations.
//
// Fixing it took vibrato from 0.979 to 0.994 in the SHIPPED configuration and
// to 0.999 under `PORTA_PERIOD=1`, where it now matches the references as
// closely as they match each other. `6xy` moved with it, as one shared LFO
// predicts.
//
// Three smaller findings came out of the same read, each pinned below:
//   - tremolo's depth is `>> 6` where vibrato's is `>> 7`, so ~4 volume units
//     per depth-unit, not the 1.0 we used;
//   - the LFOs do not run on tick 0 at all;
//   - a new note restarts them only when bit 2 of the waveform select is clear.
//
// These are pure arithmetic and trajectory checks, so they run everywhere. The
// audio measurement behind them needs openmpt123/xmp/mod2wav and lives in the
// opt-in `tracker_effect_reference_sweep_test.dart`.

import 'dart:math' as math;

import 'package:comet_beat/core/audio/tracker_engine.dart' show TrackerCell;
import 'package:comet_beat/core/audio/tracker_replay.dart'
    show kDefaultTicksPerRow, kFxSetVolume;
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LFO rate', () {
    test('a full vibrato cycle takes 64/x ticks, not 32/x', () {
      // The whole X2 finding in one assertion. Speed 1 → 64 ticks per cycle.
      const ticksPerCycle = 2 * math.pi / kVibratoRadPerSpeedUnit;
      expect(ticksPerCycle, closeTo(64, 1e-9));
      // Speed 4 → 16 ticks.
      expect(4 * kVibratoRadPerSpeedUnit * 16, closeTo(2 * math.pi, 1e-9));
    });

    test('tremolo runs at the same rate as vibrato', () {
      expect(kTremoloRadPerSpeedUnit, kVibratoRadPerSpeedUnit);
    });

    test('panbrello runs at IT\'s 256/x, not ProTracker\'s 64/x', () {
      // This used to assert 32/x and called it deliberate: ProTracker has no
      // panbrello, so the 64/x finding was no evidence about it, and rather
      // than let a ProTracker result silently change an untested effect the
      // constant was left alone with a comment admitting it was unverified.
      //
      // That was the right call to make without evidence, and the wrong number.
      // Counting pan sweeps off the reference renders of
      // `test/fixtures/fmt/panbrello_*.it` put us EIGHT times too fast — 18
      // cycles where libopenmpt counted 3 — because IT steps a 256-entry table
      // by the speed nibble. See PLAN.md §6.
      expect(kPanbrelloRadPerSpeedUnit, isNot(kVibratoRadPerSpeedUnit));
      expect(2 * math.pi / kPanbrelloRadPerSpeedUnit, closeTo(256, 1e-9));
      // A quarter of vibrato's rate — the two are genuinely different rules,
      // which is why they keep separate constants.
      expect(
        kPanbrelloRadPerSpeedUnit * 4,
        closeTo(kVibratoRadPerSpeedUnit, 1e-12),
      );
    });
  });

  group('depth', () {
    test('vibrato depth is 255/128 period units per depth-unit', () {
      // `(table[i] * y) >> 7` over a table peaking at 255.
      expect(kVibratoPeriodPerDepthUnit, closeTo(255 / 128, 1e-12));
      // A depth nibble of 15 bends just under 30 period units either way.
      expect(15 * kVibratoPeriodPerDepthUnit, closeTo(29.88, 0.01));
    });

    test('tremolo depth is 255/64 volume units — FOUR times what we used', () {
      // `>> 6`, one shift less than vibrato. We had 1.0 per depth-unit, so
      // every tremolo swung a quarter as far as it should.
      expect(kTremoloDepthPerUnit, closeTo(255 / 64, 1e-12));
      // `7xF` therefore covers essentially the whole 0..64 volume range.
      expect(15 * kTremoloDepthPerUnit, greaterThan(kMaxVolume - 5));
    });

    test('a period-unit depth bends further at high pitch than at low', () {
      // The same reason the semitone model cannot be right: a fixed period
      // delta is a bigger interval on a short period.
      const delta = 8 * kVibratoPeriodPerDepthUnit;
      final lowBend = 48 - pitchForPeriod(periodForPitch(48) + delta);
      final highBend = 72 - pitchForPeriod(periodForPitch(72) + delta);
      expect(highBend, greaterThan(lowBend * 2));
    });
  });

  group('protrackerLfo shape', () {
    test('sine and square agree with the general-purpose LFO', () {
      for (final phase in [0.0, 0.7, 2.0, 3.5, 5.9]) {
        expect(protrackerLfo(0, phase), closeTo(trackerLfo(0, phase), 1e-12));
        expect(protrackerLfo(2, phase), closeTo(trackerLfo(2, phase), 1e-12));
      }
    });

    test('the ramp RISES where the general-purpose one falls', () {
      // ProTracker's ramp is `+(i<<3)` on the first half and `-(255 - (i<<3))`
      // on the second, which over a whole cycle is a rising sawtooth in period
      // space. Reusing the falling `lfoValue` ramp here would invert E41.
      expect(protrackerLfo(1, 0), closeTo(0.0, 1e-12));
      expect(protrackerLfo(1, math.pi * 0.99), greaterThan(0.9));
      expect(protrackerLfo(1, math.pi * 1.01), lessThan(-0.9));
      expect(protrackerLfo(1, 2 * math.pi * 0.999), closeTo(0.0, 0.01));
      // The general-purpose one goes the other way, which is why they are
      // separate functions rather than one shared table.
      expect(trackerLfo(1, 0), closeTo(1.0, 1e-12));
    });

    test('every shape stays inside [-1, 1]', () {
      for (var w = 0; w < 4; w++) {
        for (var i = 0; i < 200; i++) {
          final v = protrackerLfo(w, i * 0.1);
          expect(v, inInclusiveRange(-1.0, 1.0));
        }
      }
    });
  });

  group('when the LFO runs', () {
    test('tick 0 carries the plain note; the LFO starts at tick 1', () {
      // ProTracker reads the row and triggers voices on tick 0, and runs the
      // per-tick effect handler only on ticks 1..speed-1.
      final t = traceChannel([
        const TrackerCell(midi: 60, fxCmd: kFxExtended, fxParam: 0x42), // E42
        const TrackerCell(fxCmd: kFxVibrato, fxParam: 0x88),
      ]);
      expect(t.pitchAt(1, 0), closeTo(60, 1e-9));
      expect((t.pitchAt(1, 1) - 60).abs(), greaterThan(0.1));
    });

    test('the sine reads the table BEFORE advancing it', () {
      // So the first effect tick sits on the zero crossing and the bend only
      // becomes visible on the second — the detail that made my first
      // direction assertion fail.
      final t = traceChannel([
        const TrackerCell(midi: 60),
        const TrackerCell(fxCmd: kFxVibrato, fxParam: 0x48),
      ]);
      expect(t.pitchAt(1, 1), closeTo(60, 1e-9));
      expect(t.pitchAt(1, 2), lessThan(60));
    });

    test('the first lobe bends DOWN, because it LENGTHENS the period', () {
      final t = traceChannel([
        const TrackerCell(midi: 60),
        const TrackerCell(fxCmd: kFxVibrato, fxParam: 0x48),
      ]);
      final firstHalf = [
        for (var k = 2; k < kDefaultTicksPerRow; k++) t.pitchAt(1, k),
      ];
      expect(
        firstHalf.every((p) => p <= 60 + 1e-9),
        isTrue,
        reason: 'adding the LFO to the PITCH instead of the period made every '
            'vibrato start upward — a half cycle out of phase with the '
            'hardware and with every reference player: $firstHalf',
      );
    });

    test('tremolo also skips tick 0', () {
      const base = kMaxVolume ~/ 2;
      final t = traceChannel([
        const TrackerCell(midi: 60, fxCmd: kFxSetVolume, fxParam: base),
        const TrackerCell(fxCmd: kFxExtended, fxParam: 0x72), // E72 square
        const TrackerCell(fxCmd: kFxTremolo, fxParam: 0x88),
      ]);
      expect(t.volumeAt(2, 0), closeTo(base.toDouble(), 1e-9));
      expect((t.volumeAt(2, 1) - base).abs(), greaterThan(1));
    });
  });

  group('LFO retrigger on a new note', () {
    // Bit 2 of the waveform select is the "continue through the note" flag —
    // which is why the nibble runs 0..7 for three shapes. We reset
    // unconditionally, so a module using it had its LFO restarted every note.
    test('E40 (sine, retrigger) restarts the LFO on each note', () {
      final t = traceChannel([
        const TrackerCell(midi: 60, fxCmd: kFxExtended, fxParam: 0x40),
        const TrackerCell(fxCmd: kFxVibrato, fxParam: 0x48),
        const TrackerCell(midi: 60, fxCmd: kFxVibrato, fxParam: 0x48),
      ]);
      // Row 2 re-triggers, so its trajectory repeats row 1's.
      for (var k = 0; k < kDefaultTicksPerRow; k++) {
        expect(t.pitchAt(2, k), closeTo(t.pitchAt(1, k), 1e-9));
      }
    });

    test('E44 (sine, CONTINUE) carries the phase across the new note', () {
      final t = traceChannel([
        const TrackerCell(midi: 60, fxCmd: kFxExtended, fxParam: 0x44),
        const TrackerCell(fxCmd: kFxVibrato, fxParam: 0x48),
        const TrackerCell(midi: 60, fxCmd: kFxVibrato, fxParam: 0x48),
      ]);
      final differs = [
        for (var k = 1; k < kDefaultTicksPerRow; k++)
          (t.pitchAt(2, k) - t.pitchAt(1, k)).abs(),
      ].any((d) => d > 1e-6);
      expect(
        differs,
        isTrue,
        reason: 'with the continue flag set the second note must NOT repeat '
            'the first note trajectory',
      );
    });
  });
}
