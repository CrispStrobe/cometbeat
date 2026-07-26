// Web (`dart:js_interop`) codec seam: bridges to the glint wasm shim exposed on
// `globalThis.glintCodec` by web/glint/bootstrap.js.
//
// The wasm has always carried the full codec surface — it just wasn't reachable
// from Dart. Through here the WEB build gets:
//
//   encode  MP3 / AAC-LC / Ogg-Opus
//   decode  MP3 / AAC-LC / Ogg-Opus / Ogg-Vorbis / FLAC (auto-detected)
//
// which is actually WIDER than the native FFI plugin, whose vendored closure
// has no MP3/AAC decoder.
//
// LOADING: the wasm is fetched lazily, so [ensureGlintCodecReady] must be
// awaited once before the sync entry points return anything. Until then every
// loader hands back a function that returns null — the same "not available
// here" contract the native seam has, so callers never special-case web.
//
// Selected by encode_capability.dart on the web target (no dart:ffi).

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/encoded_audio.dart';

export 'package:comet_beat/core/audio/sf2/encoded_audio.dart';

@JS('globalThis.glintCodec')
external _GlintCodec? get _glintCodec;

extension type _GlintCodec._(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> init();
  external bool ready();
  external JSUint8Array? encodeSync(
    JSFloat32Array pcm,
    int channels,
    int sampleRate,
    int format,
    int bitrateKbps,
    int vbrQuality,
    int quality,
  );
  external _DecodeResult? decodeSync(JSUint8Array bytes);
}

extension type _DecodeResult._(JSObject _) implements JSObject {
  external JSFloat32Array get pcm;
  external int get sampleRate;
  external int get channels;
  external int get frames;
}

/// glint's `glint_enc_format` values.
int _formatCode(EncodedAudioFormat format) => switch (format) {
      EncodedAudioFormat.mp3 => 0,
      EncodedAudioFormat.aac => 1,
      EncodedAudioFormat.opus => 2,
    };

/// Load the glint wasm module (once). Await this before encoding or decoding on
/// web; false if the shim isn't on the page at all.
Future<bool> ensureGlintCodecReady() async {
  final g = _glintCodec;
  if (g == null) return false;
  try {
    await g.init().toDart;
    return g.ready();
  } catch (_) {
    return false;
  }
}

DecodedAudio? _toDecoded(_DecodeResult? r) {
  if (r == null) return null;
  final ch = r.channels < 1 ? 1 : r.channels;
  final frames = r.frames;
  if (frames < 1) return null;
  // Copy out of the wasm heap view: it can be detached by a later heap grow.
  final flat = r.pcm.toDart;
  final pcm = Float64List(frames * ch);
  for (var i = 0; i < pcm.length && i < flat.length; i++) {
    pcm[i] = flat[i];
  }
  return DecodedAudio(
    pcm: pcm,
    channels: ch,
    sampleRate: r.sampleRate > 0 ? r.sampleRate : 48000,
  );
}

/// A glint-wasm-backed encoder, or null if the shim is absent. Returns null
/// per call until [ensureGlintCodecReady] has resolved.
EncodeAudio? loadGlintEncoder({String? libraryPath}) {
  final g = _glintCodec;
  if (g == null) return null;
  return (
    Float64List interleaved, {
    required int channels,
    required int sampleRate,
    required EncodedAudioFormat format,
    int bitrateKbps = 128,
    int vbrQuality = -1,
    int quality = 5,
  }) {
    if (!g.ready() || interleaved.isEmpty || channels < 1) return null;
    // glint's wasm ABI takes float32; Dart carries float64.
    final pcm = Float32List(interleaved.length);
    for (var i = 0; i < interleaved.length; i++) {
      pcm[i] = interleaved[i];
    }
    final out = g.encodeSync(
      pcm.toJS,
      channels,
      sampleRate,
      _formatCode(format),
      bitrateKbps,
      vbrQuality,
      quality,
    );
    if (out == null) return null;
    final bytes = out.toDart;
    return bytes.isEmpty ? null : bytes;
  };
}

/// Ogg-Opus → PCM on web. glint auto-detects the container, so this is the
/// general decoder narrowed to the Opus case for API parity with native.
OpusFileDecode? loadOpusFileDecoder({String? libraryPath}) {
  final g = _glintCodec;
  if (g == null) return null;
  return (Uint8List ogg) {
    if (!g.ready() || ogg.isEmpty) return null;
    return _toDecoded(g.decodeSync(ogg.toJS));
  };
}

/// Whole-file decode of any format glint recognises (MP3, AAC, Opus, Vorbis,
/// FLAC), auto-detected. This is the seam native currently lacks.
AudioFileDecode? loadAudioDecoder({String? libraryPath}) {
  final g = _glintCodec;
  if (g == null) return null;
  return (Uint8List bytes) {
    if (!g.ready() || bytes.isEmpty) return null;
    return _toDecoded(g.decodeSync(bytes.toJS));
  };
}
