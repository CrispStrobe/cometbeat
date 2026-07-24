import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/crisp_dsp/envelope.dart';
import 'package:comet_beat/core/audio/synth.dart';

// A mock tracker instrument that just outputs a constant DC signal for its length
class MockDcInstrument extends TrackerInstrument {
  final int samples;
  MockDcInstrument(this.samples);
  
  @override
  String get id => 'mock_dc';

  @override
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) {
    final buf = Float64List(samples);
    for (var i = 0; i < samples; i++) buf[i] = 1.0;
    return buf;
  }
}

void main() {
  group('Polyphony and Choke Semantics', () {
    test('MultiSampleInstrument (Monophonic) strictly chokes tails', () {
      final kick = MockDcInstrument(1000); // Kick is 1000 samples long
      final snare = MockDcInstrument(1000); // Snare is 1000 samples long
      
      final drumKit = MultiSampleInstrument(
        'kit',
        { 60: kick, 62: snare },
        polyphonic: false, // Monophonic (choke)
      );
      
      final fastTiming = TrackerTiming(tempoBpm: 60000, rows: 4, stepsPerBeat: 1); // 1 step = 44 samples!
      
      final cells = [
        TrackerCell(midi: 60), // Kick
        TrackerCell(midi: 62), // Snare chokes Kick after 44 samples
        TrackerCell.empty,
        TrackerCell.empty,
      ];
      
      final out = drumKit.renderChannel(cells, fastTiming);
      
      // Kick starts at 0. At sample 44, snare starts.
      // If monophonic, the kick should NOT continue past sample 44!
      // Out buffer size = 44 * 4 = 176 samples.
      
      // Kick amplitude is 1.0. Snare amplitude is 1.0.
      // Overlap would mean amplitude 2.0. Choke means amplitude 1.0.
      expect(out[45], 1.0); // Snare only!
    });

    test('MultiSampleInstrument (Polyphonic) allows overlapping drum tails', () {
      final crash = MockDcInstrument(1000); 
      final kick = MockDcInstrument(1000); 
      
      final drumKit = MultiSampleInstrument(
        'kit',
        { 60: crash, 62: kick },
        polyphonic: true, // Polyphonic!
      );
      
      final fastTiming = TrackerTiming(tempoBpm: 60000, rows: 4, stepsPerBeat: 1); // 1 step = 44 samples
      
      final cells = [
        TrackerCell(midi: 60), // Crash
        TrackerCell(midi: 62), // Kick hits while crash is still ringing out
        TrackerCell.empty,
        TrackerCell.empty,
      ];
      
      final out = drumKit.renderChannel(cells, fastTiming);
      
      // Crash starts at 0. At sample 44, Kick starts.
      // Because it's polyphonic, crash (1.0) + kick (1.0) = 2.0 at sample 45!
      expect(out[45], 2.0); 
    });
  });
}
