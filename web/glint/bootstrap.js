// Loaded from web/index.html as a module. Imports the glint wasm shims and
// exposes them on globalThis so Dart (dart:js_interop) can reach them. The wasm
// is fetched LAZILY on the first init() call (not at app startup), so this adds
// no startup cost until a .sf3 SoundFont is loaded or audio is imported/exported.
//
// Both objects share ONE wasm module instance (glint_codec.mjs caches it), so
// exposing the codec surface costs no extra download over the Vorbis shim alone.
import { glintVorbisInit, glintVorbisReady, glintVorbisDecodeSync }
  from './glint_vorbis_web.js';
import { glintCodecInit, glintCodecReady, glintEncodeSync, glintDecodeSync }
  from './glint_codec_web.js';

globalThis.glintVorbis = {
  init: glintVorbisInit,          // async → resolves when the wasm is ready
  ready: glintVorbisReady,        // bool
  decodeSync: glintVorbisDecodeSync, // (Uint8Array) → {pcm,channels,frames}|null
};

// The full codec surface: MP3/AAC/Opus ENCODE and MP3/AAC/Opus/Vorbis/FLAC
// DECODE. Reached from lib/core/audio/sf2/encode_capability_web.dart.
globalThis.glintCodec = {
  init: glintCodecInit,           // async → resolves when the wasm is ready
  ready: glintCodecReady,         // bool
  // (Float32Array, channels, sampleRate, format, kbps, vbrQ, quality)
  //   → Uint8Array | null       format: 0=MP3 1=AAC 2=Opus
  encodeSync: glintEncodeSync,
  // (Uint8Array) → {pcm,sampleRate,channels,frames} | null
  decodeSync: glintDecodeSync,
};
