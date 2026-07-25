// O15 — the STFT behind the spectrogram view. The assertions are about the
// PHYSICS, not the plumbing: a tone must land in its own bin at the right
// level, a sweep must move over time, and silence must floor rather than
// return -infinity (which would paint as a black hole).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/spectrogram.dart';
import 'package:flutter_test/flutter_test.dart';

const _rate = 44100;

Float64List _tone(double freq, int samples, {double amp = 1.0}) =>
    Float64List.fromList([
      for (var i = 0; i < samples; i++)
        amp * math.sin(2 * math.pi * freq * i / _rate),
    ]);

/// The loudest bin of a frame.
int _peakBin(Float64List frame) {
  var best = 0;
  for (var i = 1; i < frame.length; i++) {
    if (frame[i] > frame[best]) best = i;
  }
  return best;
}

void main() {
  test('a tone lands in the bin for its own frequency', () {
    for (final freq in [220.0, 1000.0, 5000.0]) {
      final s = computeSpectrogram(_tone(freq, 8192), sampleRate: _rate);
      final bin = _peakBin(s.frames[2]); // a fully-populated middle frame
      expect(
        s.frequencyOf(bin),
        closeTo(freq, s.binHz),
        reason: '$freq Hz',
      );
      expect(s.binFor(freq), bin, reason: '$freq Hz round-trip');
    }
  });

  test('a full-scale sine reads about 0 dBFS in its bin', () {
    final s = computeSpectrogram(_tone(1000, 8192), sampleRate: _rate);
    final frame = s.frames[2];
    expect(frame[_peakBin(frame)], closeTo(0, 1.5));
  });

  test('halving the amplitude drops the peak by ~6 dB', () {
    final loud = computeSpectrogram(_tone(1000, 8192), sampleRate: _rate);
    final quiet = computeSpectrogram(
      _tone(1000, 8192, amp: 0.5),
      sampleRate: _rate,
    );
    final a = loud.frames[2][_peakBin(loud.frames[2])];
    final b = quiet.frames[2][_peakBin(quiet.frames[2])];
    expect(a - b, closeTo(6.02, 0.3));
  });

  test('energy is concentrated, not smeared across the spectrum', () {
    // This is what the Hann window buys: without it a tone leaks everywhere.
    final s = computeSpectrogram(_tone(1000, 8192), sampleRate: _rate);
    final frame = s.frames[2];
    final peak = _peakBin(frame);
    // A bin an octave away must be far quieter than the peak.
    expect(frame[s.binFor(2000)], lessThan(frame[peak] - 40));
    expect(frame[s.binFor(200)], lessThan(frame[peak] - 40));
  });

  test('silence floors instead of returning -infinity', () {
    final s = computeSpectrogram(Float64List(4096), sampleRate: _rate);
    for (final frame in s.frames) {
      for (final v in frame) {
        expect(v, s.floorDb);
        expect(v.isFinite, isTrue);
      }
    }
  });

  test('a rising sweep moves up the spectrum over time', () {
    // 200 Hz for the first half, 4000 Hz for the second.
    final pcm = Float64List.fromList([
      ..._tone(200, 8192),
      ..._tone(4000, 8192),
    ]);
    final s = computeSpectrogram(pcm, sampleRate: _rate);
    final early = _peakBin(s.frames[2]);
    final late = _peakBin(s.frames[s.frames.length - 4]);
    expect(s.frequencyOf(early), closeTo(200, s.binHz * 2));
    expect(s.frequencyOf(late), closeTo(4000, s.binHz * 2));
    expect(late, greaterThan(early));
  });

  test('geometry: frame count, bin count and timing line up', () {
    final s = computeSpectrogram(
      _tone(440, _rate), // exactly one second
      sampleRate: _rate,
      hop: 512,
    );
    expect(s.bins, 512);
    expect(s.binHz, closeTo(_rate / 1024, 1e-9));
    expect(s.frameMs, closeTo(512 * 1000 / _rate, 1e-9));
    expect(s.frames.length, (_rate / 512).ceil());
    for (final frame in s.frames) {
      expect(frame, hasLength(512));
    }
  });

  test('an empty buffer yields no frames rather than throwing', () {
    final s = computeSpectrogram(Float64List(0), sampleRate: _rate);
    expect(s.frames, isEmpty);
    expect(s.bins, 512);
  });

  test('a buffer shorter than one window still produces a frame', () {
    final s = computeSpectrogram(_tone(1000, 100), sampleRate: _rate);
    expect(s.frames, hasLength(1)); // zero-padded
    expect(s.frames.single, hasLength(512));
  });
}
