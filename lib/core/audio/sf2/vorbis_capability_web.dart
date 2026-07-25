// Web (`dart:js_interop`) `.sf3` Vorbis decoder seam: bridges to the glint wasm
// shim exposed on `globalThis.glintVorbis` by web/glint/bootstrap.js. The wasm
// loads lazily on the first [ensureGlintVorbisReady] call; after that, decoding
// is synchronous (so it fits `Sf2SoundFont.parse`'s sync [VorbisDecode]).
//
// Selected by vorbis_capability.dart on the web target (no dart:ffi). Degrades
// gracefully to null / false if the shim isn't present, so `.sf3` just stays
// unsupported rather than crashing.

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2.dart' show VorbisDecode;
import 'package:comet_beat/core/audio/sf2/vorbis_pcm.dart';

export 'package:comet_beat/core/audio/sf2/vorbis_pcm.dart';

@JS('globalThis.glintVorbis')
external _GlintVorbis? get _glintVorbis;

extension type _GlintVorbis._(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> init();
  external bool ready();
  external _DecodeResult? decodeSync(JSUint8Array bytes);
}

extension type _DecodeResult._(JSObject _) implements JSObject {
  external JSFloat32Array get pcm;
  external int get channels;
  external int get frames;
}

/// Load the glint Vorbis wasm module (once). Returns true when it's ready to
/// decode `.sf3`; the app should await this before parsing a compressed
/// soundfont on web. No-op/false if the shim isn't on the page.
Future<bool> ensureGlintVorbisReady() async {
  final g = _glintVorbis;
  if (g == null) return false;
  try {
    await g.init().toDart;
    return g.ready();
  } catch (_) {
    return false;
  }
}

/// A glint-wasm-backed [VorbisDecode] for `.sf3`, or null if the shim is absent.
/// Returns null per-call until [ensureGlintVorbisReady] has resolved. The
/// [libraryPath] arg is native-only (ignored here, kept for API parity).
VorbisDecode? loadGlintVorbis({String? libraryPath}) {
  final g = _glintVorbis;
  if (g == null) return null;
  return (Uint8List ogg) {
    if (!g.ready()) return null;
    final r = g.decodeSync(ogg.toJS);
    if (r == null) return null;
    final ch = r.channels < 1 ? 1 : r.channels;
    final frames = r.frames;
    if (frames <= 0) return null;
    final flat = r.pcm.toDart; // interleaved Float32List
    final out = Float64List(frames);
    if (ch == 1) {
      for (var i = 0; i < frames; i++) {
        out[i] = flat[i];
      }
    } else {
      // .sf3 samples are mono; downmix defensively for any stereo stream.
      for (var i = 0; i < frames; i++) {
        var s = 0.0;
        for (var c = 0; c < ch; c++) {
          s += flat[i * ch + c];
        }
        out[i] = s / ch;
      }
    }
    return out;
  };
}

/// The `.ogg` FILE decoder on web: the wasm shim returns interleaved PCM and a
/// channel count but NOT the rate, so the rate is read from the Vorbis identity
/// header instead (pure Dart, in vorbis_pcm.dart).
VorbisFileDecode? loadGlintVorbisFile({String? libraryPath}) {
  final g = _glintVorbis;
  if (g == null) return null;
  return (Uint8List ogg) {
    if (!g.ready()) return null;
    final r = g.decodeSync(ogg.toJS);
    if (r == null) return null;
    final ch = r.channels < 1 ? 1 : r.channels;
    final frames = r.frames;
    if (frames <= 0) return null;
    final flat = r.pcm.toDart; // interleaved Float32List
    final left = Float64List(frames);
    final right = ch > 1 ? Float64List(frames) : null;
    for (var i = 0; i < frames; i++) {
      left[i] = flat[i * ch];
      if (right != null) right[i] = flat[i * ch + 1];
    }
    final rate = oggVorbisSampleRate(ogg);
    return VorbisPcm(
      left: left,
      right: right,
      sampleRate: rate > 0 ? rate : 44100,
    );
  };
}
