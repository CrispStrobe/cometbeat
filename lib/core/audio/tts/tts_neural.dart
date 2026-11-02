// lib/core/audio/tts/tts_neural.dart
//
// Platform-conditional factory for the neural (CrispASR: Piper + Kokoro) voices.
// Mirrors aec_capability.dart: the dart:io + ffi implementation is compiled ONLY
// where those libraries exist; web (and any io-less target) gets a stub that
// returns null, so `flutter build web` never sees dart:io/ffi/isolate. Callers
// (main.dart) treat null as "no neural backend — use the platform voice".

export 'tts_neural_stub.dart' if (dart.library.io) 'tts_neural_io.dart';
