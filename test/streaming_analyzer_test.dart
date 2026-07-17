// test/streaming_analyzer_test.dart
//
// Exercises the CLI/mic-shared streaming path: WAV read-back, chunk-boundary
// invariance, and note tracking over a rendered sequence. This is the headless
// stand-in for "real audio streaming" — the same code the CLI runs on a file
// or on live stdin.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/streaming_analyzer.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _toMono(Int16List pcm) {
  final out = Float64List(pcm.length);
  for (var i = 0; i < pcm.length; i++) {
    out[i] = pcm[i] / 32768.0;
  }
  return out;
}

void main() {
  test('WAV round-trips through the writer/reader and still detects pitch', () {
    // synth.dart writes it; wav_io reads it back — the real file path.
    final wavBytes0 = renderWav([
      (freqs: [midiToFrequency(57)], ms: 800), // A3 = 220 Hz
    ]);
    final wav = readWavPcm16(Uint8List.fromList(wavBytes0));
    expect(wav.sampleRate, kSampleRate);
    expect(wav.channels, 1);

    final mono = wavToMonoFloat(wav);
    final analyzer = StreamingAudioAnalyzer(detector: PitchDetector());
    final frames = analyzer.addSamples(mono);
    final voiced = frames.where((f) => f.pitch.hasPitch).toList();
    expect(voiced, isNotEmpty);
    // The steady middle of the note should read A3.
    expect(voiced[voiced.length ~/ 2].pitch.noteName, 'A3');
  });

  test('chunk size does not change the result (boundary invariance)', () {
    final pcm = renderSegments([
      (freqs: [midiToFrequency(45)], ms: 500), // A2
      (freqs: [midiToFrequency(57)], ms: 500), // A3
    ]);
    final mono = _toMono(pcm);

    List<AnalyzerFrame> run(int chunk) {
      final a = StreamingAudioAnalyzer(detector: PitchDetector());
      final out = <AnalyzerFrame>[];
      for (var i = 0; i < mono.length; i += chunk) {
        final end = (i + chunk < mono.length) ? i + chunk : mono.length;
        out.addAll(a.addSamples(mono.sublist(i, end)));
      }
      return out;
    }

    final whole = run(mono.length); // one giant chunk
    final tiny = run(97); // awkward chunk size, straddles windows
    expect(tiny.length, whole.length);
    for (var i = 0; i < whole.length; i++) {
      expect(tiny[i].startSample, whole[i].startSample);
      expect(tiny[i].pitch.frequency, closeTo(whole[i].pitch.frequency, 1e-9));
    }
  });

  test('tracks a note change over the stream with rising timestamps', () {
    final pcm = renderSegments([
      (freqs: [midiToFrequency(50)], ms: 600), // D3
      (freqs: [midiToFrequency(64)], ms: 600), // E4
    ]);
    final analyzer = StreamingAudioAnalyzer(detector: PitchDetector());
    final frames = analyzer.addSamples(_toMono(pcm));

    final voiced = frames.where((f) => f.pitch.hasPitch).toList();
    expect(voiced.first.pitch.noteName, 'D3');
    expect(voiced.last.pitch.noteName, 'E4');
    // Timestamps are monotonic and cover roughly the whole 1.2 s.
    for (var i = 1; i < frames.length; i++) {
      expect(frames[i].timeSeconds, greaterThan(frames[i - 1].timeSeconds));
    }
    expect(frames.last.timeSeconds, greaterThan(1.0));
  });

  test('reader rejects non-PCM / malformed input', () {
    expect(() => readWavPcm16(Uint8List(10)), throwsFormatException);
  });
}
