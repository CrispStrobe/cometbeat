// module_convert.dart — the XM/IT sample-tuning numeric conversions between a
// C-5 playback speed (Hz) and a signed-nibble finetune / XM relative-note +
// finetune. Pure integer math, so the anchor points and clamps are exact.
import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('c5speedToFinetune', () {
    test('the reference C-5 speed (8363 Hz) is zero finetune', () {
      expect(c5speedToFinetune(8363), 0);
    });

    test('clamps into the signed-nibble range [-8, 7]', () {
      expect(c5speedToFinetune(100000), 7); // way sharp
      expect(c5speedToFinetune(1000), -8); // way flat
    });

    test('a sharper speed reads as a higher finetune than a flatter one', () {
      expect(c5speedToFinetune(8600), greaterThan(c5speedToFinetune(8363)));
      expect(c5speedToFinetune(8100), lessThan(c5speedToFinetune(8363)));
    });
  });

  group('xmTuningToC5speed', () {
    test('no relative note and no finetune is the reference speed', () {
      expect(xmTuningToC5speed(0, 0), 8363);
    });

    test('+12 relative semitones doubles the speed (one octave up)', () {
      expect(xmTuningToC5speed(12, 0), closeTo(16726, 1)); // 8363 × 2
    });

    test('-12 relative semitones halves the speed (one octave down)', () {
      expect(xmTuningToC5speed(-12, 0), closeTo(4181, 1)); // 8363 / 2
    });
  });
}
