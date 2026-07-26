// kokoro_model_store.dart — NATIVE model/voice provisioning for the Kokoro TTS
// runner. The `dart:io` half kept OUT of the web-safe `kokoro_synth.dart`, so
// the runner itself stays importable on web/WASM. Only native callers touch
// this (CLI, tests, and the app behind `!kIsWeb`), mirroring
// `transcription/basic_pitch_model_store.dart`.
//
// Downloads (and caches) the Apache-2.0 Kokoro-82M ONNX graph + a voice pack
// from `onnx-community/Kokoro-82M-v1.0-ONNX` on demand, plus the Apache-2.0
// LICENSE for attribution.
//
// MODEL VARIANT — `onnx/model_q4f16.onnx` (~154 MB, int4 `MatMulNBits` + fp16).
// This is the SMALLEST `onnx/` variant that both loads AND runs correctly on
// `onnx_runtime_dart`. The smaller int8/uint8 exports do NOT work here:
//   - `model_q8f16.onnx` (~86 MB) / `model_uint8f16.onnx` (~114 MB): fail to
//     LOAD — their per-tensor fp16 quant-scale initializers are stored empty
//     (`"*_scale" raw_data too short: 0 bytes`), which the loader rejects.
//   - `model_quantized.onnx` (uint8, ~92 MB): loads but fails to RUN — its LSTM
//     is the MS-custom `DynamicQuantizeLSTM` op, unimplemented in the pure-Dart
//     interpreter.
// `model_q4f16.onnx` keeps a standard fp16 LSTM (int4 only on the matmuls), so
// it runs and yields audio indistinguishable in level from fp16 (RMS ≈ 0.052).
//
// WEB NOTE: the browser download + IndexedDB cache path is a FOLLOW-UP (not
// built here); on web the caller fetches these bytes itself and uses
// `OnnxModel.fromBytes` + `KokoroSynth.voiceFromBytes`.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/kokoro/kokoro_synth.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// Resolves + caches the Kokoro-82M ONNX model and voice packs. Override the
/// cache location with `COMET_KOKORO_DIR` (tests use this).
class KokoroModelStore {
  KokoroModelStore({this.cacheDirOverride});

  final String? cacheDirOverride;

  static const _repo =
      'https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/main';
  static const modelFileName = 'model_q4f16.onnx';
  static const _modelUrl = '$_repo/onnx/$modelFileName';
  static const _licenseUrl = '$_repo/LICENSE';

  /// Default voice for English (also used for German — Kokoro v1.0 ships no
  /// German voice). ~510 KB.
  static const defaultVoice = 'af_heart';

  OnnxModel? _cachedModel;

  String cacheDir() {
    if (cacheDirOverride != null && cacheDirOverride!.isNotEmpty) {
      return cacheDirOverride!;
    }
    final env = Platform.environment['COMET_KOKORO_DIR'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.cache/comet_beat/models';
  }

  File modelFile() => File('${cacheDir()}/$modelFileName');
  File voiceFile(String name) => File('${cacheDir()}/voices/$name.bin');

  /// The cached ONNX model, downloading it (+ the Apache-2.0 LICENSE) on first
  /// use. Returns null if absent and the download fails (offline) — callers
  /// gate the synthesis path skip-if-absent.
  Future<File?> ensureModel() async {
    final file = modelFile();
    if (file.existsSync() && file.lengthSync() > 50 * 1024 * 1024) return file;
    try {
      Directory(cacheDir()).createSync(recursive: true);
      final bytes = await _get(_modelUrl);
      if (bytes == null || bytes.length < 50 * 1024 * 1024) return null;
      await file.writeAsBytes(bytes);
      final lic = await _get(_licenseUrl);
      if (lic != null) {
        await File('${cacheDir()}/LICENSE.kokoro').writeAsBytes(lic);
      }
      return file;
    } catch (_) {
      return null;
    }
  }

  /// The cached voice pack `.bin`, downloading on first use. Returns null on
  /// failure (offline).
  Future<File?> ensureVoice([String name = defaultVoice]) async {
    final file = voiceFile(name);
    if (file.existsSync() && file.lengthSync() > 100 * 1024) return file;
    try {
      file.parent.createSync(recursive: true);
      final bytes = await _get('$_repo/voices/$name.bin');
      if (bytes == null || bytes.length < 100 * 1024) return null;
      await file.writeAsBytes(bytes);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Loads (and memoises) the ONNX model, downloading if needed. Throws
  /// [StateError] if it can't be obtained (offline).
  Future<OnnxModel> loadModel() async {
    if (_cachedModel != null) return _cachedModel!;
    final file = await ensureModel();
    if (file == null) {
      throw StateError('Kokoro model unavailable (offline?). '
          'Expected at ${modelFile().path}');
    }
    // model_q4f16.onnx is self-contained (no external data), so bytes →
    // OnnxModel keeps this off the _io external-data loader.
    return _cachedModel = OnnxModel.fromBytes(file.readAsBytesSync());
  }

  /// Loads a voice pack as a [Float32List] (rows × 256), downloading if needed.
  /// Throws [StateError] if unavailable.
  Future<Float32List> loadVoice([String name = defaultVoice]) async {
    final file = await ensureVoice(name);
    if (file == null) {
      throw StateError('Kokoro voice "$name" unavailable (offline?)');
    }
    return KokoroSynth.voiceFromBytes(file.readAsBytesSync());
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
