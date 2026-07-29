// WS-T7 — the decisions a live record pass has to make, as pure functions.
//
// The Tracker already had FT2-style live record: while playing, a typed note
// lands at the SOUNDING row instead of the edit cursor. What it did not have was
// anything a real performance needs, and each gap is a decision rather than
// plumbing:
//
//   * **A chord is more than one note.** Every note went to the cursor channel,
//     so playing three keys wrote one cell three times and you got the last one.
//     A tracker's answer is the one hardware trackers have always used: a chord
//     spreads across consecutive channels.
//   * **A count-in has to gate the WRITES, not the transport.** The Tracker's
//     Stopwatch is the clock everything else follows (it hands the transport its
//     position through `syncTo`), so a count-in cannot be "delay the clock" —
//     it has to be "the pattern is running, you can hear it, but nothing is
//     committed yet."
//   * **A record pass is one action.** Not one per note: the screen snapshots
//     the whole pattern per undo entry against an 80-entry cap, so ten seconds
//     of jamming used to push every earlier edit off the end of the history.
//
// Pure Dart, no Flutter, no engine — it decides WHERE a note goes and WHETHER it
// is committed; the screen does the writing. That split is deliberate: the
// screen cannot be unit-tested at speed (its playhead Ticker never stops, so
// `pumpAndSettle` hangs), and these are exactly the parts worth testing.

import 'package:comet_beat/core/audio/tracker_song.dart' show quantizeRowToBeat;

/// Where one recorded note should land.
class RecordedNote {
  const RecordedNote({
    required this.channel,
    required this.row,
    required this.midi,
  });

  final int channel;
  final int row;
  final int midi;

  @override
  String toString() => 'RecordedNote(ch $channel, row $row, midi $midi)';

  @override
  bool operator ==(Object other) =>
      other is RecordedNote &&
      other.channel == channel &&
      other.row == row &&
      other.midi == midi;

  @override
  int get hashCode => Object.hash(channel, row, midi);
}

/// Which row a note played at [row] + [phase] should be written to.
///
/// [phase] is the fraction through the current row (0..1) — without it a note
/// played a hair EARLY quantizes to the row it was aiming at, but a note played
/// a hair LATE quantizes back to the row it just left, and a performance that
/// drags slightly comes out a whole row behind the beat.
///
/// Delegates the snapping itself to `quantizeRowToBeat`, which the Tracker
/// already uses, so typing and playing cannot disagree about where a note goes.
int recordRow({
  required int row,
  required double phase,
  required bool quantize,
  required int stepsPerBeat,
  required int totalRows,
}) {
  if (!quantize) return row;
  return quantizeRowToBeat(row, phase, stepsPerBeat, totalRows);
}

/// Spread simultaneously-held [notes] across consecutive channels from
/// [startChannel].
///
/// A chord is the case the old path got wrong: three keys down wrote the same
/// cell three times, so two notes of every chord silently vanished. Consecutive
/// channels is what hardware trackers do and what the grid makes readable — a
/// chord reads as a vertical stack.
///
/// [channelCount] bounds it. Notes past the last channel are DROPPED rather than
/// wrapped onto channel 0: wrapping would overwrite the start of the same chord
/// with its own top notes, which looks like the bug this function exists to fix.
/// The caller learns how many landed from the length of the result.
///
/// Lowest note first, so the root of a chord keeps the channel the player was
/// on and only the added notes spill sideways.
List<RecordedNote> allocateChord({
  required List<int> notes,
  required int row,
  required int startChannel,
  required int channelCount,
}) {
  if (notes.isEmpty || channelCount <= 0) return const [];
  final sorted = [...notes]..sort();
  final out = <RecordedNote>[];
  for (var i = 0; i < sorted.length; i++) {
    final channel = startChannel + i;
    if (channel >= channelCount) break;
    out.add(RecordedNote(channel: channel, row: row, midi: sorted[i]));
  }
  return out;
}

/// A count-in for a surface whose own clock is the authority.
///
/// `TransportService` has count-in machinery, but it belongs to `advance()` —
/// the mode where the transport owns the clock. The Tracker is the other kind of
/// client: its Stopwatch is authoritative and it pushes position DOWN with
/// `syncTo`, so it cannot ask the transport to hold time back. What it can do is
/// keep playing and refuse to commit, which is what a count-in is for anyway:
/// you hear the beat, you play along, and only what comes after the count is
/// kept.
///
/// The [bars] setting still comes from the transport, so the two surfaces share
/// one preference rather than growing a second one.
class RecordCountIn {
  const RecordCountIn({
    required this.startedAtMs,
    required this.bars,
    required this.barMs,
  });

  /// Transport position when recording was armed and playback began.
  final double startedAtMs;

  /// Bars to count, from `TransportService.countInBars`. 0 = no count-in.
  final int bars;

  /// One bar in milliseconds at the pattern's tempo and meter.
  final double barMs;

  /// No count-in at all — commit from the first note.
  static const RecordCountIn none = RecordCountIn(
    startedAtMs: 0,
    bars: 0,
    barMs: 0,
  );

  /// When committing starts.
  double get endsAtMs => startedAtMs + bars * barMs;

  /// Whether a note played at [nowMs] should be committed.
  ///
  /// Inclusive at the end so a note landing exactly on the downbeat that ends
  /// the count is KEPT — that is the note the count-in exists to prepare, and
  /// dropping it would punish the one player who was perfectly in time.
  bool commits(double nowMs) => bars <= 0 || nowMs >= endsAtMs;

  /// Whole bars still to count at [nowMs] (for a "3… 2… 1…" readout), 0 once
  /// recording is live.
  int barsRemaining(double nowMs) {
    if (commits(nowMs)) return 0;
    if (barMs <= 0) return bars;
    return ((endsAtMs - nowMs) / barMs).ceil();
  }
}

/// One live-record pass: everything played between arming and stopping.
///
/// It exists to answer "is this one undo entry or forty?" The screen's history
/// snapshots the WHOLE pattern per entry against an 80-entry cap, so a note per
/// entry meant a short jam pushed every earlier edit off the end — the work you
/// wanted to keep, evicted by the take you were still trying. A pass takes ONE
/// snapshot, on the first note actually committed: arming and then playing
/// nothing must not cost a history entry either.
class RecordPass {
  RecordPass({this.countIn = RecordCountIn.none});

  final RecordCountIn countIn;

  bool _snapshotTaken = false;
  int _committed = 0;

  /// Notes committed so far — what a "recorded N notes" readout shows, and how
  /// a caller knows the pass was not empty.
  int get committedCount => _committed;

  /// Whether anything has been committed, i.e. whether an undo entry exists.
  bool get hasCommitted => _snapshotTaken;

  /// Ask whether a note played at [nowMs] should be written, and learn whether
  /// this is the first one.
  ///
  /// Returns null when the count-in has not finished. Otherwise
  /// `needsSnapshot` is true exactly once per pass, so the caller pushes undo
  /// on the first committed note and never again.
  ({bool needsSnapshot})? commit(double nowMs) {
    if (!countIn.commits(nowMs)) return null;
    final first = !_snapshotTaken;
    _snapshotTaken = true;
    _committed++;
    return (needsSnapshot: first);
  }
}
