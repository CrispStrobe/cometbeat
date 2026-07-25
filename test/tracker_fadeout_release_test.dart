// The per-tick SAMPLE voice's key-off RELEASE envelope.
//
// Before: every sample voice faded on key-off with a hardcoded 30 ms curve,
// ignoring the instrument's real IT/XM fadeout rate. Now, when a played
// [SampleInstrument] carries a non-zero `nativeFadeout`, the tick voice fades at
// that native rate (the same `exp(-(fadeout/1024) * n / kSampleRate * 8)` used by
// the native-zone path); when `nativeFadeout == 0` it keeps the exact 30 ms
// fallback, so no-fadeout files (e.g. MOD) render byte-identically.
//
// These tests build a minimal one-channel song: a constant-DC sample that loops
// forever (so it never exhausts and carries no waveform of its own), a note held
// then keyed off, and a per-tick effect so the voice routes through the tick
// path being tested. Post-key-off amplitude is therefore shaped ONLY by the
// release envelope, which we can read straight off the PCM.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sampleLen = 8000;
  // Constant DC: the loop region is flat too, so a released voice reading through
  // it contributes a steady base amplitude modulated purely by `release`.
  final flat = Float64List.fromList(List<double>.filled(sampleLen, 0.5));

  // Row 4 is the key-off; at default timing (8 rows ≈ 1000 ms) that leaves ~4
  // rows of tail to observe the decay.
  const timing = TrackerTiming(rows: 8);
  final keyOff = timing.stepStartSample(4);

  Int16List renderWithFadeout(int fadeout) {
    final cells = List<TrackerCell>.filled(8, TrackerCell.empty)
      ..[0] = const TrackerCell(midi: 60) // note on
      ..[1] =
          const TrackerCell(fxCmd: 0x4, fxParam: 0x31) // per-tick fx (vibrato)
      ..[4] = TrackerCell.noteCut; // key-off
    final song = TrackerSong.fromParts(
      channels: [
        TrackerChannel(
          id: 'fade',
          instrument: SampleInstrument(
            'fade',
            flat,
            loopLength: sampleLen, // loopStart defaults to 0 → loops forever
            normalize: false, // keep the raw 0.5 amplitude
            nativeFadeout: fadeout,
          ),
          rows: 8,
        ),
      ],
      timing: timing,
      patterns: [
        TrackerPattern(name: '00', cells: [cells]),
      ],
      order: [0],
    );
    return replaySong(song).pcm;
  }

  // The steady base amplitude just BEFORE key-off (release == 1 there), averaged
  // to shrug off any single-sample noise.
  double steadyBase(Int16List pcm) {
    var s = 0.0;
    for (var i = keyOff - 2000; i < keyOff - 500; i++) {
      s += pcm[i].abs();
    }
    return s / 1500;
  }

  // The envelopes the two code paths are supposed to produce.
  double nativeEnv(int fadeout, int n) =>
      exp(-(fadeout / 1024.0) * n / kSampleRate * 8.0);
  double old30msEnv(int n) => exp(-n / (0.03 * kSampleRate));

  test('key-off release follows the native fadeout rate (moderate = slower)',
      () {
    const fadeout = 512; // realistic IT value → fades much slower than 30 ms
    final pcm = renderWithFadeout(fadeout);
    final base = steadyBase(pcm);
    expect(
      base,
      greaterThan(0.0),
      reason: 'note must be audible before key-off',
    );

    for (final n in [500, 1000, 2000, 4000]) {
      final want = base * nativeEnv(fadeout, n);
      expect(
        pcm[keyOff + n].abs(),
        closeTo(want, want * 0.05 + 1e-6),
        reason: 'native-fadeout envelope at n=$n',
      );
    }

    // The whole point: at a fixed offset the native curve is CLEARLY slower (much
    // louder) than the old fixed 30 ms curve would have been.
    final measured = pcm[keyOff + 1000].abs() / base; // ≈ exp(-4*1000/44100)
    final old = old30msEnv(1000); // ≈ exp(-1000/1323)
    expect(
      measured,
      greaterThan(old * 1.5),
      reason: 'fadeout=512 must decay slower than the old 30 ms curve',
    );
  });

  test('a large native fadeout decays FASTER than the old 30 ms curve', () {
    const fadeout = 8192;
    final pcm = renderWithFadeout(fadeout);
    final base = steadyBase(pcm);
    for (final n in [200, 500, 1000]) {
      final want = base * nativeEnv(fadeout, n);
      expect(
        pcm[keyOff + n].abs(),
        closeTo(want, want * 0.05 + 1e-6),
        reason: 'native-fadeout envelope at n=$n',
      );
    }
    final measured = pcm[keyOff + 1000].abs() / base;
    final old = old30msEnv(1000);
    expect(
      measured,
      lessThan(old * 0.8),
      reason: 'fadeout=8192 must decay faster than the old 30 ms curve',
    );
  });

  test('nativeFadeout == 0 keeps the exact old 30 ms release (regression pin)',
      () {
    final pcm = renderWithFadeout(0);
    final base = steadyBase(pcm);
    expect(base, greaterThan(0.0));
    for (final n in [200, 500, 1000]) {
      final want = base * old30msEnv(n);
      expect(
        pcm[keyOff + n].abs(),
        closeTo(want, want * 0.05 + 1e-6),
        reason: 'fadeout==0 must match the old 30 ms curve at n=$n',
      );
    }
  });
}
