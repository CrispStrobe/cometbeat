// lib/core/services/band_stream_player.dart
//
// BB-T1/BB-U3's output: the band's windows played back to back, one stream per
// role.
//
// `GaplessLoopPlayer` loops ONE buffer; the backing band arrives as a run of
// windows that must butt up against each other with no gap. SoLoud's buffer
// stream does exactly that — data is appended while it plays and the mixer
// reads straight across the joins — so the seams are as exact as the windows
// (which `chart_render_cache.dart` makes sample-identical to a whole render).
//
// Why one stream PER ROLE (comp, bass, drums) rather than one premixed: a
// role's volume is then a voice volume — mute, level and solo are instant and
// touch nothing already rendered or queued (BB-U3's "role mute is instant and
// does not re-render"). The streams carry float samples already scaled to
// their place in the mix, and SoLoud sums voices in float before its output
// clipper, which is the same sum-then-clip the whole-piece mix does.
//
// The three start PAUSED in one voice group and are released together once the
// first window is queued on all of them, so they cannot drift apart at the
// start.
//
// Same guarded ethos as the gapless player: audio is juice, never a
// requirement. [start] returns false whenever SoLoud cannot come up (a plain
// `flutter_test`, an unsupported platform), and the caller falls back to the
// whole-render path it always had.

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

class BandStreamPlayer {
  SoLoud get _soloud => SoLoud.instance;

  bool _tried = false;
  bool _ready = false;
  final List<AudioSource> _sources = [];
  final List<SoundHandle> _handles = [];
  SoundHandle? _group;
  bool _released = false;

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

  /// Opens [voices] mono float streams at [sampleRate], paused until the first
  /// [add]. False when streaming is unavailable here.
  Future<bool> start(int sampleRate, {int voices = 3}) async {
    await stop();
    if (!await _ensure()) return false;
    try {
      for (var v = 0; v < voices; v++) {
        final source = _soloud.setBufferStream(
          sampleRate: sampleRate,
          format: BufferType.f32le,
          bufferingType: BufferingType.released,
          // A window is several seconds; half a second of cushion is plenty
          // and keeps the first note close to the first window landing.
          bufferingTimeNeeds: 0.5,
          // Only the first voice reports, so the clock pauses once, not thrice.
          onBuffering: v == 0
              ? (buffering, _, __) => onBuffering?.call(buffering)
              : null,
        );
        _sources.add(source);
        _handles.add(await _soloud.play(source, paused: true));
      }
      final group = _soloud.createVoiceGroup();
      _soloud.addVoicesToGroup(group, _handles);
      _group = group;
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[BAND STREAM] start failed: $e');
      await stop();
      return false;
    }
  }

  /// Appends one window: one buffer per voice, in voice order.
  void add(List<Float32List> perVoice) {
    try {
      for (var v = 0; v < perVoice.length && v < _sources.length; v++) {
        final data = perVoice[v];
        _soloud.addAudioDataStream(
          _sources[v],
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      }
      final group = _group;
      if (!_released && group != null) {
        _soloud.setPause(group, false); // all voices start on the same frame
        _released = true;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BAND STREAM] add failed: $e');
    }
  }

  /// Sets voice [voice]'s volume (0 = muted). Instant; nothing re-renders.
  void setVolume(int voice, double volume) {
    if (voice < 0 || voice >= _handles.length) return;
    try {
      _soloud.setVolume(_handles[voice], volume);
    } catch (_) {}
  }

  /// Sets voice [voice]'s stereo position (−1 left … 1 right). Instant.
  void setPan(int voice, double pan) {
    if (voice < 0 || voice >= _handles.length) return;
    try {
      _soloud.setPan(_handles[voice], pan);
    } catch (_) {}
  }

  /// No more windows: the streams play out what they have and end.
  void end() {
    for (final source in _sources) {
      try {
        _soloud.setDataIsEnded(source);
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    final handles = [..._handles];
    final sources = [..._sources];
    final group = _group;
    _handles.clear();
    _sources.clear();
    _group = null;
    _released = false;
    try {
      for (final h in handles) {
        await _soloud.stop(h);
      }
      for (final s in sources) {
        await _soloud.disposeSource(s);
      }
      if (group != null) _soloud.destroyVoiceGroup(group);
    } catch (_) {}
  }
}
