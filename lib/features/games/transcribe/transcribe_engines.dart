// Turns the user's TranscriptionEngineConfig + what's actually installed into the
// concrete engines to inject into the pipeline. This is the bridge between the
// Settings choices and route.dart's F0Estimator / NeuralTranscriber seams:
// config.resolve() decides WHICH backend a step wants; the providers decide
// whether it's actually present; anything unpicked or absent falls back to
// pure-Dart (a null engine).

import 'package:comet_beat/core/audio/transcription/crispasr_pitch.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:comet_beat/core/audio/transcription/harmony.dart'
    show ChordEstimator;
import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator, NeuralTranscriber;
import 'package:comet_beat/features/games/transcribe/crepe_provider.dart';
import 'package:comet_beat/features/games/transcribe/harmony_provider.dart';
import 'package:comet_beat/features/games/transcribe/neural_provider.dart';
import 'package:comet_beat/features/games/transcribe/rmvpe_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// The neural engines to inject for a single-recording transcription: an [f0]
/// estimator (RMVPE/CREPE) for the monophonic path, a [neural] transcriber (Basic
/// Pitch) for the polyphonic path, and a [chords] recogniser (BTC). Each null ⇒
/// use the pure-Dart default (or, for chords, none).
typedef TranscriptionEngines = ({
  F0Estimator? f0,
  NeuralTranscriber? neural,
  ChordEstimator? chords,
});

// ---------------------------------------------------------------------------
// The two native-FFI runtimes (the 2nd and 3rd of the "3 paths"). Each is a null
// STUB until its binding + libs land; un-stubbing any one is a few lines, and it
// then appears in `available` so the resolver can pick it. Until then a chosen
// FFI backend gracefully falls back to pure-Dart ONNX.
// ---------------------------------------------------------------------------

/// `crispasr` runtime — CREPE F0 via CrispASR ggml. WIRED via the `crispasr
/// --pitch` CLI (`crispasr_pitch.dart`): available when the binary + a CREPE
/// GGUF are configured (env `CRISPASR_BIN` / `CRISPASR_CREPE_GGUF`). Null → the
/// resolver falls to the ONNX F0 path. (A future FFI binding to `crepe_compute_f0`
/// — once the crispasr pub package ships it — can replace the CLI here.)
Future<F0Estimator?> loadCrispasrCrepeF0({bool download = false}) async =>
    crispasrCliCrepeF0();

/// `crispasr` runtime — polyphonic transcription via CrispASR ggml PIANO (Kong).
/// Returns [NoteEvent]s; blocked on the pub release exposing the piano C ABI.
Future<NeuralTranscriber?> loadCrispasrPiano({bool download = false}) async =>
    null;

/// `onnxFfi` runtime — the same CREPE/RMVPE `.onnx` models on the NATIVE ONNX
/// Runtime via FFI. Blocked on a native-ORT binding + bundled libs.
Future<F0Estimator?> loadOnnxFfiF0({bool download = false}) async => null;

/// `onnxFfi` runtime — Basic Pitch `.onnx` on the native ONNX Runtime.
Future<NeuralTranscriber?> loadOnnxFfiNeural({bool download = false}) async =>
    null;

/// `onnxFfi` runtime — BTC chords `.onnx` on the native ONNX Runtime.
Future<ChordEstimator?> loadOnnxFfiChords({bool download = false}) async =>
    null;

