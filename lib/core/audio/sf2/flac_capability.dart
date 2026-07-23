// Platform seam for shared FLAC audio import. Native builds use glint's FFI
// decoder; web and platforms without the native library degrade to null.
export 'flac_capability_stub.dart'
    if (dart.library.ffi) 'flac_capability_ffi.dart';
