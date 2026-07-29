// lib/core/games/highway/highway_review.dart
//
// REVIEW: what you actually played, against what was written.
//
// Live microphone grading is monophonic — the detector tracks one pitch at a
// time — and the polyphonic transcriber cannot answer in time to grade a note
// as it passes (it works on ten-second segments). So the honest way to grade a
// two-handed piano take by ear is not to do it live at all: play the whole
// thing, then look at the recording.
//
// That is what this file aligns. It is deliberately pure and separate from the
// screen: matching heard notes to written ones is the entire musical question,
// and it should be testable without a microphone, a model, or a widget.

import 'package:comet_beat/core/audio/transcription/contracts.dart'
    show NoteEvent;
import 'package:comet_beat/core/games/highway/highway_chart.dart';

/// Which of [events] the player actually played, given what was [heard].
///
/// Returns the indices of the events that were matched. The rules mirror live
/// tap grading, because the same fairness questions arise:
///
///  * a heard note claims AT MOST ONE written note — the nearest in time — so
///    a sustained or re-struck note cannot answer for a whole bar of the same
///    pitch;
///  * a written note is claimed at most once, for the same reason;
///  * extra notes the player added are ignored rather than penalised. A
///    transcriber hears the room, the pedal and the neighbour's television, and
///    a take should not be marked down for what the microphone found.
///
/// [startOffsetMs] is where the chart's beat 0 sits inside the recording (a
/// count-in, typically). [windowMs] is how far from its written time a note may
/// be heard and still count.
Set<int> matchHeardToChart({
  required List<HighwayEvent> events,
  required List<NoteEvent> heard,
  required double beatMs,
  required double startOffsetMs,
  required double windowMs,
}) {
  final claimed = <int>{};
  // Nearest-first, so a note played once between two written ones goes to the
  // closer of them rather than to whichever was listed first.
  final pairs = <({int index, int heardIndex, double distance})>[];
  for (var e = 0; e < events.length; e++) {
    final midi = events[e].midi;
    if (midi == null) continue;
    final atMs = startOffsetMs + events[e].startBeat * beatMs;
    for (var h = 0; h < heard.length; h++) {
      if (heard[h].midi != midi) continue;
      final distance = (heard[h].onMs - atMs).abs();
      if (distance > windowMs) continue;
      pairs.add((index: e, heardIndex: h, distance: distance));
    }
  }
  pairs.sort((a, b) => a.distance.compareTo(b.distance));

  final usedHeard = <int>{};
  for (final pair in pairs) {
    if (claimed.contains(pair.index)) continue;
    if (usedHeard.contains(pair.heardIndex)) continue;
    claimed.add(pair.index);
    usedHeard.add(pair.heardIndex);
  }
  return claimed;
}