/// Resolve the engines from [config], probing every RUNTIME for every step and
/// honouring the per-step backend choice. Each step can run on up to three
/// neural runtimes (config.resolve prefers ggml > native-ORT FFI > pure-Dart
/// ONNX):
///   • F0        — pure-Dart ONNX: RMVPE (preferred) or CREPE; native-ORT FFI
///     (stub); ggml CREPE (stub).
///   • polyphony — pure-Dart ONNX: Basic Pitch; native-ORT FFI (stub); ggml
///     piano (stub).
///   • chords    — pure-Dart ONNX: BTC; native-ORT FFI (stub). (No ggml yet.)
/// An explicit (non-auto) choice downloads its model; auto is probe-only. Test
/// seams: pass fake loaders. A backend whose loader returns null just isn't in
/// `available`, so the resolver falls to the next runtime (or pure-Dart).
Future<TranscriptionEngines> resolveEngines(
  TranscriptionEngineConfig config, {
  bool isWeb = kIsWeb,
  // onnx (pure-Dart) loaders — the live path.
  Future<NeuralTranscriber?> Function({bool download}) loadNeural =
      loadNeuralTranscriber,
  Future<F0Estimator?> Function({bool download}) loadRmvpe =
      loadRmvpeF0Estimator,
  Future<F0Estimator?> Function({bool download}) loadCrepeOnnx =
      loadCrepeF0Estimator,
  Future<ChordEstimator?> Function({bool download}) loadHarmony =
      loadHarmonyEstimator,
  // onnxFfi (native ONNX Runtime) loaders — stubs until a binding lands.
  Future<F0Estimator?> Function({bool download}) loadF0OnnxFfi = loadOnnxFfiF0,
  Future<NeuralTranscriber?> Function({bool download}) loadNeuralOnnxFfi =
      loadOnnxFfiNeural,
  Future<ChordEstimator?> Function({bool download}) loadChordsOnnxFfi =
      loadOnnxFfiChords,
  // crispasr (ggml) loaders — stubs until the pub package ships.
  Future<F0Estimator?> Function({bool download}) loadCrepeGgml =
      loadCrispasrCrepeF0,
  Future<NeuralTranscriber?> Function({bool download}) loadPianoGgml =
      loadCrispasrPiano,
}) async {
  final f0Explicit = config.backendFor(TranscriptionStep.f0) != Backend.auto;
  final polyExplicit =
      config.backendFor(TranscriptionStep.polyphonic) != Backend.auto;
  final chordsExplicit =
      config.backendFor(TranscriptionStep.chords) != Backend.auto;

  // Probe every runtime for every step. RMVPE is preferred over CREPE within the
  // pure-Dart ONNX runtime; the FFI runtimes are single-model (stubs today).
  final onnxF0 = await loadRmvpe(download: f0Explicit) ??
      await loadCrepeOnnx(download: f0Explicit);
  final ffiF0 = await loadF0OnnxFfi(download: f0Explicit);
  final ggmlF0 = await loadCrepeGgml(download: f0Explicit);

  final onnxNeural = await loadNeural(download: polyExplicit);
  final ffiNeural = await loadNeuralOnnxFfi(download: polyExplicit);
  final ggmlNeural = await loadPianoGgml(download: polyExplicit);

  final onnxChords = await loadHarmony(download: chordsExplicit);
  final ffiChords = await loadChordsOnnxFfi(download: chordsExplicit);

  final f0 = config.resolve(
    TranscriptionStep.f0,
    isWeb: isWeb,
    available: {
      if (ggmlF0 != null) Backend.crispasr,
      if (ffiF0 != null) Backend.onnxFfi,
      if (onnxF0 != null) Backend.onnx,
    },
  );
  final poly = config.resolve(
    TranscriptionStep.polyphonic,
    isWeb: isWeb,
    available: {
      if (ggmlNeural != null) Backend.crispasr,
      if (ffiNeural != null) Backend.onnxFfi,
      if (onnxNeural != null) Backend.onnx,
    },
  );
  final chords = config.resolve(
    TranscriptionStep.chords,
    isWeb: isWeb,
    available: {
      if (ffiChords != null) Backend.onnxFfi,
      if (onnxChords != null) Backend.onnx,
    },
  );

  return (
    f0: switch (f0.backend) {
      Backend.crispasr => ggmlF0,
      Backend.onnxFfi => ffiF0,
      Backend.onnx => onnxF0,
      _ => null,
    },
    neural: switch (poly.backend) {
      Backend.crispasr => ggmlNeural,
      Backend.onnxFfi => ffiNeural,
      Backend.onnx => onnxNeural,
      _ => null,
    },
    chords: switch (chords.backend) {
      Backend.onnxFfi => ffiChords,
      Backend.onnx => onnxChords,
      _ => null,
    },
  );
}
