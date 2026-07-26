// prebaked_narration.dart — play pre-rendered neural-voice narration from
// bundled WAV assets (built offline by tool/bake_narration.dart with the
// pure-Dart Piper core + CC0 voices). Instant on web, ZERO client inference —
// the practical way to get the neural voice into a browser (runtime synthesis
// there would freeze the single-threaded main isolate; see bin/tts_render.dart).
//
// LICENSE: MIT (this project). The baked audio is generated from CC0 Piper
// voices; the manifest/lookup here carries no third-party data.
//
// Web-safe: only `rootBundle` asset loading — no dart:io/ffi. The manifest KEY
// is the normalized text string (NOT a numeric hash), because a VM-side hash
// wouldn't match on the web (53-bit ints); only the asset FILENAME is hashed,
// and that is read from the manifest, never recomputed at lookup.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/narration_key.dart';
import 'package:comet_beat/core/services/tts_service.dart' show TtsBackend;
import 'package:flutter/services.dart' show rootBundle;

export 'package:comet_beat/core/audio/tts/narration_key.dart'
    show narrationKey, normalizeNarration;

/// Resolves narration strings to bundled WAV assets via `manifest.json`.
class PrebakedNarration {
  PrebakedNarration({Future<String> Function()? loadManifest})
      : _loadManifest = loadManifest ??
            (() => rootBundle.loadString('assets/narration/manifest.json'));

  final Future<String> Function() _loadManifest;
  Map<String, String>? _cache;

  Future<Map<String, String>> _manifest() async {
    if (_cache != null) return _cache!;
    try {
      final decoded = jsonDecode(await _loadManifest()) as Map<String, dynamic>;
      _cache = {for (final e in decoded.entries) e.key: e.value as String};
    } catch (_) {
      _cache = const {}; // no manifest bundled yet → nothing is prebaked
    }
    return _cache!;
  }

  /// The bundled asset path for [text]/[langCode], or null if not pre-baked.
  Future<String?> assetFor(String text, String langCode) async =>
      (await _manifest())[narrationKey(text, langCode)];
}

/// A [TtsBackend] that plays a pre-baked narration asset when one exists. When
/// the text isn't baked, [speak] no-ops (and [has] is false) so the caller
/// falls back to the platform/neural voice.
class PrebakedNarrationBackend implements TtsBackend {
  PrebakedNarrationBackend({
    required this.play,
    PrebakedNarration? narration,
    Future<Uint8List> Function(String assetPath)? loadAsset,
    this.stopPlayback,
  })  : narration = narration ?? PrebakedNarration(),
        _loadAsset = loadAsset ??
            ((p) async =>
                (await rootBundle.load('assets/$p')).buffer.asUint8List());

  /// Plays a finished WAV (e.g. AudioService.playWavBytes).
  final Future<void> Function(Uint8List wav) play;
  final PrebakedNarration narration;
  final Future<Uint8List> Function(String assetPath) _loadAsset;
  final Future<void> Function()? stopPlayback;

  /// Whether [text]/[langCode] has a bundled narration asset.
  Future<bool> has(String text, String langCode) async =>
      (await narration.assetFor(text, langCode)) != null;

  @override
  Future<void> speak(String text, {required String langCode}) async {
    final asset = await narration.assetFor(text, langCode);
    if (asset == null) return; // not prebaked → caller falls back
    final wav = await _loadAsset(asset);
    await play(wav);
  }

  @override
  Future<void> stop() async => stopPlayback?.call();
}
