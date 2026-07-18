// lib/features/games/composition/multipart_to_tracker.dart
//
// One place that turns a MultiPartScore into a TrackerSong — one chromatic
// tracker channel per part. Shared by the Advanced Tracker's score import and
// by any "open in Tracker" interconnection (e.g. Loop Mixer groove → Tracker),
// so the conversion lives once, not copy-pasted per caller.

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/features/games/composition/tracker_notation.dart'
    show scoreToChannels;
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
