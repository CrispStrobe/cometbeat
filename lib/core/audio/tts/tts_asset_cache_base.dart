// tts_asset_cache_base.dart — the platform-agnostic interface for the TTS
// model/asset byte cache. Web-safe (no dart:io, no package:web). Obtain a
// concrete instance via `createTtsAssetCache` (tts_asset_cache.dart facade):
// native → a file cache under the app's models dir; web → an IndexedDB store.
//
// Keys are relative POSIX-style paths (e.g. `piper/en_US-kathleen-low.onnx`).
// The native impl roots them at the SAME `~/.cache/comet_beat/models` dir that
// PiperVoiceStore reads, so a manager download transparently populates the
// exact files native synthesis loads — one cache, one downloader.

import 'dart:typed_data';

/// A keyed byte cache for downloaded TTS models/voices. Implementations never
/// throw for a missing key — `read`/`has` just report absence.
abstract class TtsAssetCache {
  /// Whether [key] is present with non-empty bytes.
  Future<bool> has(String key);

  /// The cached bytes for [key], or null if absent/empty.
  Future<Uint8List?> read(String key);

  /// Store [bytes] under [key], overwriting any existing value.
  Future<void> write(String key, Uint8List bytes);

  /// Remove [key] if present (no-op otherwise).
  Future<void> delete(String key);

  /// All present keys (relative paths).
  Future<List<String>> keys();

  /// Total bytes stored across all keys (best-effort; for a UI size readout).
  Future<int> totalBytes();
}
