import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/audio/tracker_engine.dart' show TrackerCell;

/// Syncs a Tracker channel's monophonic cells with a polyphonic Drumkit model.
class DrumKitBridge {
  static Map<Drum, List<bool>> toDrumRows(List<TrackerCell> cells, int steps) {
    final rows = { for (final d in Drum.values) d: List<bool>.filled(steps, false) };
    for (var i = 0; i < cells.length && i < steps; i++) {
      final m = cells[i].midi;
      if (m != null && m >= 0 && m < Drum.values.length) {
        rows[Drum.values[m]]![i] = true;
      }
    }
    return rows;
  }

  static List<TrackerCell> toCells(Map<Drum, List<bool>> rows, int steps) {
    final cells = List<TrackerCell>.filled(steps, const TrackerCell());
    for (var i = 0; i < steps; i++) {
      for (final d in Drum.values) {
        if (rows[d]![i]) {
          cells[i] = TrackerCell(midi: d.index, volume: 1.0);
          break; // First drum wins on this monophonic step
        }
      }
    }
    return cells;
  }
}
