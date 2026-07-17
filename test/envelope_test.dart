// test/envelope_test.dart
//
// Per-note ADSR volume envelope: shapes a note (attack in, release out), is an
// identity when flat, length/pitch-safe, deterministic. Synthetic buffers only.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/envelope_test.dart

import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/envelope.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _dc(int n, [double v = 1.0]) => Float64List(n)..fillRange(0, n, v);
double _peak(Float64List b) => b.fold(0.0, (m, v) => v.abs() > m ? v.abs() : m);

void main() {
  const sr = 44100;

  test('Envelope.none is an identity (unchanged copy)', () {
    final buf = _dc(1000, 0.5);
    final out = applyEnvelope(buf, Envelope.none);
    expect(out.length, buf.length);
    for (var i = 0; i < buf.length; i++) {
      expect(out[i], buf[i]);
    }
  });

  test('attack ramps in from silence; release fades out to silence', () {
    final buf = _dc(sr); // 1 s of DC
    const env = Envelope(attack: 0.01, release: 0.02); // 10ms / 20ms
    final out = applyEnvelope(buf, env);

    expect(out.length, buf.length);
    expect(out.first, closeTo(0.0, 1e-9)); // starts silent
    expect(out.last, lessThan(0.02)); // faded out (last gain = sustain/release)
    // A middle sample (sustain region, sustain 1) is untouched.
    expect(out[sr ~/ 2], closeTo(1.0, 1e-9));
    // Monotonic ramp over the first 10ms.
    final aSamples = (0.01 * sr).round();
    expect(out[aSamples ~/ 2], greaterThan(out[1]));
    expect(out[aSamples ~/ 2], lessThan(out[aSamples]));
    expect(_peak(out), lessThanOrEqualTo(1.0));
  });

  test('decay falls to the sustain level', () {
    final buf = _dc(sr);
    const env = Envelope(attack: 0.0, decay: 0.1, sustain: 0.5, release: 0.0);
    final out = applyEnvelope(buf, env);
    // After the 100ms decay, gain sits at sustain 0.5.
    expect(out[sr ~/ 2], closeTo(0.5, 1e-9));
    // Early in the decay it's above sustain.
    expect(out[(0.02 * sr).round()], greaterThan(0.5));
  });

  test('a very short note is safe (stages scaled to fit); deterministic', () {
    final tiny = _dc(64);
    const env = Envelope(attack: 0.02, release: 0.02); // 40ms >> 64 samples
    final a = applyEnvelope(tiny, env);
    final b = applyEnvelope(tiny, env);
    expect(a.length, tiny.length);
    expect(a.every((v) => v.isFinite), isTrue);
    expect(_peak(a), lessThanOrEqualTo(1.0));
    for (var i = 0; i < a.length; i++) {
      expect(a[i], b[i]); // deterministic
    }
  });

  test('empty input is safe', () {
    expect(applyEnvelope(Float64List(0), Envelope.declick).length, 0);
  });
}
