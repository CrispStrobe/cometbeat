// lib/core/services/gapless_loop_player.dart
//
// A two-player looping channel that swaps buffers without the silent hiccup a
// single-player stop→play causes. On each swap it starts the new buffer on the
// IDLE player at the requested phase, and only then stops the outgoing player —
// so the two briefly overlap on the same audio at the same position instead of
// leaving a gap. No timers (they'd leave pending timers under flutter_test); the
// overlap is just the play() call's own latency. Same guarded ethos as
// LoopPlayerService — audio failures are swallowed so tests / audioless
// platforms never break. Drop-in compatible with LoopPlayerService's API.

import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class GaplessLoopPlayer {
  final List<AudioPlayer?> _players = [null, null];
  int _active = 0;

  /// Swaps to [wav] looping forever from [position], seamlessly.
  Future<void> playLoop(
    Uint8List wav, {
    Duration position = Duration.zero,
  }) async {
    try {
      final next = 1 - _active;
      final incoming = _players[next] ??= AudioPlayer();
      final outgoing = _players[_active];

      await incoming.setReleaseMode(ReleaseMode.loop);
      final source = kIsWeb
          // BytesSource isn't supported on web; a data URI plays fine there.
          ? UrlSource('data:audio/wav;base64,${base64Encode(wav)}')
          : BytesSource(wav, mimeType: 'audio/wav');
      await incoming.play(source, position: position);
      _active = next;

      // The new buffer is now sounding at the same phase — stop the old with no
      // audible gap (a brief overlap on identical audio is inaudible).
      if (outgoing != null) {
        try {
          await outgoing.stop();
        } catch (_) {
          // ignore — the incoming player already carries the groove.
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[GAPLESS] playback unavailable: $e');
    }
  }

  Future<void> stop() async {
    for (final p in _players) {
      try {
        await p?.stop();
      } catch (e) {
        if (kDebugMode) debugPrint('[GAPLESS] stop unavailable: $e');
      }
    }
  }

  /// Pauses the sounding loop in place (keeps the buffer + position, so [resume]
  /// continues from the same phase). Guarded like [stop].
  Future<void> pause() async {
    try {
      await _players[_active]?.pause();
    } catch (e) {
      if (kDebugMode) debugPrint('[GAPLESS] pause unavailable: $e');
    }
  }

  /// Resumes a [pause]d loop from where it stopped.
  Future<void> resume() async {
    try {
      await _players[_active]?.resume();
    } catch (e) {
      if (kDebugMode) debugPrint('[GAPLESS] resume unavailable: $e');
    }
  }

  void dispose() {
    for (final p in _players) {
      p?.dispose();
    }
    _players[0] = null;
    _players[1] = null;
  }
}
