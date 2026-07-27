// B5 — the spectrogram as a picture.
//
// `spectrogram.dart` could always compute one; nothing outside the app could
// look at it. A picture answers questions no number does — where the hum sits,
// which band the hiss is in, whether a filter did what its parameters claimed —
// so the assertions here are about the PICTURE being readable: the right pixel
// is bright, the wrong ones are not, and the axes point the way everyone draws
// them.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/spectrogram_png.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const int _sr = 44100;

Float64List _tone(double hz, {int ms = 500, double amp = 0.7}) {
  final n = ms * _sr ~/ 1000;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amp * math.sin(2 * math.pi * hz * i / _sr);
  }
  return out;
}

/// Perceived brightness of a pixel, 0..1.
double _brightness(img.Image image, int x, int y) {
  final p = image.getPixel(x, y);
  return (p.r + p.g + p.b) / (3 * 255);
}

img.Image _render(
  Float64List pcm, {
  int height = 256,
  double? maxHz,
  SpectrogramPalette palette = SpectrogramPalette.heat,
}) =>
    img.decodePng(
      pcmToSpectrogramPng(
        pcm,
        sampleRate: _sr,
        height: height,
        maxHz: maxHz,
        palette: palette,
      ),
    )!;

void main() {
  test('it is a real PNG of the requested height', () {
    final image = _render(_tone(440), height: 200);
    expect(image.height, 200);
    expect(image.width, greaterThan(10));
  });

  test('the bright row is where the tone actually is', () {
    // The whole point: a 1 kHz tone in a picture cropped at 4 kHz must light up
    // a quarter of the way up, not somewhere else.
    const maxHz = 4000.0;
    const height = 300;
    final image = _render(_tone(1000), height: height, maxHz: maxHz);

    // Brightest row in a column from the middle of the tone.
    final x = image.width ~/ 2;
    var brightest = 0;
    var best = -1.0;
    for (var y = 0; y < image.height; y++) {
      final b = _brightness(image, x, y);
      if (b > best) {
        best = b;
        brightest = y;
      }
    }
    // Row 0 is the TOP, and frequency runs bottom-to-top, so 1 kHz of 4 kHz
    // should sit three quarters of the way DOWN the image.
    final expected = height - (1000 / maxHz * height).round();
    expect(brightest, closeTo(expected, height * 0.06));
    expect(best, greaterThan(0.5), reason: 'the tone should be bright');
  });

  test('frequency runs bottom-to-top, the way everyone draws it', () {
    // A low tone and a high one: the low one must be lower in the picture.
    const maxHz = 4000.0;
    int brightestRow(double hz) {
      final image = _render(_tone(hz), maxHz: maxHz);
      final x = image.width ~/ 2;
      var row = 0;
      var best = -1.0;
      for (var y = 0; y < image.height; y++) {
        final b = _brightness(image, x, y);
        if (b > best) {
          best = b;
          row = y;
        }
      }
      return row;
    }

    // Larger row index = further down = lower frequency.
    expect(brightestRow(300), greaterThan(brightestRow(3000)));
  });

  test('silence is dark and a tone is not', () {
    final silent = _render(Float64List(_sr ~/ 2));
    var brightestSilent = 0.0;
    for (var x = 0; x < silent.width; x++) {
      for (var y = 0; y < silent.height; y++) {
        brightestSilent = math.max(brightestSilent, _brightness(silent, x, y));
      }
    }
    expect(brightestSilent, lessThan(0.1));

    final loud = _render(_tone(1000));
    var brightestLoud = 0.0;
    for (var y = 0; y < loud.height; y++) {
      brightestLoud =
          math.max(brightestLoud, _brightness(loud, loud.width ~/ 2, y));
    }
    expect(brightestLoud, greaterThan(0.5));
  });

  test('time runs left to right', () {
    // Silence, then a tone: the left half must be darker than the right.
    final pcm = Float64List.fromList([
      ...Float64List(_sr ~/ 2),
      ..._tone(1000),
    ]);
    final image = _render(pcm, height: 128);
    double columnEnergy(int x) {
      var sum = 0.0;
      for (var y = 0; y < image.height; y++) {
        sum += _brightness(image, x, y);
      }
      return sum;
    }

    expect(
      columnEnergy(image.width ~/ 8),
      lessThan(columnEnergy(image.width * 7 ~/ 8)),
    );
  });

  test('cropping with maxHz keeps the interesting part', () {
    // A full-spectrum plot spends three quarters of its height on air; cropping
    // is what makes the picture usable, so the crop has to actually move things.
    final wide = _render(_tone(1000));
    final cropped = _render(_tone(1000), maxHz: 2000);
    int brightestRow(img.Image image) {
      final x = image.width ~/ 2;
      var row = 0;
      var best = -1.0;
      for (var y = 0; y < image.height; y++) {
        final b = _brightness(image, x, y);
        if (b > best) {
          best = b;
          row = y;
        }
      }
      return row;
    }

    // In the cropped picture the same tone sits much higher up the frame.
    expect(brightestRow(cropped), lessThan(brightestRow(wide)));
  });

  test('greyscale is grey', () {
    final image = _render(_tone(1000), palette: SpectrogramPalette.grey);
    for (var x = 0; x < image.width; x += 7) {
      for (var y = 0; y < image.height; y += 7) {
        final p = image.getPixel(x, y);
        expect(p.r, p.g);
        expect(p.g, p.b);
      }
    }
  });

  test('empty audio yields a valid image rather than a crash', () {
    final png = pcmToSpectrogramPng(Float64List(0), sampleRate: _sr);
    expect(img.decodePng(png), isNotNull);
  });
}
