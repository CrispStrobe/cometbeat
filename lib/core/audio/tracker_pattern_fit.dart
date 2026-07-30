// WS-X2 — fitting a FOREIGN pattern into the one on screen.
//
// A dropped document arrives as a whole `TrackerSong` with its own shape: its
// own channel count, its own row count, its own tempo. The pattern it is landing
// in has none of those things in common, and `TrackerEngine.setChannelCells`
// **asserts that the cell list matches the row count** — every existing caller
// satisfies that by construction (they edit the pattern they are in), so nothing
// had ever handed it a grid from somewhere else. That is the third time in this
// arc that accepting a foreign document has broken an invariant a surface's own
// callers happened to keep; the fix is to fit deliberately, and to say what
// fitting cost.
//
// Pure Dart, no engine and no widgets: the arithmetic of what fits is exactly
// the part worth testing, and the Tracker screen cannot be tested at speed
// (its playhead Ticker never stops, so `pumpAndSettle` hangs on it).

import 'package:comet_beat/core/audio/tracker_engine.dart';

/// A foreign grid, cut to a target pattern's shape, plus what that cost.
class FittedPattern {
  const FittedPattern({
    required this.cells,
    required this.droppedChannels,
    required this.droppedRows,
    required this.droppedNotes,
  });

  /// Exactly `channels × rows` cells, ready for `setChannelCells`.
  final List<List<TrackerCell>> cells;

  /// Channels the target has no room for.
  final int droppedChannels;

  /// Rows past the end of the target pattern.
  final int droppedRows;

  /// Notes actually lost — the number worth showing a person.
  ///
  /// Channels and rows describe the SHAPE; a song can be 32 rows long and only
  /// use the first four, in which case "16 rows trimmed" is technically true and
  /// practically alarming for no reason. This counts what really went.
  final int droppedNotes;

  /// Whether anything was lost, i.e. whether a drop needs to say so.
  bool get isLossy => droppedNotes > 0;
}

/// Cut [source] (a channel-major grid, as `TrackerEngine.exportCells` returns)
/// to [channels] × [rows].
///
/// Extra channels and extra rows are dropped rather than wrapped or squeezed:
/// wrapping a 32-row pattern into 16 would interleave the second half of the
/// music with the first, which is unrecognisable rather than merely shorter, and
/// squeezing would silently change the rhythm. A short source is padded with
/// empty cells so the result always matches the target exactly.
FittedPattern fitCellsToPattern(
  List<List<TrackerCell>> source, {
  required int channels,
  required int rows,
}) {
  if (channels <= 0 || rows <= 0) {
    return const FittedPattern(
      cells: [],
      droppedChannels: 0,
      droppedRows: 0,
      droppedNotes: 0,
    );
  }
  var droppedNotes = 0;
  final out = <List<TrackerCell>>[];
  for (var channel = 0; channel < channels; channel++) {
    final from =
        channel < source.length ? source[channel] : const <TrackerCell>[];
    out.add([
      for (var row = 0; row < rows; row++)
        row < from.length ? from[row] : TrackerCell.empty,
    ]);
    for (var row = rows; row < from.length; row++) {
      if (from[row].midi != null) droppedNotes++;
    }
  }
  for (var channel = channels; channel < source.length; channel++) {
    for (final cell in source[channel]) {
      if (cell.midi != null) droppedNotes++;
    }
  }
  final sourceRows = source.fold<int>(
    0,
    (widest, channel) => channel.length > widest ? channel.length : widest,
  );
  return FittedPattern(
    cells: out,
    droppedChannels: source.length > channels ? source.length - channels : 0,
    droppedRows: sourceRows > rows ? sourceRows - rows : 0,
    droppedNotes: droppedNotes,
  );
}
