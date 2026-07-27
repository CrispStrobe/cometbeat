// tts_asset_cache.dart — facade for the TTS model/asset byte cache. Picks the
// platform impl at compile time: native (dart:io true) → a file cache under the
// app models dir; web → an IndexedDB store. Import THIS file; never the _io /
// _web halves directly (that would drag dart:io or package:web onto the wrong
// platform and break the build).
//
//   final cache = createTtsAssetCache();          // right impl for the platform
//   await cache.write('piper/foo.onnx', bytes);
//
// The VM test host has dart:io, so tests exercise the real file cache.

export 'package:comet_beat/core/audio/tts/tts_asset_cache_base.dart';
export 'package:comet_beat/core/audio/tts/tts_asset_cache_web.dart'
    if (dart.library.io) 'package:comet_beat/core/audio/tts/tts_asset_cache_io.dart';
