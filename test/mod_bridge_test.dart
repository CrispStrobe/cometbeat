// Tracker ↔ MOD bridge — the contract/spec for modToTracker & trackerToMod.
// Pure Dart; the MOD-bridge agent implements mod_bridge.dart to make these pass.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/mod.dart';
import 'package:comet_beat/core/audio/mod/mod_bridge.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tiny 1-channel module: one sample, one pattern with a note on rows 0 and 32.
ModModule _tinyMod() {
  final rows = List.generate(
    64,
    (r) => <ModCell>[const ModCell()], // 1 channel, empty
  );
  rows[0] = [const ModCell(sample: 1, period: 428)]; // C-2
  rows[32] = [const ModCell(sample: 1, period: 214)]; // C-3
  return ModModule(
    channelCount: 1,
    samples: [
      ModSample(
        name: 'saw',
        pcm: Int8List.fromList([0, 40, 80, 120, -120, -40]),
      ),
      for (var i = 1; i < 31; i++) ModSample.empty(),
    ],
    order: [0],
    patterns: [ModPattern(rows)],
  );
}

void main() {
  group('modToTracker (import)', () {
    test('maps notes onto the grid at the quantized steps', () {
      final imp = modToTracker(_tinyMod());
      expect(imp.channelCount, 1);
      expect(imp.patterns.length, 1); // one song position

      final ch = imp.patterns[0][0]; // pattern 0, channel 0
      expect(ch.length, 8);
      // mod row 0 → step 0; mod row 32 → step (32*8/64)=4.
      expect(ch[0].midi, periodToMidi(428));
      expect(ch[4].midi, periodToMidi(214));
      expect(ch[1].isEmpty, isTrue);
    });

    test('builds a SampleInstrument from the mod sample', () {
      final imp = modToTracker(_tinyMod());
      expect(imp.channelInstruments.length, 1);
      final inst = imp.channelInstruments[0];
      expect(inst, isA<SampleInstrument>());
      expect((inst as SampleInstrument).sample.length, 6); // the 6 PCM bytes
      expect(inst.baseMidi, modBridgeBaseMidi);
    });
  });

  group('trackerToMod (export)', () {
    test('exported notes survive write→read as the right periods', () {
      // One 8-step channel with two notes.
      final cells =
          List<TrackerCell>.filled(8, TrackerCell.empty, growable: true)
            ..[0] = const TrackerCell(midi: 60)
            ..[4] = const TrackerCell(midi: 72);
      final sample = Int8List.fromList([0, 50, 100, -100]);
      final mod = trackerToMod(
        [
          [cells],
        ],
        channelInstruments: [SampleInstrument('v', Float64List(4))],
      );

      // Round-trip through the codec — the notes must land as periods.
      final back = parseMod(writeMod(mod));
      final row0 = back.patterns[0].rows[0][0];
      final row32 = back.patterns[0].rows[32][0];
      expect(row0.period, midiToPeriod(60));
      expect(row32.period, midiToPeriod(72));
      // Sample carried (non-empty PCM in slot 0).
      expect(back.samples[0].pcm.isNotEmpty || sample.isEmpty, isTrue);
    });
  });

  group('round-trip (mod → tracker → mod)', () {
    test('a mod imports and re-exports with notes intact', () {
      final imp = modToTracker(_tinyMod());
      final mod2 = trackerToMod(
        imp.patterns,
        channelInstruments: imp.channelInstruments,
      );
      final back = parseMod(writeMod(mod2));
      // The C-2 note at step 0 → mod row 0 with a period near C-2.
      expect(
        periodToMidi(back.patterns[0].rows[0][0].period),
        periodToMidi(428),
      );
    });
  });
}
