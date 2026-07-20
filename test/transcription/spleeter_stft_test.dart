// Validates the center=FALSE STFT/iSTFT path (Spleeter's front-end) against a
// kaldi-native-fbank (`knf.Stft`, center=False, Hann) reference dump. This is
// the DSP gate for the Spleeter separator — the model runs on |STFT|.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/stft.dart';
import 'package:flutter_test/flutter_test.dart';

const int _sr = 44100;

/// The exact deterministic synthetic signal the reference oracle used (ch0).
Float64List synthCh0(int n) {
  final x = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = i.toDouble();
    var v = 0.30 * math.sin(2 * math.pi * 220.0 * t / _sr) +
        0.20 * math.sin(2 * math.pi * 440.0 * t / _sr);
    v *= 0.8 + 0.2 * math.sin(2 * math.pi * 3.0 * t / _sr);
    x[i] = v;
  }
  return x;
}

Float32List readBin(String path) {
  final bytes = File(path).readAsBytesSync();
  final bd = ByteData.sublistView(bytes);
  final count = bd.getInt32(0, Endian.little);
  final out = Float32List(count);
  for (var i = 0; i < count; i++) {
    out[i] = bd.getFloat32(4 + i * 4, Endian.little);
  }
  return out;
}

void main() {
  const dir = 'test/transcription';

  test('center=false STFT matches knf.Stft (Hann, no padding)', () {
    final sig = synthCh0(8192);
    final st = Stft(4096, 1024, center: false);
    final (re, im, nFrames) = st.forward(sig);
    expect(nFrames, 5); // 1 + (8192-4096)/1024
    expect(st.nFreq, 2049);

    final refRe = readBin('$dir/spleeter_short_stft_re.bin');
    final refIm = readBin('$dir/spleeter_short_stft_im.bin');
    expect(refRe.length, nFrames * st.nFreq);

    var maxRe = 0.0, maxIm = 0.0;
    for (var i = 0; i < re.length; i++) {
      maxRe = math.max(maxRe, (re[i] - refRe[i]).abs());
      maxIm = math.max(maxIm, (im[i] - refIm[i]).abs());
    }
    // knf computes in float32; allow a small tolerance.
    expect(maxRe, lessThan(2e-3), reason: 'real max|Δ|=$maxRe');
    expect(maxIm, lessThan(2e-3), reason: 'imag max|Δ|=$maxIm');
  });

  test('center=false iSTFT matches knf.IStft (COLA overlap-add)', () {
    final sig = synthCh0(8192);
    final st = Stft(4096, 1024, center: false);
    final (re, im, nFrames) = st.forward(sig);

    final refIstft = readBin('$dir/spleeter_short_istft.bin');
    // knf iSTFT length = (nFrames-1)*hop + nFft = 8192 here.
    final recon = st.inverse(re, im, nFrames, refIstft.length);

    var maxD = 0.0;
    // Interior samples only — the edges of a center=false OLA are under-summed
    // (only one window covers them), which both knf and torch leave un-scaled.
    final lo = 4096, hi = refIstft.length - 4096;
    for (var i = lo; i < hi; i++) {
      maxD = math.max(maxD, (recon[i] - refIstft[i]).abs());
    }
    expect(maxD, lessThan(2e-3), reason: 'iSTFT interior max|Δ|=$maxD');
  });
}
