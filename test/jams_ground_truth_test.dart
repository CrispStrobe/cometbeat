// JAMS as a GROUND-TRUTH PROVIDER for automated detection testing.
//
// The importer's job is "annotation → app content"; the harder question is "is
// our DETECTION any good?". JAMS answers both: it is the MIR-standard ground-
// truth interchange. The JAMS writers (notesToJams / chordsToJams) let a test
// author a machine-readable ground truth; we then SYNTHESIZE audio from it and
// run the app's own detectors, asserting they recover the ground truth. This is
// the input-side acceptance loop
//
//     author JAMS ground truth → synthesize → detect → compare
//
// with JAMS as the interchange — so the same fixtures could later be swapped for
// real annotated datasets (Isophonics, MedleyDB, …) with no test changes. The
// writers round-trip through the readers here too, so the ground truth we author
// is exactly what the importer would read.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/features/games/songs/import/chordpro.dart';
import 'package:comet_beat/features/games/songs/import/jams.dart';
import 'package:flutter_test/flutter_test.dart';

/// A centred analysis window of a synthesized tone at [freq].
Float64List _toneWindow(double freq, int windowSize, int sampleRate) {
  final samples = renderSegments(
    [
      (freqs: [freq], ms: 500),
    ],
    sampleRate: sampleRate,
  );
  final start = (samples.length - windowSize) ~/ 2;
  final out = Float64List(windowSize);
  for (var i = 0; i < windowSize; i++) {
    out[i] = samples[start + i] / 32768.0;
  }
  return out;
}

/// A centred FFT window of simultaneous [freqs] (a chord).
Float64List _chordWindow(List<double> freqs, int windowSize) {
  final samples = renderSegments([
    (freqs: freqs, ms: 600),
  ]);
  final start = (samples.length - windowSize) ~/ 2;
  final out = Float64List(windowSize);
  for (var i = 0; i < windowSize; i++) {
    out[i] = samples[start + i] / 32768.0;
  }
  return out;
}

void main() {
  test('pitch detector recovers a JAMS note_midi ground truth', () {
    // 1. Author the ground truth AS JAMS (the provider).
    const scale = [60, 62, 64, 65, 67, 69, 71, 72];
    final groundTruth = notesToJams(
      [
        for (var i = 0; i < scale.length; i++)
          (time: i * 0.5, duration: 0.5, midi: scale[i]),
      ],
      title: 'C major scale',
      tempo: 120,
    );

    // 2. Read it back the way the importer does (writer↔reader round-trip).
    final truth = jamsMelodyNotes(groundTruth);
    expect(truth.map((n) => n.midi), scale);

    // 3. Synthesize each ground-truth note and 4. assert the detector recovers it.
    final detector = PitchDetector();
    for (final n in truth) {
      final window = _toneWindow(
        midiToFrequency(n.midi),
        detector.windowSize,
        detector.sampleRate,
      );
      final r = detector.analyze(window);
      expect(r.hasPitch, isTrue, reason: 'midi ${n.midi} not detected');
      expect(
        r.nearestMidi,
        n.midi,
        reason: 'detected ${r.noteName} for ground-truth midi ${n.midi}',
      );
    }
  });

  test('chord detector recovers a JAMS chord ground truth', () {
    // Author a chord progression as JAMS, then read it back to the app's names.
    final groundTruth = chordsToJams(['C', 'Am', 'F', 'G'], title: 'I-vi-IV-V');
    final truth = parseChordPro(jamsToChordPro(groundTruth)).chords;
    expect(truth, ['C', 'Am', 'F', 'G']);

    // Synthesize each ground-truth chord (its triad) and detect it.
    const windowSize = 4096;
    final detector = ChordDetector();
    for (final name in truth) {
      final midis = chordMidis(name)!;
      final window =
          _chordWindow(midis.map(midiToFrequency).toList(), windowSize);
      final r = detector.analyze(window);
      expect(r.hasChord, isTrue, reason: '$name should match something');
      expect(
        r.best!.name,
        name,
        reason: 'detected ${r.candidates.take(3).join(", ")} for $name',
      );
    }
  });
}
