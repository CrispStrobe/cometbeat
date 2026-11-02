// lib/core/audio/tts/tts_neural_io.dart
//
// Native (dart:io + ffi) build of the neural-voice factory: the CrispASR
// runtime that plays the catalog's Piper + Kokoro voices. Model files live in
// CrispASR's cache dir (inside the app container on sandboxed macOS) and are
// downloaded only on an explicit user action.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/crispasr_voice_runtime.dart';
import 'package:comet_beat/core/audio/tts/neural_voice_runtime.dart';

NeuralVoiceRuntime? createNeuralTts({
  required Future<void> Function(Uint8List wav) play,
  Future<void> Function()? stopPlayback,
}) =>
    CrispAsrVoiceRuntime(play: play, stopPlayback: stopPlayback);
