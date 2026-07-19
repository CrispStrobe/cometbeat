// Separator provider for whole-song transcription, behind a conditional import
// so the screen compiles on web. The IO impl loads the HTDemucs ONNX (dart:io)
// and wraps it as a stems.dart Separator; the stub returns null (web / no model),
// so transcribeSong falls back to a single part.

export 'separator_provider_stub.dart'
    if (dart.library.io) 'separator_provider_io.dart';
