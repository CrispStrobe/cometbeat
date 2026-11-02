// Platform seam for audio ENCODING (MP3 / AAC-LC / Ogg-Opus via glint) and the
// whole-file DECODE that pairs with it.
//
// Native builds reach glint through dart:ffi; WEB reaches the same C code
// compiled to wasm. Anything else degrades to null and the export UI simply
// doesn't offer those formats rather than failing at save time.
//
// Both sides carry glint's whole-file decoder (MP3/AAC/Opus/Vorbis/FLAC) —
// the native plugin vendors it too since the glint 0.8.1 re-vendor. Callers
// must still treat null as "not supported here". For MP3 use
// loadMp3Decoder(), which only accepts a gapless glint (>= 0.8.1).
//
// On web the wasm loads lazily: await ensureGlintCodecReady() once before the
// sync entry points return anything.
//
// `ffi` is checked first so native never falls into the web path.
export 'encode_capability_stub.dart'
    if (dart.library.ffi) 'encode_capability_ffi.dart'
    if (dart.library.js_interop) 'encode_capability_web.dart';
