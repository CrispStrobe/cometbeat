// Sf2Zone volume-envelope generators decode correctly: timecents → seconds
// (2^(tc/1200)) and sustain centibels → linear gain (10^(-cB/200)). These drive
// the resampling voice's DAHDSR so a font's own attack/decay/sustain/release
// play as designed.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('envelope timecents → seconds and sustain cB → gain', () {
    const z = Sf2Zone(
      keyLo: 0,
      keyHi: 127,
      sampleIndex: 0,
      rootKey: 60,
      attackVolTc: 0, // 2^0 = 1 s
      holdVolTc: -6000, // 2^-5 = 1/32 s
      decayVolTc: 1200, // 2^1 = 2 s
      sustainVolCb: 200, // −20 dB → 0.1
    );
    expect(z.attackVolSec, closeTo(1.0, 1e-9));
    expect(z.holdVolSec, closeTo(1 / 32, 1e-9));
    expect(z.decayVolSec, closeTo(2.0, 1e-9));
    expect(z.releaseVolSec, closeTo(0.0009766, 1e-6));
    expect(z.sustainGain, closeTo(0.1, 1e-9));
  });

  test('the defaults are a full-level gate (unset font behaves like before)',
      () {
    const z = Sf2Zone(keyLo: 0, keyHi: 127, sampleIndex: 0, rootKey: 60);
    expect(z.attackVolSec, lessThan(0.002)); // ~1 ms → instant attack
    expect(z.releaseVolSec, lessThan(0.002));
    expect(z.sustainGain, closeTo(1.0, 1e-9)); // full sustain
    // Default filter = wide open (≈ 20 kHz), Butterworth (no resonance).
    expect(z.filterCutoffHz, closeTo(19912, 60));
    expect(z.filterQ, closeTo(0.707, 0.01));
  });

  test('filter: cutoff cents → Hz and resonance cB → Q', () {
    const z = Sf2Zone(
      keyLo: 0,
      keyHi: 127,
      sampleIndex: 0,
      rootKey: 60,
      filterFcCents: 7200, // 7200/1200 = 6 → 8.176 · 2^6 = 523.3 Hz
      filterQCb: 120, // 12 dB → resonant (Q > 1)
    );
    expect(z.filterCutoffHz, closeTo(523.3, 1));
    expect(z.filterQ, greaterThan(1.0));
  });

  test('LFO: frequency cents → Hz; depths default to no effect', () {
    const off = Sf2Zone(keyLo: 0, keyHi: 127, sampleIndex: 0, rootKey: 60);
    expect(off.vibLfoHz, closeTo(8.176, 0.01)); // 0 cents → 8.176 Hz
    expect(off.vibLfoToPitchCents, 0); // no vibrato by default
    expect(off.modLfoToVolumeCb, 0); // no tremolo by default

    const vib = Sf2Zone(
      keyLo: 0,
      keyHi: 127,
      sampleIndex: 0,
      rootKey: 60,
      freqVibLfoCents: 1200, // ×2 → ~16.35 Hz
      vibLfoToPitchCents: 40,
    );
    expect(vib.vibLfoHz, closeTo(16.35, 0.05));
    expect(vib.vibLfoToPitchCents, 40);
  });

  test('zone pan (gen 17) 0.1%→−1..1 + sample L/R type', () {
    const centre = Sf2Zone(keyLo: 0, keyHi: 127, sampleIndex: 0, rootKey: 60);
    expect(centre.pan, 0);
    const left = Sf2Zone(
      keyLo: 0,
      keyHi: 127,
      sampleIndex: 0,
      rootKey: 60,
      panTenthPct: -500,
    );
    const half = Sf2Zone(
      keyLo: 0,
      keyHi: 127,
      sampleIndex: 0,
      rootKey: 60,
      panTenthPct: 250,
    );
    expect(left.pan, closeTo(-1.0, 1e-9));
    expect(half.pan, closeTo(0.5, 1e-9));

    final l = Sf2Sample(
      name: 's',
      pcm: Float64List(4),
      sampleRate: 44100,
      originalPitch: 60,
      pitchCorrection: 0,
      loopStart: 0,
      loopEnd: 0,
      sampleType: 4,
    );
    expect(l.isLeft, isTrue);
    expect(l.isRight, isFalse);
  });
}
