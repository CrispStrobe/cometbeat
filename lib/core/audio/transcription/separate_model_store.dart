// lib/core/audio/transcription/separate_model_store.dart
//
// NATIVE model provisioning for the HTDemucs separator — the `dart:io` half kept
// OUT of the web-safe `separate.dart`. Mirrors BasicPitchModelStore /
// CrepeModelStore exactly.
//
// TODO(model worker): set [_modelUrl] to a published MIT HTDemucs (or Demucs)
// ONNX export (input [1,2,N] → output [1,4,2,N]). Until then ensureFile()
// returns null and the separator is simply unavailable (transcribeSong falls
// back to a single part); nothing breaks. Ship the model's MIT LICENSE beside
// it. NB: these are LARGE (tens–hundreds of MB) — strictly opt-in, native-only.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// Resolves + loads the MIT HTDemucs ONNX. Override the cache location with
/// `COMET_DEMUCS_DIR` (tests use this).
class DemucsModelStore {
  DemucsModelStore({this.cacheDirOverride});

  final String? cacheDirOverride;

  // TODO(model worker): the published HTDemucs ONNX URL. Empty = unavailable.
  static const _modelUrl = '';
  static const _licenseUrl = '';

  OnnxModel? _cached;

  String cacheDir() {
    if (cacheDirOverride != null && cacheDirOverride!.isNotEmpty) {
      return cacheDirOverride!;
    }
    final env = Platform.environment['COMET_DEMUCS_DIR'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.cache/comet_beat/models';
  }

  File modelFile() => File('${cacheDir()}/htdemucs.onnx');

  /// True when the model is already on disk (large enough), no network — the
  /// "is separation ready?" gate.
  bool isPresent() {
    final f = modelFile();
    return f.existsSync() && f.lengthSync() > 1000000;
  }

  /// The cached model file, downloading on first use. Returns null when absent
  /// and the download fails or no URL is configured yet.
  Future<File?> ensureFile() async {
    final file = modelFile();
    if (file.existsSync() && file.lengthSync() > 1000000) return file;
    if (_modelUrl.isEmpty) return null;
    try {
      Directory(cacheDir()).createSync(recursive: true);
      final bytes = await _get(_modelUrl);
      if (bytes == null || bytes.length < 1000000) return null;
      await file.writeAsBytes(bytes);
      if (_licenseUrl.isNotEmpty) {
        final lic = await _get(_licenseUrl);
        if (lic != null) {
          await File('${cacheDir()}/LICENSE.htdemucs').writeAsBytes(lic);
        }
      }
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Loads (and memoises) the model, downloading if needed. Throws a
  /// [StateError] if it can't be obtained.
  Future<OnnxModel> load() async {
    if (_cached != null) return _cached!;
    final file = await ensureFile();
    if (file == null) {
      throw StateError('HTDemucs model unavailable (no URL configured, or '
          'offline). Expected at ${modelFile().path}');
    }
    return _cached = OnnxModel.fromBytes(file.readAsBytesSync());
  }

  static Future<Uint8List?> _get(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      if (resp.statusCode != 200) return null;
      final chunks = <int>[];
      await for (final c in resp) {
        chunks.addAll(c);
      }
      return Uint8List.fromList(chunks);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
