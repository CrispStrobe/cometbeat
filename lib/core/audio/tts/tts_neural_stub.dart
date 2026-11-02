// lib/core/audio/tts/tts_neural_stub.dart
//
// Web / io-less stub: no native neural voices here. Returns null so TtsService
// uses the platform (flutter_tts) voice and any pre-baked clips.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/neural_voice_runtime.dart';

NeuralVoiceRuntime? createNeuralTts({
  required Future<void> Function(Uint8List wav) play,
  Future<void> Function()? stopPlayback,
}) =>
    null;
