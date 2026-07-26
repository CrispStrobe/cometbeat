// stream_save.dart — write bytes to a path incrementally, NATIVE only.
//
// Used by the export sheet's bounded-memory WAV save: instead of building the
// whole file in RAM (pcmFloatToWav → Uint8List) and handing it to
// XFile.saveTo, the DAW streams `streamTimelineWav` chunks straight to disk.
// Platform-conditional so audio_export.dart stays web-safe (no dart:io): on the
// web there is no filesystem to stream to, so the stub returns false and the
// caller falls back to the in-memory bake path.
export 'stream_save_stub.dart' if (dart.library.io) 'stream_save_io.dart';
