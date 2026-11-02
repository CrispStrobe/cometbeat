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

import 'dart:convert';

import 'package:comet_beat/core/audio/tts/neural_voice_catalog.dart';
import 'package:comet_beat/core/audio/tts/neural_voice_runtime.dart';
import 'package:comet_beat/core/audio/tts/prebaked_narration.dart'
    show PrebakedNarrationBackend;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The speech engine behind [TtsService]. Swappable for tests and for a future
/// neural backend.
abstract class TtsBackend {
  /// Speak [text] in the given BCP-47 [langCode] (e.g. `de-DE`, `en-US`).
  /// Should interrupt any in-progress utterance.
  Future<void> speak(String text, {required String langCode});

  /// Stop any in-progress utterance.
  Future<void> stop();
}

/// One selectable on-device platform voice (Apple/Android/web). `name` +
/// `locale` are what `flutter_tts.setVoice` needs; kept as an opaque pair.
@immutable
class TtsVoiceOption {
  const TtsVoiceOption({required this.name, required this.locale});
  final String name;
  final String locale;

  Map<String, String> toMap() => {'name': name, 'locale': locale};

  /// Persist form: JSON `{name, locale}` — robust to any characters in a
  /// voice name (spaces, dots, dashes).
  String encode() => jsonEncode({'name': name, 'locale': locale});
  static TtsVoiceOption? decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      final name = m['name'] as String?;
      final locale = m['locale'] as String?;
      if (name == null || locale == null) return null;
      return TtsVoiceOption(name: name, locale: locale);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TtsVoiceOption && other.name == name && other.locale == locale;
  @override
  int get hashCode => Object.hash(name, locale);
}

/// A backend that can enumerate + select the OS's on-device voices. Only the
/// platform (`flutter_tts`) backend implements this — neural backends have a
/// single fixed voice. [TtsService] checks with `is PlatformVoiceControl`.
abstract interface class PlatformVoiceControl {
  /// The on-device voices whose locale starts with [langPrefix] (e.g. `de`).
  Future<List<TtsVoiceOption>> availableVoices(String langPrefix);

  /// Use [voice] for subsequent utterances (null ⇒ the OS default for the
  /// utterance's language).
  Future<void> applyVoice(TtsVoiceOption? voice);
}

/// The real backend, driving the `flutter_tts` plugin. Every call is guarded:
/// on a platform/locale without a voice it degrades to silence, never a crash.
class FlutterTtsBackend implements TtsBackend, PlatformVoiceControl {
  FlutterTtsBackend() {
    // A calm, child-friendly cadence. Rates are best-effort per platform.
    _tts
      ..setSpeechRate(0.45)
      ..setVolume(1.0)
      ..setPitch(1.0);
  }

  final FlutterTts _tts = FlutterTts();
  String? _lang;

  /// The voice [TtsService] asked us to use next (null ⇒ OS default). Applied
  /// lazily in [speak] so we set it exactly once per change.
  TtsVoiceOption? _voice;
  TtsVoiceOption? _appliedVoice;

  @override
  Future<void> applyVoice(TtsVoiceOption? voice) async => _voice = voice;

