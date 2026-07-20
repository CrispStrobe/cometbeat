// Turns the user's TranscriptionEngineConfig + what's actually installed into the
// concrete engines to inject into the pipeline. This is the bridge between the
// Settings choices and route.dart's F0Estimator / NeuralTranscriber seams:
// config.resolve() decides WHICH backend a step wants; the providers decide
// whether it's actually present; anything unpicked or absent falls back to
// pure-Dart (a null engine).

import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator, NeuralTranscriber;
import 'package:comet_beat/features/games/transcribe/crepe_provider.dart';
import 'package:comet_beat/features/games/transcribe/neural_provider.dart';
import 'package:comet_beat/features/games/transcribe/rmvpe_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// The neural engines to inject for a single-recording transcription: an [f0]
/// estimator (CREPE) for the monophonic path and a [neural] transcriber (Basic
/// Pitch) for the polyphonic path. Either null ⇒ use the pure-Dart default.
typedef TranscriptionEngines = ({F0Estimator? f0, NeuralTranscriber? neural});

/// CREPE F0 via CrispASR ggml. Returns null until the `crispasr` pub package
/// exposes its pitch FFI — the in-repo `flutter/crispasr` binding already has
/// `List<PitchFrame> pitch(Float32List pcm16k)` whose PitchFrame IS our
/// `{timeMs, f0Hz, voicedProb}` — so wiring is: resample mono→16 kHz Float32,
/// call `pitch()`, map frames → PitchTrack. Kept a null stub here so nothing
/// depends on an unpublished API; un-stub the day crispasr ships it.
Future<F0Estimator?> loadCrispasrCrepeF0({bool download = false}) async => null;

/// Resolve the engines from [config], probing availability via the injected
/// loaders and honouring the per-step backend choice. F0 has THREE neural
/// backends: RMVPE ONNX (best for voice — [loadRmvpe]) and CREPE ONNX
/// ([loadCrepeOnnx]) both map to `onnx` (RMVPE preferred when present), and
/// CrispASR ggml CREPE (future — [loadCrepeGgml], stub) maps to `crispasr`;
/// polyphony uses Basic Pitch ONNX ([loadNeural]). An explicitly-chosen
/// (non-auto) neural F0 backend downloads its model; auto is probe-only (uses
/// whatever's cached). Test seams: pass fake loaders.
Future<TranscriptionEngines> resolveEngines(
  TranscriptionEngineConfig config, {
  bool isWeb = kIsWeb,
  Future<NeuralTranscriber?> Function({bool download}) loadNeural =
      loadNeuralTranscriber,
  Future<F0Estimator?> Function({bool download}) loadRmvpe =
      loadRmvpeF0Estimator,
  Future<F0Estimator?> Function({bool download}) loadCrepeOnnx =
      loadCrepeF0Estimator,
  Future<F0Estimator?> Function({bool download}) loadCrepeGgml =
      loadCrispasrCrepeF0,
}) async {
  final neuralFn = await loadNeural();
  // A concrete F0 choice opts into a download; auto just uses what's cached.
  final f0Explicit = config.backendFor(TranscriptionStep.f0) != Backend.auto;
  final rmvpeFn = await loadRmvpe(download: f0Explicit);
  final crepeOnnxFn = await loadCrepeOnnx(download: f0Explicit);
  final crepeGgmlFn = await loadCrepeGgml(download: f0Explicit);
  final onnxF0 = rmvpeFn ?? crepeOnnxFn; // RMVPE preferred over CREPE

  final poly = config.resolve(
    TranscriptionStep.polyphonic,
    isWeb: isWeb,
    available: {if (neuralFn != null) Backend.onnx},
  );
  final f0 = config.resolve(
    TranscriptionStep.f0,
    isWeb: isWeb,
    available: {
      if (crepeGgmlFn != null) Backend.crispasr,
      if (onnxF0 != null) Backend.onnx,
    },
  );

  return (
    neural: poly.backend == Backend.onnx ? neuralFn : null,
    f0: switch (f0.backend) {
      Backend.crispasr => crepeGgmlFn,
      Backend.onnx => onnxF0,
      _ => null,
    },
  );
}
