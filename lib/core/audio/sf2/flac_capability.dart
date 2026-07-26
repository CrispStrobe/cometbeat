// Platform seam for shared FLAC audio import. Native builds use glint's FFI
// decoder; WEB uses the same glint code compiled to wasm (its whole-file
// decoder auto-detects FLAC); anything else degrades to null.
//
// Web used to fall into the null stub, so a .flac that imported fine on desktop
// was rejected in the browser even though the capability was already sitting in
// the shipped wasm.
export 'flac_capability_stub.dart'
    if (dart.library.ffi) 'flac_capability_ffi.dart'
    if (dart.library.js_interop) 'flac_capability_web.dart';
