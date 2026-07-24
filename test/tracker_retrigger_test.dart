import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/envelope.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'SampleInstrument strictly sustains until retrigger boundary without pre-release fade',
      () {
    final sampleBuf = Float64List(44100);
    for (var i = 0; i < sampleBuf.length; i++) {
      sampleBuf[i] = 1.0;
    } // DC offset

    final inst = SampleInstrument(
      'test',
      sampleBuf,
      envelope: const Envelope(attack: 0.0, release: 0.5),
    );

    const timing = TrackerTiming(
      tempoBpm: 60000,
      rows: 4,
      stepsPerBeat: 1,
    ); // 1 step = 44 samples

    final cells = [
      const TrackerCell(midi: 60), // Note 1
      const TrackerCell(midi: 62), // Note 2 chokes Note 1 at step 1
      TrackerCell.empty,
      TrackerCell.empty,
    ];

    // renderChannel should return a buffer of length 4*44 = 176
    final out = inst.renderChannel(cells, timing);

    // Note 1 plays for the first 44 samples (0 to 43).
    // It should sustain at exactly 1.0 right up until sample 43!
    // Since release is 0.5s (22050 samples), if it pre-released, it would start dropping immediately.
    expect(out[0], closeTo(1.0, 0.001));
    expect(out[20], closeTo(1.0, 0.001));
    expect(
      out[43],
      closeTo(1.0, 0.001),
      reason: 'Must sustain fully until the exact choke boundary',
    );

    // Note 2 starts at sample 44. Since it's monophonic renderChannel, Note 1 is gone.
    // Note 2 also outputs 1.0.
    expect(out[44], closeTo(1.0, 0.001));
  });
}
