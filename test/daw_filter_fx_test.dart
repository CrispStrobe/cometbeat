// O11 — the rest of the biquad set (band-pass · notch · peaking · shelves) and
// the new phaser, exercised as real clip effects. The assertions are spectral,
// not "the code ran": each filter is fed two pure tones and must keep one and
// remove/boost the other, which is the only thing that proves the right
// BiquadKind reached the DSP with the right parameters.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/phaser.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

const _rate = kDawSampleRate;

Float64List _tone(double freq, {int samples = _rate, double amp = 0.5}) =>
    Float64List.fromList([
      for (var i = 0; i < samples; i++)
        amp * math.sin(2 * math.pi * freq * i / _rate),
    ]);

Float64List _mix(Float64List a, Float64List b) => Float64List.fromList([
      for (var i = 0; i < a.length; i++) a[i] + b[i],
    ]);

/// Energy at [freq] via a one-bin Goertzel-style correlation — enough to say
/// "this partial survived" or "this partial is gone" without a full FFT.
double _energyAt(Float64List pcm, double freq) {
  var re = 0.0;
  var im = 0.0;
  for (var i = 0; i < pcm.length; i++) {
    final w = 2 * math.pi * freq * i / _rate;
    re += pcm[i] * math.cos(w);
    im += pcm[i] * math.sin(w);
  }
  return math.sqrt(re * re + im * im) / pcm.length;
}

/// Run one clip effect over [input] with the given params.
Float64List _apply(
  DawClipEffectType type,
  Float64List input, {
  Map<String, double> params = const {},
}) {
  final base = defaultDawClipEffect(type);
  return applyClipEffectChain(
    input,
    [
      base.copyWith(params: {...base.params, ...params}),
    ],
    _rate,
  );
}

