// Web FLAC decode, over the same glint wasm module the codec seam loads.
//
// FLAC import used to be native-only: flac_capability.dart had a dart:ffi
// branch and a null stub, and web fell into the stub — so a `.flac` file that
// worked on desktop was rejected in the browser. glint's wasm decoder
// auto-detects FLAC, so the capability was already sitting in the bundle.
//
// The wasm loads lazily: await ensureGlintCodecReady() before this returns
// anything (the same contract as the Vorbis and codec seams).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/encode_capability_web.dart'
    show loadAudioDecoder;

/// Re-declared here rather than imported from the stub: the conditional export
/// picks exactly ONE of stub/ffi/web, so each variant owns these names.
class FlacPcm {
  const FlacPcm({
    required this.left,
    required this.right,
    required this.sampleRate,
  });

  final Float64List left;
  final Float64List? right;
  final int sampleRate;
}

typedef FlacDecode = FlacPcm? Function(Uint8List flac);

/// A glint-wasm-backed FLAC decoder, or null if the shim isn't on the page.
FlacDecode? loadGlintFlac({String? libraryPath}) {
  final decode = loadAudioDecoder();
  if (decode == null) return null;
  return (Uint8List flac) {
    final d = decode(flac);
    if (d == null || d.frames < 1) return null;
    final ch = d.channels < 1 ? 1 : d.channels;
    final left = Float64List(d.frames);
    final right = ch > 1 ? Float64List(d.frames) : null;
    for (var i = 0; i < d.frames; i++) {
      left[i] = d.pcm[i * ch];
      if (right != null) right[i] = d.pcm[i * ch + 1];
    }
    return FlacPcm(
      left: left,
      right: right,
      sampleRate: d.sampleRate > 0 ? d.sampleRate : 44100,
    );
  };
}
