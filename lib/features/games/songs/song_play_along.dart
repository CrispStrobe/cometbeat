// Turns a Song Book song's notation into a sing-along target, so a child can
// sing a stored song against the moving-score highway (the shipped
// PlayAlongEngine + mic grading). Pure and Flutter-free — unit-tested.

import 'package:comet_beat/core/audio/play_along.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show NoteElement, Score, playbackTimeline;

/// Derives a play/sing-along [PlayAlongChart] from [score].
///
/// Each sounded note becomes a [TargetNote] at its **top** pitch (a chord's
/// melody note), timed in quarter-note beats from [playbackTimeline] — so rests
/// leave gaps and repeats/navigation expand exactly as playback does.
///
/// [octaveAgnostic] (the default) is right for **singing** — a child matches the
/// melody in their own comfortable range and it still counts. Pass `false` for
/// **playing** an instrument, where the written octave is the target.
///
/// The tempo is [bpmOverride] if given, else the score's own initial tempo, else
/// 100 bpm. An all-rest (or empty) score yields a chart with no notes.
PlayAlongChart chartFromScore(
  Score score, {
  required String name,
  int? bpmOverride,
  bool octaveAgnostic = true,
}) {
  // Top (melody) midi per element id — the highest pitch of a chord.
  final topMidiOf = <String, int>{};
  for (final measure in score.measures) {
    for (final element in measure.elements) {
      if (element is NoteElement &&
          element.id != null &&
          element.pitches.isNotEmpty) {
        topMidiOf[element.id!] = element.pitches
            .map((p) => p.midiNumber)
            .reduce((a, b) => a > b ? a : b);
      }
    }
  }

  final notes = <TargetNote>[];
  for (final n in playbackTimeline(score)) {
    if (n.isRest) continue;
    final midi = topMidiOf[n.elementId];
    if (midi == null) continue; // grace/unknown — no target
    // Whole-note fractions → quarter-note beats (× 4).
    notes.add(
      TargetNote(
        midi: midi,
        startBeat: n.start.numerator / n.start.denominator * 4,
        beats: n.duration.numerator / n.duration.denominator * 4,
      ),
    );
  }

  final scoreBpm = score.tempo != null ? score.tempo!.quarterBpm.round() : 100;
  final bpm = bpmOverride ?? scoreBpm;
  return PlayAlongChart(
    name: name,
    bpm: bpm > 0 ? bpm : 100,
    notes: notes,
    octaveAgnostic: octaveAgnostic,
  );
}
