// Analysing recorded audio FILES (not just live mic): analyzeRecording decodes
// a PCM16 WAV and runs the same pitch/chord detection over it, at the file's
// own sample rate. Verified against synth-rendered recordings.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/recording_analysis.dart';
import 'package:comet_beat/core/audio/streaming_analyzer.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:flutter_test/flutter_test.dart';

// A RecordingAnalysis built directly from a per-window MIDI track (null =
// unvoiced) — for testing the smoother/segmenter without rendering audio.
RecordingAnalysis _fromTrack(List<int?> midis) => RecordingAnalysis(
      sampleRate: 44100,
      channels: 1,
      durationSeconds: midis.length * 1024 / 44100,
      frames: [
        for (var i = 0; i < midis.length; i++)
          AnalyzerFrame(
            startSample: i * 1024,
            sampleRate: 44100,
            pitch: midis[i] == null
                ? PitchReading.silent()
                : PitchReading(
                    frequency: midiToFrequency(midis[i]!),
                    clarity: 1,
                    a4: kDefaultA4,
                  ),
            chord: null,
          ),
      ],
    );

// A WAV recording of [segments] at [sr] (renderWav is fixed at 44.1k, so build
// the PCM + header at the requested rate explicitly).
Uint8List _wav(List<Segment> segments, {int sr = 44100}) =>
    wavBytes(renderSegments(segments, sampleRate: sr), sampleRate: sr);

Segment _note(int midi, int ms) => (freqs: [midiToFrequency(midi)], ms: ms);

// A melody recording: each note followed by a short rest so note boundaries
// read cleanly (a straddling window lands on silence, not a pitch smear).
Uint8List _song(List<int> midis, {int noteMs = 400, int gapMs = 70}) => _wav([
      for (final m in midis) ...[
        _note(m, noteMs),
        (freqs: const <double>[], ms: gapMs),
      ],
    ]);

// A chord recording: each triad followed by a rest.
Uint8List _chords(
  List<List<int>> triads, {
  int chordMs = 800,
  int gapMs = 90,
}) =>
    _wav([
      for (final t in triads) ...[
        (freqs: [for (final m in t) midiToFrequency(m)], ms: chordMs),
        (freqs: const <double>[], ms: gapMs),
      ],
    ]);

void main() {
  test('a single-note recording transcribes to that note', () {
    final r = analyzeRecording(_wav([_note(69, 800)])); // A4
    expect(r.sampleRate, 44100);
    expect(r.channels, 1);
    expect(r.durationSeconds, closeTo(0.8, 0.02));
    expect(r.voiced, isNotEmpty);
    expect(r.noteRun(), [69]);
  });

  test('a two-note recording transcribes to the run', () {
    final r = analyzeRecording(_wav([_note(57, 600), _note(69, 600)])); // A3→A4
    expect(r.noteRun(), [57, 69]);
  });

  test('analysis uses the FILE sample rate (not a hardcoded 44.1k)', () {
    final r = analyzeRecording(_wav([_note(69, 800)], sr: 22050));
    expect(r.sampleRate, 22050);
    expect(r.noteRun(), [69]); // still A4, because the detector uses 22050
  });

  test('chord detection over a recording names the chord', () {
    final cMajor = (
      freqs: [
        midiToFrequency(60),
        midiToFrequency(64),
        midiToFrequency(67),
      ],
      ms: 1000
    );
    final r = analyzeRecording(_wav([cMajor]), detectChords: true);
    expect(r.chordRun(), contains('C'));
    // Without the flag, no chord track.
    final noChords = analyzeRecording(_wav([cMajor]));
    expect(noChords.chordRun(), isEmpty);
  });

  test('a silent recording yields no notes and does not crash', () {
    final r = analyzeRecording(_wav([(freqs: const <double>[], ms: 500)]));
    expect(r.voiced, isEmpty);
    expect(r.noteRun(), isEmpty);
  });

  test('a recording shorter than one window is safe (empty frames)', () {
    final r = analyzeRecording(_wav([_note(69, 5)])); // ~5 ms
    expect(r.frames, isEmpty);
    expect(r.noteRun(), isEmpty);
  });

  group('real children\'s songs read back as the known melody', () {
    // Note numbers are middle-C-relative (C4 = 60), the melody as taught.
    test('C major scale → the full scale', () {
      final r = analyzeRecording(_song([60, 62, 64, 65, 67, 69, 71, 72]));
      expect(r.noteRun(), [60, 62, 64, 65, 67, 69, 71, 72]);
    });

    test('Alle meine Entchen (C D E F G G) → C D E F G', () {
      final r = analyzeRecording(_song([60, 62, 64, 65, 67, 67]));
      expect(r.noteRun(), [60, 62, 64, 65, 67]); // repeated G collapses
    });

    test('Twinkle Twinkle (C C G G A A G) → C G A G', () {
      final r = analyzeRecording(_song([60, 60, 67, 67, 69, 69, 67]));
      expect(r.noteRun(), [60, 67, 69, 67]);
    });

    test('Mary Had a Little Lamb (E D C D E E E) → E D C D E', () {
      final r = analyzeRecording(_song([64, 62, 60, 62, 64, 64, 64]));
      expect(r.noteRun(), [64, 62, 60, 62, 64]);
    });
  });

  group('melody() is robust to real-audio frame noise', () {
    test('on clean synthetic audio it matches the played scale', () {
      final r = analyzeRecording(_song([60, 62, 64, 65, 67, 69, 71, 72]));
      expect(r.melody(), [60, 62, 64, 65, 67, 69, 71, 72]);
    });

    test('median smoothing removes octave spikes + vibrato wobble', () {
      // Three sustained notes (~8 windows each) peppered with the single-window
      // glitches a real recording produces: an octave jump, a low dropout, a
      // semitone wobble, and a brief unvoiced gap. The melody is still C D E.
      final noisy = <int?>[
        60, 60, 72, 60, 60, 61, 60, 60, // C4 with a +12 spike and a wobble
        62, 62, 62, null, 50, 62, 62, 62, // D4 with a gap + a low glitch
        64, 63, 64, 64, 76, 64, 64, 64, // E4 with a wobble + a spike
      ];
      expect(_fromTrack(noisy).melody(), [60, 62, 64]);
    });

    test('a too-short blip is dropped; empty/unvoiced is empty', () {
      // A 2-window blip between two real notes is below minFrames → dropped.
      expect(
        _fromTrack([60, 60, 60, 60, 60, 74, 74, 67, 67, 67, 67, 67]).melody(),
        [60, 67],
      );
      expect(_fromTrack([]).melody(), isEmpty);
      expect(_fromTrack([null, null, null]).melody(), isEmpty);
    });
  });

  test('a I–IV–V–I progression reads back as C F G C', () {
    final r = analyzeRecording(
      _chords([
        [60, 64, 67], // C
        [65, 69, 72], // F
        [67, 71, 74], // G
        [60, 64, 67], // C
      ]),
      detectChords: true,
    );
    expect(r.chordRun(), ['C', 'F', 'G', 'C']);
  });
}
