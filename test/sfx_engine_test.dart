// Sound Lab SFX engine — render, presets, share token, morph/mutate/randomize.

import 'dart:typed_data';

import 'package:comet_beat/features/sound_lab/sfx_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const _sr = 44100.0;

void main() {
  test('render length matches the envelope; output is audible', () {
    const p = SfxParams(attack: 0.01);
    final pcm = sfxRender(p);
    expect(pcm.length, closeTo((0.31 * _sr).round(), 2));
    expect(sfxPeakDb(pcm), greaterThan(-40)); // not silence
  });

  test('every waveform produces sound', () {
    for (final w in SfxWave.values) {
      final pcm = sfxRender(SfxParams(wave: w));
      expect(sfxPeakDb(pcm), greaterThan(-40), reason: '$w');
    }
  });

  test('every preset renders audibly', () {
    for (final e in kSfxPresets.entries) {
      final pcm = sfxRender(e.value);
      expect(pcm, isNotEmpty, reason: e.key);
      expect(sfxPeakDb(pcm), greaterThan(-40), reason: e.key);
    }
  });

  test('output never clips beyond [-1, 1]', () {
    final pcm = sfxRender(
      kSfxPresets['explosion']!.copyWith({'distortion': 0.8, 'volume': 0.9}),
    );
    expect(pcm.every((v) => v >= -1.0 && v <= 1.0), isTrue);
  });

  group('share token', () {
    test('round-trips every param', () {
      const p = SfxParams(
        wave: SfxWave.sawtooth,
        baseFreq: 733,
        freqRamp: -1234,
        distortion: 0.4,
        duty: 0.31,
      );
      final back = SfxParams.fromShareToken(p.shareToken)!;
      expect(back.toJson(), p.toJson());
    });

    test('garbage token → null (never throws)', () {
      expect(SfxParams.fromShareToken('not-a-token!!'), isNull);
    });
  });

  test('morph interpolates numerics and snaps the wave at the midpoint', () {
    const a = SfxParams(baseFreq: 200);
    const b = SfxParams(wave: SfxWave.sine, baseFreq: 400);
    final mid = a.morph(b, 0.5);
    expect(mid.baseFreq, closeTo(300, 1e-6));
    expect(a.morph(b, 0.25).wave, SfxWave.square); // <0.5 keeps A
    expect(a.morph(b, 0.75).wave, SfxWave.sine); // ≥0.5 takes B
  });

  test('mutate stays in range and respects locks', () {
    const base = SfxParams();
    final m = mutate(base, seed: 3, amount: 0.3, locked: {'baseFreq'});
    expect(m.baseFreq, 440); // locked → untouched
    expect(m.duty, inInclusiveRange(0.05, 0.95)); // clamped to its range
  });

  test('randomize varies params but keeps locked ones + is seed-stable', () {
    const base = SfxParams();
    final r1 = randomize(base, seed: 9, locked: {'baseFreq'});
    final r2 = randomize(base, seed: 9, locked: {'baseFreq'});
    expect(r1.toJson(), r2.toJson()); // deterministic
    expect(r1.baseFreq, 440); // locked
    // At least one unlocked param moved off the base.
    expect(r1.decay == base.decay && r1.sustain == base.sustain, isFalse);
  });

  test('sfxPeakDb of silence is very low', () {
    expect(sfxPeakDb(Float64List(100)), lessThan(-100));
  });
}
