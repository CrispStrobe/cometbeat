// Native RMVPE provider: load the ONNX + mel bundle (download-on-demand) and
// expose the pooled estimator as an F0Estimator. dart:io only — reached solely
// through rmvpe_provider.dart's conditional import.

import 'package:comet_beat/core/audio/transcription/rmvpe_model_store.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator;

/// An RMVPE-backed [F0Estimator], or null. With [download] false, returns
/// non-null only if the (~361 MB) bundle is already cached; true fetches it.
/// Null on any failure so the caller falls back to CREPE/pYIN.
Future<F0Estimator?> loadRmvpeF0Estimator({bool download = false}) async {
  try {
    final store = _store ??= RmvpeModelStore();
    if (!download && !store.isPresent()) return null;
    // Memoised, and that is load-bearing rather than tidy: `estimator()` sets
    // up an isolate pool whose workers nothing disposes, and this is called
    // once per transcription. A fresh store/estimator per call would re-read
    // the 361 MB model and spawn another pool every time — the exact caveat
    // the Basic Pitch path (`loadNeuralTranscriber`) already handles.
    return _estimator ??= await store.estimator();
  } on Object {
    return null;
  }
}

RmvpeModelStore? _store;
F0Estimator? _estimator;

bool rmvpeModelPresent() => RmvpeModelStore().isPresent();
