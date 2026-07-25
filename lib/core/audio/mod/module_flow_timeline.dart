// lib/core/audio/mod/module_flow_timeline.dart
//
// Flow/order timeline: a plain, human-legible summary of how a [TrackerSong]
// ACTUALLY plays back once its flow commands (Bxx position jump, Dxx pattern
// break, E6x pattern loop, Fxx speed/tempo) are expanded. It is the read-only
// analogue of the export-loss report (module_export_report.dart): a pure,
// Flutter-free data function over the model that a small UI panel can render.
//
// The heavy lifting already lives in [walkFlow] (tracker_replayer.dart), which
// unrolls order→pattern→row into the flat [PlayedRow] sequence actually played,
// annotating every row with the [ticksPerRow]/[tempoBpm] in effect. This module
// GROUPS that flat sequence back into one entry per contiguous order-visit — so
// a song that jumps or loops shows the SAME order index more than once, in play
// order — and, for each visit, reports the row range played, the timing in
// effect, and which flow commands the entry carries (with their targets).
//
// Nothing here touches audio rendering; it only reads what [walkFlow] produced.

import 'package:comet_beat/core/audio/tracker_engine.dart' show TrackerCell;
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';

/// A flow command observed inside one order-visit, with its resolved target.
enum FlowCommandKind {
  /// Bxx — continue at another order index ([target] = target order).
  positionJump,

  /// Dxx — break to the next order entry at a given row ([target] = row).
  patternBreak,

  /// E6x — pattern loop (set start / repeat span). [target] = the low nibble
  /// (0 = mark loop start, x>0 = repeat x times).
  patternLoop,

  /// Fxx `param < 0x20` — set speed (ticks/row). [target] = the new speed.
  speedChange,

  /// Fxx `param >= 0x20` — set tempo (BPM). [target] = the new tempo.
  tempoChange,
}

/// One flow command inside a timeline entry: [kind] + its resolved [target]
/// (order index, row, speed, tempo, or loop count — see [FlowCommandKind]) and
/// the [row] of the entry it occurs on.
class FlowCommand {
  const FlowCommand(this.kind, this.target, this.row);

  final FlowCommandKind kind;

  /// The command's resolved value — meaning depends on [kind].
  final int target;

  /// The row within the visited pattern the command occurs on.
  final int row;

  @override
  bool operator ==(Object other) =>
      other is FlowCommand &&
      other.kind == kind &&
      other.target == target &&
      other.row == row;

  @override
  int get hashCode => Object.hash(kind, target, row);

  @override
  String toString() => 'FlowCommand($kind → $target @row $row)';
}

/// One contiguous visit to an order entry in play order. Loops and jumps make
/// the same [orderIndex] appear in more than one entry, so a timeline is the
/// non-linear playback made legible: read top-to-bottom, it is the sequence the
/// renderer produces. Immutable value type.
class FlowTimelineEntry {
  const FlowTimelineEntry({
    required this.orderIndex,
    required this.patternIndex,
    required this.firstRow,
    required this.lastRow,
    required this.rowCount,
    required this.ticksPerRow,
    required this.tempoBpm,
    required this.commands,
  });

  /// The index into [TrackerSong.order] entered on this visit.
  final int orderIndex;

  /// The pattern that order entry points at (`order[orderIndex]`).
  final int patternIndex;

  /// The first and last pattern-row actually played on this visit (inclusive).
  final int firstRow;
  final int lastRow;

  /// How many rows were played on this visit (counts EEx-delayed repeats too, so
  /// it may exceed `lastRow - firstRow + 1`).
  final int rowCount;

  /// The speed (ticks/row) in effect as the visit ends.
  final int ticksPerRow;

  /// The tempo (BPM) in effect as the visit ends (0 → the song default).
  final int tempoBpm;

  /// The flow commands that occur on this visit, in row order.
  final List<FlowCommand> commands;

  @override
  String toString() =>
      'FlowTimelineEntry(order $orderIndex, pattern $patternIndex, '
      'rows $firstRow–$lastRow, speed $ticksPerRow, tempo $tempoBpm, '
      '${commands.length} cmd)';
}

