// lib/core/interop/drum_tracker.dart
//
// D2 — reading a drum beat back OUT of a Tracker song (PLAN.md §2.2's missing
// half).
//
// `beat_to_tracker.dart` already turns a [SharedBeat] into percussion channels,
// so a beat tapped out in the Drum Kit lands in the Tracker. Nothing read them
// back, so the trip was one-way: edit that beat in the Tracker's grid and the
// Drum Kit never hears about it. This is the exact inverse, which makes
// `beat -> song -> beat` round-trip identity a testable property rather than a
// hope — and that test is the real point of the file, because the two encodings
// are easy to drift apart.
//
// The encoding it has to reverse (from `drumSongFromBeat`):
//   * one channel per active drum, id `drum_<name>`;
//   * a PLAIN percussion channel encodes the drum in the note number
//     (`midi == Drum.index`), so the note is redundant with the channel;
//   * a channel whose drum carried a SAMPLE override plays note 60 instead (the
//     sample's natural pitch), and the drum is then only knowable from the id.
//
// So the channel id is the authority and the note is a fallback — which is why
// this reads the id first. A channel the Tracker's user added by hand, with no
// `drum_` id, is not a drum row and is reported rather than guessed at.
//
// Pure Dart, no Flutter.

import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show PercussionInstrument, TrackerChannel;
import 'package:comet_beat/core/audio/tracker_song.dart' show TrackerSong;
import 'package:comet_beat/core/interop/symbolic_annotation.dart'
    show ConversionReport;
import 'package:comet_beat/core/services/beat_bridge.dart'
    show SharedBeat, SharedVoice;

/// The channel-id prefix `drumSongFromBeat` writes.
const String kDrumChannelIdPrefix = 'drum_';

/// The result of reading a tracker song as a drum beat.
class TrackerToBeatResult {
  TrackerToBeatResult({required this.beat, required this.report});

  /// The beat, or null when [report] explains that the song has no drum rows.
  final SharedBeat? beat;
  final ConversionReport report;
}

/// The [Drum] a channel represents, or null when it is not a drum channel.
///
/// The id is authoritative (a sample-voiced drum channel plays note 60, so its
/// notes say nothing about which drum it is). A channel with no `drum_` id is
/// treated as pitched material, NOT guessed at from its notes — a bass line on
/// low MIDI numbers would otherwise silently become a kick pattern.
Drum? drumForChannel(TrackerChannel channel) {
  if (!channel.id.startsWith(kDrumChannelIdPrefix)) {
    // A percussion instrument with a non-drum id is still percussion; fall back
    // to the note encoding, which is what a hand-built channel would use.
    if (channel.instrument is PercussionInstrument) {
      for (final cell in channel.cells) {
        final midi = cell.midi;
        if (midi != null && midi >= 0 && midi < Drum.values.length) {
          return Drum.values[midi];
        }
      }
    }
    return null;
  }
  final name = channel.id.substring(kDrumChannelIdPrefix.length);
  for (final drum in Drum.values) {
    if (drum.name == name) return drum;
  }
  return null;
}

/// Reads [song]'s percussion channels back into a [SharedBeat] — the inverse of
/// `drumSongFromBeat`.
///
/// Returns a null beat (with a report saying so) when the song has no drum
/// channels at all, so a caller can offer "send to Drum Kit" only when it would
/// actually do something.
///
/// [voices] restores the per-drum sample overrides that the tracker encoding
/// cannot carry (a sample-voiced channel only knows it plays note 60). Pass the
/// ones from the beat this song came from; without them the Drum Kit uses its
/// own kit, which is a reasonable default rather than silence.
TrackerToBeatResult sharedBeatFromTrackerSong(
  TrackerSong song, {
  Map<Drum, SharedVoice> voices = const {},
  String source = 'tracker',
}) {
  final report = ConversionReport();
  final rows = <Drum, List<bool>>{};
  var pitchedChannels = 0;

  for (final channel in song.channels) {
    final drum = drumForChannel(channel);
    if (drum == null) {
      if (channel.hasAnyNote) pitchedChannels++;
      continue;
    }
    final row = [for (final cell in channel.cells) cell.midi != null];
    // Two channels can map to the same drum (a user duplicated one); OR them
    // together rather than letting the last one win, so no hit disappears.
    final existing = rows[drum];
    if (existing == null) {
      rows[drum] = row;
    } else {
      for (var i = 0; i < row.length && i < existing.length; i++) {
        existing[i] = existing[i] || row[i];
      }
      report.addApproximated('two channels played the same drum — merged');
    }
  }

  if (pitchedChannels > 0) {
    report.addLost(
      pitchedChannels == 1
          ? 'one pitched channel (a beat holds drums only)'
          : '$pitchedChannels pitched channels (a beat holds drums only)',
      'reasonPitchedChannels',
      [pitchedChannels],
    );
  }

  if (rows.isEmpty) {
    report.addLost(
      'this song has no drum channels, so there is no beat to send',
    );
    return TrackerToBeatResult(beat: null, report: report);
  }

  // Per-cell velocity and effect commands have no home in a boolean grid.
  for (final channel in song.channels) {
    if (drumForChannel(channel) == null) continue;
    if (channel.cells.any((c) => c.midi != null && (c.volume ?? 1.0) != 1.0)) {
      report.addLost('per-hit velocity (a beat row is on or off)');
      break;
    }
  }

  return TrackerToBeatResult(
    beat: SharedBeat(
      rows: rows,
      tempoBpm: song.timing.tempoBpm,
      swing: song.timing.swing,
      source: source,
      voices: voices,
    ),
    report: report,
  );
}
