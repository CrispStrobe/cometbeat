// lib/core/audio/streaming_analyzer.dart
//
// The pure-Dart windowing/buffering core shared by the live mic service and the
// command-line tool. Feed it PCM (or float) samples in arbitrary-sized chunks;
// it slides a fixed analysis window across the stream (advancing by a hop) and
// returns one [AnalyzerFrame] per completed window — pitch always, chord when a
// [ChordDetector] is supplied. No plugins, no Flutter: this is what makes the
// same detection testable headlessly, over a WAV file, or over stdin.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';

/// One analysed window.
class AnalyzerFrame {
  const AnalyzerFrame({
    required this.startSample,
    required this.sampleRate,
    required this.pitch,
    required this.chord,
  });

  /// Absolute index (in the overall stream) of this window's first sample.
  final int startSample;
  final int sampleRate;

  final PitchReading pitch;

  /// Null unless the analyzer was built with a [ChordDetector].
  final ChordReading? chord;

  /// Seconds from the start of the stream to this window's start.
  double get timeSeconds => startSample / sampleRate;
}

class StreamingAudioAnalyzer {
  StreamingAudioAnalyzer({
    required this.detector,
    this.chordDetector,
    int? hop,
  }) : hop = hop ?? _defaultHop(detector, chordDetector);

  final PitchDetector detector;
  final ChordDetector? chordDetector;

  /// Samples to advance between successive windows (< [windowSize] = overlap).
  final int hop;

  int get sampleRate => detector.sampleRate;

  /// The window fits whichever detector needs the most samples.
  int get windowSize =>
      max(detector.windowSize, chordDetector?.windowSize ?? 0);

  static int _defaultHop(PitchDetector d, ChordDetector? c) =>
      max(d.windowSize, c?.windowSize ?? 0) ~/ 2;

  final List<double> _buffer = <double>[];

  /// Absolute stream index of `_buffer[0]` — i.e. how many samples have already
  /// been consumed off the front. Drives frame timestamps.
  int _streamPos = 0;

  /// Feed normalized float samples ([-1, 1]); returns any windows completed.
  List<AnalyzerFrame> addSamples(List<double> samples) {
    _buffer.addAll(samples);
    final frames = <AnalyzerFrame>[];
    final w = windowSize;
    while (_buffer.length >= w) {
      final window = Float64List(w);
      for (var i = 0; i < w; i++) {
        window[i] = _buffer[i];
      }
      frames.add(
        AnalyzerFrame(
          startSample: _streamPos,
          sampleRate: sampleRate,
          pitch: detector.analyze(window),
          chord: chordDetector?.analyze(window),
        ),
      );
      _buffer.removeRange(0, hop);
      _streamPos += hop;
    }
    return frames;
  }

  /// Feed raw PCM16 little-endian mono bytes.
  List<AnalyzerFrame> addPcm16(Uint8List bytes) =>
      addSamples(pcm16ToFloat(bytes));

  /// Drop buffered audio (e.g. on stop) without resetting the stream clock.
  void clearBuffer() => _buffer.clear();

  /// Reset everything, including the timestamp origin.
  void reset() {
    _buffer.clear();
    _streamPos = 0;
  }
}
