// lib/core/audio/tts/onnx_ort_tts_factory.dart
//
// Platform-conditional factory for the `onnxFfi` neural TTS backend (Piper VITS
// over native ONNX Runtime). Mirrors `tts_neural.dart`: the dart:io build is
// compiled ONLY where dart:io exists; web (and any io-less target) gets a stub
// that returns null, so `flutter build web` never sees dart:io / the native ORT
// plugin. TtsService treats null as "no onnxFfi backend on this build".

export 'onnx_ort_tts_stub.dart' if (dart.library.io) 'onnx_ort_tts_io.dart';
