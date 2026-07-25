// Platform seam for native audio ENCODING (Opus / AAC / MP3 via glint).
// Native builds get the dart:ffi encoder; web and anything without the glint
// library degrade to null, and the export UI simply doesn't offer those formats
// rather than failing at save time.
export 'encode_capability_stub.dart'
    if (dart.library.ffi) 'encode_capability_ffi.dart';
