// lib/core/services/tts_service.dart
//
// Text-to-speech narration for the lessons/primers (and, later, game how-to
// text). A pre-reader (6–8yo) can HEAR a lesson before they can read it, and it
// makes the app accessible.
//
// Design: the plugin (`flutter_tts` — platform AVSpeechSynthesizer / Android TTS
// / web SpeechSynthesis, all on-device + offline + free) sits behind a
// [TtsBackend] interface, so (a) tests inject a fake with no method channel, and
// (b) a higher-quality neural backend (CrispTTS / Kokoro-ONNX via
// onnx_runtime_dart) can slot in later without touching call sites. This is the
// ONLY file that imports the TTS plugin.
//
// Narration follows the master sound switch ([soundOn], mirrored from
// SettingsService like AudioService): sound off ⇒ the app is silent, narration
// included. Speaking is best-effort — a platform with no voice for the locale
// just stays quiet rather than throwing.

import 'package:comet_beat/core/audio/tts/prebaked_narration.dart'
    show PrebakedNarrationBackend;
import 'package:comet_beat/core/audio/tts/tts_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_tts/flutter_tts.dart';

/// The speech engine behind [TtsService]. Swappable for tests and for a future
/// neural backend.
abstract class TtsBackend {
  /// Speak [text] in the given BCP-47 [langCode] (e.g. `de-DE`, `en-US`).
  /// Should interrupt any in-progress utterance.
  Future<void> speak(String text, {required String langCode});

  /// Stop any in-progress utterance.
  Future<void> stop();
}

/// The real backend, driving the `flutter_tts` plugin. Every call is guarded:
/// on a platform/locale without a voice it degrades to silence, never a crash.
class FlutterTtsBackend implements TtsBackend {
  FlutterTtsBackend() {
    // A calm, child-friendly cadence. Rates are best-effort per platform.
    _tts
      ..setSpeechRate(0.45)
      ..setVolume(1.0)
      ..setPitch(1.0);
  }

  final FlutterTts _tts = FlutterTts();
  String? _lang;

  @override
  Future<void> speak(String text, {required String langCode}) async {
    if (text.trim().isEmpty) return;
    try {
      await _tts.stop();
      if (_lang != langCode) {
        await _tts.setLanguage(langCode);
        _lang = langCode;
      }
      await _tts.speak(text);
    } catch (_) {
      // No voice / channel unavailable (e.g. headless, or a locale the OS lacks)
      // — stay silent rather than surface an error to a child.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // ignore
    }
  }
}

/// A constructed neural backend plus its probes/actions. Built by the
/// platform-conditional factory in `core/audio/tts/tts_neural.dart` (null on
/// web / where dart:io is unavailable), then handed to [TtsService].
class NeuralTts {
  const NeuralTts({
    required this.backend,
    required this.ready,
    required this.supported,
    required this.download,
  });

  final TtsBackend backend;

  /// Can synthesise right now (native lib loadable + model cached).
  final Future<bool> Function() ready;

  /// Could work on this platform (native lib loadable) — the model may still
  /// need downloading. Gates whether the settings "HD voice" tile is shown.
  final Future<bool> Function() supported;

  /// Fetch the model + [lang] voice (the opt-in download). Returns true if ready
  /// afterwards.
  final Future<bool> Function(String lang) download;
}

class TtsService with ChangeNotifier {
  TtsService({
    TtsBackend? backend,
    NeuralTts? neural,
    NeuralTts? onnx,
    PrebakedNarrationBackend? prebaked,
  })  : _injectedBackend = backend,
        _prebaked = prebaked,
        _neural = neural?.backend,
        _neuralReady = neural?.ready,
        _neuralSupported = neural?.supported,
        _neuralDownload = neural?.download,
        _onnx = onnx?.backend,
        _onnxReady = onnx?.ready;

  final TtsBackend? _injectedBackend;

  /// Optional pre-baked neural narration (bundled WAV assets). When the exact
  /// text/lang is baked, it plays instantly — the only practical neural voice
  /// on the web (runtime synthesis there would freeze the main isolate). Falls
  /// through to the platform/neural voice when nothing is baked. Null = off.
  final PrebakedNarrationBackend? _prebaked;

  /// The platform fallback (flutter_tts), created LAZILY on first narration.
  /// Building `FlutterTtsBackend()` eagerly instantiated the `flutter_tts`
  /// plugin (FlutterTts() + setSpeechRate/Volume/Pitch) at app startup — that
  /// hung the iOS-simulator screenshot capture (the app never narrates during
  /// capture, so the plugin was set up for nothing and blocked). Deferring it to
  /// the first `speak`/`stop` keeps narration working while leaving startup and
  /// the capture path free of any flutter_tts platform-channel calls.
  late final TtsBackend _backend = _injectedBackend ?? FlutterTtsBackend();

  /// Optional higher-quality neural backend (CrispASR/Kokoro). Used in
  /// preference to [_backend] when [_neuralReady] reports it can run on this
  /// device right now (native lib loadable + model cached); otherwise the
  /// platform voice covers it, so the app always speaks.
  final TtsBackend? _neural;
  final Future<bool> Function()? _neuralReady;
  final Future<bool> Function()? _neuralSupported;
  final Future<bool> Function(String lang)? _neuralDownload;

