// Facade for CrispASR beat-this beat tracking, behind a conditional import so
// web still compiles (null stub).

export 'crispasr_ffi_beats_stub.dart'
    if (dart.library.io) 'crispasr_ffi_beats_io.dart';
