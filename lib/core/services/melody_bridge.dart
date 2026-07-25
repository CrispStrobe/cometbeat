// MelodyBridge — the pitched twin of BeatBridge. One in-memory "current tune"
// that modes can PUBLISH to and PULL from, so the Loop Mixer, Live Looper and
// the Trackers can hand the SAME melody around: build it in one, load it in
// another. The unit is a bar-cycle of [PatternCell]s (the melodic pattern the
// engine already renders) plus the instrument it was voiced with and the
// tempo/key it was authored at.
//
// Like BeatBridge: a plain singleton (screens are navigated one at a time, so
// an explicit publish/pull is the right model), listenable via [melody]. Pure
// Dart (only depends on the loop-engine model) → unit-tested.

import 'package:comet_beat/core/audio/loop_engine.dart'
    show PatternCell, kPatternSteps;
import 'package:flutter/foundation.dart';

/// An immutable snapshot of a shared tune: the melodic cells plus the
/// instrument name it was voiced with and the tempo/key it was authored at.
class SharedMelody {
  SharedMelody({
    required List<PatternCell> cells,
    required this.tempoBpm,
    this.instrument,
    this.key = 0,
    this.source = '',
  }) : cells = List<PatternCell>.unmodifiable(cells);

  /// One bar-cycle of the melody, as the engine's own [PatternCell]s.
  final List<PatternCell> cells;

  /// The instrument the tune was voiced with (an `Instrument.name`), or null.
  final String? instrument;

  final int tempoBpm;

  /// Semitones the tune's pitches were transposed by (the authoring key).
  final int key;

  /// Which mode published it (e.g. 'loopmixer') — for a friendly note.
  final String source;

  /// True when there is no sounding note (all rests).
  bool get isEmpty => cells.every((c) => c.midis == null || c.midis!.isEmpty);

  /// The cells, ready to hand to `LoopEngine.setUserTrack`.
  List<PatternCell> toCells() => [...cells];
}

/// Converts a per-row melody grid (one absolute MIDI or null per step, as the
/// Tracker/Workshop hold it) into the engine's [PatternCell] run-list.
///
/// A run of empty rows following a note is folded into that note's length (the
/// tracker "let it ring" semantics — an empty cell sustains the previous
/// trigger); a leading run of empties becomes one rest cell. The result always
/// sums to [steps] (default [kPatternSteps] = the 2-bar vamp grid): rows beyond
/// [steps] are windowed off, and a shorter grid is padded with a trailing rest.
/// So a 16-step source maps 1:1; other lengths window/pad rather than resample.
List<PatternCell> patternCellsFromMidiRows(
  List<int?> rows, {
  int steps = kPatternSteps,
}) {
  final cells = <PatternCell>[];
  var i = 0;
  while (i < steps) {
    final midi = i < rows.length ? rows[i] : null;
    var len = 1;
    while (i + len < steps) {
      final next = (i + len) < rows.length ? rows[i + len] : null;
      if (next != null) break; // a fresh trigger starts a new cell
      len++;
    }
    cells.add(PatternCell(midis: midi == null ? null : [midi], steps: len));
    i += len;
  }
  return cells;
}

/// The inverse of [patternCellsFromMidiRows]: expands a [PatternCell] run-list
/// back onto a [rows]-long grid, placing each note's MIDI at its ONSET row only
/// (sustained steps stay empty — the tracker rings them). Each pitch is shifted
/// by [transpose] semitones (used to fold a shared tune's authoring key back
/// into absolute pitches). Cells past [rows] are windowed off.
List<int?> midiRowsFromPatternCells(
  List<PatternCell> cells,
  int rows, {
  int transpose = 0,
}) {
  final out = List<int?>.filled(rows, null);
  var step = 0;
  for (final c in cells) {
    if (step >= rows) break;
    final midis = c.midis;
    if (midis != null && midis.isNotEmpty) out[step] = midis.first + transpose;
    step += c.steps;
  }
  return out;
}

class MelodyBridge {
  MelodyBridge._();
  static final MelodyBridge instance = MelodyBridge._();

  /// The current shared tune (null until something publishes). Listenable so a
  /// visible screen can react.
  final ValueNotifier<SharedMelody?> melody =
      ValueNotifier<SharedMelody?>(null);

  SharedMelody? get current => melody.value;
  bool get hasMelody => melody.value != null && !melody.value!.isEmpty;

  void publish(SharedMelody m) => melody.value = m;

  void clear() => melody.value = null;
}
