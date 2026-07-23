// Native FLAC decode via the glint codec suite (MIT, ~/code/glint) over
// dart:ffi — decodes the `.flac` samples that back many SFZ instruments (VCSL,
// VSCO2, …) so the batch instrument installer can turn them into playable WAV.
// It provides a [FlacDecode] used by library/instrument_installer_io.dart.
// Web uses a separate seam (this file imports dart:ffi and must NOT be imported
// from web code — reach it through the flac_capability.dart facade, like
// vorbis_capability.dart does).
//
// glint's C ABI (native/glint/src/glint/glint.h):
//   float* glint_flac_decode(const uint8_t* flac, int len,
//                            int* out_sr, int* out_ch, int* out_frames);
//   void   glint_free(void* p);

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Decoded FLAC PCM: per-channel float samples (±1.0) plus the native rate.
/// [right] is null for mono; loadSfz's WAV path preserves both.
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

/// Decode one complete native FLAC stream, or null on error / not FLAC.
typedef FlacDecode = FlacPcm? Function(Uint8List flac);

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

/// A glint-backed FLAC decoder. Shares the `glint_vorbis` FFI library (the FLAC
/// decoder is compiled into the same native plugin — see native/glint).
class GlintFlac {
  /// Load an external glint shared library by path (dev / a bundled lib file).
  GlintFlac.open(String libraryPath) : this._(DynamicLibrary.open(libraryPath));

  /// Use symbols linked directly into the host process — the normal in-app path
  /// when the glint FFI plugin compiled the decoder into the app.
  GlintFlac.process() : this._(DynamicLibrary.process());

  GlintFlac._(this._lib) {
    _decode = _lib.lookupFunction<_DecodeNative, _Decode>('glint_flac_decode');
    _free = _lib.lookupFunction<_FreeNative, _Free>('glint_free');
  }

  final DynamicLibrary _lib;
  late final _Decode _decode;
  late final _Free _free;

  /// The [FlacDecode] seam.
  FlacDecode get flacDecode => decode;

  /// Decode ONE complete FLAC stream, keeping channels + native rate, or null.
  FlacPcm? decode(Uint8List flac) {
    if (flac.isEmpty) return null;
    final inPtr = calloc<Uint8>(flac.length);
    final sr = calloc<Int32>();
    final ch = calloc<Int32>();
    final fr = calloc<Int32>();
    try {
      inPtr.asTypedList(flac.length).setAll(0, flac);
      final out = _decode(inPtr, flac.length, sr, ch, fr);
      if (out == nullptr) return null;
      final frames = fr.value;
      final channels = ch.value < 1 ? 1 : ch.value;
      final rate = sr.value;
      if (frames <= 0 || rate <= 0) {
        _free(out.cast());
        return null;
      }
      final interleaved = out.asTypedList(frames * channels);
      final left = Float64List(frames);
      Float64List? right;
      if (channels == 1) {
        for (var i = 0; i < frames; i++) {
          left[i] = interleaved[i];
        }
      } else {
        // Keep L/R; fold any >2 channels into the two stereo sides.
        right = Float64List(frames);
        for (var i = 0; i < frames; i++) {
          left[i] = interleaved[i * channels];
          right[i] = interleaved[i * channels + 1];
        }
      }
      _free(out.cast());
      return FlacPcm(left: left, right: right, sampleRate: rate);
    } finally {
      calloc
        ..free(inPtr)
        ..free(sr)
        ..free(ch)
        ..free(fr);
    }
  }
}

/// Candidate glint library names to try, in order, per platform (same library
/// as the Vorbis decoder — one native plugin compiles both).
List<String> _candidates() {
  if (Platform.isMacOS) {
    return const [
      'libglint_vorbis.dylib',
      'glint_vorbis.framework/glint_vorbis',
    ];
  }
  if (Platform.isIOS) return const ['glint_vorbis.framework/glint_vorbis'];
  if (Platform.isAndroid || Platform.isLinux) {
    return const ['libglint_vorbis.so'];
  }
  if (Platform.isWindows) return const ['glint_vorbis.dll'];
  return const [];
}

/// A glint-backed [FlacDecode], or null if the glint decoder can't be loaded on
/// this platform (then FLAC samples stay undecoded, no crash). Resolution: an
/// explicit [libraryPath]; then the FFI plugin compiled into the app (symbols
/// in-process); then a platform-conventional bundled library name.
FlacDecode? loadGlintFlac({String? libraryPath}) {
  if (libraryPath != null) {
    try {
      return GlintFlac.open(libraryPath).flacDecode;
    } catch (_) {
      return null;
    }
  }
  try {
    return GlintFlac.process().flacDecode;
  } catch (_) {
    // Not compiled in (tests / plugin absent) → try a bundled library file.
  }
  for (final name in _candidates()) {
    try {
      return GlintFlac.open(name).flacDecode;
    } catch (_) {
      // Try the next candidate, else null.
    }
  }
  return null;
}
