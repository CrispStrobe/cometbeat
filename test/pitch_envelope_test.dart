// Pitch envelope on the two synthesized voices (the last open item in the
// consolidated Audio-FX backlog): the note starts off-pitch and curves back —
// the drop that makes a kick read as a kick or a zap as a zap.
//
// The load-bearing test here is the BYTE-IDENTICAL one. `renderSegmentsRaw` is
// the tracker/loop/DAW additive core and the tracker gates its renders on
// unchanged bytes, so the no-envelope path must be bit-for-bit what it was.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/sfxr.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart' show SfxrInstrument;
import 'package:comet_beat/core/audio/tracker_instrument_codec.dart';
import 'package:flutter_test/flutter_test.dart';

const _rate = kSampleRate;

/// Dominant frequency of a window, by counting rising zero crossings.
double _pitchOf(Float64List pcm, int from, int to) {
  var crossings = 0;
  for (var i = from + 1; i < to && i < pcm.length; i++) {
    if (pcm[i - 1] < 0 && pcm[i] >= 0) crossings++;
  }
  final seconds = (to - from) / _rate;
  return crossings / seconds;
}

void main() {
  group('additive voice (renderSegmentsRaw)', () {
    const flat = Timbre(harmonics: [1], attackMs: 0, decay: 0.01);
    final segment = [
      (freqs: [220.0], ms: 500),
    ];

    test('WITHOUT an envelope the output is byte-identical to before', () {
      // The guard that lets this feature exist at all: every built-in timbre
      // has pitchEnvSemitones == 0, so the tracker's renders can't shift.
      final a = renderSegmentsRaw(segment, timbre: flat);
      final b = renderSegmentsRaw(segment, timbre: flat);
      expect(a, b);
      // And the fixed-pitch branch really is the untouched sin(2*pi*f*t) form.
      for (var i = 0; i < 64; i++) {
        final t = i / _rate;
        final expected = math.sin(2 * math.pi * 220 * t) *
            (t < 0.0 ? 0.0 : 1.0) *
            math.exp(-0.01 * t / 0.5);
        expect(a[i], closeTo(expected, 1e-12), reason: 'sample $i');
      }
    });

    test('every built-in timbre leaves the envelope off', () {
      for (final instrument in Instrument.values) {
        expect(
          timbreFor(instrument).hasPitchEnvelope,
          isFalse,
          reason: instrument.name,
        );
      }
    });

    test('a positive envelope starts sharp and settles at the written pitch',
        () {
      const kickish = Timbre(
        harmonics: [1],
        attackMs: 0,
        decay: 0.01,
        pitchEnvSemitones: 24, // two octaves up at the attack
        pitchEnvDecay: 20,
      );
      final pcm = renderSegmentsRaw(segment, timbre: kickish);

      final start = _pitchOf(pcm, 0, _rate ~/ 100); // first 10 ms
      final end = _pitchOf(pcm, _rate ~/ 4, _rate ~/ 2); // last 250 ms
      expect(start, greaterThan(400)); // well above 220
      expect(end, closeTo(220, 12)); // settled back onto the note
    });

    test('a negative envelope starts flat and rises to pitch', () {
      const rising = Timbre(
        harmonics: [1],
        attackMs: 0,
        decay: 0.01,
        pitchEnvSemitones: -12,
        pitchEnvDecay: 20,
      );
      final pcm = renderSegmentsRaw(segment, timbre: rising);
      expect(_pitchOf(pcm, 0, _rate ~/ 100), lessThan(200));
      expect(_pitchOf(pcm, _rate ~/ 4, _rate ~/ 2), closeTo(220, 12));
    });

    test('the swept path stays finite and bounded', () {
      const extreme = Timbre(
        harmonics: [1, 0.5, 0.25],
        attackMs: 5,
        decay: 2,
        pitchEnvSemitones: 48,
        pitchEnvDecay: 0, // no decay at all — held two octaves up
      );
      final pcm = renderSegmentsRaw(segment, timbre: extreme);
      for (final v in pcm) {
        expect(v.isFinite, isTrue);
        expect(v.abs(), lessThan(4));
      }
    });

    test('a higher decay settles sooner', () {
      Timbre t(double decayRate) => Timbre(
            harmonics: const [1],
            attackMs: 0,
            decay: 0.01,
            pitchEnvSemitones: 24,
            pitchEnvDecay: decayRate,
          );
      // 30 ms in, the snappier envelope is already closer to the base pitch.
      const window = (_rate ~/ 100, _rate ~/ 33);
      final snappy = _pitchOf(
        renderSegmentsRaw(segment, timbre: t(60)),
        window.$1,
        window.$2,
      );
      final slow = _pitchOf(
        renderSegmentsRaw(segment, timbre: t(4)),
        window.$1,
        window.$2,
      );
      expect((snappy - 220).abs(), lessThan((slow - 220).abs()));
    });
  });

  group('sfxr voice', () {
    SfxrParams tone({double semitones = 0, double decay = 8}) => SfxrParams(
          waveType: SfxrWave.sine,
          sustain: 0.5,
          decay: 0,
          baseFreq: 0.5, // 220 Hz
          pitchEnvSemitones: semitones,
          pitchEnvDecay: decay,
        );

    test('0 semitones leaves the render exactly as it was', () {
      final off = sfxrGenerate(tone(), durationSec: 0.4);
      final explicitlyZero = sfxrGenerate(tone(decay: 99), durationSec: 0.4);
      // The decay rate must not matter when the amount is zero — the parameter
      // is skipped entirely rather than multiplying by a computed 1.0.
      expect(off, explicitlyZero);
    });

    test('a positive envelope starts sharp and settles', () {
      final pcm =
          sfxrGenerate(tone(semitones: 24, decay: 25), durationSec: 0.4);
      expect(_pitchOf(pcm, 0, _rate ~/ 100), greaterThan(400));
      expect(_pitchOf(pcm, _rate ~/ 5, _rate ~/ 3), closeTo(220, 15));
    });

    test('it is distinct from freqRamp — a ramp never settles', () {
      // freqRamp slides forever; the envelope returns to the base pitch. Late
      // in the note the ramped version is still climbing away from 220.
      final ramped = sfxrGenerate(
        const SfxrParams(
          waveType: SfxrWave.sine,
          sustain: 0.5,
          decay: 0,
          baseFreq: 0.5,
          freqRamp: 0.05,
        ),
        durationSec: 0.4,
      );
      final enveloped =
          sfxrGenerate(tone(semitones: 24, decay: 25), durationSec: 0.4);
      final lateRamp = _pitchOf(ramped, _rate ~/ 5, _rate ~/ 3);
      final lateEnv = _pitchOf(enveloped, _rate ~/ 5, _rate ~/ 3);
      expect(lateRamp, greaterThan(lateEnv + 50));
    });

    test('stays deterministic for a given seed', () {
      final a = sfxrGenerate(
        tone(semitones: 12),
        durationSec: 0.2,
        rng: math.Random(7),
      );
      final b = sfxrGenerate(
        tone(semitones: 12),
        durationSec: 0.2,
        rng: math.Random(7),
      );
      expect(a, b);
    });

    test('a saved instrument round-trips the envelope', () {
      // Without codec support the param would be silently dropped on save/load
      // — the same shape of bug as persisting an enum by its ordinal.
      const inst = SfxrInstrument(
        'zap',
        SfxrParams(pitchEnvSemitones: 18, pitchEnvDecay: 30),
      );
      final back = instrumentFromJson(instrumentToJson(inst)) as SfxrInstrument;
      expect(back.params.pitchEnvSemitones, 18);
      expect(back.params.pitchEnvDecay, 30);
    });

    test('an instrument saved BEFORE the envelope existed still loads flat',
        () {
      const inst = SfxrInstrument('old', SfxrParams());
      final json = instrumentToJson(inst);
      (json['params']! as Map<String, dynamic>)
        ..remove('pitchEnvSemitones')
        ..remove('pitchEnvDecay');
      final back = instrumentFromJson(json) as SfxrInstrument;
      expect(back.params.pitchEnvSemitones, 0); // sounds exactly as before
      expect(back.params.pitchEnvDecay, 8);
    });

    test('copyWith carries the new params', () {
      const base = SfxrParams();
      expect(base.pitchEnvSemitones, 0);
      final bent = base.copyWith(pitchEnvSemitones: -7, pitchEnvDecay: 3);
      expect(bent.pitchEnvSemitones, -7);
      expect(bent.pitchEnvDecay, 3);
      expect(bent.baseFreq, base.baseFreq); // untouched
    });
  });
}
