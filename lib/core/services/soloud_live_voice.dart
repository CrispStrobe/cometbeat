// lib/core/services/soloud_live_voice.dart
//
// The REAL-TIME live-voice backend (the "3" of the feel/instrument arc), built
// on flutter_soloud. Unlike the classic audioplayers pool — which re-decodes a
// WAV on every tap — SoLoud decodes each note/pad WAV ONCE (`loadMem`) and then
// replays it instantly and polyphonically, with a per-tap volume (velocity).
//
// This is the ONLY file that imports flutter_soloud. It sits behind
// [LiveVoiceEngine]'s capability hook: every SoLoud call is guarded, and
// `init()` returns false (→ graceful degrade to the pool) whenever the engine
// can't come up — an unsupported platform, a missing native library, or a
// headless test. The process-wide SoLoud engine is left initialised on dispose
// so re-entering Perform doesn't pay the init cost again.

import 'package:comet_beat/core/services/live_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

class SoLoudLiveVoice implements LiveVoice {
  final Map<String, AudioSource> _sources = {};
  bool _ready = false;

  SoLoud get _soloud => SoLoud.instance;

  @override
  bool get isRealtime => true;

  @override
  Future<bool> init() async {
    if (_ready) return true;
    try {
      if (!_soloud.isInitialized) {
        // SoLoud's default sample rate (44100) matches the app's kSampleRate,
        // so the rendered note/pad WAVs play back at the right pitch/speed.
        await _soloud.init();
      }
      _ready = _soloud.isInitialized;
    } catch (e) {
      if (kDebugMode) debugPrint('[SOLOUD] init failed: $e');
      _ready = false;
    }
    return _ready;
  }

  @override
  Future<void> play(String key, Uint8List wav, {double volume = 1.0}) async {
    if (!_ready) return;
    try {
      final src = _sources[key] ??= await _soloud.loadMem(key, wav);
      await _soloud.play(src, volume: volume.clamp(0.0, 1.0));
    } catch (e) {
      if (kDebugMode) debugPrint('[SOLOUD] play failed: $e');
    }
  }

  @override
  void invalidate() {
    for (final src in _sources.values) {
      try {
        _soloud.disposeSource(src);
      } catch (_) {
        // Best-effort; a disposed/absent source is fine to ignore.
      }
    }
    _sources.clear();
  }

  @override
  void dispose() {
    invalidate();
    // Leave the process-wide engine initialised (warm) for the next screen.
  }
}
