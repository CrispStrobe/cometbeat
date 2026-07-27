// synth.dart — the pure stem-mixer and drum-kit lookup. mixStemsFloat
// peak-normalises each stem to its gain then sums (combo-independent levels);
// its exact contract is asserted here. drumKitById is a table lookup with a
// clean-kit fallback.
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart';
import 'package:flutter_test/flutter_test.dart';

MixStem _stem(List<double> s, double gain) =>
    (samples: Float64List.fromList(s), gain: gain);

void main() {
  group('mixStemsFloat', () {
    test('no stems → silence of exactly the requested length', () {
      final mix = mixStemsFloat(const [], totalSamples: 8);
      expect(mix.length, 8);
      expect(mix.every((v) => v == 0.0), isTrue);
    });

    test('a stem is peak-normalised to its gain', () {
      // peak 0.5, gain 0.8 → scale 1.6 → [0, 0.8, -0.8].
      final mix = mixStemsFloat(
        [
          _stem([0, 0.5, -0.5], 0.8),
        ],
        totalSamples: 3,
      );
      expect(mix[0], closeTo(0.0, 1e-12));
      expect(mix[1], closeTo(0.8, 1e-12));
      expect(mix[2], closeTo(-0.8, 1e-12));
    });

    test('length is always totalSamples — a long stem truncates, short pads',
        () {
      expect(
        mixStemsFloat(
          [
            _stem([1, 1, 1, 1], 1),
          ],
          totalSamples: 2,
        ).length,
        2,
      );
      final padded = mixStemsFloat(
        [
          _stem([1.0], 1),
        ],
        totalSamples: 4,
      );
      expect(padded.length, 4);
      expect(padded[1], 0.0); // beyond the stem → silence
    });

    test('a silent stem is skipped (no divide-by-zero)', () {
      final mix = mixStemsFloat(
        [
          _stem([0, 0, 0], 1),
        ],
        totalSamples: 3,
      );
      expect(mix.every((v) => v == 0.0), isTrue);
    });

    test('aligned stems sum after each is normalised', () {
      // each normalised to 0.3 at its own peak, aligned at sample 0 → 0.6.
      final mix = mixStemsFloat(
        [
          _stem([0.5], 0.3),
          _stem([1.0], 0.3),
        ],
        totalSamples: 1,
      );
      expect(mix[0], closeTo(0.6, 1e-12));
    });
  });

  group('drumKitById', () {
    test('finds every registered kit by its id', () {
      for (final k in kDrumKits) {
        expect(drumKitById(k.id).id, k.id);
      }
    });

    test('an unknown id falls back to the clean kit', () {
      expect(drumKitById('__nope__').id, kDrumKitClean.id);
    });
  });
}
