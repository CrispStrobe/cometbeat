// Decode + separate a picked song for the practice player — conditional
// import (the worker needs dart:io + the CrispASR FFI; web gets a stub).

export 'practice_song_split_stub.dart'
    if (dart.library.io) 'practice_song_split_io.dart';
