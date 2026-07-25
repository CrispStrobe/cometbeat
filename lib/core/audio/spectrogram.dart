// lib/core/audio/spectrogram.dart
//
// Short-time Fourier transform → a spectrogram: what frequencies are present,
// and when. The waveform view answers "how loud"; this answers "how bright",
// which is what you actually need to spot a rumble, a whistle, a mains hum, or
// where one instrument stops and another starts.
//
// Reuses the radix-2 FFT already in chroma_analysis.dart. Pure Dart,
// deterministic, Flutter-free — the painter is a separate widget.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart' show fft;

/// A computed spectrogram: [frames] of magnitudes in dBFS, oldest first, each
/// holding [bins] values from DC up to the Nyquist frequency.
class Spectrogram {
  const Spectrogram({
    required this.frames,
    required this.fftSize,
    required this.hop,
    required this.sampleRate,
    required this.floorDb,
  });

  /// `frames[t][bin]` — dBFS, clamped at [floorDb] so silence has a finite
  /// value to paint instead of −infinity.
  final List<Float64List> frames;
  final int fftSize;
  final int hop;
  final int sampleRate;
  final double floorDb;

  /// Frequency bins per frame (DC…Nyquist).
  int get bins => fftSize ~/ 2;

  /// Width of one bin in Hz.
  double get binHz => sampleRate / fftSize;

  /// Time between frame starts, in ms.
  double get frameMs => hop * 1000 / sampleRate;

  /// The centre frequency of [bin].
  double frequencyOf(int bin) => bin * binHz;

  /// The bin [hz] falls in — the inverse of [frequencyOf], for assertions and
  /// for a cursor read-out.
  int binFor(double hz) => (hz / binHz).round().clamp(0, bins - 1);
}

/// STFT of [pcm]. [fftSize] must be a power of two; [hop] is how far the window
/// advances per frame (fftSize ~/ 4 gives the usual 75% overlap).
///
/// Each window is Hann-tapered — without it, the hard window edges smear every
/// tone across the whole spectrum and the picture turns to mush. Magnitudes are
/// normalised so a full-scale sine reads ≈0 dBFS in its own bin.
Spectrogram computeSpectrogram(
  Float64List pcm, {
  required int sampleRate,
  int fftSize = 1024,
  int? hop,
  double floorDb = -90,
}) {
  assert(fftSize > 1 && fftSize & (fftSize - 1) == 0, 'fftSize must be 2^n');
  final step = hop ?? fftSize ~/ 4;
  final bins = fftSize ~/ 2;
  final frames = <Float64List>[];
  if (pcm.isEmpty || step < 1) {
    return Spectrogram(
      frames: frames,
      fftSize: fftSize,
      hop: step,
      sampleRate: sampleRate,
      floorDb: floorDb,
    );
  }

  // Hann window, precomputed once.
  final window = Float64List(fftSize);
  for (var i = 0; i < fftSize; i++) {
    window[i] = 0.5 * (1 - math.cos(2 * math.pi * i / (fftSize - 1)));
  }
  // Coherent gain of the Hann window is 0.5, so undo it to keep dBFS honest.
  final scale = 2.0 / (fftSize * 0.5);

  final re = Float64List(fftSize);
  final im = Float64List(fftSize);
  for (var start = 0; start < pcm.length; start += step) {
    for (var i = 0; i < fftSize; i++) {
      final at = start + i;
      re[i] = at < pcm.length ? pcm[at] * window[i] : 0;
      im[i] = 0;
    }
    fft(re, im);
    final frame = Float64List(bins);
    for (var b = 0; b < bins; b++) {
      final mag = math.sqrt(re[b] * re[b] + im[b] * im[b]) * scale;
      frame[b] = mag <= 0
          ? floorDb
          : math.max(floorDb, 20 * math.log(mag) / math.ln10);
    }
    frames.add(frame);
  }

  return Spectrogram(
    frames: frames,
    fftSize: fftSize,
    hop: step,
    sampleRate: sampleRate,
    floorDb: floorDb,
  );
}
