// lib/core/services/gapless_loop_player.dart
//
// A looping playback channel that repeats WITHOUT the seam "hiccup" the OS media
// player leaves. The whole Loop Suite (Loop Mixer / Loop Studio, the Beginner
// Tracker, and the Advanced Tracker) plays through this one class, so the loop
// quality of all three is decided here.
//
// PRIMARY backend — flutter_soloud. SoLoud loops the PCM inside its own realtime
// mixer, so the bar-to-bar repeat is sample-accurate with NO gap. This is the
// thing audioplayers' `ReleaseMode.loop` could not do: that mode hands the WAV
// to the platform media element and asks *it* to loop, and the media element's
// loop-reset re-buffers — an audible gap/click at every wrap. SoLoud has no such
// reset; the loop is just the mixer reading past the end back to the start.
// On a buffer SWAP (a live edit, or an infinite-mode variation every loop) the
// incoming loop is started at the requested phase and micro-crossfaded over the
// outgoing one, so edits land seamlessly too.
//
// FALLBACK backend — the original two-player audioplayers swap. Used whenever
// SoLoud can't come up: a headless `flutter_test`, an unsupported platform, or a
// missing native library. The engine is a process-wide singleton (shared with
// `SoLoudLiveVoice`); we only ever init it, never de-init, so other surfaces
// keep their warm engine.
//
// Same guarded ethos throughout — audio is juice, never a requirement. Every
// backend call is wrapped so tests and audioless platforms never break. Ops are
// serialized on a queue so rapid edits can't race. Drop-in compatible API.

import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

class GaplessLoopPlayer {
  // A short equal-time fade over the swap boundary. SoLoud runs the ramp on its
  // own audio thread (no Dart timer, so no pending-timer failures under
  // flutter_test), and 12 ms is long enough to mask a swap yet short enough to
  // feel instant.
  static const Duration _fade = Duration(milliseconds: 12);

  // ---- SoLoud (primary) ----
  SoLoud get _soloud => SoLoud.instance;
  bool _soloudTried = false;
  bool _soloudReady = false;

  AudioSource? _curSource;
  SoundHandle? _curHandle;
  // The loop from the previous swap, already faded to silence but still resident
  // until the next swap disposes it (so its fade-out can finish undisturbed).
  AudioSource? _retireSource;
  SoundHandle? _retireHandle;
  int _gen = 0;

  // ---- audioplayers (fallback) ----
  final List<AudioPlayer?> _players = [null, null];
  int _active = 0;