/// Groups the flat [walkFlow] sequence for [song] into one [FlowTimelineEntry]
/// per contiguous order-visit and attaches the flow commands each visit carries.
///
/// A new entry starts whenever the played order index changes OR the row jumps
/// backward within the same order (an E6x pattern loop replaying the marked span
/// starts a fresh visit), so a looped/repeated order shows as separate entries
/// in play order — exactly the sequence the renderer walks. The tempo/speed
/// reported for an entry is the value in effect as that visit ENDS, so an Fxx
/// change mid-song is reflected by the entry that runs under the new value.
///
/// Pure: it only reads what [walkFlow] produced and re-scans the visited rows
/// for the flow-command effect columns — no audio state, no rendering.
List<FlowTimelineEntry> songFlowTimeline(
  TrackerSong song, {
  int maxRows = 65536,
}) {
  final played = walkFlow(song, maxRows: maxRows);
  final out = <FlowTimelineEntry>[];
  if (played.isEmpty) return out;

  var startIdx = 0;
  for (var i = 1; i <= played.length; i++) {
    final boundary = i == played.length ||
        played[i].orderIndex != played[i - 1].orderIndex ||
        played[i].row < played[i - 1].row;
    if (!boundary) continue;
    out.add(_buildEntry(song, played, startIdx, i));
    startIdx = i;
  }
  return out;
}

/// Builds one entry from the [played] slice `[from, to)` (all one order-visit).
FlowTimelineEntry _buildEntry(
  TrackerSong song,
  List<PlayedRow> played,
  int from,
  int to,
) {
  final head = played[from];
  final tail = played[to - 1];
  var firstRow = head.row;
  var lastRow = head.row;
  for (var i = from; i < to; i++) {
    if (played[i].row < firstRow) firstRow = played[i].row;
    if (played[i].row > lastRow) lastRow = played[i].row;
  }

  // Re-scan the DISTINCT visited rows for flow-command effect columns. Rows may
  // repeat within a visit (EEx pattern delay), so scan each row once, in the
  // order it first appears.
  final commands = <FlowCommand>[];
  final seenRows = <int>{};
  final patternIndex = head.patternIndex;
  final valid = patternIndex >= 0 && patternIndex < song.patterns.length;
  final cells =
      valid ? song.patterns[patternIndex].cells : const <List<TrackerCell>>[];
  for (var i = from; i < to; i++) {
    final row = played[i].row;
    if (!seenRows.add(row)) continue;
    _scanRowCommands(cells, row, commands);
  }

  return FlowTimelineEntry(
    orderIndex: head.orderIndex,
    patternIndex: patternIndex,
    firstRow: firstRow,
    lastRow: lastRow,
    rowCount: to - from,
    ticksPerRow: tail.ticksPerRow,
    tempoBpm: tail.tempoBpm,
    commands: commands,
  );
}

/// Appends the flow commands on [row] (first of each kind across channels wins,
/// matching [walkFlow]'s own scan) to [out].
void _scanRowCommands(
  List<List<TrackerCell>> cells,
  int row,
  List<FlowCommand> out,
) {
  var haveJump = false;
  var haveBreak = false;
  var haveLoop = false;
  var haveSpeed = false;
  var haveTempo = false;
  for (final col in cells) {
    if (row < 0 || row >= col.length) continue;
    final c = col[row];
    if (c.fxCmd == kFxPositionJump && !haveJump) {
      haveJump = true;
      out.add(FlowCommand(FlowCommandKind.positionJump, c.fxParam, row));
    } else if (c.fxCmd == kFxPatternBreak && !haveBreak) {
      haveBreak = true;
      final target = (c.fxParam >> 4) * 10 + (c.fxParam & 0xF);
      out.add(FlowCommand(FlowCommandKind.patternBreak, target, row));
    } else if (c.fxCmd == kFxExtended &&
        ((c.fxParam >> 4) & 0xF) == kExPatternLoop &&
        !haveLoop) {
      haveLoop = true;
      out.add(FlowCommand(FlowCommandKind.patternLoop, c.fxParam & 0xF, row));
    } else if (c.fxCmd == kFxSetSpeed) {
      if (c.fxParam >= 0x20 && !haveTempo) {
        haveTempo = true;
        out.add(FlowCommand(FlowCommandKind.tempoChange, c.fxParam, row));
      } else if (c.fxParam > 0 && c.fxParam < 0x20 && !haveSpeed) {
        haveSpeed = true;
        out.add(FlowCommand(FlowCommandKind.speedChange, c.fxParam, row));
      }
    }
  }
}
