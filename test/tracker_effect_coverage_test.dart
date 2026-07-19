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
    test('square vibrato deviates by exactly ±depth every tick', () {
      const depth = 8 * kVibratoDepthSemitonesPerUnit; // 4xy depth nibble = 8
      // Row 0: note + E42 (select square waveform). Row 1: vibrato 4-8-8.
      final t = traceChannel([
        const TrackerCell(midi: 60, fxCmd: kFxExtended, fxParam: 0x42),
        const TrackerCell(fxCmd: kFxVibrato, fxParam: 0x88),
      ]);
      for (var k = 0; k < kDefaultTicksPerRow; k++) {
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
        for (var k = 0; k < kDefaultTicksPerRow; k++)
          (t.pitchAt(1, k) - 60).abs(),
      ].any((d) => d < depth - 1e-6);
      expect(anyIntermediate, isTrue);
    });
  });

  group('E7x tremolo waveform', () {
    test('square tremolo swings volume by exactly ±depth', () {
      const depth = 8 * kTremoloDepthPerUnit; // 7xy depth nibble = 8
      const base = kMaxVolume - 16; // mid volume so ±depth stays in range
      final t = traceChannel([
        const TrackerCell(midi: 60, fxCmd: kFxSetVolume, fxParam: base),
        // E72: select the square tremolo waveform.
        const TrackerCell(fxCmd: kFxExtended, fxParam: 0x72),
        const TrackerCell(fxCmd: kFxTremolo, fxParam: 0x88),
      ]);
      for (var k = 0; k < kDefaultTicksPerRow; k++) {
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

    test('T00 (no cycle) leaves the note fully on', () {
      final t = traceChannel([
        const TrackerCell(midi: 60, fxCmd: kFxTremor), // param 0 = T00
      ]);
      for (var k = 0; k < kDefaultTicksPerRow; k++) {
        expect(t.volumeAt(0, k), closeTo(kMaxVolume, 1e-9));
      }
    });
  });
}
