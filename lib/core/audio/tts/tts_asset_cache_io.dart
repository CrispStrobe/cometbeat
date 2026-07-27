// tts_asset_cache_io.dart — native (dart:io) file cache for TTS assets. Roots
// keys under `~/.cache/comet_beat/models` (override via ctor / COMET_MODELS_DIR)
// — the SAME root PiperVoiceStore uses, so `manager.ensure('piper/<file>')`
// writes exactly where PiperVoiceStore.modelFile reads it. Writes are atomic
// (tmp `.part` → rename) so a killed download never leaves a half file that
// `has`/synthesis would mistake for complete.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/tts_asset_cache_base.dart';

/// Native factory — see the tts_asset_cache.dart facade. [dirOverride] sets the
/// cache root (tests pass a temp dir).
TtsAssetCache createTtsAssetCache({String? dirOverride}) =>
    FileAssetCache(dirOverride: dirOverride);

class FileAssetCache implements TtsAssetCache {
  FileAssetCache({String? dirOverride}) : _root = dirOverride ?? _defaultRoot();

  final String _root;

  static String _defaultRoot() {
    final env = Platform.environment['COMET_MODELS_DIR'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.cache/comet_beat/models';
  }

  /// Map a key to an absolute path, keeping sub-dirs but refusing traversal.
  String _pathFor(String key) {
    final safe = key
        .split('/')
        .where((s) => s.isNotEmpty && s != '..' && s != '.')
        .map((s) => s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_'))
        .join('/');
    return '$_root/$safe';
  }

  @override
  Future<bool> has(String key) async {
    final f = File(_pathFor(key));
    return f.existsSync() && f.lengthSync() > 0;
  }

  @override
  Future<Uint8List?> read(String key) async {
    final f = File(_pathFor(key));
    if (!f.existsSync() || f.lengthSync() == 0) return null;
    return f.readAsBytes();
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    final path = _pathFor(key);
    File(path).parent.createSync(recursive: true);
    final tmp = File('$path.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(path);
  }

  @override
  Future<void> delete(String key) async {
    final f = File(_pathFor(key));
    if (f.existsSync()) await f.delete();
  }

  @override
  Future<List<String>> keys() async {
    final dir = Directory(_root);
    if (!dir.existsSync()) return const [];
    final rootLen = _root.endsWith('/') ? _root.length : _root.length + 1;
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.substring(rootLen))
        .where((p) => !p.endsWith('.part'))
        .toList();
  }

  @override
  Future<int> totalBytes() async {
    final dir = Directory(_root);
    if (!dir.existsSync()) return 0;
    var total = 0;
    for (final e in dir.listSync(recursive: true).whereType<File>()) {
      if (e.path.endsWith('.part')) continue;
      total += e.lengthSync();
    }
    return total;
  }
}
