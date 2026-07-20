// The native-ORT ("onnxFfi") F0 path. Two things are testable headlessly:
//   1. crepeF0WithRunner — the runtime-agnostic seam: given a fake activation
//      runner (no model, no native lib), the SAME framing/decoding produces the
//      pitch the activation encodes. This is exactly what the native-ORT session
//      drives in an app build.
//   2. The provider is null-safe: with no native ORT loadable here (and/or no
//      model), loadOnnxFfi* return null so the resolver falls back.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/crepe.dart';
import 'package:comet_beat/features/games/transcribe/onnx_ffi_provider.dart';
import 'package:flutter_test/flutter_test.dart';

// CREPE bin geometry (torchcrepe): cents = 20·bin + 1997.3794…, hz = 10·2^(c/1200).
const double _centsPerBin = 20;
const double _centsBase = 1997.3794084376191;
double _binToHz(int bin) =>
    10.0 * math.pow(2.0, (_centsPerBin * bin + _centsBase) / 1200.0);

void main() {
  test('crepeF0WithRunner decodes the activation the runner returns', () {
    // A one-hot-ish activation peaked at a fixed bin (≈441 Hz), neighbours far
    // negative so sigmoid weighting picks that bin cleanly.
    const peakBin = 228;
    Float32List fakeRun(Float32List frames, int nFrames) {
      final act = Float32List(nFrames * 360)..fillRange(0, nFrames * 360, -20);
      for (var f = 0; f < nFrames; f++) {
        act[f * 360 + peakBin] = 20; // sigmoid(20)≈1, sigmoid(-20)≈0
      }
      return act;
    }

    // 16 kHz mono so there's no resample; a few frames' worth of samples.
    final mono = Float64List(1600); // 100 ms → ~11 frames at a 10 ms hop
    final track = crepeF0WithRunner(mono, sampleRate: 16000, run: fakeRun);

    expect(track, isNotEmpty);
    for (final f in track) {
      expect(f.f0Hz, closeTo(_binToHz(peakBin), 0.5));
      expect(f.voicedProb, closeTo(1.0, 1e-3));
    }
  });

  test('empty audio → empty track through the seam', () {
    final track = crepeF0WithRunner(
      Float64List(0),
      sampleRate: 16000,
      run: (frames, nFrames) => Float32List(nFrames * 360),
    );
    expect(track, isEmpty);
  });

  test('onnxFfi loaders are null-safe headlessly (no native ORT / model)',
      () async {
    // No download requested, and even if a CREPE model is cached, the native
    // ORT dylib can't load under `flutter test`, so the session build fails →
    // null → the resolver falls back to the pure-Dart onnx path.
    expect(await loadOnnxFfiF0(), isNull);
    expect(await loadOnnxFfiNeural(), isNull);
    expect(await loadOnnxFfiChords(), isNull);
  });
}
