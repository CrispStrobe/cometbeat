// test/pitch_robustness_test.dart
//
// Characterizes the pitch detector against real-world conditions a physical
// instrument/voice introduces — vibrato, background noise, soft dynamics — so we
// know where it holds and where it gives up. The golden rule asserted here: the
// detector may return "no pitch", but it must never confidently report the
// WRONG note. (A real acoustic-instrument-into-a-mic pass still needs a human;
// this is the headless proxy — see PLAN.md.)

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/audio/pitch_analysis.dart';

double _f(int midi) => 440.0 * pow(2.0, (midi - 69) / 12.0);

/// One analysis window of a sine at [freq], optionally with cents-depth
/// [vibrato] at [vibratoHz], additive white [noise], and amplitude [amp].
Float64List _signal(
  double freq, {
  double vibrato = 0,
  double vibratoHz = 5,
  double noise = 0,
  double amp = 0.8,
  int n = 2048,
  int sr = 44100,
  int seed = 1,
}) {
  final rng = Random(seed);
  final out = Float64List(n);
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    final f = vibrato == 0
        ? freq
        : freq * pow(2.0, (vibrato / 100) * sin(2 * pi * vibratoHz * t) / 12);
    phase += f / sr;
    var s = amp * sin(2 * pi * phase);
    if (noise > 0) s += noise * (rng.nextDouble() * 2 - 1);
    out[i] = s;
  }
  return out;
}

void main() {
  final d = PitchDetector();

  test('holds pitch through singer-style vibrato (±20 cents, 5-6 Hz)', () {
    for (final hz in [5.0, 6.0]) {
      final r = d.analyze(_signal(_f(57), vibrato: 20, vibratoHz: hz)); // A3
      expect(r.hasPitch, isTrue, reason: 'vibrato $hz Hz lost the note');
      expect(r.nearestMidi, 57, reason: 'vibrato $hz Hz → ${r.noteName}');
      expect(r.cents.abs(), lessThan(25));
    }
  });

  test('never reports a WRONG note as noise rises (graceful give-up)', () {
    var lastDetectedNoise = 0.0;
    for (final noise in [0.0, 0.1, 0.25, 0.5, 1.0, 2.0]) {
      final r = d.analyze(_signal(_f(57), amp: 0.6, noise: noise, seed: 3));
      if (r.hasPitch) {
        expect(
          r.nearestMidi,
          57,
          reason: 'noise $noise misdetected as ${r.noteName}',
        );
        lastDetectedNoise = noise;
      }
    }
    // It should survive at least a modest amount of noise before giving up.
    expect(lastDetectedNoise, greaterThanOrEqualTo(0.25));
  });

  test('soft dynamics: audible is detected, near-silent gives no pitch', () {
    // pp but real → detected; ~silence → no pitch.
    expect(d.analyze(_signal(_f(60), amp: 0.05)).hasPitch, isTrue);
    expect(d.analyze(_signal(_f(60), amp: 0.0005)).hasPitch, isFalse);
  });

  test('rich, bright timbres do not cause octave errors', () {
    // A harmonically rich waveform (fundamental + strong overtones), like a
    // reedy string or a bright music-box, must still land on the fundamental.
    Float64List rich(int midi) {
      const n = 2048;
      final out = Float64List(n);
      final f = _f(midi);
      const harm = [1.0, 0.7, 0.5, 0.4, 0.3, 0.2];
      for (var i = 0; i < n; i++) {
        final t = i / 44100;
        var s = 0.0;
        for (var h = 0; h < harm.length; h++) {
          s += harm[h] * sin(2 * pi * f * (h + 1) * t);
        }
        out[i] = 0.2 * s;
      }
      return out;
    }

    for (final midi in [43, 55, 62]) {
      // G2, G3, D3
      final r = d.analyze(rich(midi));
      expect(r.hasPitch, isTrue);
      expect(r.nearestMidi, midi, reason: 'octave error: ${r.noteName}');
    }
  });
}
