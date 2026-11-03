// lib/features/games/practice/stem_player.dart
//
// Plays separated stems together, each on its own voice, so muting, soloing and
// levels are instant (a voice volume — nothing re-renders). Built on
// [BandStreamPlayer]'s SoLoud buffer streams: the stems are fed a few seconds
// ahead of the play position rather than all at once, so a four-minute song
// does not sit in the mixer twice.
//
// Seeking restarts the streams at the new frame — a buffer stream cannot be
// rewound — which is instant at practice granularity (whole seconds).

import 'dart:async';
import 'dart:math' as math;

import 'package:comet_beat/core/audio/practice/practice_mix.dart';
import 'package:comet_beat/core/audio/transcription/separated_stem.dart';
import 'package:comet_beat/core/services/band_stream_player.dart';
import 'package:comet_beat/features/games/playalong/play_along_screen.dart'
    show PlayAlongAudioBacking;

class StemPlayer {
  StemPlayer(List<SeparatedStem> stems, {bool loop = false})
      : this.source(StemListSource(stems), loop: loop);

  /// Plays [source] — a loop region or a slowed song is rendered window by
  /// window as it is fed, never whole.
  StemPlayer.source(this.source, {this.loop = false})
      : _volumes = List.filled(source.count, 1);

  final StemSource source;

  /// Repeat the whole buffer seamlessly (a practice loop) instead of ending.
  final bool loop;
  final BandStreamPlayer _band = BandStreamPlayer();
  List<double> _volumes;

  Timer? _feeder;
  int _fedTo = 0;
  int _startFrame = 0;
  final Stopwatch _clock = Stopwatch();
  bool _playing = false;

  /// Seconds queued ahead of the play position.
  static const double _aheadSeconds = 6;

  int get sampleRate => source.sampleRate;
  int get frames => source.frames;
  Duration get length => Duration(microseconds: frames * 1000000 ~/ sampleRate);
  bool get playing => _playing;

  /// Where playback is (stopped: where it would resume). Looping, it wraps.
  Duration get position {
    final f = _startFrame + _clock.elapsedMicroseconds * sampleRate ~/ 1000000;
    final at = loop ? f % frames : math.min(f, frames);
    return Duration(microseconds: at * 1000000 ~/ sampleRate);
  }

  /// Applies [volumes] (one per stem, 0 = silent). Instant.
  void setVolumes(List<double> volumes) {
    _volumes = List.of(volumes);
    for (var i = 0; i < source.count && i < volumes.length; i++) {
      _band.setVolume(i, volumes[i]);
    }
  }

  /// Starts at [from] (default: the current position). False when audio
  /// streaming is unavailable here.
  Future<bool> play({Duration? from}) async {
    await _halt();
    final start = from == null
        ? _startFrame
        : (from.inMicroseconds * sampleRate ~/ 1000000).clamp(0, frames);
    _startFrame = start;
    if (start >= frames) return false;
    _band.onBuffering = (b) => b ? _clock.stop() : _clock.start();
    if (!await _band.start(sampleRate, voices: source.count, stereo: true)) {
      return false;
    }
    setVolumes(_volumes);
    _fedTo = start;
    _feed();
    _clock
      ..reset()
      ..start();
    _playing = true;
    _feeder = Timer.periodic(const Duration(milliseconds: 500), (_) => _feed());
    return true;
  }

  void _feed() {
    final playhead =
        _startFrame + _clock.elapsedMicroseconds * sampleRate ~/ 1000000;
    // [_fedTo] and the playhead count frames WITHOUT wrapping; a loop wraps
    // only where the windows are cut.
    final ahead = playhead + (_aheadSeconds * sampleRate).round();
    final want = loop ? ahead : math.min(frames, ahead);
    if (want <= _fedTo) {
      if (!loop && _fedTo >= frames) {
        _band.end();
        _feeder?.cancel();
        if (playhead >= frames) _playing = false;
      }
      return;
    }
    while (_fedTo < want) {
      final from = _fedTo % frames;
      final chunk = math.min(want - _fedTo, frames - from);
      _band.add([
        for (var i = 0; i < source.count; i++) source.window(i, from, chunk),
      ]);
      _fedTo += chunk;
    }
  }

  /// Stops and remembers the position for the next [play].
  Future<void> pause() async {
    final at = position;
    await _halt();
    _startFrame = at.inMicroseconds * sampleRate ~/ 1000000;
  }

  /// Stops and rewinds to the start.
  Future<void> stop() async {
    await _halt();
    _startFrame = 0;
  }

  Future<void> _halt() async {
    _feeder?.cancel();
    _feeder = null;
    _clock
      ..stop()
      ..reset();
    _playing = false;
    await _band.stop();
  }
}

/// The non-vocal stems as a [PlayAlongAudioBacking]: the learner's own song
/// minus the voice they are about to sing.
class StemBacking implements PlayAlongAudioBacking {
  StemBacking(List<SeparatedStem> stems) : _player = StemPlayer(stems);

  final StemPlayer _player;

  @override
  Future<void> start() async {
    await _player.play(from: Duration.zero);
  }

  @override
  Future<void> stop() => _player.stop();
}
