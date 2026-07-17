// lib/core/audio/groove_capture.dart
//
// "Sing a track into existence": turns a raw mic pitch trace into a Loop
// Mixer pattern. The screen records ~2 bars of PitchReadings; this quantizes
// them onto the eighth-step grid (dominant pitch per step), snaps every note
// to C pentatonic (so the sung layer always grooves with the band — the
// Colour Melody rule) and octave-shifts the whole line into a comfortable
// render register. Pure Dart, testable headlessly like melody_recorder.dart.

import 'package:comet_beat/core/audio/loop_engine.dart';

/// One raw capture sample: elapsed ms → detected midi (null = silence).
typedef PitchSample = (double, int?);

const _pentatonicClasses = [0, 2, 4, 7, 9];

/// Nearest C-pentatonic midi (every pitch class is at most 1 semitone away;
/// downward wins ties, which keeps sung leading tones on the scale).
int snapToPentatonic(int midi) {
  for (var d = 0; d <= 2; d++) {
    for (final candidate in [midi - d, midi + d]) {
      if (_pentatonicClasses.contains(candidate % 12)) return candidate;
    }
  }
  return midi;
}

/// Quantizes [samples] (spanning [totalMs]) onto [steps] grid cells:
/// per step the longest-held pitch wins (silence wins if it dominates), the
/// line is octave-shifted so its median lands near C4–C5, every pitch snaps
/// to C pentatonic, and equal neighbours merge into held cells. Returns null
/// when nothing pitched was captured.
List<PatternCell>? quantizeToGroove(
  List<PitchSample> samples, {
  required int totalMs,
  int steps = kPatternSteps,
}) {
  if (samples.isEmpty || totalMs <= 0) return null;
  final stepMs = totalMs / steps;

  // Accumulate held-duration per (step, midi); each sample holds until the
  // next one, sliced across step boundaries.
  final tallies = List.generate(steps, (_) => <int?, double>{});
  for (var i = 0; i < samples.length; i++) {
    final (ms, midi) = samples[i];
    final until =
        (i + 1 < samples.length ? samples[i + 1].$1 : totalMs.toDouble())
            .clamp(0.0, totalMs.toDouble());
    var t = ms.clamp(0.0, totalMs.toDouble());
    while (t < until) {
      final step = (t / stepMs).floor().clamp(0, steps - 1);
      final stepEnd = (step + 1) * stepMs;
      final end = until < stepEnd ? until : stepEnd;
      tallies[step][midi] = (tallies[step][midi] ?? 0) + (end - t);
      t = end;
    }
  }

  final stepMidis = <int?>[
    for (final tally in tallies)
      tally.isEmpty
          ? null
          : tally.entries.reduce((a, b) => b.value > a.value ? b : a).key,
  ];
  final pitched = stepMidis.whereType<int>().toList()..sort();
  if (pitched.isEmpty) return null;

  // Whole-line octave shift: median → as close to E4 (64) as octaves allow.
  final median = pitched[pitched.length ~/ 2];
  final shift = ((64 - median) / 12).round() * 12;

  final cells = <PatternCell>[];
  for (final midi in stepMidis) {
    final snapped = midi == null ? null : snapToPentatonic(midi + shift);
    final last = cells.isEmpty ? null : cells.last;
    if (last != null &&
        ((last.midis?.singleOrNull == snapped && snapped != null) ||
            (last.midis == null && snapped == null))) {
      cells[cells.length - 1] = (midis: last.midis, steps: last.steps + 1);
    } else {
      cells.add((midis: snapped == null ? null : [snapped], steps: 1));
    }
  }
  return cells;
}
