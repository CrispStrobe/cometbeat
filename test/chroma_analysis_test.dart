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

  // Regression: the silence gate used to sum `chromagram`, which peak-normalizes
  // its output — so the sum was scale-invariant (always ≈1..12 for ANY non-zero
  // input) and the gate could only ever fire on bit-exact silence. Inaudible
  // room noise was emitted as a confident chord. The all-zeros test above was
  // vacuous: it hit the one case the broken gate happened to catch.
  group('silence gate is an absolute level (regression: scale invariance)', () {
    final detector = ChordDetector();
    final loud = _chordWindow([_f(60), _f(64), _f(67)], 4096); // C major

    Float64List scaled(double by) =>
        Float64List.fromList([for (final s in loud) s * by]);

    test('an audible chord still matches', () {
      expect(detector.analyze(loud).hasChord, isTrue);
    });

    test('the same chord at an inaudible level is silence', () {
      expect(detector.analyze(scaled(1e-6)).hasChord, isFalse);
    });

    test('energy tracks level rather than being scale-invariant', () {
      final full = detector.analyze(loud).energy;
      final tenth = detector.analyze(scaled(0.1)).energy;
      expect(full, greaterThan(0));
      // Magnitudes are linear in amplitude, so a tenth of the level is a tenth
      // of the energy — the old normalized sum returned the SAME value for both.
      expect(tenth, closeTo(full * 0.1, full * 0.02));
    });

    test('near-silent noise yields no chord', () {
      final rnd = Random(7);
      final noise = Float64List(4096);
      for (var i = 0; i < noise.length; i++) {
        noise[i] = 1e-7 * (rnd.nextDouble() * 2 - 1);
      }
      expect(detector.analyze(noise).hasChord, isFalse);
    });
  });

  group('bass detection (BB-H1)', () {
    // A chromagram folds away the octave, so `C` and `C/E` are the same twelve
    // numbers and `C6` and `Am7` are literally the same four pitch classes. The
    // bass is the only thing that separates them, and chroma cannot carry it.
    //
    // ⚠️ These use a 8192-sample window, not the detector's default 4096. That is
    // not a convenience: at 44.1 kHz a 4096-point FFT has 10.77 Hz bins while a
    // semitone at C3 spans 7.8 Hz, so below ~F#3 it cannot SEPARATE adjacent
    // semitones. Measured over 100 root-position chords the bass is right 74% of
    // the time at 4096 and 100% at 8192 (tool/bass_detect_ab.dart).
    final detector = ChordDetector();
    const bassWindow = 8192;

    Float64List win(List<int> midis) =>
        _chordWindow(midis.map(_f).toList(), bassWindow);

    test('names the lowest note, not the loudest', () {
      // The bug this pins: an argmax over candidate scores finds the strongest
      // note in the register, which on this voicing is not the bass at all.
      expect(detector.analyze(win([48, 52, 55, 57])).bassPc, 0); // C3 lowest
      expect(detector.analyze(win([45, 48, 52, 55])).bassPc, 9); // A2 lowest
    });

    test('separates C6 from Am7 — the collision chroma cannot see', () {
      final c6 = detector.analyze(win([48, 52, 55, 57])); // C E G A
      final am7 = detector.analyze(win([45, 48, 52, 55])); // A C E G
      // Same four pitch classes…
      expect(
        c6.chroma.map((v) => v > 0.3).toList(),
        am7.chroma.map((v) => v > 0.3).toList(),
      );
      // …told apart only by the bass.
      expect(c6.bassPc, 0);
      expect(am7.bassPc, 9);
    });

    test('reads an inversion: C/E has E in the bass', () {
      expect(detector.analyze(win([52, 55, 60])).bassPc, 4); // E3 G3 C4
      expect(detector.analyze(win([55, 60, 64])).bassPc, 7); // G3 C4 E4
    });

    test('says nothing rather than guessing on silence', () {
      expect(detector.analyze(Float64List(bassWindow)).bassPc, isNull);
    });

    test('a too-short frame is not a crash', () {
      expect(detector.analyze(Float64List(1)).bassPc, isNull);
      expect(detector.bassPitchClass(Float64List(1)), isNull);
    });
  });

  group('deterministic ordering + bass tie-break (BB-H3)', () {
    test('the same input gives the same candidate order, every time', () {
      // Dart's List.sort is NOT stable, so equal cosines could come back in
      // either order — and with a true collision in the vocabulary that makes
      // the reported chord name arbitrary between runs.
      final d = ChordDetector();
      final w = _chordWindow([_f(48), _f(52), _f(55)], 4096);
      final first = d.analyze(w).candidates.map((c) => c.toString()).toList();
      for (var i = 0; i < 5; i++) {
        expect(
          d.analyze(w).candidates.map((c) => c.toString()).toList(),
          first,
        );
      }
    });

    test('the bass breaks a near-tie but never overrides the harmony', () {
      // A first-inversion C major has E in the bass and is still a C chord: the
      // bass is only allowed to decide between candidates that already score
      // within bassTieEpsilon of each other.
      final d = ChordDetector();
      final cOverE = d.analyze(_chordWindow([_f(52), _f(55), _f(60)], 8192));
      expect(cOverE.bassPc, 4);
      expect(
        cOverE.candidates.first.rootPc,
        0,
        reason: 'C/E must still be named C, not E-something',
      );
    });
  });

  group('ChordSmoother — temporal smoothing', () {
    // Measured on real audio (GuitarSet, tool/guitarset_chord_eval.dart): over a
    // single sustained chord, nine frames produce EIGHT different answers. A
    // per-frame chord detector is far less stable than its confidence suggests,
    // and combining frames is the largest cheap win in this path.
    final detector = ChordDetector();
    Float64List cmaj() => _chordWindow([_f(48), _f(52), _f(55)], 4096);

    test('a steady chord smooths to that chord, in every mode', () {
      for (final mode in ChordSmoothing.values) {
        final sm = ChordSmoother(detector, mode: mode);
        ChordReading? out;
        for (var i = 0; i < 9; i++) {
          out = sm.add(detector.analyze(cmaj()));
        }
        expect(out!.hasChord, isTrue, reason: mode.name);
        expect(out.candidates.first.rootPc, 0, reason: mode.name);
      }
    });

    test('one odd frame does not derail a steady chord', () {
      // The point of smoothing: a re-strum or passing note is outvoted.
      final sm = ChordSmoother(detector);
      final odd = _chordWindow([_f(54), _f(58), _f(61)], 4096); // F#
      ChordReading? out;
      for (var i = 0; i < 9; i++) {
        out = sm.add(detector.analyze(i == 4 ? odd : cmaj()));
      }
      expect(out!.candidates.first.rootPc, 0);
    });

    test('reset drops history, so one take cannot bleed into the next', () {
      final sm = ChordSmoother(detector);
      for (var i = 0; i < 9; i++) {
        sm.add(detector.analyze(cmaj()));
      }
      sm.reset();
      final after = sm.add(detector.analyze(Float64List(4096)));
      expect(after.hasChord, isFalse);
    });

    test('is deterministic', () {
      List<String> run() {
        final sm = ChordSmoother(detector);
        ChordReading? out;
        for (var i = 0; i < 9; i++) {
          out = sm.add(detector.analyze(cmaj()));
        }
        return out!.candidates.map((c) => c.toString()).toList();
      }

      expect(run(), run());
    });

    test('silence in, silence out', () {
      final sm = ChordSmoother(detector);
      final out = sm.add(ChordReading.silent());
      expect(out.hasChord, isFalse);
    });
  });
}
