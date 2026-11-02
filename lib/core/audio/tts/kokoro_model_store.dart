// lib/core/audio/tts/kokoro_model_store.dart
//
// Resolves the CrispASR/Kokoro model + per-locale voice using CrispASR's OWN
// model registry and downloader — the same mechanism the `crispasr` CLI (`-m
// auto`) and CrisperWeaver's model manager use. No hand-rolled URLs:
//   • registryLookup('kokoro')          → the canonical model GGUF + its published
//                                          HuggingFace URL (cstr/kokoro-82m-GGUF).
//   • cacheEnsureFile(filename, url)     → CrispASR's C-side downloader; caches
//                                          into its cache dir and returns the path
//                                          (or the cached path if already there).
//   • cacheDir()                          → CrispASR's cache dir (~/.cache/crispasr
//                                          on POSIX), or an app-sandbox override.
//
// Today its main job is shared plumbing for the neural NARRATION voices
// (crispasr_voice_runtime.dart): where libcrispasr is ([libPath] cascade, plus
// [loadError] — the dlopen message shown when natural voices can't run) and
// where CrispASR's cache dir is ([cacheDirPath], no FFI needed). The narration
// voices themselves (Piper + Kokoro) are listed in neural_voice_catalog.dart.

import 'dart:ffi';
import 'dart:io';

import 'package:crispasr/crispasr.dart';

class KokoroModelStore {
  KokoroModelStore({this.cacheDirOverride, String? libPathOverride})
      : _libOverride =
            libPathOverride ?? Platform.environment['COMET_CRISPASR_LIB'];

  /// App-sandbox cache dir; null uses CrispASR's default (`~/.cache/crispasr`).
  final String? cacheDirOverride;
  final String? _libOverride;

  static const kokoroBackend = 'kokoro';

  /// The registered model filename, if the registry can't be reached (no lib).
  static const _fallbackModelFile = 'kokoro-82m-q8_0.gguf';

  /// Per-locale voice pack (both live in cstr/kokoro-voices-GGUF). de →
  /// df_victoria (registry-registered German voice), en → af_heart.
  static const _voiceForLang = <String, String>{
    'de': 'kokoro-voice-df_victoria.gguf',
    'en': 'kokoro-voice-af_heart.gguf',
  };

  static String voiceFileFor(String lang) =>
      _voiceForLang[lang] ?? _voiceForLang['en']!;

  /// Absolute path of the native lib. Resolution cascade (first hit wins):
  ///   1. explicit override (`COMET_CRISPASR_LIB` / constructor) — dev/tests;
  ///   2. the app bundle's Frameworks dir (macOS release: dylib shipped in the
  ///      signed `.app` — see tool/bundle_macos_tts.sh);
  ///   3. `<cacheDir>/libcrispasr.dylib` — a dev/desktop drop next to the models;
  ///   4. the crispasr package's per-platform default candidate (loader search).
  String libPath() {
    if (_libOverride != null && _libOverride.isNotEmpty) return _libOverride;
    for (final p in [_bundledLibPath(), _cacheLibPath()]) {
      if (p != null && File(p).existsSync()) return p;
    }
    return CrispASR.defaultLibName();
  }

  /// The dylib inside a built macOS app: `<App>.app/Contents/Frameworks/…`,
  /// derived from the running executable (`…/Contents/MacOS/<exe>`).
  String? _bundledLibPath() {
    if (!Platform.isMacOS) return null;
    try {
      final macosDir =
          File(Platform.resolvedExecutable).parent; // Contents/MacOS
      return '${macosDir.parent.path}/Frameworks/libcrispasr.dylib';
    } catch (_) {
      return null;
    }
  }

  /// A dylib dropped alongside the cached models (desktop/dev convenience).
  String? _cacheLibPath() {
    final dir = cacheDirPath();
    return dir == null ? null : '$dir/libcrispasr.dylib';
  }

  /// CrispASR's model cache dir, resolved WITHOUT the native lib, mirroring
  /// `crispasr_cache::dir()`: override → `$CRISPASR_CACHE_DIR` →
  /// `$CRISPASR_MODELS_DIR` → `$HOME/.cache/crispasr`. In the macOS sandbox
  /// HOME is the app container, so this lands inside it.
  String? cacheDirPath() {
    if (cacheDirOverride != null && cacheDirOverride!.isNotEmpty) {
      return cacheDirOverride;
    }
    final env = Platform.environment;
    for (final k in const ['CRISPASR_CACHE_DIR', 'CRISPASR_MODELS_DIR']) {
      final v = env[k];
      if (v != null && v.isNotEmpty) return v;
    }
    final home = env['HOME'] ?? env['USERPROFILE'];
    return home == null ? null : '$home/.cache/crispasr';
  }

  /// Why the native lib cannot be opened (the dlopen message), or null when it
  /// loads. Lets the UI say WHY natural voices are unavailable.
  String? loadError() {
    try {
      DynamicLibrary.open(libPath());
      return null;
    } catch (e) {
      return '$e';
    }
  }

  DynamicLibrary? _tryOpenLib() {
    try {
      return DynamicLibrary.open(libPath());
    } catch (_) {
      return null;
    }
  }

  /// True iff the native lib loads on this platform — i.e. the HD voice is
  /// *possible* here (the model may still need downloading). Gates the settings
  /// tile so it only appears where neural TTS could run.
  Future<bool> supported() async => _tryOpenLib() != null;

  /// True iff the native lib loads AND the model GGUF is already cached — i.e.
  /// synthesis can run now without a download. False ⇒ TtsService uses the
  /// platform voice (and a UI action can call the backend's `download`).
  Future<bool> isReady() async {
    final lib = _tryOpenLib();
    if (lib == null) return false;
    try {
      final dir = cacheDir(override: cacheDirOverride, lib: lib);
      if (dir == null) return false;
      final model = registryLookup(kokoroBackend, lib: lib)?.filename ??
          _fallbackModelFile;
      final f = File('$dir/$model');
      return f.existsSync() && f.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }
}
