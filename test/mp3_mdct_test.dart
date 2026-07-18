// MP3 MDCT (long blocks) + alias reduction — slice 3. Verified by MDCT/rotation
// properties (silence, linearity, alias butterfly is energy-preserving), not
// glint's exact bytes (double-precision port; the algorithm is the reference).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_mdct.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('silence in -> silence MDCT', () {
    final m = Mp3Mdct();
    final sb = Float64List(32 * 18);
    final out = Float64List(32 * 18);
    m.process(sb, out);
    m.process(sb, out); // second granule (overlap now also zero)
    for (final v in out) {
      expect(v.abs(), lessThan(1e-15));
    }
  });

  test('linearity: scaling subband input scales the MDCT', () {
    final a = Mp3Mdct();
    final b = Mp3Mdct();
    final oa = Float64List(32 * 18);
    final ob = Float64List(32 * 18);
    final rnd = math.Random(7);
    for (var g = 0; g < 3; g++) {
      final s = Float64List.fromList(
        List.generate(32 * 18, (_) => rnd.nextDouble() - 0.5),
      );
      final s2 = Float64List.fromList(s.map((v) => v * 2.5).toList());
      a.process(s, oa);
      b.process(s2, ob);
    }
    for (var i = 0; i < 32 * 18; i++) {
      expect(ob[i], closeTo(oa[i] * 2.5, 1e-9));
    }
  });

  test('alias reduction is energy-preserving (orthonormal butterfly)', () {
    final m = Mp3Mdct();
    final rnd = math.Random(11);
    final mdct = Float64List.fromList(
      List.generate(32 * 18, (_) => rnd.nextDouble() - 0.5),
    );
    double energy(Float64List a) => a.fold(0.0, (s, v) => s + v * v);
    final before = energy(mdct);
    m.aliasReduce(mdct);
    expect(energy(mdct), closeTo(before, 1e-9));
  });

  test('a non-trivial signal yields a non-trivial MDCT', () {
    final m = Mp3Mdct();
    final out = Float64List(32 * 18);
    // A tone-ish ramp in subband 0 across two granules (fills the overlap).
    Float64List sig(int g) => Float64List.fromList(
          List.generate(32 * 18, (i) {
            final sb = i ~/ 18;
            final n = i % 18;
            return sb == 0 ? math.sin((g * 18 + n) * 0.3) : 0.0;
          }),
        );
    m.process(sig(0), out);
    m.process(sig(1), out);
    expect(out.any((v) => v.abs() > 1e-6), isTrue);
  });
}
