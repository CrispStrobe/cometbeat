// WS-T4 — one channel of a tracker pattern, as a piano roll.
//
// The tracker grid is exact and unapproachable: a column of `C-4 01 .. A08`
// tells you everything and shows you nothing. Someone opening a module for the
// first time cannot see the shape of a line — whether it rises, where the long
// notes are, that bar three repeats bar one. A roll shows that at a glance and
// gives up the exactness, which is why this is a VIEW beside the grid rather
// than a replacement for it.
//
// Deliberately one channel. A full multi-channel roll is a different (and much
// larger) thing, and the grid is already the multi-channel view; what is
// missing is legibility for a single line.
//
// The note-run computation is a pure function on purpose. Where a note ENDS is
// the only real logic here — a tracker cell says when a note starts and says
// nothing about when it stops — and getting it wrong is invisible in a picture
// but obvious in a test.

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/features/games/composition/tracker_meter.dart';
import 'package:flutter/material.dart';

/// One sounding note: rows `[startRow, endRow)` at [midi].
typedef RollNote = ({int startRow, int endRow, int midi, int instrument});

/// Turn one channel's cells into note runs.
///
/// A tracker cell says a note STARTS; nothing says it stops. A note runs until
/// whichever comes first:
///   * the next note on the same channel (a tracker channel is monophonic —
///     the new note takes the voice), or
///   * an explicit key-off, or
///   * the end of the pattern.
///
/// That last one is a deliberate simplification and worth naming: a note held
/// across a pattern boundary really does keep sounding into the next pattern,
/// but this view shows ONE pattern, and drawing a note running off the bottom
/// edge with no end is less honest than ending it at the edge the user can see.
List<RollNote> rollNotesFor(List<TrackerCell> cells) {
  final out = <RollNote>[];
  int? openMidi;
  var openInstrument = 0;
  var openStart = 0;

  void close(int atRow) {
    if (openMidi == null) return;
    // A zero-length run cannot be drawn and means the same note was re-struck
    // on consecutive rows; keep it one row long so it is visible as an onset.
    final end = atRow > openStart ? atRow : openStart + 1;
    out.add(
      (
        startRow: openStart,
        endRow: end,
        midi: openMidi!,
        instrument: openInstrument,
      ),
    );
    openMidi = null;
  }

  for (var row = 0; row < cells.length; row++) {
    final cell = cells[row];
    if (cell.keyOff) {
      close(row);
      continue;
    }
    if (cell.midi != null) {
      close(row);
      openMidi = cell.midi;
      openInstrument = cell.instrument;
      openStart = row;
    }
  }
  close(cells.length);
  return out;
}

/// The pitch range to draw, with a little air above and below.
///
/// Returns null when there is nothing to show — the caller then says so rather
/// than drawing an empty grid, which reads as broken.
({int lowMidi, int highMidi})? rollRange(List<RollNote> notes) {
  if (notes.isEmpty) return null;
  var low = notes.first.midi;
  var high = notes.first.midi;
  for (final note in notes) {
    if (note.midi < low) low = note.midi;
    if (note.midi > high) high = note.midi;
  }
  // A single-pitch line would otherwise be one row tall and unreadable.
  const padding = 2;
  return (lowMidi: low - padding, highMidi: high + padding);
}

/// A read-only piano roll of one channel.
class TrackerPianoRoll extends StatelessWidget {
  const TrackerPianoRoll({
    super.key,
    required this.cells,
    this.playingRow,
    this.rowHeight = 6,
    this.meter = const TrackerMeter(),
  });

  final List<TrackerCell> cells;

  /// The row currently sounding, if any — drawn as a playhead line.
  final int? playingRow;

  /// Vertical pixels per pattern row.
  final double rowHeight;

  /// WS-T6 — where the beat and bar lines go. Shared with the tracker grid so
  /// the two views cannot disagree; this used to be hardcoded to 4 and 16 here,
  /// which was wrong for any pattern that is not 4/4 at 4 rows a beat.
  final TrackerMeter meter;

  @override
  Widget build(BuildContext context) {
    final notes = rollNotesFor(cells);
    final range = rollRange(notes);
    final scheme = Theme.of(context).colorScheme;

    if (range == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No notes on this channel yet.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => CustomPaint(
        size: Size(constraints.maxWidth, cells.length * rowHeight),
        painter: _RollPainter(
          notes: notes,
          rows: cells.length,
          range: range,
          rowHeight: rowHeight,
          playingRow: playingRow,
          meter: meter,
          noteColor: scheme.primary,
          gridColor: scheme.outlineVariant,
          barColor: scheme.outline,
          playheadColor: scheme.tertiary,
        ),
      ),
    );
  }
}

class _RollPainter extends CustomPainter {
  _RollPainter({
    required this.notes,
    required this.rows,
    required this.range,
    required this.rowHeight,
    required this.playingRow,
    required this.meter,
    required this.noteColor,
    required this.gridColor,
    required this.barColor,
    required this.playheadColor,
  });

  final List<RollNote> notes;
  final int rows;
  final ({int lowMidi, int highMidi}) range;
  final double rowHeight;
  final int? playingRow;
  final TrackerMeter meter;
  final Color noteColor;
  final Color gridColor;
  final Color barColor;
  final Color playheadColor;

  @override
  void paint(Canvas canvas, Size size) {
    final pitches = range.highMidi - range.lowMidi + 1;
    if (pitches <= 0 || rows <= 0) return;
    final laneWidth = size.width / pitches;

    // Beat and bar lines, from the SHARED meter — without them the roll is a
    // field of blocks with no rhythm to read against, and with the wrong ones
    // it reads as a different piece of music.
    final grid = Paint()..color = gridColor;
    final bar = Paint()..color = barColor;
    for (var row = 0; row <= rows; row += meter.rowsPerBeat) {
      // Bar first: every bar row is also a beat row, so testing the beat first
      // would draw every bar as a beat and the meter would read as 4/4.
      final isBar = meter.isBar(row);
      canvas.drawRect(
        Rect.fromLTWH(0, row * rowHeight, size.width, isBar ? 1.2 : 0.6),
        isBar ? bar : grid,
      );
    }

    final notePaint = Paint()..color = noteColor;
    for (final note in notes) {
      final lane = note.midi - range.lowMidi;
      final rect = Rect.fromLTWH(
        lane * laneWidth + 0.5,
        note.startRow * rowHeight,
        (laneWidth - 1).clamp(1.0, laneWidth),
        ((note.endRow - note.startRow) * rowHeight - 1).clamp(1.0, size.height),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        notePaint,
      );
    }

    if (playingRow case final row? when row >= 0 && row < rows) {
      canvas.drawRect(
        Rect.fromLTWH(0, row * rowHeight, size.width, 1.5),
        Paint()..color = playheadColor,
      );
    }
  }

  @override
  bool shouldRepaint(_RollPainter old) =>
      old.notes != notes ||
      old.playingRow != playingRow ||
      old.range != range ||
      old.rowHeight != rowHeight ||
      old.meter != meter;
}
