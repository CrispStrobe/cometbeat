// Turns the user's TranscriptionEngineConfig + what's actually installed into the
// concrete engines to inject into the pipeline. This is the bridge between the
// Settings choices and route.dart's F0Estimator / NeuralTranscriber seams:
// config.resolve() decides WHICH backend a step wants; the providers decide
// whether it's actually present; anything unpicked or absent falls back to
// pure-Dart — a null neural/chords engine (→ the chain's built-in), and the
// model-free WORLD DIO estimator for F0.

import 'package:comet_beat/core/audio/transcription/crispasr_ffi_piano.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_pitch.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_separate.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_pitch.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_separate.dart'
    show loadCrispasrSeparatorFromEnv;
import 'package:comet_beat/core/audio/transcription/dio.dart' show dioEstimator;
import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:comet_beat/core/audio/transcription/harmony.dart'
    show ChordEstimator;
import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator, NeuralTranscriber;
import 'package:comet_beat/core/audio/transcription/stems.dart' show Separator;
import 'package:comet_beat/features/games/transcribe/crepe_provider.dart';
import 'package:comet_beat/features/games/transcribe/harmony_provider.dart';
import 'package:comet_beat/features/games/transcribe/neural_provider.dart';
import 'package:comet_beat/features/games/transcribe/onnx_ffi_provider.dart'
    as onnx_ffi;
import 'package:comet_beat/features/games/transcribe/rmvpe_provider.dart';
import 'package:comet_beat/features/games/transcribe/separator_provider.dart';
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

/// `crispasr` runtime — CREPE F0 via CrispASR ggml. Prefers the in-app FFI
/// binding (`crispasr_ffi_pitch.dart` → `CrispasrSession.pitch`, crispasr
/// 0.8.16+; model auto-resolved via CrispASR's registry, cstr/crepe-GGUF), and
/// falls back to the `crispasr --pitch` CLI (`crispasr_pitch.dart`, env-gated)
/// for dev without a bundled lib. Null → the resolver falls to the ONNX F0 path.
Future<F0Estimator?> loadCrispasrCrepeF0({bool download = false}) async =>
    await crispasrFfiCrepeF0(download: download) ?? crispasrCliCrepeF0();

/// `crispasr` runtime — polyphonic transcription via CrispASR ggml note events.
/// WIRED via the clean FFI note-event API (`crispasr_ffi_piano.dart` →
/// `CrispasrSession.pianoNotes`, crispasr 0.8.17+): its `{midi, onMs, offMs,
/// velocity}` maps straight onto [NoteEvent]. Null (no lib/model) → the resolver
/// falls back to the pure-Dart onnx Basic Pitch.
///
/// [model] picks WHICH note model the runtime loads — piano-transcription
/// (today's default), Basic Pitch, or MT3. One entry point, three models; see
/// [CrispasrNoteModel] for what each costs and what each is good at.
Future<NeuralTranscriber?> loadCrispasrPiano({
  bool download = false,
  CrispasrNoteModel model = CrispasrNoteModel.auto,
}) =>
    loadCrispasrPianoFfi(download: download, model: model);

/// `onnxFfi` runtime — the same CREPE `.onnx` model on the NATIVE ONNX Runtime
/// via FFI (the `onnxruntime` plugin), reusing crepeF0WithRunner. WIRED for F0
/// (`onnx_ffi_provider.dart`): live in a desktop/mobile app build with the CREPE
/// model cached; null elsewhere (web / headless / model absent) → falls back to
/// the pure-Dart onnx F0 path.
Future<F0Estimator?> loadOnnxFfiF0({bool download = false}) =>
    onnx_ffi.loadOnnxFfiF0(download: download);

/// `onnxFfi` runtime — Basic Pitch `.onnx` on the native ONNX Runtime. Not yet
/// wired (the pure-Dart onnx path serves polyphony); stub via the provider.
Future<NeuralTranscriber?> loadOnnxFfiNeural({bool download = false}) =>
    onnx_ffi.loadOnnxFfiNeural(download: download);

/// `onnxFfi` runtime — BTC chords `.onnx` on the native ONNX Runtime. Not yet
/// wired (the pure-Dart onnx path serves chords); stub via the provider.
Future<ChordEstimator?> loadOnnxFfiChords({bool download = false}) =>
    onnx_ffi.loadOnnxFfiChords(download: download);

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
  Future<NeuralTranscriber?> Function({
    bool download,
    CrispasrNoteModel model,
  }) loadPianoGgml = loadCrispasrPiano,
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
  // The note-model choice only ever reaches the ggml probe; it is inert for
  // every other runtime. `download` stays tied to an EXPLICIT backend choice,
  // so neither the 77 MB piano model nor MT3's 96 MB is ever fetched by an
  // `auto` probe — a user has to have asked for the ggml polyphonic engine.
  final ggmlNeural = await loadPianoGgml(
    download: polyExplicit,
    model: config.crispasrNoteModel,
  );

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
      // The pure-Dart F0 tier is WORLD DIO+StoneMask (model-free, web-safe,
      // pyworld-parity) — a strict upgrade over the chain's built-in pYIN, and
      // the only F0 that needs no download. Injected so it runs on web and
      // whenever a user picks "on-device" or nothing else is installed.
      Backend.pureDart => dioEstimator(),
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

/// Resolve the whole-song source [Separator] from [config] — the framework's
/// `separation` step (whole-song only, not part of [resolveEngines]'s
/// per-recording engines). Probes the two separation runtimes and honours the
/// per-step choice: `crispasr` = the `--separate` CLI (env-gated, FFI once
/// 0.8.17 lands); `onnx` = Open-Unmix (the WORKING pure-Dart-ONNX separator).
/// Auto prefers crispasr > onnx. Null ⇒ no separator available (→ the song
/// pipeline makes a single part). There is no pure-Dart separator, so a
/// `pureDart` choice resolves to null. Test seams: pass fake loaders.
/// The `crispasr` separation backend: the in-app FFI htdemucs
/// (`CrispasrSession.separate`, crispasr 0.8.17+), falling back to the
/// `--separate` CLI (env-gated) for a dev box without a bundled lib.
Future<Separator?> _crispasrSeparator({bool download = false}) async =>
    await loadCrispasrFfiSeparator(download: download) ??
    await loadCrispasrSeparatorFromEnv();

Future<Separator?> resolveSeparator(
  TranscriptionEngineConfig config, {
  bool isWeb = kIsWeb,
  Future<Separator?> Function({bool download}) loadOnnx = loadUmxSeparator,
  Future<Separator?> Function({bool download}) loadCrispasr =
      _crispasrSeparator,
}) async {
  final explicit =
      config.backendFor(TranscriptionStep.separation) != Backend.auto;
  final onnx = await loadOnnx(download: explicit);
  final ggml = await loadCrispasr(download: explicit);
  final r = config.resolve(
    TranscriptionStep.separation,
    isWeb: isWeb,
    available: {
      if (ggml != null) Backend.crispasr,
      if (onnx != null) Backend.onnx,
    },
  );
  return switch (r.backend) {
    Backend.crispasr => ggml,
    Backend.onnx => onnx,
    _ => null, // no pure-Dart separator
  };
}
