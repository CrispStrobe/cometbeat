// Auto base-pitch detection: a recording's fundamental is read as the nearest
// MIDI note, and tunedRecordedSample plays a tune IN TUNE (render a note → the
// detector reads back the right pitch). Pure Dart, no device.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/sample_pitch.dart';
import 'package:comet_beat/core/audio/synth.dart'
    show kSampleRate, midiToFrequency;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A clean sine at the frequency of MIDI [midi], [n] samples at the engine rate.
  Float64List tone(int midi, {int n = 8192, double amp = 0.7}) {
    final f = midiToFrequency(midi);
    final s = Float64List(n);
    for (var i = 0; i < n; i++) {
      s[i] = amp * sin(2 * pi * f * i / kSampleRate);
    }
    return s;
  }

  group('detectSampleBaseMidi', () {
    test('reads the nearest MIDI note of a recorded tone', () {
      expect(detectSampleBaseMidi(tone(69)), 69); // A4 = 440 Hz
      expect(detectSampleBaseMidi(tone(60)), 60); // C4
      expect(detectSampleBaseMidi(tone(72)), 72); // C5
      expect(detectSampleBaseMidi(tone(45)), 45); // A2 (low)
    });

    test('silence and noise return null', () {
      expect(detectSampleBaseMidi(Float64List(8192)), isNull); // silence
      final rng = Random(1);
      final noise = Float64List(8192);
      for (var i = 0; i < noise.length; i++) {
        noise[i] = rng.nextDouble() * 2 - 1;
      }
      expect(detectSampleBaseMidi(noise), isNull);
    });
  });

  group('tunedRecordedSample', () {
    test('sets baseMidi from the recording + auto-loops a periodic tone', () {
      final inst = tunedRecordedSample('rec', tone(67)); // G4
      expect(inst.baseMidi, 67);
      expect(inst.loops, isTrue); // a steady tone auto-loops
    });

    test('a recording with no clear pitch falls back to baseMidi 60', () {
      final rng = Random(2);
      final noise = Float64List(8192);
      for (var i = 0; i < noise.length; i++) {
        noise[i] = rng.nextDouble() * 2 - 1;
      }
      expect(tunedRecordedSample('n', noise).baseMidi, 60);
    });

    test('plays IN TUNE — render a note, the detector reads that note back',
        () {
      // Recorded at A4 (69); auto base = 69, so note 69 plays at ratio 1 (440 Hz)
      // and note 81 an octave up (880 Hz). A wrong base would detune both.
      final inst = tunedRecordedSample('rec', tone(69));
      expect(inst.baseMidi, 69);

      final det = PitchDetector(); // defaults to the engine rate (44.1 kHz)
      int renderedNote(int note) {
        const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
        final cells = [
          TrackerCell(midi: note),
          ...List<TrackerCell>.filled(7, TrackerCell.empty),
        ];
        final buf = inst.renderChannel(cells, timing);
        // Analyse a window well past the attack.
        final w = det.windowSize;
        final view = Float64List.sublistView(buf, 8000, 8000 + w);
        return det.analyze(view).nearestMidi;
      }

      expect(renderedNote(69), 69); // in tune at its own pitch
      expect(renderedNote(81), 81); // an octave up
      expect(renderedNote(64), 64); // and down a fourth
    });
  });
}
