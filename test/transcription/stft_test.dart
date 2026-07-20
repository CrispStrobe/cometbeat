// Validates the Dart STFT/iSTFT against torch.stft: complex parity on a fixture
// and perfect overlap-add reconstruction (round-trip). The DSP gate for source
// separation.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/stft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ref = jsonDecode(
    File('test/transcription/stft_ref.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final sr = ref['sr'] as int;
  final nFft = ref['nFft'] as int;
  final hop = ref['hop'] as int;
  final tones = (ref['tones'] as List).cast<num>();
  final amps = (ref['amps'] as List).cast<num>();
  final dur = (ref['dur'] as num).toDouble();

  Float64List signal() {
    final n = (sr * dur).round();
    final y = Float64List(n);
    for (var i = 0; i < n; i++) {
      var s = 0.0;
      for (var k = 0; k < tones.length; k++) {
        s += amps[k].toDouble() * sin(2 * pi * tones[k].toDouble() * i / sr);
      }
      y[i] = s;
    }
    return y;
  }

  test('STFT complex matches torch.stft', () {
    final st = Stft(nFft, hop);
    final (re, im, nFrames) = st.forward(signal());
    final frames = (ref['frames'] as List).cast<int>();
    final refRe =
        (ref['re'] as List).map((r) => (r as List).cast<num>()).toList();
    final refIm =
        (ref['im'] as List).map((r) => (r as List).cast<num>()).toList();
    expect(nFrames, ref['nFrames']);
    var maxErr = 0.0;
    for (var fi = 0; fi < frames.length; fi++) {
      final t = frames[fi];
      for (var f = 0; f < st.nFreq; f++) {
        final dr = (re[t * st.nFreq + f] - refRe[fi][f].toDouble()).abs();
        final di = (im[t * st.nFreq + f] - refIm[fi][f].toDouble()).abs();
        if (dr > maxErr) maxErr = dr;
        if (di > maxErr) maxErr = di;
      }
    }
    // ignore: avoid_print
    print('STFT parity max|Δ| = $maxErr');
    expect(maxErr, lessThan(0.01));
  });

  test('iSTFT(STFT(x)) reconstructs x', () {
    final st = Stft(nFft, hop);
    final x = signal();
    final (re, im, nFrames) = st.forward(x);
    final y = st.inverse(re, im, nFrames, x.length);
    var maxErr = 0.0;
    // Skip the first/last frame edges (COLA is exact only in the interior).
    for (var i = nFft; i < x.length - nFft; i++) {
      final d = (y[i] - x[i]).abs();
      if (d > maxErr) maxErr = d;
    }
    // ignore: avoid_print
    print('round-trip max|Δ| (interior) = $maxErr');
    expect(maxErr, lessThan(1e-6));
  });
}
