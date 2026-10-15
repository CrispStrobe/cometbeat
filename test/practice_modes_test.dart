import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/features/harmony/practice_modes.dart';
import 'package:comet_beat/features/harmony/streamed_band.dart';
import 'package:flutter_test/flutter_test.dart';

/// BB-T3 — practice modes as pure rules over (pass, bar).

Chart _chart(String text) => parseChartText(text).chart;

final _blues = _chart(
  'tempo: 100\n[A]\n| C7 | F7 | C7 | C7 |\n| F7 | F7 | C7 | C7 |\n'
  '| G7 | F7 | C7 | G7 |',
);

int _pc(ChartBeatChord c) => (c.chord.root.midiNumber % 12 + 12) % 12;

void main() {
  group('key cycling', () {
    for (final mode in [KeyCycle.chromatic, KeyCycle.fourths]) {
      test('$mode: twelve keys, every chord moved and spelled for its key', () {
        const c = PracticeConfig(keyCycle: KeyCycle.chromatic);
        final cfg = PracticeConfig(keyCycle: mode);
        final seen = <int>{};
        final original = [
          for (final b in _blues.barsInPlayOrder) ...b.chords.map(_pc),
        ];
        for (var pass = 0; pass < 12; pass++) {
          final plan = passPlan(cfg, _blues, pass);
          final chart = plan.chart;
          seen.add(chart.tonicPitchClass);
          final shift = mode == KeyCycle.chromatic ? pass : 5 * pass;
          final moved = [
            for (final b in chart.barsInPlayOrder) ...b.chords.map(_pc),
          ];
          expect(moved, [for (final p in original) (p + shift) % 12]);
          // Spelled for the key: no more than six accidentals, and no sharp
          // roots in a flat key (nor flats in a sharp one).
          expect(chart.keyFifths.abs(), lessThanOrEqualTo(6));
          for (final b in chart.barsInPlayOrder) {
            for (final chord in b.chords) {
              final alter = chord.chord.root.alter;
              if (chart.keyFifths < 0) expect(alter, lessThanOrEqualTo(0));
              if (chart.keyFifths > 0) expect(alter, greaterThanOrEqualTo(0));
            }
          }
        }
        expect(seen, hasLength(12), reason: 'all twelve keys');
        expect(c.isOff, isFalse);
      });
    }

    test('random keys are seeded and never repeat the last pass', () {
      const cfg = PracticeConfig(keyCycle: KeyCycle.random, seed: 3);
      final a = [for (var p = 0; p < 10; p++) passKeyFifths(cfg, _blues, p)];
      final b = [for (var p = 0; p < 10; p++) passKeyFifths(cfg, _blues, p)];
      expect(a, b);
      for (var p = 1; p < a.length; p++) {
        expect(a[p], isNot(a[p - 1]));
      }
    });
  });

  test('tempo ramps by step, or to a target and holds', () {
    const step = PracticeConfig(tempoStep: 5);
    final stepped = [for (var p = 0; p < 4; p++) passTempo(step, 100, p)];
    expect(stepped, const [100, 105, 110, 115]);
    const target = PracticeConfig(tempoTarget: 140);
    final ramped = [for (var p = 0; p < 6; p++) passTempo(target, 100, p)];
    expect(ramped, const [100, 110, 120, 130, 140, 140]);
    expect(passPlan(step, _blues, 2).chart.tempoBpm, 110);
  });

  test('harmony fade: comp, then bass, then only the click', () {
    const cfg = PracticeConfig(harmonyFade: true);
    expect(passPlan(cfg, _blues, 0).silent, isEmpty);
    expect(passPlan(cfg, _blues, 1).silent, {BandRole.comp});
    expect(passPlan(cfg, _blues, 2).silent, {BandRole.comp, BandRole.bass});
    final last = passPlan(cfg, _blues, 3);
    expect(last.kit, isFalse);
    expect(last.clickOnly, isTrue);
  });

  test('drop-outs are reproducible, never on the first pass', () {
    const cfg = PracticeConfig(dropOut: 0.3, seed: 11);
    final first = [for (var b = 0; b < 48; b++) isDropOut(cfg, 0, b)];
    expect(first.any((d) => d), isFalse);
    final a = [for (var b = 0; b < 48; b++) isDropOut(cfg, 2, b)];
    final again = [for (var b = 0; b < 48; b++) isDropOut(cfg, 2, b)];
    expect(a, again);
    final share = a.where((d) => d).length / a.length;
    expect(share, inInclusiveRange(0.1, 0.5));
  });

  test('density tapers a level a pass', () {
    const cfg = PracticeConfig(densityTaper: true);
    final levels = [
      for (var p = 0; p < 4; p++) passPlan(cfg, _blues, p).intensity,
    ];
    expect(levels, const [2, 1, 0, 0]);
  });
}
