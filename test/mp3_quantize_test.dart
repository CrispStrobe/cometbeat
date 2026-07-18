// MP3 nonlinear quantizer — slice 4. Verified by quantizer properties
// (zero, monotone gain, round-trip within quant error, rzero, the 0.75 law).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_quantize.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zeros quantize to zeros', () {
    final ix = mp3QuantizeUniform(Float64List(576), 180);
    expect(ix.every((v) => v == 0), isTrue);
    expect(mp3Rzero(ix), 0);
  });

  test('sign is preserved', () {
    final mdct = Float64List(576);
    mdct[0] = 12.0;
    mdct[1] = -12.0;
    final ix = mp3QuantizeUniform(mdct, 210);
    expect(ix[0] > 0, isTrue);
    expect(ix[1] < 0, isTrue);
    expect(ix[0], -ix[1]); // symmetric magnitudes
  });

  test('higher global_gain quantizes coarser (fewer total steps)', () {
    final rnd = math.Random(3);
    final mdct = Float64List.fromList(
      List.generate(576, (_) => (rnd.nextDouble() - 0.5) * 50),
    );
    int total(int g) =>
        mp3QuantizeUniform(mdct, g).fold(0, (s, v) => s + v.abs());
    expect(total(230), lessThan(total(200)));
  });

  test('round-trips within quantization error', () {
    final rnd = math.Random(5);
    // Values scaled so the quantizer lands in a healthy 10..2000 range at gg=180.
    final mdct = Float64List.fromList(
      List.generate(576, (_) => (rnd.nextDouble() - 0.5) * 200),
    );
    const gg = 180;
    final back = mp3Dequantize(mp3QuantizeUniform(mdct, gg), gg);
    // Relative error per coefficient should be small (nonlinear quant step).
    for (var i = 0; i < 576; i++) {
      if (mdct[i].abs() > 5) {
        expect((back[i] - mdct[i]).abs() / mdct[i].abs(), lessThan(0.15));
      }
    }
  });

  test('rzero finds the last non-zero line', () {
    final mdct = Float64List(576);
    mdct[100] = 30.0;
    final ix = mp3QuantizeUniform(mdct, 200);
    expect(mp3Rzero(ix), 101);
  });

  test('clamps to the 8191 ceiling', () {
    // Low global_gain = a large step, so a big line saturates the 13-bit max.
    final mdct = Float64List(576)..[0] = 1e6;
    final ix = mp3QuantizeUniform(mdct, 0);
    expect(ix[0], 8191);
  });
}
