// Edge-case robustness lock for the pure-Dart audio analyzers. PitchDetector
// (MPM/NSDF) and ChordDetector (radix-2 FFT + chromagram) run over live mic and
// imported-file audio — buffers whose length and contents the app doesn't
// control. Both must degrade cleanly (return a reading, never throw) on the
// pathological inputs that break naive DSP: an empty or length-1 window, an
// all-zero window (autocorrelation / energy normalization → 0/0), a NON-power-
// of-two length (the FFT asserts power-of-two, which is off in release), and
// NaN / Infinity / extreme magnitudes. A probe found all pass; this pins it.
// Pure Dart.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _buf(int n, double Function(int) f) =>
    Float64List.fromList([for (var i = 0; i < n; i++) f(i)]);

Map<String, Float64List> _edgeCases() => {
      'empty': Float64List(0),
      'length-1': _buf(1, (_) => 0.5),
      'all-zero (2048)': Float64List(2048),
      'non-power-of-2 (1000)': _buf(1000, (i) => 0.3),
      'non-power-of-2 (4095)': _buf(4095, (i) => 0.3),
      'leading NaN': _buf(2048, (i) => i == 0 ? double.nan : 0.1),
      'leading Infinity': _buf(2048, (i) => i == 0 ? double.infinity : 0.1),
      'huge magnitude': _buf(2048, (_) => 1e300),
      'tiny magnitude': _buf(2048, (_) => 1e-300),
    };

void main() {
  group('audio analyzers degrade cleanly on pathological windows', () {
    test('PitchDetector.analyze never throws', () {
      final d = PitchDetector();
      _edgeCases().forEach((name, buf) {
        expect(() => d.analyze(buf), returnsNormally, reason: name);
      });
    });

    test('ChordDetector.analyze never throws', () {
      final d = ChordDetector();
      _edgeCases().forEach((name, buf) {
        expect(() => d.analyze(buf), returnsNormally, reason: name);
      });
    });

    test('a clean silent window reads as no pitch / no chord (not garbage)',
        () {
      final silence = Float64List(2048);
      final p = PitchDetector().analyze(silence);
      final c = ChordDetector().analyze(silence);
      // Silence has no pitch and no chord — the detectors must say so, not
      // invent a note from 0/0.
      expect(p.hasPitch, isFalse);
      expect(c.hasChord, isFalse);
    });
  });
}