void main() {
  // 200 Hz + 5000 Hz, equal level: a low and a high partial to separate.
  final low = _tone(200);
  final high = _tone(5000);
  final both = _mix(low, high);

  group('biquad clip effects', () {
    test('band pass keeps its centre and rejects the far partial', () {
      final out = _apply(
        DawClipEffectType.bandpass,
        both,
        params: {'freq': 200, 'q': 2},
      );
      expect(_energyAt(out, 200), greaterThan(0.5 * _energyAt(both, 200)));
      expect(_energyAt(out, 5000), lessThan(0.15 * _energyAt(both, 5000)));
    });

    test('notch removes its centre and keeps everything else', () {
      final out = _apply(
        DawClipEffectType.notch,
        both,
        params: {'freq': 5000, 'q': 4},
      );
      expect(_energyAt(out, 5000), lessThan(0.2 * _energyAt(both, 5000)));
      expect(_energyAt(out, 200), greaterThan(0.9 * _energyAt(both, 200)));
    });

    test('peaking EQ boosts only around its centre', () {
      final out = _apply(
        DawClipEffectType.peakingEq,
        both,
        params: {'freq': 200, 'q': 1, 'gainDb': 12},
      );
      // +12 dB is ~4x; the distant partial must be left alone.
      expect(_energyAt(out, 200), greaterThan(2 * _energyAt(both, 200)));
      expect(
        _energyAt(out, 5000),
        closeTo(_energyAt(both, 5000), 0.1 * _energyAt(both, 5000)),
      );
    });

    test('peaking EQ cuts with a negative gain', () {
      final out = _apply(
        DawClipEffectType.peakingEq,
        both,
        params: {'freq': 200, 'q': 1, 'gainDb': -12},
      );
      expect(_energyAt(out, 200), lessThan(0.5 * _energyAt(both, 200)));
    });

    test('low shelf lifts the bottom, high shelf lifts the top', () {
      final lowShelf = _apply(
        DawClipEffectType.lowShelf,
        both,
        params: {'freq': 800, 'gainDb': 12},
      );
      expect(_energyAt(lowShelf, 200), greaterThan(2 * _energyAt(both, 200)));
      expect(
        _energyAt(lowShelf, 5000),
        closeTo(_energyAt(both, 5000), 0.15 * _energyAt(both, 5000)),
      );

      final highShelf = _apply(
        DawClipEffectType.highShelf,
        both,
        params: {'freq': 1500, 'gainDb': 12},
      );
      expect(
        _energyAt(highShelf, 5000),
        greaterThan(2 * _energyAt(both, 5000)),
      );
      expect(
        _energyAt(highShelf, 200),
        closeTo(_energyAt(both, 200), 0.15 * _energyAt(both, 200)),
      );
    });

    test('mix 0 is an exact bypass for every new filter', () {
      for (final type in [
        DawClipEffectType.bandpass,
        DawClipEffectType.notch,
        DawClipEffectType.peakingEq,
        DawClipEffectType.lowShelf,
        DawClipEffectType.highShelf,
      ]) {
        final out = _apply(type, both, params: {'mix': 0});
        expect(out, both, reason: type.name);
      }
    });

    test('every new type has defaults and survives a project round-trip', () {
      for (final type in [
        DawClipEffectType.bandpass,
        DawClipEffectType.notch,
        DawClipEffectType.peakingEq,
        DawClipEffectType.lowShelf,
        DawClipEffectType.highShelf,
        DawClipEffectType.phaser,
      ]) {
        final fx = defaultDawClipEffect(type);
        expect(fx.type, type);
        expect(fx.params, isNotEmpty, reason: type.name);
        // Effects serialize by NAME, so appending to the enum can't shift an
        // older saved project onto the wrong effect.
        final restored = DawClipEffect.fromJson(fx.toJson());
        expect(restored, isNotNull, reason: type.name);
        expect(restored!.type, type, reason: type.name);
        expect(restored.params, fx.params, reason: type.name);
      }
    });
  });

  group('convolution reverb as a clip effect', () {
    /// An impulse: the cleanest way to see a reverb tail, since anything after
    /// sample 0 is the effect's own output.
    Float64List impulse(int samples) => Float64List(samples)..[0] = 1.0;

    test('adds a decaying tail after the dry hit', () {
      final out = _apply(
        DawClipEffectType.convolutionReverb,
        impulse(_rate),
        params: {'seconds': 1.0, 'mix': 1},
      );
      double energy(int from, int to) {
        var sum = 0.0;
        for (var i = from; i < to && i < out.length; i++) {
          sum += out[i] * out[i];
        }
        return sum;
      }

      // There is real energy after the impulse...
      expect(energy(100, _rate ~/ 4), greaterThan(0));
      // ...and it decays: the first quarter-second holds more than the last.
      expect(
        energy(100, _rate ~/ 4),
        greaterThan(energy(_rate ~/ 2, _rate)),
      );
    });

    test('pre-delay pushes the tail later', () {
      Float64List tail(double predelayMs) => _apply(
            DawClipEffectType.convolutionReverb,
            impulse(_rate ~/ 2),
            params: {'predelayMs': predelayMs, 'mix': 1, 'seconds': 0.5},
          );
      int firstTailIndex(Float64List pcm) {
        for (var i = 50; i < pcm.length; i++) {
          if (pcm[i].abs() > 1e-6) return i;
        }
        return pcm.length;
      }

      expect(
        firstTailIndex(tail(50)),
        greaterThan(firstTailIndex(tail(0))),
      );
    });

    test('mix 0 is an exact bypass', () {
      final input = _tone(440, samples: 4410);
      expect(
        _apply(
          DawClipEffectType.convolutionReverb,
          input,
          params: {'mix': 0},
        ),
        input,
      );
    });

    test('is deterministic — the same settings render the same tail', () {
      // The IR is synthesized from a FIXED seed, which is what lets a baked
      // clip stay byte-identical across renders.
      final a = _apply(DawClipEffectType.convolutionReverb, impulse(8192));
      final b = _apply(DawClipEffectType.convolutionReverb, impulse(8192));
      expect(a, b);
    });

    test('differs audibly from the algorithmic reverb', () {
      // Both are reverbs; if they rendered the same there'd be no reason to
      // offer both.
      final conv = _apply(DawClipEffectType.convolutionReverb, impulse(8192));
      final algo = _apply(DawClipEffectType.reverb, impulse(8192));
      var diff = 0.0;
      for (var i = 0; i < 8192; i++) {
        diff += (conv[i] - algo[i]).abs();
      }
      expect(diff, greaterThan(1));
    });

    test('has defaults and survives a project round-trip', () {
      final fx = defaultDawClipEffect(DawClipEffectType.convolutionReverb);
      expect(fx.params.keys, containsAll(['seconds', 'decay', 'mix']));
      final restored = DawClipEffect.fromJson(fx.toJson());
      expect(restored!.type, DawClipEffectType.convolutionReverb);
      expect(restored.params, fx.params);
    });
  });

  group('phaser', () {
    test('sweeping notches make the output vary over time', () {
      // A phaser on steady input must NOT be steady: the moving notches change
      // the level as they sweep past the partial. That is the whole effect.
      final out = _apply(
        DawClipEffectType.phaser,
        _tone(1000),
        params: {'rateHz': 2, 'depth': 1, 'minFreq': 300, 'maxFreq': 3000},
      );
      double rmsOver(int from, int to) {
        var sum = 0.0;
        for (var i = from; i < to; i++) {
          sum += out[i] * out[i];
        }
        return math.sqrt(sum / (to - from));
      }

      // Compare eighths of a second across one LFO cycle.
      final levels = [
        for (var k = 0; k < 8; k++)
          rmsOver(k * _rate ~/ 8, (k + 1) * _rate ~/ 8),
      ];
      final min = levels.reduce(math.min);
      final max = levels.reduce(math.max);
      expect(max - min, greaterThan(0.01), reason: 'the sweep must modulate');
      expect(out, hasLength(_rate));
    });

    test('depth 0 is an exact bypass', () {
      final input = _tone(440, samples: 4410);
      expect(phaserFx(input, sampleRate: _rate.toDouble(), depth: 0), input);
      // ...and the effect wrapper agrees.
      expect(
        _apply(DawClipEffectType.phaser, input, params: {'depth': 0}),
        input,
      );
    });

    test('stays bounded and finite with extreme feedback', () {
      final out = phaserFx(
        _tone(440, samples: _rate ~/ 2),
        sampleRate: _rate.toDouble(),
        depth: 1,
        feedback: 5, // clamped internally — must not blow up
        stages: 12,
      );
      for (final v in out) {
        expect(v.isFinite, isTrue);
        expect(v.abs(), lessThan(10));
      }
    });

    test('an empty buffer is handled', () {
      expect(
        phaserFx(Float64List(0), sampleRate: _rate.toDouble()),
        isEmpty,
      );
    });
  });
}
