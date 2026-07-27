// lib/core/audio/tts/onnx_ort_tts_io.dart
//
// Native (dart:io) build of the `onnxFfi` TTS factory. Wires the Piper-over-ORT
// backend to a CC0 Piper voice store and returns it with its readiness probes;
// TtsService routes to it only when `ready` passes (native ORT loadable + a voice
// cached). Model files download through `PiperVoiceStore` (HuggingFace CC0
// voices) — the same store the pure-Dart Piper path uses.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/onnx_ort_tts_backend.dart';
import 'package:comet_beat/core/audio/tts/piper/piper_voice_store.dart';
import 'package:comet_beat/core/services/tts_service.dart';

NeuralTts? createOnnxOrtTts({
  required Future<void> Function(Uint8List wav) play,
  Future<void> Function()? stopPlayback,
}) {
  final backend = OnnxOrtTtsBackend(
    store: PiperVoiceStore(),
    play: play,
    stopPlayback: stopPlayback,
  );
  return NeuralTts(
    backend: backend,
    ready: backend.isAvailable,
    supported: backend.supported,
    download: backend.download,
  );
}
