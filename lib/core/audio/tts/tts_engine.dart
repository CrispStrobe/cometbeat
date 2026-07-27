// tts_engine.dart — WHICH runtime synthesizes speech, resolved per platform +
// availability. The TTS twin of the transcription decision framework
// (transcription/engine_config.dart `Backend` + `resolve`): a single place that
// picks the best usable neural path, with the platform voice as the floor.
//
// Pure Dart, no I/O — just the decision logic, so it's unit-testable and safe on
// every target (web included). The backends themselves live behind TtsService.

/// The runtimes that can turn text into speech, fastest/best first (roughly).
enum TtsEngine {
  /// Let [resolveTtsEngines] choose by platform + availability.
  auto,

  /// OS / browser text-to-speech (flutter_tts → AVSpeech / Android TTS / web
  /// SpeechSynthesis). Everywhere, instant, the universal floor.
  platform,

  /// Pre-rendered CC0 Piper WAV assets (bundled / CI-baked) played back for
  /// FIXED text. Instant + neural on web with zero client inference; only
  /// covers strings that were baked (checked per-utterance, not here).
  prebaked,

  /// CrispASR/Kokoro ggml via `dart:ffi` over libcrispasr. Native only, fast HD.
  crispasrFfi,

  /// Native ONNX Runtime (the `onnxruntime` FFI plugin) running Kokoro/Piper
  /// ONNX. Native only, GPU-capable.
  onnxFfi,

  /// `onnx_runtime_dart` (pure-Dart ONNX). Runs everywhere incl. web/WASM, but
  /// single-threaded → viable for INTERACTIVE speech only on native (isolates);
  /// on web it is offline/pre-render only (a live synth would freeze the tab).
  pureDartOnnx,

  /// CrispASR/Kokoro compiled to WebAssembly + a JS-interop seam — live neural
  /// on the web. Present only if that build ships (a moonshot; may be absent).
  crispasrWasm,
}

/// Engines that need native FFI, so they can never run on the web.
bool ttsEngineNeedsFfi(TtsEngine e) =>
    e == TtsEngine.crispasrFfi || e == TtsEngine.onnxFfi;

/// The ordered INTERACTIVE-synthesis fallback chain for this platform, given
/// which engines' runtime + model are actually [available] right now. The first
/// entry is preferred; callers try each until one speaks. [platform] is always
/// appended as the floor.
///
/// Pre-baked assets are NOT part of this chain — they're checked per-utterance
/// (only some text is baked) before falling back to whatever this returns.
///
/// - Native auto: crispasr-FFI → native-ORT → pure-Dart ONNX → platform.
/// - Web auto: crispasr-WASM → platform. (Pure-Dart ONNX is excluded on web:
///   single-threaded, a live synth of any real length would freeze the page.)
List<TtsEngine> resolveTtsEngines({
  required bool isWeb,
  required Set<TtsEngine> available,
  TtsEngine preferred = TtsEngine.auto,
}) {
  bool usable(TtsEngine e) {
    if (e == TtsEngine.platform) return true; // the floor is always usable
    if (isWeb && ttsEngineNeedsFfi(e)) return false; // no FFI in the browser
    // Pure-Dart ONNX is single-threaded → a live web synth would freeze the tab.
    if (isWeb && e == TtsEngine.pureDartOnnx) return false;
    return available.contains(e);
  }

  final order = <TtsEngine>[];
  void add(TtsEngine e) {
    if (usable(e) && !order.contains(e)) order.add(e);
  }

  // An explicit, usable preference wins the top slot; else the auto chain.
  if (preferred != TtsEngine.auto && preferred != TtsEngine.platform) {
    add(preferred);
  }
  for (final e in isWeb
      ? const [TtsEngine.crispasrWasm, TtsEngine.platform]
      : const [
          TtsEngine.crispasrFfi,
          TtsEngine.onnxFfi,
          TtsEngine.pureDartOnnx,
          TtsEngine.platform,
        ]) {
    add(e);
  }
  if (!order.contains(TtsEngine.platform)) order.add(TtsEngine.platform);
  return order;
}
