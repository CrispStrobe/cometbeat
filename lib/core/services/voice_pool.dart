// lib/core/services/voice_pool.dart
//
// A small pool of audio voices for POLYPHONIC one-shot playback. The shared
// AudioService is monophonic — it `stop()`s whatever is sounding before every
// play — so tapping two keys cuts the first one off. A VoicePool round-robins
// across N players and stops only the voice it reuses, so a kid can hold a
// chord or let notes ring (sustain) on the Perform keyboard/pads.
//
// Like LoopPlayerService, the players are created LAZILY on first play (so
// headless tests never touch the plugin) and every failure is swallowed —
// audio is juice, never a requirement.

import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:comet_beat/core/services/audio_cache_directory.dart';
import 'package:flutter/foundation.dart';

class VoicePool {
  VoicePool({this.size = 6});

  /// How many notes can ring at once before the oldest voice is stolen.
  final int size;

  final List<AudioPlayer> _players = [];
  int _next = 0;

  /// The voice index [play] will use next — the round-robin cursor.
  int get nextVoice => _next;

  /// Advance the round-robin cursor (pure — extracted for testing).
  static int advance(int current, int size) =>
      size <= 0 ? 0 : (current + 1) % size;

  /// Play [wav] on the next voice WITHOUT stopping the others, so notes ring
  /// together. Only the reused voice is stopped (classic voice-stealing).
  /// [volume] (0..1+) sets this voice's level — used for play-in velocity.
  Future<void> play(Uint8List wav, {double volume = 1.0}) async {
    try {
      while (_players.length < size) {
        _players.add(AudioPlayer());
      }
      final player = _players[_next];
      _next = advance(_next, size);
      await player.stop();
      await player.setVolume(volume.clamp(0.0, 1.0));
      if (kIsWeb) {
        // BytesSource is unsupported on web; a data URI plays fine.
        await player.play(
          UrlSource('data:audio/wav;base64,${base64Encode(wav)}'),
        );
      } else {
        await prepareAudioCacheDirectory();
        await player.play(BytesSource(wav, mimeType: 'audio/wav'));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[VOICE] playback unavailable: $e');
    }
  }

  void dispose() {
    for (final p in _players) {
      p.dispose();
    }
    _players.clear();
  }
}
