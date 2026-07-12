// test/pitch_analysis_test.dart
//
// Validates the monophonic pitch detector against synth.dart's own tones — so
// the capture-layer math is proven end-to-end without needing a microphone.
// We synthesize a note (cello timbre, harmonics and all), hand the middle
// window to the detector, and assert it recovers the pitch and the intonation.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/audio/pitch_analysis.dart';
import 'package:klang_universum/core/audio/synth.dart';

/// Render a steady tone at [freq] and return a centred analysis window,
/// avoiding the attack/decay edges so we test the sustained portion.
Float64List _window(double freq, PitchDetector d, {Instrument? voice}) {
  final samples = renderSegments(
    [
      (freqs: [freq], ms: 500),
    ],
    sampleRate: d.sampleRate,
    timbre: voice == null ? null : timbreFor(voice),
  );
  final start = (samples.length - d.windowSize) ~/ 2;
  final out = Float64List(d.windowSize);
  for (var i = 0; i < d.windowSize; i++) {
    out[i] = samples[start + i] / 32768.0;
  }
  return out;
}

void main() {
  final detector = PitchDetector();

  group('detects synthesized pitches', () {
    // Cello open strings + a couple of high references. C2 is the acid test:
    // an FFT at this window could not resolve it, MPM does.
    final cases = <String, double>{
      'C2 (cello low C)': 65.41,
      'G2 (cello G)': 98.00,
      'D3 (cello D)': 146.83,
      'A3 (cello A)': 220.00,
      'A4 (reference)': 440.00,
      'A5': 880.00,
    };
    cases.forEach((name, freq) {
      test(name, () {
        final r = detector.analyze(_window(freq, detector));
        expect(r.hasPitch, isTrue, reason: '$name should be detected');
        // Within 3 cents of the true frequency.
        final cents = 1200 * (log(r.frequency / freq) / log(2));
        expect(
          cents.abs(),
          lessThan(3),
          reason: '$name off by ${cents.toStringAsFixed(2)}¢',
        );
        expect(r.clarity, greaterThan(0.8));
      });
    });
  });

  test('works with the cello timbre (rich harmonics), no octave error', () {
    final r =
        detector.analyze(_window(98.0, detector, voice: Instrument.cello));
    expect(r.hasPitch, isTrue);
    // The classic failure mode is snapping an octave down/up; guard it.
    expect(r.frequency, closeTo(98.0, 2.0));
    expect(r.noteName, 'G2');
  });

  test('reports intonation error in cents (fretless use-case)', () {
    // 25 cents sharp of A3 (220 Hz).
    final sharp = 220.0 * pow(2, 25 / 1200);
    final r = detector.analyze(_window(sharp.toDouble(), detector));
    expect(r.nearestMidi, 57); // A3
    expect(r.cents, closeTo(25, 2));
    expect(r.noteName, 'A3');
  });

  test('silence and noise produce no pitch', () {
    final silence = Float64List(detector.windowSize); // all zeros
    expect(detector.analyze(silence).hasPitch, isFalse);

    final rng = Random(42);
    final noise = Float64List(detector.windowSize);
    for (var i = 0; i < noise.length; i++) {
      noise[i] = (rng.nextDouble() * 2 - 1) * 0.5;
    }
    expect(
      detector.analyze(noise).hasPitch,
      isFalse,
      reason: 'white noise is not periodic — should be rejected',
    );
  });

  test('pcm16ToFloat round-trips a known ramp', () {
    final bytes = Uint8List(8);
    final bd = ByteData.sublistView(bytes);
    bd.setInt16(0, 0, Endian.little);
    bd.setInt16(2, 16384, Endian.little); // +0.5
    bd.setInt16(4, -32768, Endian.little); // -1.0
    bd.setInt16(6, 32767, Endian.little); // ~+1.0
    final f = pcm16ToFloat(bytes);
    expect(f[0], closeTo(0.0, 1e-9));
    expect(f[1], closeTo(0.5, 1e-9));
    expect(f[2], closeTo(-1.0, 1e-9));
    expect(f[3], closeTo(1.0, 1e-3));
  });
}
