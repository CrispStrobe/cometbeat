// lib/features/games/composition/multipart_to_tracker.dart
//
// One place that turns a MultiPartScore into a TrackerSong — one chromatic
// tracker channel per part. Shared by the Advanced Tracker's score import and
// by any "open in Tracker" interconnection (e.g. Loop Mixer groove → Tracker),
// so the conversion lives once, not copy-pasted per caller.

import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/interop/tracker_song_flatten.dart';
import 'package:comet_beat/features/games/composition/tracker_notation.dart'
    show scoreToChannels, trackerToScoreParts;
import 'package:comet_beat/shared/step_duration.dart' show durationToSteps;
import 'package:crisp_notation/crisp_notation.dart'
    show MultiPartScore, NoteElement, RestElement, Score;

/// Rows in one pattern of an imported song.
///
/// 64 is the tracker convention and what the pattern editor is laid out for; a
/// score longer than that becomes SEVERAL patterns rather than one long one.
const int kImportPatternRows = 64;

/// The voice channel [p] should sound through.
///
/// ⚠️ This used to be `kTrackerInstruments.first.build()` for EVERY part, i.e.
/// piano regardless of what the music sounded like where it came from. That is
/// why "open in Tracker" changed the timbre of a groove: a cello line arrived as
/// a piano line. It is not an approximation problem — the Tracker's
/// `AdditiveInstrument` wraps the SAME `Instrument` enum the Loop engine uses
/// and renders through the same `timbreFor` + `renderSegmentsRaw` path, so a
/// carried voice is identical, not merely close.
///
/// A caller with no voice to offer (a plain notation import, which genuinely
/// has none) still gets the first instrument, so that path is unchanged.
TrackerInstrument _voiceFor(List<Instrument?>? voices, int p) {
  final voice = (voices != null && p < voices.length) ? voices[p] : null;
  if (voice == null) return kTrackerInstruments.first.build();
  return AdditiveInstrument(voice.name, voice);
}

/// How many grid steps [score] needs end to end.
///
/// Every element contributes its own duration whether or not it is tied — a tie
/// merges two notes into one held cell, but the held cell still occupies both
/// durations, so summing is exact rather than an estimate.
int _stepsNeeded(Score score, TrackerTiming timing) {
  var steps = 0;
  for (final measure in score.measures) {
    for (final element in measure.elements) {
      if (element is NoteElement) {
        steps += durationToSteps(element.duration, timing.stepsPerBeat);
      } else if (element is RestElement) {
        steps += durationToSteps(element.duration, timing.stepsPerBeat);
      }
    }
  }
  return steps;
}

/// Builds a [TrackerSong] from [mp] — one chromatic channel per part (no
/// pentatonic snap). Empty score → an empty default song.
///
/// The song is sized to the MUSIC. This used to render into a single fixed
/// 64-row pattern, which silently truncated anything longer: "London Bridge"
/// arrived as its first thirteen notes and the rest was simply gone, with no
/// error and nothing in the conversion report to say so. Now the parts are
/// rendered at full length and split across as many 64-row patterns as they
/// need, which is also the shape a module importer produces — so the inverse
/// [multiPartScoreFromTrackerSong], which concatenates patterns in order,
/// reads the whole song back.
TrackerSong trackerSongFromMultiPart(
  MultiPartScore mp, {
  List<Instrument?>? voices,
}) {
  const timing = TrackerTiming(rows: kImportPatternRows);

  // Long enough for the longest part, and never shorter than one pattern.
  var total = 0;
  for (final part in mp.parts) {
    final steps = _stepsNeeded(part, timing);
    if (steps > total) total = steps;
  }
  if (total < kImportPatternRows) total = kImportPatternRows;
  final patternCount = (total + kImportPatternRows - 1) ~/ kImportPatternRows;
  final fullRows = patternCount * kImportPatternRows;
  final fullTiming = timing.copyWith(rows: fullRows);

  // Render each part across the WHOLE length first, then slice: a note's row is
  // its position in the piece, so slicing after placement keeps every note where
  // the music put it, including notes that straddle a pattern boundary.
  final full = <List<TrackerCell>>[];
  for (final Score part in mp.parts) {
    final col = scoreToChannels(
      part,
      fullTiming,
      channelCount: 1,
      snapToScale: false,
    ).first;

    // Stop the last note where the music stops. A tracker cell sounds until
    // something replaces it, so without this the final note runs on through the
    // padding rows up to the pattern boundary — which reads back as a longer
    // note than was written, or as an extra tied note after it.
    final end = _stepsNeeded(part, timing);
    if (end < col.length) col[end] = const TrackerCell(keyOff: true);

    full.add(col);
  }
  if (full.isEmpty) return TrackerSong();

  final patterns = <TrackerPattern>[];
  for (var p = 0; p < patternCount; p++) {
    final start = p * kImportPatternRows;
    patterns.add(
      TrackerPattern(
        name: p.toString().padLeft(2, '0'),
        cells: [
          for (final col in full)
            List<TrackerCell>.of(
              col.sublist(start, start + kImportPatternRows),
            ),
        ],
      ),
    );
  }

  // Channels mirror the selected (first) pattern — `fromParts` loads that one
  // into the editing engine.
  final channels = <TrackerChannel>[
    for (var p = 0; p < full.length; p++)
      TrackerChannel(
        id: 'part${p + 1}',
        instrument: _voiceFor(voices, p),
        rows: kImportPatternRows,
        cells: patterns.first.cells[p],
      ),
  ];

  return TrackerSong.fromParts(
    channels: channels,
    timing: timing,
    patterns: patterns,
    order: [for (var p = 0; p < patternCount; p++) p],
  );
}

/// Converts a tracker's played pattern order into a notation score. Tracker
/// channels are monophonic, so percussion and empty channels are omitted; all
/// pitched pattern rows are concatenated in order before quantization into
/// measures. This is intentionally lossy, but preserves the melodic content
/// well enough for Score/Tab editing.
MultiPartScore multiPartScoreFromTrackerSong(TrackerSong song) {
  // Shared with the Tab and Loop converters, which used to flatten the song
  // themselves — or, in their case, forget to and read only the loaded pattern.
  final channels = trackerChannelsAcrossOrder(song);
  if (channels.isEmpty) return MultiPartScore(const []);
  return MultiPartScore(
    trackerToScoreParts(
      channels,
      song.timing.copyWith(rows: channels.first.cells.length),
    ),
  );
}
