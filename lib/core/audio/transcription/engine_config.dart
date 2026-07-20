// lib/core/audio/transcription/engine_config.dart
//
// Which BACKEND runs each transcription step, and at what MODEL SIZE/QUANT. The
// pipeline has several stages, and each can run on a different engine:
//
//   • pure-Dart — pYIN, note-HMM, rhythm, meter, chroma chords, drum DSP,
//     notation. No model, runs everywhere incl. web, fast, lower ceiling.
//   • onnx — onnx_runtime_dart (pure-Dart ONNX, no FFI; runs on web too). Basic
//     Pitch ships this way; CREPE/HTDemucs ONNX are fallbacks.
//   • crispasr — CrispASR ggml/GGUF via FFI (native only, GPU-fast). CREPE +
//     HTDemucs/RoFormer separation live here (see the CrispASR music-transcription
//     port). Needs the crispasr package to expose the pitch/separate FFI.
//
// Some steps are DELIBERATELY Dart-only (CrispASR's own triage: W-METRE and
// W-NOTATION "operate on score types, not audio — keep in Dart"; W-DRUMS "DSP
// belongs where the app is"). This config never routes those to a neural backend.
//
// `resolve(step, isWeb, available)` applies the whole decision framework: the
// user's per-step preference, platform, and which backends are actually present.

/// A distinct stage of the transcription pipeline.
enum TranscriptionStep {
  f0, // monophonic pitch (pYIN | CREPE)
  polyphonic, // polyphonic notes (Basic Pitch)
  separation, // stems (HTDemucs / RoFormer) — whole-song only
  onsetBeat, // onsets + tempo + beat + meter (rhythm.dart / metre.dart)
  chords, // chord/key (chroma templates | neural, future)
  drums, // drum transcription (DSP)
  notation, // voice/staff separation, spelling (crisp_notation)
}

/// The runtime a step's model runs on. [auto] picks the best AVAILABLE one.
///
/// Three neural runtimes (the "3 paths"), fastest-first for native:
///   • [crispasr] — CrispASR ggml/GGUF via FFI. Native, GPU-fast. Has CREPE,
///     piano, and separation (htdemucs/RoFormer) today; not RMVPE/Basic-Pitch/BTC.
///   • [onnxFfi]  — the native ONNX Runtime via FFI. Native, fast; runs any of
///     our .onnx models. Needs a native-ORT binding + bundled libs (no web).
///   • [onnx]     — onnx_runtime_dart, PURE Dart (no native lib). Runs on WEB.
///     The default neural runtime today; the others are drop-ins as they land.
/// Plus [pureDart] (pYIN, chroma, DSP — everywhere) and [auto].
enum Backend { auto, pureDart, onnx, onnxFfi, crispasr }

/// Whether [b] needs native FFI (so it's unavailable on web).
bool backendNeedsFfi(Backend b) =>
    b == Backend.crispasr || b == Backend.onnxFfi;

/// One quality preset that maps to a concrete size+quant (users pick this, not
/// the raw knobs). fast = smallest/quickest; accurate = biggest/best; balanced
/// is the shipping default.
enum ModelQuality { fast, balanced, accurate }

enum ModelSize { tiny, full }

enum ModelQuant { q4k, q8, f16 }

/// The concrete engine chosen for a step after applying the framework.
typedef ResolvedEngine = ({Backend backend, ModelSize size, ModelQuant quant});

/// Steps that have no audio model and MUST stay pure-Dart (CrispASR's triage).
const Set<TranscriptionStep> kDartOnlySteps = {
  TranscriptionStep.onsetBeat,
  TranscriptionStep.drums,
  TranscriptionStep.notation,
};

/// The per-step, persisted engine preferences.
class TranscriptionEngineConfig {
  const TranscriptionEngineConfig({
    this.backends = const {},
    this.quality = ModelQuality.balanced,
  });

  /// Per-step backend preference; a missing step means [Backend.auto].
  final Map<TranscriptionStep, Backend> backends;

  /// Global quality preset → (size, quant) for the neural steps.
  final ModelQuality quality;

  Backend backendFor(TranscriptionStep step) => backends[step] ?? Backend.auto;

  TranscriptionEngineConfig copyWith({
    Map<TranscriptionStep, Backend>? backends,
    ModelQuality? quality,
  }) =>
      TranscriptionEngineConfig(
        backends: backends ?? this.backends,
        quality: quality ?? this.quality,
      );

  /// Resolve the engine for [step]. [isWeb] forces pure-Dart/ONNX (no FFI);
  /// [available] is the set of backends whose runtime + model are actually
  /// present right now (e.g. `{Backend.onnx}` if a Basic Pitch model downloaded,
  /// `{Backend.crispasr}` once its FFI + GGUF are there). Never routes a
  /// Dart-only step to a neural backend, and always falls back to pure-Dart.
  ResolvedEngine resolve(
    TranscriptionStep step, {
    required bool isWeb,
    required Set<Backend> available,
  }) {
    final (size, quant) = _qualityToModel(quality);
    ResolvedEngine dart() =>
        (backend: Backend.pureDart, size: size, quant: quant);

    if (kDartOnlySteps.contains(step)) return dart();

    final pref = backendFor(step);
    // A concrete preference is honoured only if it's usable.
    bool usable(Backend b) {
      if (b == Backend.pureDart) return true;
      if (isWeb && backendNeedsFfi(b)) return false; // no FFI on web
      return available.contains(b);
    }

    if (pref != Backend.auto) {
      return usable(pref) ? (backend: pref, size: size, quant: quant) : dart();
    }

    // Auto: prefer the fastest available runtime for this step. Native →
    // CrispASR ggml > native-ORT FFI > pure-Dart ONNX > pure-Dart. Web → ONNX
    // (pure-Dart) > pure-Dart, since the FFI runtimes can't run there.
    for (final b in isWeb
        ? const [Backend.onnx]
        : const [Backend.crispasr, Backend.onnxFfi, Backend.onnx]) {
      if (usable(b)) return (backend: b, size: size, quant: quant);
    }
    return dart();
  }

  static (ModelSize, ModelQuant) _qualityToModel(ModelQuality q) => switch (q) {
        // Smallest/fastest — but note tiny+q4k can octave-slip on low-confidence
        // frames (CrispASR eval), so it is NOT the default.
        ModelQuality.fast => (ModelSize.tiny, ModelQuant.q4k),
        // The shipping default: tiny model, q8 weights.
        ModelQuality.balanced => (ModelSize.tiny, ModelQuant.q8),
        // Biggest/best, for offline high-accuracy work.
        ModelQuality.accurate => (ModelSize.full, ModelQuant.f16),
      };

  // ---- persistence (index-based, stable across reorders via explicit maps) ---

  Map<String, Object> toJson() => {
        'quality': quality.name,
        'backends': {
          for (final e in backends.entries) e.key.name: e.value.name,
        },
      };

  static TranscriptionEngineConfig fromJson(Map<String, Object?> json) {
    final q = ModelQuality.values.asNameMap()[json['quality']] ??
        ModelQuality.balanced;
    final raw = (json['backends'] as Map?) ?? const {};
    final steps = TranscriptionStep.values.asNameMap();
    final backs = Backend.values.asNameMap();
    return TranscriptionEngineConfig(
      quality: q,
      backends: {
        for (final e in raw.entries)
          if (steps[e.key] case final s?)
            if (backs[e.value] case final b?) s: b,
      },
    );
  }
}
