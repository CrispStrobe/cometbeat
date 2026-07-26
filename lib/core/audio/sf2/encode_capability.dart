// Platform seam for audio ENCODING (MP3 / AAC-LC / Ogg-Opus via glint) and the
// whole-file DECODE that pairs with it.
//
// Native builds reach glint through dart:ffi; WEB reaches the same C code
// compiled to wasm. Anything else degrades to null and the export UI simply
// doesn't offer those formats rather than failing at save time.
//
// Note the two sides are not identical: the wasm carries glint's whole-file
// decoder (MP3/AAC/Opus/Vorbis/FLAC), while the native plugin vendors only the
// encode closure plus the Vorbis/FLAC/Opus decoders. So loadAudioDecoder()
// returns non-null on web and null on native today. Callers must treat null as
// "not supported here" either way.
//
// On web the wasm loads lazily: await ensureGlintCodecReady() once before the
// sync entry points return anything.
//
// `ffi` is checked first so native never falls into the web path.
export 'encode_capability_stub.dart'
    if (dart.library.ffi) 'encode_capability_ffi.dart'
    if (dart.library.js_interop) 'encode_capability_web.dart';
