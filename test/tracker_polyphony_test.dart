import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/envelope.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Polyphony and Choke Semantics with SampleInstrument', () {
    test('MultiSampleInstrument (Monophonic) strictly chokes tails', () {
      final sampleBuf = Float64List(44100);
      for (var i = 0; i < sampleBuf.length; i++) {
        sampleBuf[i] = 1.0;
      }

      final kick = SampleInstrument(
        'kick',
        sampleBuf,
        envelope: const Envelope(attack: 0.0, release: 0.2),
      );

      final snare = SampleInstrument(
        'snare',
        sampleBuf,
        baseMidi: 62,
        envelope: const Envelope(attack: 0.0, release: 0.2),
      );

      final drumKit = MultiSampleInstrument(
        'kit',
        {60: kick, 62: snare},
      );

      const fastTiming = TrackerTiming(
        tempoBpm: 60000,
        rows: 4,
        stepsPerBeat: 1,
      ); // 1 step = 44 samples!

      final cells = [
        const TrackerCell(midi: 60),
        const TrackerCell(midi: 62),
        TrackerCell.empty,
        TrackerCell.empty,
      ];

      final out = drumKit.renderChannel(cells, fastTiming);

      // Kick amplitude is 1.0. Snare amplitude is 1.0.
      // At sample 45, snare is playing. Because monophonic, kick should have faded out or choked.
      // Wait, because we added a 0.2s release to the kick, and it is truncated at 44 samples,
      // it applies its release inside the last 0.2s of the 44-sample run. 44 samples is ~0.001s.
      // Since 0.2s > 0.001s, the envelope scales release down to 44 samples.
      // Thus, at sample 44 (when snare starts), the kick is perfectly 0.0.
      // So at sample 45, out[45] should be 1.0 (snare only).

      expect(out[45], closeTo(1.0, 0.01));
    });

    test('MultiSampleInstrument (Polyphonic) allows overlapping drum tails',
        () {
      final sampleBuf = Float64List(44100);
      for (var i = 0; i < sampleBuf.length; i++) {
        sampleBuf[i] = 1.0;
      }

      final crash = SampleInstrument(
        'crash',
        sampleBuf,
        envelope: const Envelope(attack: 0.0, release: 0.2),
      );

      final kick = SampleInstrument(
        'kick',
        sampleBuf,
        baseMidi: 62,
        envelope: const Envelope(attack: 0.0, release: 0.2),
      );

      final drumKit = MultiSampleInstrument(
        'kit',
        {60: crash, 62: kick},
        polyphonic: true,
      );

      const fastTiming = TrackerTiming(
        tempoBpm: 60000,
        rows: 4,
        stepsPerBeat: 1,
      ); // 1 step = 44 samples

      final cells = [
        const TrackerCell(midi: 60), // Crash
        const TrackerCell(
          midi: 62,
        ), // Kick hits while crash is still ringing out
        TrackerCell.empty,
        TrackerCell.empty,
      ];

      final out = drumKit.renderChannel(cells, fastTiming);

      // Because it's polyphonic, crash should NOT be truncated at 44 samples.
      // It will continue ringing out past sample 44.
      // Kick also starts at sample 44.
      // At sample 45, crash is still 1.0 (sustaining) and kick is 1.0.
      // 1.0 + 1.0 = 2.0!
      expect(out[45], closeTo(2.0, 0.01));
    });
  });
}