  @override
  Future<List<TtsVoiceOption>> availableVoices(String langPrefix) async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return const [];
      final prefix = langPrefix.toLowerCase();
      final out = <TtsVoiceOption>[];
      final seen = <String>{};
      for (final v in raw) {
        if (v is! Map) continue;
        final name = v['name']?.toString();
        final locale = v['locale']?.toString();
        if (name == null || locale == null) continue;
        if (!locale.toLowerCase().startsWith(prefix)) continue;
        if (!seen.add('$name|$locale')) continue;
        out.add(TtsVoiceOption(name: name, locale: locale));
      }
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return out;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> speak(String text, {required String langCode}) async {
    if (text.trim().isEmpty) return;
    try {
      await _tts.stop();
      final voice = _voice;
      if (voice != null) {
        // A chosen voice fixes the language too; set it only when it changed.
        if (_appliedVoice != voice) {
          await _tts.setVoice(voice.toMap());
          _appliedVoice = voice;
          _lang = null; // force a setLanguage if we later drop back to default
        }
      } else {
        _appliedVoice = null;
        if (_lang != langCode) {
          await _tts.setLanguage(langCode);
          _lang = langCode;
        }
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

/// Where narration is requested from. Lessons/primers ([lesson]) may carry
/// their own persisted voice override on top of the Settings choice.
enum NarrationScope { global, lesson }

/// The persisted voice choice values besides a catalog voice id.
const String kNarrationVoiceAuto = 'auto';
const String kNarrationVoiceDevice = 'device';

/// Why narration did not use the voice the user chose — surfaced in the UI so
/// a silent downgrade to the device voice is never a mystery.
@immutable
class NarrationFallback {
  const NarrationFallback(this.kind, this.voice, this.detail);

  /// What went wrong.
  final TtsFailure kind;

  /// The neural voice that was wanted.
  final NeuralVoice voice;

  /// Technical detail (English), e.g. the HTTP status or dlopen error.
  final String detail;
}

/// What [resolveNarrationVoice] decided: speak with [voice] (null ⇒ the device
/// voice) and, when that is a downgrade from the user's choice, [fallback].
@immutable
class NarrationPlan {
  const NarrationPlan({this.voice, this.fallback});
  final NeuralVoice? voice;
  final NarrationFallback? fallback;
}

/// Pure voice resolution (no I/O) — unit-tested.
///
/// - `device` → the device voice, no complaint.
/// - a catalog id → that voice when the engine runs here and it is
///   downloaded; otherwise the device voice WITH the reason.
/// - `auto` (or an unknown/foreign-language id) → the first DOWNLOADED voice
///   for [lang] in catalog order; the device voice when none is (not a
///   complaint — nothing was asked for).
NarrationPlan resolveNarrationVoice({
  required String choice,
  required String lang,
  required String? runtimeUnavailable,
  required bool Function(NeuralVoice) installed,
}) {
  if (choice == kNarrationVoiceDevice) return const NarrationPlan();
  final wanted = neuralVoiceById(choice);
  if (wanted != null && wanted.lang == lang) {
    if (runtimeUnavailable != null) {
      return NarrationPlan(
        fallback: NarrationFallback(
          TtsFailure.runtimeUnavailable,
          wanted,
          runtimeUnavailable,
        ),
      );
    }
    if (!installed(wanted)) {
      return NarrationPlan(
        fallback: NarrationFallback(
          TtsFailure.notDownloaded,
          wanted,
          '${wanted.name} is not downloaded',
        ),
      );
    }
    return NarrationPlan(voice: wanted);
  }
  if (runtimeUnavailable != null) return const NarrationPlan();
  for (final v in neuralVoicesFor(lang)) {
    if (installed(v)) return NarrationPlan(voice: v);
  }
  return const NarrationPlan();
}

class TtsService with ChangeNotifier {
  TtsService({
    TtsBackend? backend,
    NeuralVoiceRuntime? neural,
    PrebakedNarrationBackend? prebaked,
  })  : _injectedBackend = backend,
        _prebaked = prebaked,
        _neural = neural;

  final TtsBackend? _injectedBackend;

  /// Optional pre-baked neural narration (bundled WAV assets). When the exact
  /// text/lang is baked AND no other voice was chosen (auto, nothing
  /// downloaded) it plays instantly — the only practical neural voice on the
  /// web. Null = off.
  final PrebakedNarrationBackend? _prebaked;

  /// The platform fallback (flutter_tts), created LAZILY on first narration.
  /// Building `FlutterTtsBackend()` eagerly instantiated the `flutter_tts`
  /// plugin at app startup — that hung the iOS-simulator screenshot capture.
  /// Deferring it to the first `speak`/`stop` keeps startup and the capture
  /// path free of any flutter_tts platform-channel calls.
  late final TtsBackend _backend = _injectedBackend ?? FlutterTtsBackend();

  /// The neural voice runtime (CrispASR: Piper + Kokoro). Null on web.
  final NeuralVoiceRuntime? _neural;

  /// Whether this build has a neural runtime at all (before any probe).
  bool get hasNeural => _neural != null;

  /// Null when neural voices can run here; otherwise why not. Web/no runtime
  /// reports a fixed reason.
  Future<String?> neuralUnavailableReason() async {
    final n = _neural;
    if (n == null) return 'no neural voice engine in this build';
    try {
      return await n.unavailableReason();
    } catch (e) {
      return '$e';
    }
  }

  // ── Voice choice (persisted) ─────────────────────────────────────────────
  static const _globalPrefix = 'tts_voice_choice_';
  static const _lessonPrefix = 'tts_lesson_voice_';
  static const _legacyEngineKey = 'tts_engine';
  static const _voicePrefix = 'tts_voice_';

  final Map<String, String> _global = {};
  final Map<String, String> _lesson = {};

  static String _baseLang(String langCode) =>
      langCode.toLowerCase().split(RegExp('[-_]')).first;

  /// The Settings voice choice for [lang] (`auto` when never set).
  String globalVoiceChoice(String lang) =>
      _global[_baseLang(lang)] ?? kNarrationVoiceAuto;

  /// The lessons' own override for [lang], or null (= follow Settings).
  String? lessonVoiceOverride(String lang) => _lesson[_baseLang(lang)];

  /// The choice that applies to narration requested from [scope].
  String voiceChoice(
    String lang, {
    NarrationScope scope = NarrationScope.global,
  }) {
    if (scope == NarrationScope.lesson) {
      final o = lessonVoiceOverride(lang);
      if (o != null) return o;
    }
    return globalVoiceChoice(lang);
  }

  /// Set the voice for [lang] in [scope] and persist it. For the lesson scope
  /// a null [choice] clears the override (lessons follow Settings again).
  Future<void> setVoiceChoice(
    String lang,
    String? choice, {
    NarrationScope scope = NarrationScope.global,
  }) async {
    final l = _baseLang(lang);
    final map = scope == NarrationScope.lesson ? _lesson : _global;
    if (choice == null) {
      map.remove(l);
    } else {
      map[l] = choice;
    }
    _lastFallback = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final key =
        '${scope == NarrationScope.lesson ? _lessonPrefix : _globalPrefix}$l';
    if (choice == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, choice);
    }
  }

  // ── Downloads ────────────────────────────────────────────────────────────
  final Map<String, double> _progress = {};
  final Map<String, String> _downloadErrors = {};
  final Set<String> _installed = {};

  /// Download progress 0..1 for a voice being fetched, else null.
  double? downloadProgress(String voiceId) => _progress[voiceId];

  /// The last download error for a voice (cleared on retry/success).
  String? downloadError(String voiceId) => _downloadErrors[voiceId];

  /// Cached installed-state (call [refreshInstalled] to update).
  bool isInstalledCached(String voiceId) => _installed.contains(voiceId);

  /// Re-scan which catalog voices are on disk; notifies.
  Future<void> refreshInstalled() async {
    final n = _neural;
    final next = <String>{};
    if (n != null) {
      for (final v in kNeuralVoices) {
        try {
          if (await n.isInstalled(v)) next.add(v.id);
        } catch (_) {}
      }
    }
    _installed
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  /// Download [voice] (user action). Progress + errors are kept here so they
  /// survive the picker closing. Returns true when installed afterwards.
  Future<bool> downloadVoice(NeuralVoice voice) async {
    final n = _neural;
    if (n == null || _progress.containsKey(voice.id)) return false;
    _downloadErrors.remove(voice.id);
    _progress[voice.id] = 0;
    notifyListeners();
    var lastNotify = DateTime.now();
    try {
      await n.download(
        voice,
        onProgress: (r, t) {
          _progress[voice.id] = t > 0 ? (r / t).clamp(0.0, 1.0) : 0;
          final now = DateTime.now();
          if (now.difference(lastNotify).inMilliseconds > 150) {
            lastNotify = now;
            notifyListeners();
          }
        },
      );
      _installed.add(voice.id);
      return true;
    } on TtsVoiceException catch (e) {
      _downloadErrors[voice.id] = e.detail;
      _logError('download ${voice.id}', e);
      return false;
    } catch (e) {
      _downloadErrors[voice.id] = '$e';
      _logError('download ${voice.id}', e);
      return false;
    } finally {
      _progress.remove(voice.id);
      if (_lastFallback?.voice.id == voice.id) _lastFallback = null;
      notifyListeners();
    }
  }

  /// Delete a downloaded voice; a choice pointing at it falls back to auto.
  Future<void> removeVoice(NeuralVoice voice) async {
    await _neural?.remove(voice);
    _installed.remove(voice.id);
    notifyListeners();
  }

  // ── Narration ─────────────────────────────────────────────────────────────
  NarrationFallback? _lastFallback;

  /// Set when the last narration had to fall back from the chosen neural
  /// voice to the device voice (cleared by a successful neural utterance or a
  /// new choice). The lesson sheet shows it.
  NarrationFallback? get lastFallback => _lastFallback;

  /// The neural voice the last utterance actually used (null = device /
  /// pre-baked). For tests + a "now speaking" hint.
  NeuralVoice? get lastNeuralVoice => _lastNeuralVoice;
  NeuralVoice? _lastNeuralVoice;

  /// Download the voices a lesson will need? No — narration NEVER downloads;
  /// the picker does, on an explicit tap.

  /// Warm the pre-baked narration cache for [items] (each a `(text, langCode)`).
  /// A no-op in bundled mode or when no pre-baked backend is wired.
  /// Best-effort; never throws. Returns the count newly cached.
  Future<int> prefetchNarration(Iterable<(String, String)> items) async {
    try {
      return await _prebaked?.prefetch(items) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Master sound switch, mirrored from SettingsService (see main.dart).
  bool soundOn = true;

  /// Read-aloud switch, mirrored from SettingsService — independent of
  /// [soundOn]. When off, [speak] no-ops. On by default.
  bool narrationOn = true;

  /// True while an utterance has been requested and not yet stopped.
  bool get isSpeaking => _speaking;
  bool _speaking = false;

  /// Map an app [Locale] to a platform BCP-47 voice tag. German → `de-DE`,
  /// everything else → `en-US` (the app ships de + en).
  static String voiceTag(Locale locale) =>
      locale.languageCode == 'de' ? 'de-DE' : 'en-US';

  /// Narrate [text] in [locale] with the voice chosen for [scope]. No-op when
  /// sound or narration is off or the text is blank. A chosen neural voice
  /// that cannot run falls back to the device voice and records why in
  /// [lastFallback].
  Future<void> speak(
    String text, {
    required Locale locale,
    NarrationScope scope = NarrationScope.global,
  }) async {
    if (!soundOn || !narrationOn || text.trim().isEmpty) return;
    final langCode = voiceTag(locale);
    await _speakWith(voiceChoice(langCode, scope: scope), text, langCode);
  }

  /// Speak [text] with an explicit [choice] (the picker's preview).
  Future<void> preview(String choice, String text, {required Locale locale}) {
    if (!soundOn || text.trim().isEmpty) return Future.value();
    return _speakWith(choice, text, voiceTag(locale));
  }

  Future<void> _speakWith(String choice, String text, String langCode) async {
    await stop();
    _speaking = true;
    notifyListeners();
    final lang = _baseLang(langCode);
    final n = _neural;
    final reason = choice == kNarrationVoiceDevice
        ? null
        : await neuralUnavailableReason();
    final installed = <String>{};
    if (n != null && reason == null) {
      for (final v in neuralVoicesFor(lang)) {
        try {
          if (await n.isInstalled(v)) installed.add(v.id);
        } catch (_) {}
      }
    }
    final plan = resolveNarrationVoice(
      choice: choice,
      lang: lang,
      // `auto` with no runtime is not a complaint — only an explicit choice is.
      runtimeUnavailable: reason,
      installed: (v) => installed.contains(v.id),
    );

    final voice = plan.voice;
    if (voice != null && n != null) {
      try {
        await n.speak(voice, text);
        _lastNeuralVoice = voice;
        _lastFallback = null;
        notifyListeners();
        return;
      } on TtsVoiceException catch (e) {
        _logError('speak ${voice.id}', e);
        _lastFallback = NarrationFallback(e.kind, voice, e.detail);
      } catch (e) {
        _logError('speak ${voice.id}', e);
        _lastFallback = NarrationFallback(TtsFailure.synthFailed, voice, '$e');
      }
    } else {
      _lastFallback = plan.fallback;
      // Nothing neural chosen/available: a pre-baked clip of this exact text
      // is the next best thing (instant, works on the web).
      final prebaked = _prebaked;
      if (choice != kNarrationVoiceDevice &&
          plan.fallback == null &&
          prebaked != null &&
          await prebaked.has(text, langCode)) {
        _lastNeuralVoice = null;
        notifyListeners();
        await prebaked.speak(text, langCode: langCode);
        return;
      }
    }
    _lastNeuralVoice = null;
    notifyListeners();
    final backend = _backend;
    if (backend is PlatformVoiceControl) {
      await (backend as PlatformVoiceControl).applyVoice(_chosenVoices[lang]);
    }
    await backend.speak(text, langCode: langCode);
  }

  void _logError(String what, Object e) {
    debugPrint('[tts] $what failed: $e');
  }

  // ── On-device platform voice selection (Apple/Android/web) ────────────────

  /// The user's chosen platform voice per base language (`de`/`en`). Empty ⇒
  /// the OS default. Applied when the device voice speaks.
  final Map<String, TtsVoiceOption> _chosenVoices = {};

  /// The chosen platform voice for [langCode], or null (OS default).
  TtsVoiceOption? chosenNarrationVoice(String langCode) =>
      _chosenVoices[_baseLang(langCode)];

  /// The on-device voices available for [langCode]. Touches the platform
  /// plugin, so call it from a user action, not startup.
  Future<List<TtsVoiceOption>> narrationVoices(String langCode) async {
    final b = _backend;
    if (b is PlatformVoiceControl) {
      return (b as PlatformVoiceControl).availableVoices(_baseLang(langCode));
    }
    return const [];
  }

  /// Choose [voice] (null ⇒ OS default) for [langCode]; persists + notifies.
  Future<void> chooseNarrationVoice(
    String langCode,
    TtsVoiceOption? voice,
  ) async {
    final lang = _baseLang(langCode);
    if (voice == null) {
      _chosenVoices.remove(lang);
    } else {
      _chosenVoices[lang] = voice;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (voice == null) {
      await prefs.remove('$_voicePrefix$lang');
    } else {
      await prefs.setString('$_voicePrefix$lang', voice.encode());
    }
  }

  /// Load persisted TTS prefs (voice choices + OS voices) and the installed
  /// state. Deliberately does NOT touch the lazy platform backend, so app
  /// startup and the screenshot-capture path stay free of flutter_tts calls.
  Future<void> loadNarrationPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    // Migrate the old engine switch: "device voice" forced is the one value
    // that maps cleanly onto the new per-language choice.
    final legacy = prefs.getString(_legacyEngineKey);
    for (final lang in const ['de', 'en']) {
      final g = prefs.getString('$_globalPrefix$lang');
      if (g != null) {
        _global[lang] = g;
      } else if (legacy == 'platform') {
        _global[lang] = kNarrationVoiceDevice;
      }
      final o = prefs.getString('$_lessonPrefix$lang');
      if (o != null) _lesson[lang] = o;
      final v = TtsVoiceOption.decode(prefs.getString('$_voicePrefix$lang'));
      if (v != null) _chosenVoices[lang] = v;
    }
    notifyListeners();
    await refreshInstalled();
  }

  /// Stop narrating (e.g. the sheet was dismissed or the page changed).
  Future<void> stop() async {
    if (_speaking) {
      _speaking = false;
      notifyListeners();
    }
    await _neural?.stop();
    await _prebaked?.stop();
    await _backend.stop();
  }

  @override
  void dispose() {
    _neural?.stop();
    _backend.stop();
    super.dispose();
  }
}
