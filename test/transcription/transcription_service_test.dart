// N2 — the app-facing service. A synthesized WAV goes in, a crisp_notation Score
// comes out via the router → rhythm → engraver, with no neural engine injected
// (the web / no-model path). Also proves a forced/injected neural engine is
// honoured. Headless: no device, no file-picker, no ONNX.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/harmony.dart'
    show ChordEvent;
import 'package:comet_beat/core/audio/transcription/route.dart';
import 'package:comet_beat/core/audio/transcription/transcription_service.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _sr = 44100;
double _hz(int midi) => 440 * pow(2, (midi - 69) / 12).toDouble();

// A one-note-per-beat melody at 120 BPM, encoded as PCM16 WAV bytes.
Uint8List _wav(List<int> midis) {
  const beat = 0.5; // 120 BPM
  final noteN = (beat * 0.85 * _sr).round();
  final restN = (beat * 0.15 * _sr).round();
  final pcm = Int16List(midis.length * (noteN + restN));
  var off = 0;
  for (final m in midis) {
    final f = _hz(m);
    for (var i = 0; i < noteN; i++) {
      final env = min(1.0, min(i, noteN - i) / (0.01 * _sr));
      pcm[off + i] = (0.5 * env * sin(2 * pi * f * i / _sr) * 32767).round();
    }
    off += noteN + restN;
  }
  return wavBytes(pcm);
}

List<String> _steps(Score score) => [
      for (final m in score.measures)
        for (final e in m.elements)
          if (e is NoteElement) e.pitches.first.step.name.toUpperCase(),
    ];

void main() {
  test('a synth scale WAV transcribes to a Score (monophonic, no neural)',
      () async {
    const scale = [60, 62, 64, 65, 67];
    final r = await transcribeRecording(_wav(scale));

    expect(r.engine, TranscriptionEngine.monophonic);
    expect(r.score.measures, isNotEmpty);
    expect(r.notes, isNotEmpty);
    expect(r.bpm, greaterThan(90));
    expect(r.bpm, lessThan(150));
    // The engraved score reads the ascending scale.
    expect(_steps(r.score), ['C', 'D', 'E', 'F', 'G']);
  });

  test('an injected neural engine is used when the probe prefers it', () async {
    var called = false;
    Future<List<NoteEvent>> fakeNeural(Float64List mono, int sr) async {
      called = true;
      return [
        (midi: 60, onMs: 0, offMs: 500, confidence: 0.9),
        (midi: 64, onMs: 500, offMs: 1000, confidence: 0.9),
      ];
    }

    // A three-note chord stacked into one window → the probe prefers neural.
    final chord = Int16List(_sr);
    for (var i = 0; i < chord.length; i++) {
      final s = sin(2 * pi * _hz(60) * i / _sr) +
          sin(2 * pi * _hz(64) * i / _sr) +
          sin(2 * pi * _hz(67) * i / _sr);
      chord[i] = (s / 3 * 0.5 * 32767).round();
    }
    final r = await transcribeRecording(
      wavBytes(chord),
      neural: fakeNeural,
    );
    expect(called, isTrue);
    expect(r.engine, TranscriptionEngine.neural);
    expect(r.notes, hasLength(2));
  });

  test('a neural chord flows through to a chord note-head in the Score',
      () async {
    // A polyphonic transcriber returns a C-major triad struck together.
    Future<List<NoteEvent>> chordNeural(Float64List mono, int sr) async => [
          (midi: 60, onMs: 0, offMs: 500, confidence: 0.9),
          (midi: 64, onMs: 0, offMs: 500, confidence: 0.9),
          (midi: 67, onMs: 0, offMs: 500, confidence: 0.9),
        ];

    final chord = Int16List(_sr);
    for (var i = 0; i < chord.length; i++) {
      final s = sin(2 * pi * _hz(60) * i / _sr) +
          sin(2 * pi * _hz(64) * i / _sr) +
          sin(2 * pi * _hz(67) * i / _sr);
      chord[i] = (s / 3 * 0.5 * 32767).round();
    }
    final r = await transcribeRecording(wavBytes(chord), neural: chordNeural);
    final chords = [
      for (final m in r.score.measures)
        for (final e in m.elements)
          if (e is NoteElement) e.pitches.length,
    ];
    expect(chords, contains(3), reason: 'one 3-note chord note-head');
  });

  test('an injected chord estimator populates result.chords', () async {
    Future<List<ChordEvent>> fakeChords(Float64List m, int sr) async => const [
          (label: 'C', rootPc: 0, quality: 'maj', onMs: 0, offMs: 500),
          (label: 'G', rootPc: 7, quality: 'maj', onMs: 500, offMs: 1000),
        ];
    final r = await transcribeRecording(
      _wav(const [60, 62, 64]),
      chordEstimator: fakeChords,
    );
    expect(r.chords, hasLength(2));
    expect(r.chords.first.label, 'C');
  });

  test('empty / near-silent audio never throws, yields an empty score',
      () async {
    final r = await transcribeRecording(wavBytes(Int16List(_sr)));
    expect(r.notes, isEmpty);
    expect(r.score.measures, isEmpty);
  });
}
