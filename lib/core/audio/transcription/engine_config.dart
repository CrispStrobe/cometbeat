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
  tab, // audio→guitar tab (TabCNN: onnx | ggml). Consumed by the Tab Workshop's
  // audioToTab, not the resolve()/resolveEngines() pipeline — the enum is just
  // the shared vocabulary so this preference persists + shows a picker.
}

/// The runtime a step's model runs on. [auto] picks the best AVAILABLE one.
///
/// Three neural runtimes (the "3 paths"), fastest-first for native:
///   • [crispasr] — CrispASR ggml/GGUF via FFI. Native, GPU-fast. Has CREPE,
///     separation (htdemucs/RoFormer), and THREE note-event models behind one
///     entry point — piano-transcription, Basic Pitch and MT3, picked with
///     [CrispasrNoteModel]; not RMVPE/BTC.
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

/// Which NOTE-EVENT model the `crispasr` runtime loads for the polyphonic step.
///
/// All three reach the same C entry point — `crispasr_session_piano`, surfaced
/// in Dart as `CrispasrSession.pianoNotes` — so this is a choice of MODEL, not a
/// second code path. (The C parameter is still spelled `pcm_16k` for historical
/// reasons; the rate is per-model and must be QUERIED, see [sampleRate].)
///
/// They differ in what they can hear, what they cost to fetch, and how they run:
///   • [basicPitch] — Spotify Basic Pitch (Apache-2.0), ~110 KB, 22050 Hz. The
///     same model as the pure-Dart ONNX default, on the ggml runtime.
///   • [pianoTranscription] — ByteDance/Kong high-resolution piano (MIT),
///     ~77 MB, 16000 Hz. A piano SPECIALIST: on non-piano material it correctly
///     declines rather than guessing, so it is not a general upgrade.
///   • [mt3] — Magenta MT3 (Apache-2.0), ~96 MB, 16000 Hz. Multi-instrument,
///     and by a wide margin the most accurate of the three on real recordings
///     (MusicNet test split, mir_eval.transcription: F1 76.5% vs 47.7% for
///     piano-transcription and 44.2% for Basic Pitch). It is an autoregressive
///     encoder-decoder that greedy-decodes up to 1024 tokens per 2.048 s
///     segment, so its cost is decode-bound and it is a FILE-IMPORT engine, not
///     a live one.
///
/// [auto] keeps today's behaviour — [pianoTranscription] — because the other two
/// have not been A/B'd on this app's own material, and because MT3's 96 MB
/// download should follow from a deliberate choice, not from a step preference.
enum CrispasrNoteModel { auto, basicPitch, pianoTranscription, mt3 }

extension CrispasrNoteModelInfo on CrispasrNoteModel {
  /// The CrispASR registry key — what `registryLookup` / `CrispasrSession.open`
  /// take. [auto] resolves here, so callers never special-case it.
  String get registryBackend => switch (this) {
        CrispasrNoteModel.auto => 'piano-transcription',
        CrispasrNoteModel.basicPitch => 'basic-pitch',
        CrispasrNoteModel.pianoTranscription => 'piano-transcription',
        CrispasrNoteModel.mt3 => 'mt3',
      };

  /// Approximate download, in bytes — for a UI that warns before a big fetch.
  /// Advisory only; the registry is the authority on the actual file.
  int get approxDownloadBytes => switch (this) {
        CrispasrNoteModel.basicPitch => 110 * 1024,
        CrispasrNoteModel.auto ||
        CrispasrNoteModel.pianoTranscription =>
          77 * 1024 * 1024,
        CrispasrNoteModel.mt3 => 96 * 1024 * 1024,
      };

  /// Whether fetching this model is big enough to deserve an explicit user
  /// action rather than an incidental first-use download (> 16 MB).
  bool get needsExplicitDownloadConsent =>
      approxDownloadBytes > 16 * 1024 * 1024;

  /// The model's native input rate, in Hz. Informational only — the live path
  /// asks the session (`pianoSampleRate`), which is the authority and also acts
  /// as the capability probe (it returns 0 when there is no piano arm).
  int get sampleRate => this == CrispasrNoteModel.basicPitch ? 22050 : 16000;
}

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
    this.f0Viterbi = false,
    this.crispasrNoteModel = CrispasrNoteModel.auto,
  });

  /// Per-step backend preference; a missing step means [Backend.auto].
  final Map<TranscriptionStep, Backend> backends;

  /// Global quality preset → (size, quant) for the neural steps.
  final ModelQuality quality;

  /// Path-smooth the neural F0 decode (crepe/rmvpe/fcpe) over the pitch lattice
  /// instead of per-frame argmax — steadier notes, a touch slower. Applied via
  /// [F0DecodeOptions] by the config service.
  final bool f0Viterbi;

  /// Which model the `crispasr` runtime loads for [TranscriptionStep.polyphonic].
  /// Only consulted when that step actually resolves to [Backend.crispasr];
  /// every other backend ignores it.
  final CrispasrNoteModel crispasrNoteModel;

  Backend backendFor(TranscriptionStep step) => backends[step] ?? Backend.auto;

  TranscriptionEngineConfig copyWith({
    Map<TranscriptionStep, Backend>? backends,
    ModelQuality? quality,
    bool? f0Viterbi,
    CrispasrNoteModel? crispasrNoteModel,
  }) =>
      TranscriptionEngineConfig(
        backends: backends ?? this.backends,
        quality: quality ?? this.quality,
        f0Viterbi: f0Viterbi ?? this.f0Viterbi,
        crispasrNoteModel: crispasrNoteModel ?? this.crispasrNoteModel,
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
        'f0Viterbi': f0Viterbi,
        'crispasrNoteModel': crispasrNoteModel.name,
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
      f0Viterbi: json['f0Viterbi'] == true,
      // Absent (a config written before the model choice existed) ⇒ auto, which
      // is today's model — an older config keeps behaving exactly as it did.
      crispasrNoteModel:
          CrispasrNoteModel.values.asNameMap()[json['crispasrNoteModel']] ??
              CrispasrNoteModel.auto,
      backends: {
        for (final e in raw.entries)
          if (steps[e.key] case final s?)
            if (backs[e.value] case final b?) s: b,
      },
    );
  }
}