  Future<void> _queue = Future<void>.value();
  bool _disposed = false;

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _queue.then((_) => operation());
    // Keep the queue usable after a backend operation fails. The individual
    // operations already log and swallow expected audio errors.
    _queue = result.then<void>((_) {}, onError: (_, __) {});
    return result;
  }

  /// Brings up SoLoud once, guarded. Returns false (→ audioplayers fallback)
  /// whenever the engine can't initialise.
  Future<bool> _ensureSoloud() async {
    if (_soloudReady) return true;
    if (_soloudTried) return false;
    _soloudTried = true;
    try {
      if (!_soloud.isInitialized) {
        // SoLoud's default sample rate (44100) matches the app's kSampleRate,
        // so the rendered loop WAVs play back at the right pitch/speed.
        await _soloud.init();
      }
      _soloudReady = _soloud.isInitialized;
    } catch (e) {
      if (kDebugMode) debugPrint('[GAPLESS] soloud init failed: $e');
      _soloudReady = false;
    }
    return _soloudReady;
  }

  /// Swaps to [wav] looping forever from [position], seamlessly.
  Future<void> playLoop(
    Uint8List wav, {
    Duration position = Duration.zero,
  }) =>
      _enqueue(() => _playLoop(wav, position: position));

  Future<void> _playLoop(
    Uint8List wav, {
    required Duration position,
  }) async {
    if (_disposed) return;
    if (await _ensureSoloud()) {
      await _playLoopSoloud(wav, position: position);
    } else {
      await _playLoopAudioplayers(wav, position: position);
    }
  }

  // ---------------------------------------------------------------------------
  // SoLoud path — genuinely gapless repeat + crossfaded swap.
  // ---------------------------------------------------------------------------
  Future<void> _playLoopSoloud(
    Uint8List wav, {
    required Duration position,
  }) async {
    try {
      // Retire the loop that was fading out from the PREVIOUS swap; its 12 ms
      // fade is long finished by the time a new swap arrives.
      await _disposeRetiring();

      // Each swap loads a fresh source (the WAV bytes changed). `path` is only a
      // reference key, so a monotonic name keeps SoLoud from de-duping edits.
      final src = await _soloud.loadMem('cb_loop_${_gen++}', wav);

      // Start silent + looping the whole buffer (loopingStartAt defaults to 0,
      // so the loop region is [0..end]). Then enter at the live groove phase and
      // fade up over the seam.
      final handle = await _soloud.play(src, volume: 0, looping: true);
      if (position > Duration.zero) {
        try {
          _soloud.seek(handle, position);
        } catch (_) {
          // A coarse/failed seek just starts the new loop at 0 — still gapless.
        }
      }
      _soloud.fadeVolume(handle, 1.0, _fade);

      // Fade the outgoing loop down and hold it for retirement on the next swap.
      if (_curHandle case final old?) {
        try {
          _soloud.fadeVolume(old, 0.0, _fade);
        } catch (_) {}
        _retireHandle = old;
        _retireSource = _curSource;
      }
      _curHandle = handle;
      _curSource = src;
    } catch (e) {
      if (kDebugMode) debugPrint('[GAPLESS] soloud playback unavailable: $e');
    }
  }

  Future<void> _disposeRetiring() async {
    final handle = _retireHandle;
    final source = _retireSource;
    _retireHandle = null;
    _retireSource = null;
    if (handle != null) {
      try {
        await _soloud.stop(handle);
      } catch (_) {}
    }
    if (source != null) {
      try {
        await _soloud.disposeSource(source);
      } catch (_) {}
    }
  }

  Future<void> _stopSoloud() async {
    await _disposeRetiring();
    final handle = _curHandle;
    final source = _curSource;
    _curHandle = null;
    _curSource = null;
    if (handle != null) {
      try {
        await _soloud.stop(handle);
      } catch (_) {}
    }
    if (source != null) {
      try {
        await _soloud.disposeSource(source);
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // audioplayers fallback — the original two-player swap (loop via ReleaseMode).
  // ---------------------------------------------------------------------------
  Future<void> _playLoopAudioplayers(
    Uint8List wav, {
    required Duration position,
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

  Future<void> stop() => _enqueue(_stop);

  Future<void> _stop() async {
    if (_soloudReady) {
      await _stopSoloud();
    }
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
  Future<void> pause() => _enqueue(_pause);

  Future<void> _pause() async {
    if (_disposed) return;
    if (_soloudReady) {
      if (_curHandle case final h?) {
        try {
          _soloud.setPause(h, true);
        } catch (e) {
          if (kDebugMode) debugPrint('[GAPLESS] soloud pause unavailable: $e');
        }
      }
      return;
    }
    try {
      await _players[_active]?.pause();
    } catch (e) {
      if (kDebugMode) debugPrint('[GAPLESS] pause unavailable: $e');
    }
  }

  /// Resumes a [pause]d loop from where it stopped.
  Future<void> resume() => _enqueue(_resume);

  Future<void> _resume() async {
    if (_disposed) return;
    if (_soloudReady) {
      if (_curHandle case final h?) {
        try {
          _soloud.setPause(h, false);
        } catch (e) {
          if (kDebugMode) debugPrint('[GAPLESS] soloud resume unavailable: $e');
        }
      }
      return;
    }
    try {
      await _players[_active]?.resume();
    } catch (e) {
      if (kDebugMode) debugPrint('[GAPLESS] resume unavailable: $e');
    }
  }

  void dispose() {
    _disposed = true;
    // Best-effort teardown of SoLoud sources (leave the shared engine warm).
    if (_soloudReady) {
      for (final source in [_curSource, _retireSource]) {
        if (source != null) {
          try {
            _soloud.disposeSource(source);
          } catch (_) {}
        }
      }
    }
    _curSource = null;
    _curHandle = null;
    _retireSource = null;
    _retireHandle = null;
    for (final p in _players) {
      p?.dispose();
    }
    _players[0] = null;
    _players[1] = null;
  }
}
