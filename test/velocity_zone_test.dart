import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/envelope.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A constant-DC sample instrument makes zone selection trivially observable:
  // the sign/level of the rendered output identifies which zone answered.
  // Envelope.none keeps the first sample equal to value*volume (no declick ramp).
  SampleInstrument dc(String id, double value) => SampleInstrument(
        id,
        Float64List(44100)..fillRange(0, 44100, value),
        envelope: Envelope.none,
      );

  List<TrackerCell> noteAt(int midi, double volume) => [
        TrackerCell(midi: midi, volume: volume),
        const TrackerCell(),
        const TrackerCell(),
        const TrackerCell(),
      ];

  group('zoneForNoteVelocity', () {
    test('velocity splits on the same note select by velocity', () {
      final soft = dc('soft', 0.25);
      final loud = dc('loud', 1.0);
      final multi = MultiSampleInstrument(
        'multi',
        {60: loud},
      ).copyWith(
        velocityZones: [
          VelocityZone(note: 60, instrument: soft, velHigh: 63),
          VelocityZone(note: 60, instrument: loud, velLow: 64),
        ],
      );

      // Low velocity (volume 0.3 -> 38/127) -> soft zone.
      expect(multi.zoneForNoteVelocity(60, 0.3), same(soft));
      // High velocity (volume 0.9 -> 114/127) -> loud zone.
      expect(multi.zoneForNoteVelocity(60, 0.9), same(loud));
      // Just above the 0..63 window (0.5039 * 127 rounds to 64) -> loud.
      expect(multi.zoneForNoteVelocity(60, 0.5039), same(loud));
      // Just inside the window (0.49 * 127 = 62.2 -> 62) -> soft.
      expect(multi.zoneForNoteVelocity(60, 0.49), same(soft));
    });

    test('a single full-range zone matches zoneForNote (byte-identical)', () {
      final loud = dc('loud', 1.0);
      // No velocity splits: velocity is not consulted at all.
      final multi = MultiSampleInstrument('multi', {60: loud, 72: loud});
      for (final vel in [null, 0.0, 0.1, 0.5, 1.0]) {
        expect(
          multi.zoneForNoteVelocity(60, vel),
          same(multi.zoneForNote(60)),
        );
        expect(
          multi.zoneForNoteVelocity(72, vel),
          same(multi.zoneForNote(72)),
        );
      }
    });

    test('an unmatched velocity falls back to the plain zone map', () {
      final base = dc('base', 1.0);
      final soft = dc('soft', 0.25);
      final multi = MultiSampleInstrument(
        'multi',
        {60: base},
        velocityZones: [
          VelocityZone(note: 60, instrument: soft, velHigh: 40),
        ],
      );
      // Velocity above the split window -> plain base zone.
      expect(multi.zoneForNoteVelocity(60, 1.0), same(base));
      // A note with no split defined -> plain map (nearest key).
      expect(multi.zoneForNoteVelocity(60, 0.1), same(soft));
    });
  });

  group('render honours velocity splits', () {
    const timing = TrackerTiming(rows: 4);

    test('low and high velocity notes render different zones', () {
      final soft = dc('soft', 0.25);
      final loud = dc('loud', 1.0);
      final multi = MultiSampleInstrument(
        'multi',
        {60: loud},
        velocityZones: [
          VelocityZone(note: 60, instrument: soft, velHigh: 63),
          VelocityZone(note: 60, instrument: loud, velLow: 64),
        ],
      );

      // Soft note: volume 0.4 -> velocity 51 -> soft zone (DC 0.25).
      const softVol = 0.4;
      final softOut = multi.renderChannel(noteAt(60, softVol), timing);
      // Loud note: volume 0.9 -> velocity 114 -> loud zone (DC 1.0).
      const loudVol = 0.9;
      final loudOut = multi.renderChannel(noteAt(60, loudVol), timing);

      // The SampleInstrument scales its DC by the note volume; dividing it back
      // out isolates which zone answered (0.25 vs 1.0 DC).
      expect(softOut[0] / softVol, closeTo(0.25, 1e-9));
      expect(loudOut[0] / loudVol, closeTo(1.0, 1e-9));
    });

    test('a non-sample (additive) velocity zone renders non-silent', () {
      const additive = AdditiveInstrument('addPiano', Instrument.piano);
      final loud = dc('loud', 1.0);
      final multi = MultiSampleInstrument(
        'multi',
        {60: loud},
        velocityZones: const [
          VelocityZone(note: 60, instrument: additive, velHigh: 63),
        ],
      );

      final out = multi.renderChannel(noteAt(60, 0.2), timing);

      var energy = 0.0;
      for (final s in out) {
        energy += s.abs();
      }
      expect(
        energy,
        greaterThan(0.0),
        reason: 'additive velocity zone should produce audible output',
      );
    });

    test('no velocity splits: same zone selected at every velocity', () {
      final loud = dc('loud', 1.0);
      final multi = MultiSampleInstrument('multi', {60: loud});
      // With no velocity splits the same (loud, DC 1.0) zone answers at any
      // velocity, so the render is exactly volume * DC — byte-identical
      // selection to the pre-velocity code path.
      final a = multi.renderChannel(noteAt(60, 0.1), timing);
      final b = multi.renderChannel(noteAt(60, 1.0), timing);
      expect(a[0] / 0.1, closeTo(1.0, 1e-9));
      expect(b[0] / 1.0, closeTo(1.0, 1e-9));
    });
  });
}
