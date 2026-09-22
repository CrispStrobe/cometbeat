// Rhythm chain (Worker 2) — locked against synthetic click tracks and the
// mir_eval-style ruler in note_metrics.dart. Onsets F ≥ 0.9 (30 ms), tempo
// ±3 %, beats evenly spaced + phase-aligned, quantise exact.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/rhythm.dart';
import 'package:flutter_test/flutter_test.dart';

import 'note_metrics.dart';

const _sr = 44100;

/// A short broadband transient (a decaying noise burst) — a clean onset.
Float64List _click({double ms = 8, double amp = 0.9, int seed = 1}) {
  final n = (ms * _sr / 1000).round();
  final buf = Float64List(n);
  final rng = math.Random(seed);
  for (var i = 0; i < n; i++) {
    final decay = math.exp(-i / (n * 0.3));
    buf[i] = amp * decay * (rng.nextDouble() * 2 - 1);
  }
  return buf;
}

/// Places a click at each [onsetMs] into a [totalMs]-long silent buffer.
Float64List _clickTrack(List<double> onsetMs, double totalMs) {
  final n = (totalMs * _sr / 1000).ceil();
  final buf = Float64List(n);
  final click = _click();
  for (final ms in onsetMs) {
    final s = (ms * _sr / 1000).round();
    for (var i = 0; i < click.length && s + i < n; i++) {
      buf[s + i] += click[i];
    }
  }
  return buf;
}

List<NoteEvent> _asOnsets(List<double> ms) =>
    notes([for (final m in ms) (0, m, m + 1)]);

List<double> _every(double periodMs, int count, {double start = 0}) =>
    [for (var i = 0; i < count; i++) start + i * periodMs];

void main() {
  test('spectral-flux onsets recover a 250 ms click pattern (F ≥ 0.9)', () {
    final onsets = _every(250, 7, start: 250); // leading silence, then 7 hits
    final grid = detectRhythm(_clickTrack(onsets, 2200));
    final prf = onsetPrf(
      _asOnsets(onsets),
      _asOnsets(grid.onsetMs),
      onsetTolMs: 30,
    );
    expect(prf.f, greaterThanOrEqualTo(0.9), reason: 'onset F=${prf.f}');
  });

  test('tempo of a 120 BPM click is within ±3 %', () {
    final grid = detectRhythm(_clickTrack(_every(500, 8, start: 500), 4500));
    expect(grid.bpm, closeTo(120, 120 * 0.03), reason: 'bpm=${grid.bpm}');
  });

  test('tempo of a 90 BPM click is within ±3 %', () {
    final grid = detectRhythm(
      _clickTrack(_every(2000 / 3, 7, start: 2000 / 3), 5000),
    );
    expect(grid.bpm, closeTo(90, 90 * 0.03), reason: 'bpm=${grid.bpm}');
  });

  test('beats are ~500 ms apart and phase-aligned to a 120 BPM click', () {
    final clicks = _every(500, 8, start: 500);
    final grid = detectRhythm(_clickTrack(clicks, 4500));
    expect(grid.beatMs.length, greaterThanOrEqualTo(6));

    // Even spacing near 500 ms.
    final diffs = [
      for (var i = 1; i < grid.beatMs.length; i++)
        grid.beatMs[i] - grid.beatMs[i - 1],
    ]..sort();
    final median = diffs[diffs.length ~/ 2];
    expect(median, closeTo(500, 60), reason: 'median beat gap=$median');

    // Each beat sits near a click (phase lock), ignoring the ends.
    for (final b in grid.beatMs) {
      final nearest =
          clicks.map((c) => (c - b).abs()).reduce((a, c) => a < c ? a : c);
      expect(nearest, lessThan(70), reason: 'beat $b far from any click');
    }
  });

  test('quantiseToGrid maps notes to exact beats and durations', () {
    const grid = (
      bpm: 120.0,
      beatMs: [0.0, 500.0, 1000.0, 1500.0, 2000.0],
      onsetMs: <double>[],
    );
    const quarterOnBeat2 =
        (midi: 60, onMs: 1000.0, offMs: 1500.0, confidence: 1.0, program: -1);
    const eighthOnBeat0 =
        (midi: 62, onMs: 0.0, offMs: 250.0, confidence: 1.0, program: -1);
    final out = quantizeToGrid([quarterOnBeat2, eighthOnBeat0], grid);

    expect(out[0].startBeat, closeTo(2.0, 1e-9));
    expect(out[0].beats, closeTo(1.0, 1e-9));
    expect(out[1].startBeat, closeTo(0.0, 1e-9));
    expect(out[1].beats, closeTo(0.5, 1e-9));
  });

  test('empty / too-short audio yields an empty grid, never throws', () {
    expect(detectRhythm(Float64List(0)).beatMs, isEmpty);
    expect(detectRhythm(Float64List(100)).onsetMs, isEmpty);
  });
}
