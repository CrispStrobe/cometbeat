// lib/core/services/loop_player_service.dart
//
// Gapless-looping playback channel for the Loop Mixer. Deliberately a second,
// dedicated AudioPlayer — AudioService's shared SFX player stops whatever is
// sounding on every play, so a feedback blip anywhere would kill the groove
// (and the groove would eat SFX). Like AudioService, playback failures are
// swallowed: audio is juice, never a requirement — tests and platforms
// without audio must not break.

import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:comet_beat/core/services/audio_cache_directory.dart';
import 'package:flutter/foundation.dart';

class LoopPlayerService {
  AudioPlayer? _player;

  /// Starts (or swaps to) [wav] looping forever, from [position] into the
  /// buffer. The Loop Mixer keeps its own musical clock and passes the
  /// clock's phase here on every toggle, so swapping the mix preserves the
  /// groove's position instead of restarting the bar.
  Future<void> playLoop(
    Uint8List wav, {
    Duration position = Duration.zero,
  }) async {
    try {
      final player = _player ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.stop();
      if (!kIsWeb) await prepareAudioCacheDirectory();
      final source = kIsWeb
          // BytesSource is not supported by the web implementation; a data
          // URI plays fine in the browser's audio element.
          ? UrlSource('data:audio/wav;base64,${base64Encode(wav)}')
          : BytesSource(wav, mimeType: 'audio/wav');
      await player.play(source, position: position);
    } catch (e) {
      if (kDebugMode) debugPrint('[LOOP] playback unavailable: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (e) {
      if (kDebugMode) debugPrint('[LOOP] stop unavailable: $e');
    }
  }

  void dispose() {
    _player?.dispose();
    _player = null;
  }
}