  /// Optional native-ONNX-Runtime neural backend (Piper VITS over the
  /// `onnxruntime` FFI plugin — the [TtsEngine.onnxFfi] path). Native-only (null
  /// on web / io-less builds). Selected by the engine resolver AFTER crispasr-FFI
  /// when its `ready` probe passes (native ORT loadable + a voice cached).
  final TtsBackend? _onnx;
  final Future<bool> Function()? _onnxReady;

  /// Whether a neural backend exists on this build (before any probe).
  bool get hasNeural => _neural != null;

  /// Could the neural (HD) voice work on this platform? (native lib present)
  Future<bool> neuralSupported() async {
    try {
      return await _neuralSupported?.call() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Is the neural voice ready to speak now? (lib + model cached)
  Future<bool> neuralReady() async {
    try {
      return await _neuralReady?.call() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Download the HD voice for [locale] (settings opt-in). Notifies listeners so
  /// a tile can refresh its state.
  Future<bool> downloadNeuralVoice(Locale locale) async {
    final dl = _neuralDownload;
    if (dl == null) return false;
    try {
      final ok = await dl(voiceTag(locale));
      notifyListeners();
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Master sound switch, mirrored from SettingsService (see main.dart). When
  /// off, narration is silent along with the rest of the app.
  bool soundOn = true;

  /// True while an utterance has been requested and not yet stopped. Purely for
  /// UI affordance (e.g. a speaking indicator); best-effort, not frame-accurate.
  bool get isSpeaking => _speaking;
  bool _speaking = false;

  /// Map an app [Locale] to a platform BCP-47 voice tag. German → `de-DE`,
  /// everything else → `en-US` (the app ships de + en).
  static String voiceTag(Locale locale) =>
      locale.languageCode == 'de' ? 'de-DE' : 'en-US';

  /// Narrate [text] in [locale]. No-op when the master sound switch is off or
  /// the text is blank. Interrupts any current utterance. Prefers the neural
  /// backend when it's ready, else the platform voice.
  Future<void> speak(String text, {required Locale locale}) async {
    if (!soundOn || text.trim().isEmpty) return;
    _speaking = true;
    notifyListeners();
    final langCode = voiceTag(locale);
    // Prefer a pre-baked neural narration asset when one exists for this exact
    // text/lang (instant, works on web); otherwise the platform/neural voice.
    final prebaked = _prebaked;
    if (prebaked != null && await prebaked.has(text, langCode)) {
      await prebaked.speak(text, langCode: langCode);
    } else {
      final backend = await _pick();
      await backend.speak(text, langCode: langCode);
    }
  }

  /// The user's engine preference (settings). [TtsEngine.auto] → the resolver
  /// picks the best usable path for the platform.
  TtsEngine _preferred = TtsEngine.auto;
  TtsEngine get preferredEngine => _preferred;
  set preferredEngine(TtsEngine e) {
    if (_preferred == e) return;
    _preferred = e;
    notifyListeners();
  }

  /// Which engines can synthesize RIGHT NOW (runtime + model ready). Grows as
  /// the onnx-FFI / pure-Dart-onnx / crispasr-wasm backends land; for now only
  /// crispasr-FFI (when its lib+model are ready) beyond the always-on platform.
  Future<Set<TtsEngine>> _availableEngines() async {
    final set = <TtsEngine>{TtsEngine.platform};
    final neural = _neural;
    final ready = _neuralReady;
    if (neural != null && ready != null) {
      try {
        if (await ready()) set.add(TtsEngine.crispasrFfi);
      } catch (_) {
        // treat a probe failure as "not available"
      }
    }
    final onnx = _onnx;
    final onnxReady = _onnxReady;
    if (onnx != null && onnxReady != null) {
      try {
        if (await onnxReady()) set.add(TtsEngine.onnxFfi);
      } catch (_) {
        // treat a probe failure as "not available"
      }
    }
    return set;
  }

  /// The live backend for a resolved engine, or null if not wired yet.
  TtsBackend? _backendFor(TtsEngine e) => switch (e) {
        TtsEngine.crispasrFfi => _neural,
        TtsEngine.onnxFfi => _onnx,
        TtsEngine.platform => _backend,
        // pureDartOnnx / crispasrWasm attach here as they land.
        _ => null,
      };

  /// Resolves the interactive-synthesis backend through the shared engine
  /// framework (platform + availability + the user's preference), with the
  /// platform voice as the guaranteed floor.
  Future<TtsBackend> _pick() async {
    final chain = resolveTtsEngines(
      isWeb: kIsWeb,
      available: await _availableEngines(),
      preferred: _preferred,
    );
    for (final e in chain) {
      final b = _backendFor(e);
      if (b != null) return b;
    }
    return _backend;
  }

  /// Stop narrating (e.g. the sheet was dismissed or the page changed).
  Future<void> stop() async {
    if (_speaking) {
      _speaking = false;
      notifyListeners();
    }
    await _neural?.stop();
    await _onnx?.stop();
    await _backend.stop();
  }

  @override
  void dispose() {
    _neural?.stop();
    _onnx?.stop();
    _backend.stop();
    super.dispose();
  }
}
