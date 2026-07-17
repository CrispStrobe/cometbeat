// test/chroma_analysis_test.dart
//
// Validates the phase-2 chord recognizer against synth.dart chords — no mic
// needed. We render real triads/sevenths (with piano harmonics) and assert the
// chromagram + template match names the right chord.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:flutter_test/flutter_test.dart';

/// Render simultaneous [freqs] and return a centred FFT window.
Float64List _chordWindow(List<double> freqs, int windowSize) {
  final samples = renderSegments([(freqs: freqs, ms: 600)]);
  final start = (samples.length - windowSize) ~/ 2;
  final out = Float64List(windowSize);
  for (var i = 0; i < windowSize; i++) {
    out[i] = samples[start + i] / 32768.0;
  }
  return out;
}

// Equal-tempered frequency for a MIDI note.
double _f(int midi) => 440.0 * pow(2.0, (midi - 69) / 12.0);

void main() {
  group('fft', () {
    test('a pure cosine peaks in exactly one bin', () {
      const n = 1024;
      const bin = 8;
      final re = Float64List(n);
      final im = Float64List(n);
      for (var i = 0; i < n; i++) {
        re[i] = cos(2 * pi * bin * i / n);
      }
      fft(re, im);
      var maxBin = 0;
      var maxMag = 0.0;
      for (var i = 0; i < n ~/ 2; i++) {
        final mag = sqrt(re[i] * re[i] + im[i] * im[i]);
        if (mag > maxMag) {
          maxMag = mag;
          maxBin = i;
        }
      }
      expect(maxBin, bin);
      expect(maxMag, closeTo(n / 2, 1e-6));
    });
  });

  group('chord recognition (synth triads)', () {
    final detector = ChordDetector();
    const windowSize = 4096;

    // MIDI: C4=60, E4=64, G4=67, A3=57, F4=65, B3=59, D4=62, Bb3=58.
    final cases = <String, ({List<int> notes, String expected})>{
      'C major': (notes: [60, 64, 67], expected: 'C'),
      'G major': (notes: [55, 59, 62], expected: 'G'),
      'A minor': (notes: [57, 60, 64], expected: 'Am'),
      'E minor': (notes: [52, 55, 59], expected: 'Em'),
      'G7': (notes: [55, 59, 62, 65], expected: 'G7'),
      'D minor': (notes: [50, 53, 57], expected: 'Dm'),
    };

    cases.forEach((label, c) {
      test(label, () {
        final window = _chordWindow(c.notes.map(_f).toList(), windowSize);
        final r = detector.analyze(window);
        expect(r.hasChord, isTrue, reason: '$label should match something');
        expect(
          r.best!.name,
          c.expected,
          reason: '$label → got ${r.candidates.take(3).join(", ")}',
        );
      });
    });
  });

  test('chromagram lights up the played pitch classes', () {
    final detector = ChordDetector();
    // C major triad: C(0), E(4), G(7) should dominate the chroma.
    final window = _chordWindow([_f(60), _f(64), _f(67)], 4096);
    final chroma = detector.chromagram(window);
    // The three chord tones should each be well above the average bin.
    final avg = chroma.reduce((a, b) => a + b) / 12;
    for (final pc in [0, 4, 7]) {
      expect(chroma[pc], greaterThan(avg), reason: 'pc $pc should be strong');
    }
  });

  test('silence yields no chord', () {
    final detector = ChordDetector();
    expect(detector.analyze(Float64List(4096)).hasChord, isFalse);
  });
}
