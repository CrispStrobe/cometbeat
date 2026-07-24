import 'dart:typed_data';
import 'package:comet_beat/core/audio/crisp_dsp/envelope.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MultiSampleInstrument routes notes and chops them properly', () {
    final zoneA = SampleInstrument('zoneA', Float64List(44100)..fillRange(0, 44100, 1.0), envelope: Envelope.none); // DC offset of 1
    final zoneB = SampleInstrument('zoneB', Float64List(44100)..fillRange(0, 44100, -1.0), envelope: Envelope.none); // DC offset of -1

    final multi = MultiSampleInstrument('multi', {
      60: zoneA,
      72: zoneB,
    });

    final timing = TrackerTiming(tempoBpm: 120, rows: 8, stepsPerBeat: 4); // each step is 125ms = 5512.5 samples
    final stepSamples = timing.stepStartSample(1);

    final cells = List.generate(8, (_) => const TrackerCell());
    cells[0] = const TrackerCell(midi: 60); // maps to zoneA (1.0)
    cells[2] = const TrackerCell(midi: 72); // maps to zoneB (-1.0)
    cells[3] = const TrackerCell(midi: 65); // maps to zoneA (closest to 60)

    final out = multi.renderChannel(cells, timing);

    // Step 0-1 (zoneA -> positive)
    expect(out[0], greaterThan(0));
    expect(out[stepSamples - 1], greaterThan(0));
    
    // Step 2 (zoneB -> negative)
    final step2 = timing.stepStartSample(2);
    expect(out[step2], lessThan(0));
    
    // Step 3 (zoneA -> positive)
    final step3 = timing.stepStartSample(3);
    expect(out[step3], greaterThan(0));
  });
}
