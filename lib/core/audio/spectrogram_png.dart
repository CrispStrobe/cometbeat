// Render a [Spectrogram] to a PNG — so you can SEE a recording.
//
// `spectrogram.dart` computes the picture but nothing outside the app could look
// at it, which made the most diagnostic view in audio unavailable to the CLI and
// to tests. A picture answers questions no number does: where the hum is, which
// band the hiss lives in, whether a "de-clicked" file still has clicks, whether
// a filter did what its parameters claimed.
//
// Kept out of `spectrogram.dart` on purpose: that file is pure computation with
// no dependencies, and this one pulls in an image encoder. A caller that only
// wants the numbers should not pay for PNG.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/spectrogram.dart';
import 'package:image/image.dart' as img;

/// How loud maps to colour.
enum SpectrogramPalette {
  /// Black → blue → red → yellow → white. Reads as heat, and the eye picks out
  /// far more detail in the quiet end than a plain greyscale ramp gives.
  heat,

  /// Black → white. Honest and boring; better for print and for anyone who
  /// finds a colour ramp misleading about how much louder "yellow" really is.
  grey,
}

/// Paint [spectrogram] as a PNG: time left→right, frequency bottom→top.
///
/// Frequency runs bottom-to-top because that is how everyone draws it and how
/// every instrument is laid out; the computed data is bin-indexed from DC, so
/// the row is flipped here rather than in the analysis.
///
/// [maxHz] crops the top of the picture. It defaults to the whole spectrum, but
/// music lives in the bottom few kHz and a full 22 kHz plot spends three
/// quarters of its height on air — pass 5000 and the interesting part fills the
/// frame.
///
/// [height] resamples the frequency axis to a fixed number of pixels so a long
/// FFT does not produce an unusably tall image; each output row takes the LOUDEST
/// bin it covers, because a peak that survives is the thing being looked for and
/// averaging would hide a narrow tone among its quiet neighbours.
Uint8List spectrogramToPng(
  Spectrogram spectrogram, {
  int? height,
  double? maxHz,
  SpectrogramPalette palette = SpectrogramPalette.heat,
}) {
  final frames = spectrogram.frames;
  if (frames.isEmpty) {
    return img.encodePng(img.Image(width: 1, height: 1));
  }
  final topBin = maxHz == null
      ? spectrogram.bins
      : (spectrogram.binFor(maxHz) + 1).clamp(1, spectrogram.bins);
  final rows = (height ?? topBin).clamp(1, 4096);
  final image = img.Image(width: frames.length, height: rows);

  final floor = spectrogram.floorDb;
  for (var x = 0; x < frames.length; x++) {
    final frame = frames[x];
    for (var y = 0; y < rows; y++) {
      // Row 0 is the BOTTOM of the picture, so the axis reads the usual way up.
      final fromBin = (y * topBin / rows).floor();
      final toBin = math.max(fromBin + 1, ((y + 1) * topBin / rows).floor());
      var loudest = floor;
      for (var b = fromBin; b < toBin && b < frame.length; b++) {
        if (frame[b] > loudest) loudest = frame[b];
      }
      final t = ((loudest - floor) / (0 - floor)).clamp(0.0, 1.0);
      final colour = _colourFor(t, palette);
      image.setPixelRgb(x, rows - 1 - y, colour.$1, colour.$2, colour.$3);
    }
  }
  return img.encodePng(image);
}

/// Compute and paint in one call — what a CLI or a test actually wants.
Uint8List pcmToSpectrogramPng(
  Float64List pcm, {
  required int sampleRate,
  int fftSize = 1024,
  int? height,
  double? maxHz,
  SpectrogramPalette palette = SpectrogramPalette.heat,
}) =>
    spectrogramToPng(
      computeSpectrogram(pcm, sampleRate: sampleRate, fftSize: fftSize),
      height: height,
      maxHz: maxHz,
      palette: palette,
    );

/// [t] in 0..1 (quiet..loud) as an RGB triple.
(int, int, int) _colourFor(double t, SpectrogramPalette palette) {
  if (palette == SpectrogramPalette.grey) {
    final v = (t * 255).round().clamp(0, 255);
    return (v, v, v);
  }
  // Four linear segments through black-blue-red-yellow-white. Piecewise rather
  // than a formula because the segment boundaries are where the eye's
  // sensitivity actually changes, and a smooth analytic ramp puts most of its
  // resolution where there is nothing to see.
  int lerp(double a, double b, double u) =>
      (a + (b - a) * u).round().clamp(0, 255);
  if (t < 0.25) {
    final u = t / 0.25;
    return (0, 0, lerp(0, 160, u));
  }
  if (t < 0.5) {
    final u = (t - 0.25) / 0.25;
    return (lerp(0, 200, u), 0, lerp(160, 80, u));
  }
  if (t < 0.75) {
    final u = (t - 0.5) / 0.25;
    return (lerp(200, 255, u), lerp(0, 200, u), lerp(80, 0, u));
  }
  final u = (t - 0.75) / 0.25;
  return (255, lerp(200, 255, u), lerp(0, 255, u));
}
