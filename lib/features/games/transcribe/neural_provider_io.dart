// Native provider: load the Basic Pitch ONNX model (download-on-demand) and wrap
// it as a NeuralTranscriber the router can inject. dart:io only — reached solely
// through neural_provider.dart's conditional import, so web never compiles it.

import 'package:comet_beat/core/audio/transcription/basic_pitch_model_store.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show NeuralTranscriber;

/// A transcriber backed by Basic Pitch, or null.
///
/// With [download] false, returns non-null only if the model is already cached
/// (no network touched). With [download] true, fetches it first. Returns null on
/// any failure so the caller can fall back to the monophonic chain.
Future<NeuralTranscriber?> loadNeuralTranscriber({
  bool download = false,
}) async {
  try {
    if (!download && !neuralModelPresent()) return null;
    // Memoised, and that is load-bearing now rather than merely tidy: the
    // pooled transcriber owns N worker isolates that nothing disposes, and
    // `_neural()` is called once per transcription. A fresh store per call
    // would re-read the model and spawn another pool every time.
    //
    // Downloads if missing (throws if it can't), then sets up the isolate GEMM
    // pool. Bitwise-identical notes to the synchronous path;
    // `COMET_BASICPITCH_WORKERS=0` falls back to it.
    return _transcriber ??=
        await (_store ??= BasicPitchModelStore()).transcriber();
  } on Object {
    return null;
  }
}

BasicPitchModelStore? _store;
NeuralTranscriber? _transcriber;

/// Whether the model is already on disk (a large-enough file), without touching
/// the network — the "is the HD engine ready?" gate for the UI.
bool neuralModelPresent() {
  try {
    final f = BasicPitchModelStore().modelFile();
    return f.existsSync() && f.lengthSync() > 100000;
  } on Object {
    return false;
  }
}
