// lib/core/audio/transcription/separate_umx_model_store.dart
//
// NATIVE model provisioning for the Open-Unmix vocals separator — the `dart:io`
// half kept OUT of the web-safe `separate_umx.dart`. Downloads the MIT umxhq
// vocals ONNX (~36 MB) on demand and caches it, mirroring `crepe_model_store`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/separate_umx.dart';
import 'package:comet_beat/core/audio/transcription/stems.dart' show Separator;
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// Resolves + loads the MIT Open-Unmix vocals ONNX. Override the cache location
/// with `COMET_UMX_DIR` (tests use this).
class UmxModelStore {
  UmxModelStore({this.cacheDirOverride});

  final String? cacheDirOverride;

  static const _modelUrl =
      'https://github.com/CrispStrobe/onnx_runtime_dart/releases/download/'
      'models-v1/umx-vocals.onnx';

  OnnxModel? _cached;

  String cacheDir() {
    if (cacheDirOverride != null && cacheDirOverride!.isNotEmpty) {
      return cacheDirOverride!;
    }
    final env = Platform.environment['COMET_UMX_DIR'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.cache/comet_beat/models';
  }

  File modelFile() => File('${cacheDir()}/umx-vocals.onnx');

  /// Whether the model is already on disk (no network) — the readiness gate.
  bool isPresent() {
    final f = modelFile();
    return f.existsSync() && f.lengthSync() > 10000000;
  }

  /// The cached model file, downloading it on first use. Returns null if absent
  /// and the download fails (offline).
  Future<File?> ensureFile() async {
    final file = modelFile();
    if (isPresent()) return file;
    try {
      Directory(cacheDir()).createSync(recursive: true);
      final bytes = await _get(_modelUrl);
      if (bytes == null || bytes.length < 10000000) return null;
      await file.writeAsBytes(bytes);
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
      throw StateError('Open-Unmix model unavailable (offline?). '
          'Expected at ${modelFile().path}');
    }
    return _cached = OnnxModel.fromBytes(file.readAsBytesSync());
  }

  /// The stems.dart [Separator] (vocals only) backed by this model.
  Future<Separator> separator() async => umxVocalSeparator(await load());

  static Future<Uint8List?> _get(String url) async {
    final client = HttpClient();
    try {
      client.userAgent = 'comet_beat-umx';
      var uri = Uri.parse(url);
      for (var hop = 0; hop < 5; hop++) {
        final req = await client.getUrl(uri);
        req.followRedirects = false;
        final resp = await req.close();
        if (resp.statusCode == 200) {
          final b = BytesBuilder(copy: false);
          await for (final chunk in resp) {
            b.add(chunk);
          }
          return b.takeBytes();
        }
        final loc = resp.headers.value(HttpHeaders.locationHeader);
        await resp.drain<void>();
        if (resp.isRedirect && loc != null) {
          uri = Uri.parse(loc);
          continue;
        }
        return null;
      }
      return null;
    } finally {
      client.close();
    }
  }
}
