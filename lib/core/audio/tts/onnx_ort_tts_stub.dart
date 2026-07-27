// lib/core/audio/tts/onnx_ort_tts_stub.dart
//
// Web / io-less stub: no native ONNX Runtime here, so there is no `onnxFfi`
// backend. Returns null, so TtsService leaves onnxFfi out of the chain and uses
// the platform (or another neural) voice.

import 'dart:typed_data';

import 'package:comet_beat/core/services/tts_service.dart';

NeuralTts? createOnnxOrtTts({
  required Future<void> Function(Uint8List wav) play,
  Future<void> Function()? stopPlayback,
}) =>
    null;
