// piper_voice_store.dart — NATIVE download+cache of CC0 Piper voices. The
// `dart:io` half kept OUT of the web-safe `piper_synth.dart` / `piper_phonemes
// .dart`, so those stay importable on web/WASM. Only native callers touch this
// (CLI, tests, and the app behind `!kIsWeb`), mirroring
// `transcription/basic_pitch_model_store.dart` and `kokoro_model_store.dart`.
//
// VOICES — both CC0 (verified against each voice's MODEL_CARD on
// `rhasspy/piper-voices`), `low` quality (smallest + fastest), 16 kHz:
//   en → en_US-kathleen-low   (dataset rhasspy/dataset-voice-kathleen, CC0)
//   de → de_DE-thorsten-low   (Thorsten-Voice, CC0)
// (Piper CODE is MIT; these datasets are CC0, so the voices are ship-safe.)
//
// WEB NOTE: the browser download + cache path (fetch + IndexedDB) is a
// FOLLOW-UP (not built here); on web the caller fetches the .onnx + .onnx.json
// bytes itself and uses `OnnxModel.fromBytes` + `phonemeIdMapFromJson`.

import 'dart:io';
import 'dart:typed_data';

import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// A CC0 Piper voice: repo sub-path + base filename + human license note.
class PiperVoice {
  const PiperVoice(this.lang, this.repoDir, this.base, this.license);
  final String lang; // 'en' | 'de'
  final String repoDir; // path under piper-voices/main
  final String base; // file stem, e.g. en_US-kathleen-low
  final String license;
}

/// Resolves + caches CC0 Piper voices (`.onnx` + `.onnx.json`). Override the
/// cache location with `COMET_PIPER_DIR` (tests use this).
class PiperVoiceStore {
  PiperVoiceStore({this.cacheDirOverride});

  final String? cacheDirOverride;

  static const _base =
      'https://huggingface.co/rhasspy/piper-voices/resolve/main';

  /// The bundled CC0 voice choices, keyed by language.
  static const Map<String, PiperVoice> voices = {
    'en': PiperVoice(
      'en',
      'en/en_US/kathleen/low',
      'en_US-kathleen-low',
      'CC0 (dataset-voice-kathleen)',
    ),
    'de': PiperVoice(
      'de',
      'de/de_DE/thorsten/low',
      'de_DE-thorsten-low',
      'CC0 (Thorsten-Voice)',
    ),
  };

  final _cachedModels = <String, OnnxModel>{};

  String cacheDir() {
    if (cacheDirOverride != null && cacheDirOverride!.isNotEmpty) {
      return cacheDirOverride!;
    }
    final env = Platform.environment['COMET_PIPER_DIR'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.cache/comet_beat/models/piper';
  }

  PiperVoice _voice(String lang) {
    final v = voices[lang.toLowerCase().contains('de') ? 'de' : 'en'];
    return v!;
  }

  File modelFile(String lang) =>
      File('${cacheDir()}/${_voice(lang).base}.onnx');
  File configFile(String lang) =>
      File('${cacheDir()}/${_voice(lang).base}.onnx.json');

  /// Ensure the voice's `.onnx` (and `.onnx.json`) are cached, downloading on
  /// first use. Returns the model File, or null if unavailable (offline).
  Future<File?> ensureModel(String lang) async {
    final v = _voice(lang);
    final mf = modelFile(lang);
    final cf = configFile(lang);
    try {
      Directory(cacheDir()).createSync(recursive: true);
      if (!(mf.existsSync() && mf.lengthSync() > 1024 * 1024)) {
        final bytes = await _get('$_base/${v.repoDir}/${v.base}.onnx');
        if (bytes == null || bytes.length < 1024 * 1024) return null;
        await mf.writeAsBytes(bytes);
      }
      if (!(cf.existsSync() && cf.lengthSync() > 100)) {
        final cfg = await _get('$_base/${v.repoDir}/${v.base}.onnx.json');
        if (cfg == null) return null;
        await cf.writeAsBytes(cfg);
      }
      return mf;
    } catch (_) {
      return null;
    }
  }

  /// The voice config json text (downloading if needed), or null if unavailable.
  Future<String?> loadConfigJson(String lang) async {
    if (await ensureModel(lang) == null) return null;
    final cf = configFile(lang);
    return cf.existsSync() ? cf.readAsStringSync() : null;
  }

  /// Loads (and memoises) the voice ONNX model, downloading if needed. Throws
  /// [StateError] if unavailable (offline).
  Future<OnnxModel> loadModel(String lang) async {
    final key = _voice(lang).base;
    final cached = _cachedModels[key];
    if (cached != null) return cached;
    final f = await ensureModel(lang);
    if (f == null) {
      throw StateError('Piper voice "$key" unavailable (offline?). '
          'Expected at ${modelFile(lang).path}');
    }
    return _cachedModels[key] = OnnxModel.fromBytes(f.readAsBytesSync());
  }

  static Future<Uint8List?> _get(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      if (resp.statusCode != 200) return null;
      final b = BytesBuilder(copy: false);
      await for (final chunk in resp) {
        b.add(chunk);
      }
      return b.takeBytes();
    } finally {
      client.close();
    }
  }
}
