// groove_capture — sing-a-track quantization. Pure Dart: synthesized pitch
// traces in, step cells out. No mic involved (mirrors melody_recorder_test).

import 'package:comet_beat/core/audio/groove_capture.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// A trace holding [midi] over [fromMs]..[toMs] sampled every 25 ms.
List<PitchSample> _hold(int? midi, double fromMs, double toMs) => [
      for (var t = fromMs; t < toMs; t += 25) (t, midi),
    ];

void main() {
  test('snapToPentatonic keeps scale tones and pulls neighbours in', () {
    for (final m in [60, 62, 64, 67, 69, 72]) {
      expect(snapToPentatonic(m), m, reason: 'midi $m is already pentatonic');
    }
    expect(snapToPentatonic(61), 60, reason: 'C# → C (down wins ties)');
    expect(snapToPentatonic(66), 67, reason: 'F# → G');
    expect(snapToPentatonic(65), 64, reason: 'F → E');
    expect(snapToPentatonic(71), 72, reason: 'B → C above');
  });

  test('a steady sung note becomes one held cell filling the loop', () {
    final cells = quantizeToGroove(_hold(69, 0, 4800), totalMs: 4800)!;
    expect(cells.length, 1);
    expect(cells.single.midis, [69]);
    expect(cells.single.steps, kPatternSteps);
  });

  test('phrases quantize per step with rests, snapped and merged', () {
    // Bar 1: C4 for 4 steps, silence 4; bar 2: F#4 (off-scale) 4, silence 4.
    final cells = quantizeToGroove(
      [
        ..._hold(60, 0, 1200),
        ..._hold(null, 1200, 2400),
        ..._hold(66, 2400, 3600),
        ..._hold(null, 3600, 4800),
      ],
      totalMs: 4800,
    )!;
    expect(cells.fold<int>(0, (s, c) => s + c.steps), kPatternSteps);
    expect(cells.length, 4);
    expect(cells[0].midis, [60]);
    expect(cells[0].steps, 4);
    expect(cells[1].midis, isNull);
    expect(cells[2].midis, [67], reason: 'F# snapped to G');
    expect(cells[2].steps, 4);
    expect(cells[3].midis, isNull);
  });

  test('a low sung line is lifted whole octaves into the render register', () {
    // Sung around A2/C3 — an octave-and-change low.
    final cells = quantizeToGroove(
      [..._hold(45, 0, 2400), ..._hold(48, 2400, 4800)],
      totalMs: 4800,
    )!;
    expect(cells[0].midis, [57], reason: 'A2 → A3, whole octaves only');
    expect(cells[1].midis, [60], reason: 'C3 → C4, interval shape kept');
  });

  test('silence-only or empty traces yield nothing', () {
    expect(quantizeToGroove(const [], totalMs: 4800), isNull);
    expect(quantizeToGroove(_hold(null, 0, 4800), totalMs: 4800), isNull);
  });

  test('the sung cells feed a real engine track, token roundtrip included', () {
    final cells = quantizeToGroove(
      [..._hold(64, 0, 2400), ..._hold(67, 2400, 4800)],
      totalMs: 4800,
    )!;
    final engine = LoopEngine()..setUserTrack(cells);
    engine.enabled.add(LoopEngine.userTrackId);
    final wav = engine.renderLoop();
    expect(wav.length, 44 + engine.timing.totalSamples * 2);

    final restored = LoopEngine()
      ..applySpec(decodeGrooveToken(encodeGrooveToken(engine.spec))!);
    expect(restored.tracks.any((t) => t.id == 'voice'), isTrue);
    expect(restored.enabled, contains('voice'));
    expect(restored.renderLoop(), equals(wav));

    // A malformed user payload in a foreign token is dropped, not crashed on.
    final bad = GrooveSpec.fromJson({
      'e': ['voice'],
      't': 100,
      'u': {
        'c': [
          [
            [64],
            999,
          ],
        ],
      },
    });
    expect(bad.userCells, isNull);
    final safe = LoopEngine()..applySpec(bad);
    expect(safe.enabled, isEmpty, reason: 'voice unknown without cells');
  });
}
