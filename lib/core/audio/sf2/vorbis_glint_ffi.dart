// Native Ogg-Vorbis decode via the glint codec suite (MIT, ~/code/glint) over
// dart:ffi — the decoder that backs the `.sf3` SoundFont path on native
// platforms. It provides a [VorbisDecode] for `Sf2SoundFont.parse(bytes,
// vorbis: …)`. Web uses a separate wasm/stub seam (this file imports dart:ffi
// and must NOT be imported from web code — reach it through a conditional-import
// capability seam, like core/audio/aec_capability.dart does for the AEC plugin).
//
// glint's C ABI (include/glint/glint.h):
//   float* glint_vorbis_decode(const uint8_t* ogg, int len,
//                              int* out_sr, int* out_ch, int* out_frames);
//   void   glint_free(void* p);
// See docs/GLINT_VORBIS_HANDOVER.md.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2.dart' show VorbisDecode;
import 'package:ffi/ffi.dart';

typedef _DecodeNative = Pointer<Float> Function(
  Pointer<Uint8>,
  Int32,
  Pointer<Int32>,
  Pointer<Int32>,
  Pointer<Int32>,
);
typedef _Decode = Pointer<Float> Function(
  Pointer<Uint8>,
  int,
  Pointer<Int32>,
  Pointer<Int32>,
  Pointer<Int32>,
);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);

/// A glint-backed Vorbis decoder. Load the glint shared library once
/// (`libglint.dylib`/`.so`/`glint.dll`), then use [decode] as the
/// [VorbisDecode] seam for `.sf3` soundfonts.
class GlintVorbis {
  GlintVorbis.open(String libraryPath)
      : this._(DynamicLibrary.open(libraryPath));

  GlintVorbis._(this._lib) {
    _decode =
        _lib.lookupFunction<_DecodeNative, _Decode>('glint_vorbis_decode');
    _free = _lib.lookupFunction<_FreeNative, _Free>('glint_free');
  }

  final DynamicLibrary _lib;
  late final _Decode _decode;
  late final _Free _free;

  /// The [VorbisDecode] to pass to `Sf2SoundFont.parse(bytes, vorbis: …)`.
  VorbisDecode get vorbisDecode => decode;

  /// Decode ONE complete Ogg-Vorbis stream to mono PCM (±1.0), or null on error.
  Float64List? decode(Uint8List ogg) {
    if (ogg.isEmpty) return null;
    final inPtr = calloc<Uint8>(ogg.length);
    final sr = calloc<Int32>();
    final ch = calloc<Int32>();
    final fr = calloc<Int32>();
    try {
      inPtr.asTypedList(ogg.length).setAll(0, ogg);
      final out = _decode(inPtr, ogg.length, sr, ch, fr);
      if (out == nullptr) return null;
      final frames = fr.value;
      final channels = ch.value < 1 ? 1 : ch.value;
      if (frames <= 0) {
        _free(out.cast());
        return null;
      }
      final interleaved = out.asTypedList(frames * channels);
      final pcm = Float64List(frames);
      if (channels == 1) {
        for (var i = 0; i < frames; i++) {
          pcm[i] = interleaved[i];
        }
      } else {
        // .sf3 samples are mono; downmix defensively for any stereo stream.
        for (var i = 0; i < frames; i++) {
          var s = 0.0;
          for (var c = 0; c < channels; c++) {
            s += interleaved[i * channels + c];
          }
          pcm[i] = s / channels;
        }
      }
      _free(out.cast());
      return pcm;
    } finally {
      calloc
        ..free(inPtr)
        ..free(sr)
        ..free(ch)
        ..free(fr);
    }
  }
}
