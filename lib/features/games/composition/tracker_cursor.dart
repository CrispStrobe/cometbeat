// lib/features/games/composition/tracker_cursor.dart
//
// The Advanced Tracker's edit cursor and block selection, out of the widget.
//
// The cursor is one cell (channel, row). A block selection is the rectangle
// between an ANCHOR corner and the cursor; with no anchor there is no block,
// and block operations act on the cursor cell alone. Every move is clamped to
// the pattern's current size, which the caller passes in (the song owns it).

/// A rectangle of tracker cells, inclusive on both ends.
typedef TrackerRect = ({int cLo, int cHi, int rLo, int rHi});

/// The tracker's edit cursor plus the anchor of an optional block selection.
class TrackerCursor {
  /// The cursor cell — keyboard and on-screen piano enter notes here.
  int channel = 0;
  int row = 0;

  /// The selection's other corner. Null = no block.
  int? anchorChannel;
  int? anchorRow;

  bool get hasSelection => anchorChannel != null && anchorRow != null;

  /// Moves the cursor to (channel,row), clamped to a [channels] × [rows] grid.
  /// Keeps any selection anchor.
  void moveTo(
    int channel,
    int row, {
    required int channels,
    required int rows,
  }) {
    this.channel = channel.clamp(0, channels - 1);
    this.row = row.clamp(0, rows - 1);
  }

  /// A plain move: goes to (channel,row) and drops the selection.
  void moveClearing(
    int channel,
    int row, {
    required int channels,
    required int rows,
  }) {
    moveTo(channel, row, channels: channels, rows: rows);
    clearSelection();
  }

  /// Extends the selection to (channel,row): anchors at the current cursor if
  /// nothing is anchored yet, then moves the cursor to the new corner.
  void extendTo(
    int channel,
    int row, {
    required int channels,
    required int rows,
  }) {
    anchorChannel ??= this.channel;
    anchorRow ??= this.row;
    moveTo(channel, row, channels: channels, rows: rows);
  }

  void clearSelection() {
    anchorChannel = null;
    anchorRow = null;
  }

  /// Selects the cursor's whole channel, top to bottom of a [rows]-row pattern.
  void selectChannel({required int rows}) {
    anchorChannel = channel;
    anchorRow = 0;
    row = rows - 1;
  }

  /// Selects every cell of a [channels] × [rows] pattern.
  void selectAll({required int channels, required int rows}) {
    anchorChannel = 0;
    anchorRow = 0;
    channel = channels - 1;
    row = rows - 1;
  }

  /// Pulls the cursor back inside a grid that has shrunk.
  void clampTo({required int channels, required int rows}) {
    if (channel >= channels) channel = channels - 1;
    if (row >= rows) row = rows - 1;
  }

  /// The selection rectangle, or the single cursor cell when nothing is marked.
  TrackerRect get rect {
    final ac = anchorChannel ?? channel;
    final ar = anchorRow ?? row;
    return (
      cLo: ac < channel ? ac : channel,
      cHi: ac > channel ? ac : channel,
      rLo: ar < row ? ar : row,
      rHi: ar > row ? ar : row,
    );
  }

  /// Whether (channel,row) lies inside a marked block. False with no block.
  bool selects(int channel, int row) {
    if (!hasSelection) return false;
    final s = rect;
    return channel >= s.cLo && channel <= s.cHi && row >= s.rLo && row <= s.rHi;
  }
}
