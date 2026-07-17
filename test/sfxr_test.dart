// sfxr — the chiptune sample generator (focused port of crispaudio's
// SynthEngine). Pure Dart, no device: bounded output, deterministic under a
// seed, and distinct timbres per preset.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/sfxr.dart';
import 'package:flutter_test/flutter_test.dart';

double _peak(Float64List b) {
  var p = 0.0;
  for (final v in b) {
    if (v.abs() > p) p = v.abs();
  }
  return p;
}

bool _allEqual(Float64List a, Float64List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  group('sfxrGenerate', () {
    test('output has the requested length and stays in [-1, 1]', () {
      final buf = sfxrGenerate(
        const SfxrParams(),
        durationSec: 0.25,
      );
      expect(buf.length, (44100 * 0.25).floor());
      expect(_peak(buf), lessThanOrEqualTo(1.0));
      expect(_peak(buf), greaterThan(0.0)); // it makes sound
    });

    test('same params + same seed = byte-identical (deterministic)', () {
      final a = sfxrGenerate(sfxrExplosion(Random(1)), rng: Random(3));
      final b = sfxrGenerate(sfxrExplosion(Random(1)), rng: Random(3));
      expect(_allEqual(a, b), isTrue);
    });

    test('noise presets differ across seeds', () {
      final a = sfxrGenerate(
        const SfxrParams(waveType: SfxrWave.noise),
        rng: Random(1),
      );
      final b = sfxrGenerate(
        const SfxrParams(waveType: SfxrWave.noise),
        rng: Random(2),
      );
      expect(_allEqual(a, b), isFalse);
    });

    test('a zero-length request is empty, not a crash', () {
      expect(sfxrGenerate(const SfxrParams(), durationSec: 0).length, 0);
    });
  });

  group('presets', () {
    test('every named preset makes audible sound', () {
      for (final entry in kSfxrPresets.entries) {
        final buf = sfxrGenerate(entry.value(Random(0)));
        expect(_peak(buf), greaterThan(0.0), reason: '${entry.key} was silent');
        expect(
          _peak(buf),
          lessThanOrEqualTo(1.0),
          reason: '${entry.key} clips',
        );
      }
    });

    test('different presets produce different waveforms', () {
      final coin = sfxrGenerate(sfxrCoin(Random(0)));
      final zap = sfxrGenerate(sfxrZap(Random(0)));
      expect(_allEqual(coin, zap), isFalse);
    });
  });
}
