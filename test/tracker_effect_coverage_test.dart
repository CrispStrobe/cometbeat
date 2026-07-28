// Replayer effect-coverage additions (opus libraries-and-tab, cross-lane) —
// E3x glissando, E4x/E7x vibrato/tremolo waveform, E5x set-finetune, and Rxy
// retrigger+volslide. Pure per-tick trajectory tests via `traceChannel` (no
// audio). Kept in a separate file from the worker's `tracker_effects_test.dart`.

import 'dart:math';

import 'package:comet_beat/core/audio/tracker_engine.dart' show TrackerCell;
import 'package:comet_beat/core/audio/tracker_replay.dart'
    show kDefaultTicksPerRow, kFxSetVolume;
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('trackerLfo waveform', () {
    test('sine is the default and smooth; square is two-valued; saw ramps', () {
      // Sine takes intermediate values; square only ±1.
      expect(trackerLfo(0, pi / 4), closeTo(sin(pi / 4), 1e-12));
      expect(trackerLfo(2, pi / 4), 1.0); // square, positive half
      expect(trackerLfo(2, pi + 0.1), -1.0); // square, negative half
      // Saw ramps down from +1 at the cycle start toward −1.
      expect(trackerLfo(1, 0), closeTo(1.0, 1e-12));
      expect(trackerLfo(1, pi), closeTo(0.0, 1e-12));
      // Waveform 3 ("random") falls back to sine (deterministic).
      expect(trackerLfo(3, pi / 3), closeTo(sin(pi / 3), 1e-12));
    });
  });

  group('E4x vibrato waveform', () {
    // NB tick 0 is excluded throughout this group. ProTracker reads the row and
    // triggers voices on tick 0 and runs the per-tick effect handler only on
    // ticks 1..speed-1, so a vibrato'd note sounds UNBENT for its first tick.
    // These loops used to start at 0 and passed because the LFO also advanced
    // on tick 0 — the bug and the test agreed with each other. See PLAN.md §6
    // X2.
    test('square vibrato deviates by exactly ±depth on every effect tick', () {
      const depth = 8 * kVibratoDepthSemitonesPerUnit; // 4xy depth nibble = 8
      // Row 0: note + E42 (select square waveform). Row 1: vibrato 4-8-8.
      final t = traceChannel([
        const TrackerCell(midi: 60, fxCmd: kFxExtended, fxParam: 0x42),
        const TrackerCell(fxCmd: kFxVibrato, fxParam: 0x88),
      ]);
      expect(
        t.pitchAt(1, 0),
        closeTo(60, 1e-9),
        reason: 'tick 0 carries the note, not the vibrato',
      );
      for (var k = 1; k < kDefaultTicksPerRow; k++) {
        expect(
          (t.pitchAt(1, k) - 60).abs(),
          closeTo(depth, 1e-9),
          reason: 'square vibrato is full-depth at every tick (tick $k)',
        );
      }
    });

    test('the default sine vibrato is NOT always full-depth', () {
      const depth = 8 * kVibratoDepthSemitonesPerUnit;
      final t = traceChannel([
        const TrackerCell(midi: 60), // no waveform set → sine
        const TrackerCell(fxCmd: kFxVibrato, fxParam: 0x88),
      ]);
      final anyIntermediate = [
        for (var k = 1; k < kDefaultTicksPerRow; k++)
          (t.pitchAt(1, k) - 60).abs(),
      ].any((d) => d < depth - 1e-6);
      expect(anyIntermediate, isTrue);
    });

    test('the sine bends DOWN first, as lengthening the period does', () {
      // ProTracker ADDS the first LFO lobe to the period, and a longer period
      // is a lower pitch. We used to add it to the pitch instead, so every
      // vibrato started by bending up — a half-cycle out of phase with the
      // hardware and every reference player.
      final t = traceChannel([
        const TrackerCell(midi: 60),
        const TrackerCell(fxCmd: kFxVibrato, fxParam: 0x48),
      ]);
      // Tick 0 is not an effect tick, and tick 1 reads the table BEFORE
      // advancing it — position 0, the zero crossing — so the earliest tick
      // that can show a direction at all is tick 2.
      expect(t.pitchAt(1, 1), closeTo(60, 1e-9));
      expect(t.pitchAt(1, 2), lessThan(60));
    });
  });

  group('E7x tremolo waveform', () {
    test('square tremolo swings volume by exactly ±depth', () {
      const depth = 8 * kTremoloDepthPerUnit; // 7xy depth nibble = 8
      // Centre the base volume: the real depth is ~4 units per nibble
      // (`>> 6`, not vibrato's `>> 7`), so a nibble of 8 swings ±31.9 and
      // anything but a mid-scale base would clamp. The old base of 48 only
      // worked because the depth was a quarter of what the hardware uses.
      const base = kMaxVolume ~/ 2;
      final t = traceChannel([
        const TrackerCell(midi: 60, fxCmd: kFxSetVolume, fxParam: base),
        // E72: select the square tremolo waveform.
        const TrackerCell(fxCmd: kFxExtended, fxParam: 0x72),
        const TrackerCell(fxCmd: kFxTremolo, fxParam: 0x88),
      ]);
      for (var k = 1; k < kDefaultTicksPerRow; k++) {
        expect((t.volumeAt(2, k) - base).abs(), closeTo(depth, 1e-9));
      }
    });
  });

  group('E3x glissando', () {
    test('tone-porta output snaps to whole semitones when glissando is on', () {
      // Row 0: note 60 + E31 (glissando on). Row 1: tone-porta toward 67.
      final t = traceChannel([
        const TrackerCell(midi: 60, fxCmd: kFxExtended, fxParam: 0x31),
        const TrackerCell(midi: 67, fxCmd: kFxTonePorta, fxParam: 0x02),
      ]);
      for (var k = 0; k < kDefaultTicksPerRow; k++) {
        final p = t.pitchAt(1, k);
        expect(
          p,
          closeTo(p.roundToDouble(), 1e-9),
          reason: 'glissando snaps the sliding pitch to a semitone (tick $k)',
        );
      }
    });

    test('without glissando the tone-porta glides through microtones', () {
      final t = traceChannel([
        const TrackerCell(midi: 60),
        const TrackerCell(midi: 67, fxCmd: kFxTonePorta, fxParam: 0x02),
      ]);
      final anyMicrotonal = [
        for (var k = 0; k < kDefaultTicksPerRow; k++) t.pitchAt(1, k),
      ].any((p) => (p - p.roundToDouble()).abs() > 1e-6);
      expect(anyMicrotonal, isTrue);
    });

    test('E30 turns glissando back off', () {
      final t = traceChannel([
        const TrackerCell(midi: 60, fxCmd: kFxExtended, fxParam: 0x31), // on
        const TrackerCell(fxCmd: kFxExtended, fxParam: 0x30), // off
        const TrackerCell(midi: 67, fxCmd: kFxTonePorta, fxParam: 0x02),
      ]);
      final anyMicrotonal = [
        for (var k = 0; k < kDefaultTicksPerRow; k++) t.pitchAt(2, k),
      ].any((p) => (p - p.roundToDouble()).abs() > 1e-6);
      expect(anyMicrotonal, isTrue);
    });
  });

  group('E5x set finetune', () {
    double tuneOf(int x) => traceChannel([
          TrackerCell(midi: 60, fxCmd: kFxExtended, fxParam: 0x50 | x),
        ]).pitchAt(0, 0);

    test('nudges the note tune by (x−8)/16 of a semitone; 8 is centre', () {
      expect(tuneOf(8), closeTo(60.0, 1e-9)); // centre — no change
      expect(tuneOf(0xC), closeTo(60 + 4 / 16, 1e-9)); // a touch sharp
      expect(tuneOf(0x0), closeTo(60 - 8 / 16, 1e-9)); // as flat as it goes
    });
  });

  group('Rxy retrigger + volume slide', () {
    test('retriggers every y ticks and changes volume by code x', () {
      // R13: x=1 (volume −1 per retrigger), y=3 (every 3 ticks).
      final t = traceChannel([
        const TrackerCell(midi: 60, fxCmd: kFxRetrigVolSlide, fxParam: 0x13),
      ]);
      expect(t.retriggerAt(0, 3), isTrue);
      expect(t.retriggerAt(0, 1), isFalse);
      expect(t.volumeAt(0, 3), closeTo(kMaxVolume - 1, 1e-9));
    });

    test('retrigVolume follows the XM table', () {
      expect(retrigVolume(40, 0), 40); // no change
      expect(retrigVolume(40, 8), 40); // no change
      expect(retrigVolume(40, 3), 36); // −4
      expect(retrigVolume(40, 7), 20); // ×½
      expect(retrigVolume(40, 0xF), kMaxVolume); // ×2, clamped
      expect(retrigVolume(10, 0xB), 14); // +4
    });
  });

  group('Txy tremor', () {
    test('pulses the note ON for x ticks, OFF for y, repeating', () {
      // T31: on for 3 ticks, off for 1 → a 4-tick cycle.
      final t = traceChannel([
        const TrackerCell(midi: 60, fxCmd: kFxTremor, fxParam: 0x31),
      ]);
      expect(t.volumeAt(0, 0), closeTo(kMaxVolume, 1e-9)); // on
      expect(t.volumeAt(0, 2), closeTo(kMaxVolume, 1e-9)); // still on
      expect(t.volumeAt(0, 3), closeTo(0, 1e-9)); // off
      expect(t.volumeAt(0, 4), closeTo(kMaxVolume, 1e-9)); // cycle repeats
    });

    test('T00 alternates every tick — a zero nibble is ONE tick, not none', () {
      // ⚠️ This test used to assert that `T00` "leaves the note fully on", on
      // the reasonable-looking grounds that a cycle of x+y = 0 has nothing to
      // gate. That was an assumption, and it was wrong. Outside FastTracker a
      // zero nibble is incremented to one (libxmp `effects.c`, `FX_TREMOR`), so
      // `T00` is one tick on, one tick off.
      //
      // MEASURED, not taken from the source: `fmt/tremor_I00.{s3m,it}` renders
      // as `#.#.#.#.` in libopenmpt — alternating every single tick — and our
      // render now matches it. The source reading is what suggested the
      // fixture; the fixture is what settled it, which is the same order that
      // caught the counter bug this file's sibling documents.
      final t = traceChannel([
        const TrackerCell(midi: 60, fxCmd: kFxTremor), // param 0 = T00
        const TrackerCell(fxCmd: kFxTremor),
      ]);
      for (var k = 0; k < kDefaultTicksPerRow; k++) {
        expect(
          t.volumeAt(0, k),
          closeTo(k.isEven ? kMaxVolume : 0, 1e-9),
          reason: 'tick $k of a T00 row',
        );
      }
    });
  });
}
