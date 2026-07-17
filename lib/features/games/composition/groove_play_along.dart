// lib/features/games/composition/groove_play_along.dart
//
// Groove → PlayAlongChart: the "follow the melody" bridge for jam mode (Loop
// Mixer follow-ups §B, the deferred per-note grading). The groove's cells are
// data on an eighth-step grid (loop_engine.dart), so turning one track into a
// PlayAlong target is a pure mapping — each pitched cell becomes a TargetNote
// in musical time, rests are gaps, and PlayAlongEngine (with a practice loop
// over the whole chart) grades the player pass after looping pass, exactly the
// way Play Along / Sing Along already grade a fixed tune.
//
// Pure and Flutter-free; unit-tested against synthetic cells.

import 'dart:math';

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/play_along.dart';

/// A [PlayAlongChart] over one groove track's [cells] at [bpm]. Two eighth-note
/// steps make a beat; each pitched cell becomes a [TargetNote] (its top voice —
/// chords/dyads collapse to the highest note, the line a player would follow),
/// and rests (`midis` null/empty) are left as gaps. [octaveAgnostic] passes
/// through for sung targets.
PlayAlongChart grooveChart(
  List<PatternCell> cells, {
  required int bpm,
  required String name,
  bool octaveAgnostic = false,
}) {
  final notes = <TargetNote>[];
  var step = 0;
  for (final cell in cells) {
    final midis = cell.midis;
    if (midis != null && midis.isNotEmpty) {
      notes.add(
        TargetNote(
          midi: midis.reduce(max),
          startBeat: step / 2.0,
          beats: cell.steps / 2.0,
        ),
      );
    }
    step += cell.steps;
  }
  return PlayAlongChart(
    name: name,
    bpm: bpm,
    notes: notes,
    octaveAgnostic: octaveAgnostic,
  );
}
