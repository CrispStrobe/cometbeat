// lib/core/audio/streaming_mixer.dart
//
// The pure, testable core of the Loop Mixer's streaming FX path (§C-1a). A real
// audio callback pulls fixed-size blocks; the [StreamingMixer] serves them from
// the looping mix PCM through the live effect chain (today a [StreamingFilter]),
// wrapping the play position seamlessly. Flutter-free — the platform sink (the
// one device-only leaf) plugs in behind [StreamingAudioSink], so this whole
// pipeline unit-tests without any audio hardware.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/streaming_filter.dart';

/// Where effected audio blocks go — a real-time output callback in production,
/// a [BufferedSink] in tests.
abstract interface class StreamingAudioSink {
  /// Consumes one block of mono samples (−1..1). Must not retain [block].
  void write(Float64List block);
}

/// A sink that concatenates every block — the headless test double.
class BufferedSink implements StreamingAudioSink {
  final List<double> _samples = [];

  @override
  void write(Float64List block) => _samples.addAll(block);

  /// Everything written so far, in order.
  Float64List get samples => Float64List.fromList(_samples);

  int get length => _samples.length;

  void clear() => _samples.clear();
}

/// Serves a looping mono mix through the live effect chain, block by block.
///
/// The [filter] is live-tunable ([setCutoff]) and its state carries across
/// [pull]s, so sweeping while streaming never clicks — the same seam-continuity
/// the offline sends rely on, but per audio block instead of per loop.
class StreamingMixer {
  StreamingMixer(this._loop, {double sampleRate = 44100})
      : filter = StreamingFilter(sampleRate: sampleRate) {
    if (_loop.isEmpty) {
      throw ArgumentError.value(_loop, 'loop', 'must be non-empty');
    }
  }

  Float64List _loop;
  int _pos = 0;

  /// The live master filter on the stream.
  final StreamingFilter filter;

  int get loopLength => _loop.length;

  /// The current play offset into the loop (0..[loopLength]).
  int get position => _pos;

  /// Live-sets the master filter cutoff (−1 low-pass … 0 off … +1 high-pass).
  void setCutoff(double value) => filter.setCutoff(value);

  /// Swaps the looping source (e.g. after a groove change). By default the play
  /// phase is preserved (mapped into the new length) so a seam scheduler stays
  /// aligned; the filter state is untouched.
  void setLoop(Float64List loop, {bool preservePhase = true}) {
    if (loop.isEmpty) {
      throw ArgumentError.value(loop, 'loop', 'must be non-empty');
    }
    _loop = loop;
    _pos = preservePhase ? _pos % loop.length : 0;
  }

  /// Pulls the next [frames] samples from the loop through the effect chain,
  /// advancing and wrapping the play position.
  Float64List pull(int frames) {
    final raw = Float64List(frames);
    for (var i = 0; i < frames; i++) {
      raw[i] = _loop[_pos];
      _pos++;
      if (_pos >= _loop.length) _pos = 0;
    }
    return filter.process(raw);
  }

  /// Streams [frames] samples into [sink] in [blockSize] chunks — the shape a
  /// real audio callback pulls. Continuity holds across blocks.
  void stream(StreamingAudioSink sink, int frames, {int blockSize = 512}) {
    if (blockSize < 1) throw ArgumentError.value(blockSize, 'blockSize');
    var remaining = frames;
    while (remaining > 0) {
      final n = remaining < blockSize ? remaining : blockSize;
      sink.write(pull(n));
      remaining -= n;
    }
  }
}
