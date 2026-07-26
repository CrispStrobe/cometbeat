// lib/core/interop/tracker_song_flatten.dart
//
// A whole tracker song as one channel per part, patterns laid end to end in
// play order.
//
// `TrackerSong.channels` is the EDITING view: it holds the pattern currently
// loaded into the engine, because that is what the grid is showing and editing.
// That makes it the wrong thing to read when you want the song — and an easy
// mistake, because for a one-pattern song the two are identical, which is
// exactly what a hand-written test fixture usually is.
//
// Reading `channels` when you meant the song silently drops every pattern after
// the first. Two converters did (Tracker → Tab, Tracker → Loop) and reported the
// result as lossless, so a song imported from a score came back as its first 64
// rows with nothing to say the rest had gone.

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';

/// [song]'s channels with every pattern in [TrackerSong.order] concatenated.
///
/// Unsaved edits to the pattern on screen are included: they live in the engine
/// rather than in the pattern snapshot, so this READS them from
/// [TrackerSong.engine]. It deliberately does not call
/// [TrackerSong.syncCurrent], which would write them back — a converter should
/// not mutate the document it is reading, and a song whose patterns were built
/// from `const` cell lists makes that write throw outright.
///
/// Out-of-range order entries are skipped rather than throwing — an order list
/// can outlive the pattern it points at.
///
/// Returns an empty list when the song has no cells at all, which callers
/// should treat as "nothing to convert" rather than as a one-row song.
List<TrackerChannel> trackerChannelsAcrossOrder(TrackerSong song) {
  final channelCount = song.channelCount;
  if (channelCount == 0) return const [];

  final live = song.engine.exportCells();
  final currentIndex = song.currentIndex;

  /// Channel [c] of [patternIndex] — the live grid for the selected pattern,
  /// the stored snapshot for every other.
  List<TrackerCell> cellsOf(int patternIndex, int c) =>
      patternIndex == currentIndex && c < live.length
          ? live[c]
          : song.patterns[patternIndex].cells[c];

  final combined = <List<TrackerCell>>[
    for (var c = 0; c < channelCount; c++) <TrackerCell>[],
  ];
  for (final patternIndex in song.order) {
    if (patternIndex < 0 || patternIndex >= song.patterns.length) continue;
    final pattern = song.patterns[patternIndex];
    for (var c = 0; c < channelCount && c < pattern.cells.length; c++) {
      combined[c].addAll(cellsOf(patternIndex, c));
    }
  }
  if (combined.first.isEmpty) return const [];

  return [
    for (var c = 0; c < channelCount; c++)
      TrackerChannel(
        id: song.channels[c].id,
        instrument: song.channels[c].instrument,
        rows: combined[c].length,
        cells: combined[c],
      ),
  ];
}

/// How many rows [trackerChannelsAcrossOrder] spans, for retiming a
/// [TrackerTiming] whose `rows` describes only the selected pattern.
int trackerRowsAcrossOrder(TrackerSong song) {
  var rows = 0;
  for (final patternIndex in song.order) {
    if (patternIndex < 0 || patternIndex >= song.patterns.length) continue;
    final pattern = song.patterns[patternIndex];
    if (pattern.cells.isEmpty) continue;
    rows += pattern.cells.first.length;
  }
  return rows;
}
