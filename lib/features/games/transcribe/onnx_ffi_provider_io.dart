// Native-ONNX-Runtime ("onnxFfi") providers. Loads the same .onnx model the
// pure-Dart path caches, but runs inference on native ORT (onnxruntime plugin)
// via the OrtFfiSession wrapper, reusing the identical Dart framing/decoding
// (crepeF0WithRunner). Returns null when the model isn't cached OR the native
// ORT runtime can't load here (headless test / `dart run`) — so it's a no-op
// fallback everywhere except a real app build. dart:io only.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/crepe.dart'
    show crepeF0WithRunner;
import 'package:comet_beat/core/audio/transcription/crepe_model_store.dart';
import 'package:comet_beat/core/audio/transcription/harmony.dart'
    show ChordEstimator;
import 'package:comet_beat/core/audio/transcription/onnx_ort_session.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator, NeuralTranscriber;

// CREPE model IO tensor names + window (mirror crepe.dart's private consts).
const String _crepeIn = 'frames';
const String _crepeOut = 'activation';
const int _crepeWindow = 1024;

/// Native-ORT CREPE F0. [download] pulls the model if missing (an explicit
/// backend choice); otherwise it's used only if already cached. Null ⇒ no model
/// or no native ORT here → the resolver falls to the pure-Dart onnx path.
Future<F0Estimator?> loadOnnxFfiF0({bool download = false}) async {
  final bytes = await _crepeBytes(download: download);
  if (bytes == null) return null;
  final session = OrtFfiSession.fromBytes(bytes);
  if (session == null) return null; // native ORT not loadable here
  Float32List runCrepe(Float32List frames, int nf) {
    final out =
        session.run(_crepeIn, frames, [nf, _crepeWindow], const [_crepeOut]);
    return out[_crepeOut]!;
  }

  return (Float64List mono, int sampleRate) async =>
      crepeF0WithRunner(mono, sampleRate: sampleRate, run: runCrepe);
}

/// Native-ORT polyphony (Basic Pitch) — not yet wired; the pure-Dart onnx path
/// serves polyphony. Stub so the resolver treats onnxFfi as absent for poly.
Future<NeuralTranscriber?> loadOnnxFfiNeural({bool download = false}) async =>
    null;

/// Native-ORT chords (BTC) — not yet wired; the pure-Dart onnx path serves
/// chords. Stub so the resolver treats onnxFfi as absent for chords.
Future<ChordEstimator?> loadOnnxFfiChords({bool download = false}) async =>
    null;

/// The cached CREPE .onnx bytes (downloading first if [download]), or null.
Future<Uint8List?> _crepeBytes({required bool download}) async {
  final store = CrepeModelStore();
  final File? file;
  if (download) {
    file = await store.ensureFile();
  } else {
    final cached = store.modelFile();
    file = cached.existsSync() ? cached : null;
  }
  if (file == null) return null;
  try {
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}
