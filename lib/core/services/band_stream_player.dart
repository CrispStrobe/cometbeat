// lib/core/services/band_stream_player.dart
//
// BB-T1's output: PCM windows played back to back as one continuous stream.
//
// `GaplessLoopPlayer` loops ONE buffer; the backing band arrives as a run of
// windows that must butt up against each other with no gap. SoLoud's buffer
// stream does exactly that — data is appended while it plays, and the mixer
// reads straight across the joins — so the seams are as exact as the windows
// themselves (which `chart_render_cache.dart` makes sample-identical to a
// whole render).
//
// Same guarded ethos as the gapless player: audio is juice, never a
// requirement. [start] returns false whenever SoLoud cannot come up (a plain
// `flutter_test`, an unsupported platform), and the caller falls back to the
// whole-render path it always had.

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

class BandStreamPlayer {
  SoLoud get _soloud => SoLoud.instance;

  bool _tried = false;
  bool _ready = false;
  AudioSource? _source;
  SoundHandle? _handle;

  /// Called with true when playback stalls waiting for data, false when it
  /// resumes — so a caller's clock can pause with it.
  void Function(bool buffering)? onBuffering;

  Future<bool> _ensure() async {
    if (_ready) return true;
    if (_tried) return false;
    _tried = true;
    try {
      if (!_soloud.isInitialized) await _soloud.init();
      _ready = _soloud.isInitialized;
    } catch (e) {
      if (kDebugMode) debugPrint('[BAND STREAM] soloud unavailable: $e');
      _ready = false;
    }
    return _ready;
  }

  /// Opens a mono PCM16 stream at [sampleRate] and starts it (silent until the
  /// first [add]). False when streaming is unavailable here.
  Future<bool> start(int sampleRate) async {
    await stop();
    if (!await _ensure()) return false;
    try {
      final source = _soloud.setBufferStream(
        sampleRate: sampleRate,
        bufferingType: BufferingType.released,
        // A window is several seconds; half a second of cushion is plenty and
        // keeps the first note close to the first window landing.
        bufferingTimeNeeds: 0.5,
        onBuffering: (buffering, _, __) => onBuffering?.call(buffering),
      );
      _source = source;
      _handle = await _soloud.play(source);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[BAND STREAM] start failed: $e');
      await stop();
      return false;
    }
  }

  /// Appends one window of samples.
  void add(Int16List pcm) {
    final source = _source;
    if (source == null) return;
    try {
      _soloud.addAudioDataStream(
        source,
        pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[BAND STREAM] add failed: $e');
    }
  }

  /// No more windows: the stream plays out what it has and ends.
  void end() {
    final source = _source;
    if (source == null) return;
    try {
      _soloud.setDataIsEnded(source);
    } catch (_) {}
  }

  Future<void> stop() async {
    final handle = _handle;
    final source = _source;
    _handle = null;
    _source = null;
    try {
      if (handle != null) await _soloud.stop(handle);
      if (source != null) await _soloud.disposeSource(source);
    } catch (_) {}
  }
}
