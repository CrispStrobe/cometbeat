// lib/features/games/composition/multipart_to_tracker.dart
//
// One place that turns a MultiPartScore into a TrackerSong — one chromatic
// tracker channel per part. Shared by the Advanced Tracker's score import and
// by any "open in Tracker" interconnection (e.g. Loop Mixer groove → Tracker),
// so the conversion lives once, not copy-pasted per caller.

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/features/games/composition/tracker_notation.dart'
    show scoreToChannels, trackerToScoreParts;
import 'package:crisp_notation/crisp_notation.dart' show MultiPartScore, Score;

/// Builds a [TrackerSong] from [mp] — one chromatic channel per part (no
/// pentatonic snap). Empty score → an empty default song.
TrackerSong trackerSongFromMultiPart(MultiPartScore mp) {
  const timing = TrackerTiming(rows: 64);
  final channels = <TrackerChannel>[];
  final cells = <List<TrackerCell>>[];
  for (var p = 0; p < mp.parts.length; p++) {
    final Score part = mp.parts[p];
    final col = scoreToChannels(
      part,
      timing,
      channelCount: 1,
      snapToScale: false,
    ).first;
    channels.add(
      TrackerChannel(
        id: 'part${p + 1}',
        instrument: kTrackerInstruments.first.build(),
        rows: timing.rows,
        cells: col,
      ),
    );
    cells.add(col);
  }
  if (channels.isEmpty) return TrackerSong();
  return TrackerSong.fromParts(
    channels: channels,
    timing: timing,
    patterns: [TrackerPattern(name: '00', cells: cells)],
    order: [0],
  );
}

/// Converts a tracker's played pattern order into a notation score. Tracker
/// channels are monophonic, so percussion and empty channels are omitted; all
/// pitched pattern rows are concatenated in order before quantization into
/// measures. This is intentionally lossy, but preserves the melodic content
/// well enough for Score/Tab editing.
MultiPartScore multiPartScoreFromTrackerSong(TrackerSong song) {
  song.syncCurrent();
  final channelCount = song.channelCount;
  final combined = <List<TrackerCell>>[
    for (var c = 0; c < channelCount; c++) <TrackerCell>[],
  ];
  for (final patternIndex in song.order) {
    if (patternIndex < 0 || patternIndex >= song.patterns.length) continue;
    final pattern = song.patterns[patternIndex];
    for (var c = 0; c < channelCount && c < pattern.cells.length; c++) {
      combined[c].addAll(pattern.cells[c]);
    }
  }
  if (combined.isEmpty || combined.first.isEmpty) {
    return MultiPartScore(const []);
  }
  final channels = [
    for (var c = 0; c < channelCount; c++)
      TrackerChannel(
        id: song.channels[c].id,
        instrument: song.channels[c].instrument,
        rows: combined[c].length,
        cells: combined[c],
      ),
  ];
  return MultiPartScore(
    trackerToScoreParts(
      channels,
      song.timing.copyWith(rows: combined.first.length),
    ),
  );
}
