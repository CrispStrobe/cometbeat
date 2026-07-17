// beat_capture — beatbox→drum-pattern quantization. The acceptance test is a
// full synth→detector→classifier roundtrip: drum one-shots from synth.dart
// are placed at known steps, windowed through the REAL PitchDetector (which
// supplies rms/zcr), and the classifier must reconstruct the pattern. No mic.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/beat_capture.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:flutter_test/flutter_test.dart';

List<BeatFrame> _analyze(Float64List audio, PitchDetector detector) {
  const hop = 1024;
  final w = detector.windowSize;
  return [
    for (var start = 0; start + w <= audio.length; start += hop)
      () {
        final r =
            detector.analyze(Float64List.sublistView(audio, start, start + w));
        return (
          ms: start * 1000 / kSampleRate,
          rms: r.rms,
          zcr: r.zcr,
          pitchedLow: r.hasPitch && r.nearestMidi < 60,
        );
      }(),
  ];
}

void main() {
  test('classifyHit matches the calibrated synth-drum signatures', () {
    // Probed via PitchDetector on renderDrum one-shots:
    // kick zcr≈0.005 (pitched A2) · snare≈0.45 · hat≈0.67 · voice≈0.01.
    expect(classifyHit(zcr: 0.005, pitchedLow: true), Drum.kick);
    expect(classifyHit(zcr: 0.1, pitchedLow: false), Drum.kick);
    expect(classifyHit(zcr: 0.45, pitchedLow: false), Drum.snare);
    expect(classifyHit(zcr: 0.67, pitchedLow: false), Drum.hat);
  });

  test('detector readings now carry rms and zcr on every frame', () {
    final detector = PitchDetector();
    final tone = renderSegmentsRaw(
      [
        (freqs: [220.0], ms: 60),
      ],
      timbre: timbreFor(Instrument.flute),
    );
    final w = Float64List(detector.windowSize);
    for (var i = 0; i < w.length && i < tone.length; i++) {
      w[i] = tone[i] / 4;
    }
    final r = detector.analyze(w);
    expect(r.rms, greaterThan(0.01));
    expect(r.zcr, greaterThan(0));
    expect(r.zcr, lessThan(0.05), reason: 'a pure tone is dark');

    final silent = detector.analyze(Float64List(detector.windowSize));
    expect(silent.rms, 0);
  });

  test('a synthesized beatbox roundtrips into the exact drum pattern', () {
    const timing = LoopTiming(tempoBpm: 100); // step = 300 ms, loop = 4800 ms
    final s = timing.stepMs;
    final performance = renderDrumPattern(
      [
        (0 * s, Drum.kick),
        (2 * s, Drum.hat),
        (4 * s, Drum.snare),
        (6 * s, Drum.hat),
        (8 * s, Drum.kick),
        (10 * s, Drum.hat),
        (12 * s, Drum.snare),
      ],
      totalMs: timing.totalMs,
    );
    for (var i = 0; i < performance.length; i++) {
      performance[i] *= 0.5; // a realistic mic level
    }

    final frames = _analyze(performance, PitchDetector());
    final pattern = quantizeToBeat(frames, totalMs: timing.totalMs)!;

    expect(rowToString(pattern.rows[Drum.kick]!), 'x.......x.......');
    expect(rowToString(pattern.rows[Drum.snare]!), '....x.......x...');
    expect(rowToString(pattern.rows[Drum.hat]!), '..x...x...x.....');
  });

  test('silence and empty traces yield nothing', () {
    expect(quantizeToBeat(const [], totalMs: 4800), isNull);
    expect(
      quantizeToBeat(
        [
          for (var ms = 0.0; ms < 4800; ms += 25)
            (ms: ms, rms: 0.001, zcr: 0.2, pitchedLow: false),
        ],
        totalMs: 4800,
      ),
      isNull,
    );
  });

  test('the captured beat feeds a real engine track and the share token', () {
    final pattern = DrumRowsPattern({
      Drum.kick: stepRow('x.......x.......'),
      Drum.hat: stepRow('..x...x...x...x.'),
    });
    final engine = LoopEngine()..setUserBeatTrack(pattern);
    engine.enabled.add(LoopEngine.beatTrackId);
    final wav = engine.renderLoop();
    expect(wav.length, 44 + engine.timing.totalSamples * 2);

    final restored = LoopEngine()
      ..applySpec(decodeGrooveToken(encodeGrooveToken(engine.spec))!);
    expect(restored.tracks.any((t) => t.id == 'beat'), isTrue);
    expect(restored.renderLoop(), equals(wav));

    // Malformed beat payloads are dropped, never crashed on.
    final bad = GrooveSpec.fromJson({
      'e': ['beat'],
      't': 100,
      'b': {'kick': 'xx'},
    });
    expect(bad.beatRows, isNull);
  });

  test('jamFit grades notes against the sounding chord', () {
    final engine = LoopEngine();
    // Vamp: bar 0 = C major, bar 1 = A minor.
    expect(engine.jamFit(60, bar: 0), JamFit.chordTone); // C over C
    expect(engine.jamFit(62, bar: 0), JamFit.scaleTone); // D over C
    expect(engine.jamFit(61, bar: 0), JamFit.outside); // C# over C
    expect(engine.jamFit(57, bar: 1), JamFit.chordTone); // A over Am

    engine.progression = kProgressions.first; // I–V–vi–IV
    expect(engine.jamFit(67, bar: 1), JamFit.chordTone); // G over V
    expect(engine.jamFit(71, bar: 1), JamFit.chordTone); // B over V
    expect(engine.jamFit(60, bar: 1), JamFit.scaleTone); // C over V
    expect(engine.jamFit(65, bar: 3), JamFit.chordTone); // F over IV
  });
}
