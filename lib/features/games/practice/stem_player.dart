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
  StemPlayer(this.stems)
      : assert(stems.isNotEmpty),
        _volumes = List.filled(stems.length, 1);

  final List<SeparatedStem> stems;
  final BandStreamPlayer _band = BandStreamPlayer();
  List<double> _volumes;

  Timer? _feeder;
  int _fedTo = 0;
  int _startFrame = 0;
  final Stopwatch _clock = Stopwatch();
  bool _playing = false;

  /// Seconds queued ahead of the play position.
  static const double _aheadSeconds = 6;

  int get sampleRate => stems.first.sampleRate;
  int get frames => stems.map((s) => s.frames).reduce(math.min);
  Duration get length => Duration(microseconds: frames * 1000000 ~/ sampleRate);
  bool get playing => _playing;

  /// Where playback is (stopped: where it would resume).
  Duration get position {
    final f = _startFrame + _clock.elapsedMicroseconds * sampleRate ~/ 1000000;
    return Duration(
      microseconds: math.min(f, frames) * 1000000 ~/ sampleRate,
    );
  }

  /// Applies [volumes] (one per stem, 0 = silent). Instant.
  void setVolumes(List<double> volumes) {
    _volumes = List.of(volumes);
    for (var i = 0; i < stems.length && i < volumes.length; i++) {
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
    if (!await _band.start(sampleRate, voices: stems.length, stereo: true)) {
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
    final want =
        math.min(frames, playhead + (_aheadSeconds * sampleRate).round());
    if (want <= _fedTo) {
      if (_fedTo >= frames) {
        _band.end();
        _feeder?.cancel();
        if (playhead >= frames) _playing = false;
      }
      return;
    }
    _band.add([
      for (final s in stems) interleavedWindow(s, _fedTo, want - _fedTo),
    ]);
    _fedTo = want;
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
