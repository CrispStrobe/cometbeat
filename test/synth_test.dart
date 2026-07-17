import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('midiToFrequency hits the reference pitches', () {
    expect(midiToFrequency(69), closeTo(440.0, 0.001)); // A4
    expect(midiToFrequency(60), closeTo(261.63, 0.01)); // C4
    expect(midiToFrequency(81), closeTo(880.0, 0.001)); // A5
  });

  test('renderSegments produces the right sample count, normalized', () {
    final samples = renderSegments([
      (freqs: [440.0], ms: 100),
      (freqs: [440.0, 550.0, 660.0], ms: 200),
    ]);
    expect(samples.length, (300 * kSampleRate) ~/ 1000);

    var peak = 0;
    for (final s in samples) {
      if (s.abs() > peak) peak = s.abs();
    }
    expect(peak, greaterThan(20000)); // audible
    expect(peak, lessThanOrEqualTo((0.8 * 32767).ceil())); // no clipping
  });

  test('each instrument timbre renders a distinct waveform', () {
    const seg = [
      (freqs: [440.0], ms: 200),
    ];
    final piano = renderSegments(seg, timbre: timbreFor(Instrument.piano));
    final cello = renderSegments(seg, timbre: timbreFor(Instrument.cello));
    expect(piano.length, cello.length);
    // Different harmonics/decay → the samples must actually differ.
    var differences = 0;
    for (var i = 0; i < piano.length; i++) {
      if (piano[i] != cello[i]) differences++;
    }
    expect(differences, greaterThan(piano.length ~/ 2));
  });

  test('wavBytes writes a valid RIFF/WAVE header', () {
    final samples = Int16List.fromList(List.filled(1000, 1234));
    final wav = wavBytes(samples);

    expect(wav.length, 44 + 2000);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    final byteData = ByteData.sublistView(wav);
    expect(byteData.getUint32(24, Endian.little), kSampleRate);
    expect(byteData.getUint16(34, Endian.little), 16); // bits per sample
  });

  test('SFX renderers produce non-empty WAV data', () {
    for (final wav in [
      renderSfxCorrect(),
      renderSfxWrong(),
      renderSfxFanfare(),
    ]) {
      expect(wav.length, greaterThan(44));
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    }
  });
}
