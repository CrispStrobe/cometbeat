// MP3 polyphase subband analysis — slice 2. Verified by known filterbank
// properties (silence, DC → subband 0, linearity), not glint's exact bytes
// (this is a double-precision port; the algorithm is the reference).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_subband.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _const(double v) => Float64List.fromList(List.filled(32, v));

void main() {
  test('silence in -> silence out', () {
    final f = Mp3SubbandAnalysis();
    final out = Float64List(32);
    for (var s = 0; s < 20; s++) {
      f.processSlot(_const(0), out);
    }
    for (final v in out) {
      expect(v.abs(), lessThan(1e-12));
    }
  });

  test('DC input concentrates energy in subband 0', () {
    final f = Mp3SubbandAnalysis();
    final out = Float64List(32);
    // Warm up the 512-tap window with a constant so the response settles.
    for (var s = 0; s < 20; s++) {
      f.processSlot(_const(0.5), out);
    }
    final e0 = out[0].abs();
    for (var i = 1; i < 32; i++) {
      expect(
        out[i].abs(),
        lessThan(e0),
        reason: 'subband $i should carry less than the DC band 0',
      );
    }
    expect(e0, greaterThan(0.1)); // real signal, not zero
  });

  test('linearity: scaling the input scales the output', () {
    final a = Mp3SubbandAnalysis();
    final b = Mp3SubbandAnalysis();
    final oa = Float64List(32);
    final ob = Float64List(32);
    // A short ramp-ish signal.
    for (var s = 0; s < 6; s++) {
      final sig = Float64List.fromList(
        List.generate(32, (i) => ((s * 32 + i) % 17) / 17 - 0.5),
      );
      final sig2 = Float64List.fromList(sig.map((v) => v * 3.0).toList());
      a.processSlot(sig, oa);
      b.processSlot(sig2, ob);
    }
    for (var i = 0; i < 32; i++) {
      expect(ob[i], closeTo(oa[i] * 3.0, 1e-9));
    }
  });

  test('reset clears state', () {
    final f = Mp3SubbandAnalysis();
    final out = Float64List(32);
    for (var s = 0; s < 5; s++) {
      f.processSlot(_const(0.9), out);
    }
    f.reset();
    // After reset, silence in immediately gives silence out.
    f.processSlot(_const(0), out);
    for (final v in out) {
      expect(v.abs(), lessThan(1e-12));
    }
  });
}
