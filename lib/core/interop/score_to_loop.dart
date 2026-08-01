// lib/core/interop/score_to_loop.dart
//
// Notation → the Loop Studio's 2-bar grid, so the music library can reach it.
//
// Loop Studio was the ONE authoring surface with no way to bring real music in:
// the Tracker, the Workshop, the Tab Workshop and the Audio Editor all call the
// music picker, and Loop Studio only ever reached the INSTRUMENT library. The
// reason it had no route is that its document is not a score — it is a fixed
// 2-bar grid of eighth-note cells — so something had to decide what "this
// 40-bar piece" means as a loop. That decision is here rather than inline in
// the screen, because it is lossy and worth being explicit about.
//
// WHICH PART BECOMES THE LOOP. The highest-sounding part, by mean pitch — NOT
// the one with the most notes. Counting notes picks the ACCOMPANIMENT on any
// voice-plus-piano score (a broken-chord left hand easily outnumbers the tune),
// which is the same trap the corpus feature-index hit and recorded. Register is
// what actually identifies a melody.
//
// WHAT IS LOST, AND WHY THAT IS THE RIGHT TRADE. The loop grid is eighths, so
// anything finer quantizes; it is two bars, so a longer piece is windowed to
// its opening; and a cell is monophonic here, so a chord keeps its top note.
// The alternative — refusing anything that does not already fit — is what the
// surface did before, and it meant the library was simply unreachable.

import 'package:comet_beat/core/audio/loop_engine.dart'
    show PatternCell, kPatternSteps;
import 'package:comet_beat/core/services/melody_bridge.dart'
    show patternCellsFromMidiRows;
import 'package:comet_beat/shared/step_duration.dart' show durationToSteps;
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show MultiPartScore, NoteElement, RestElement, Score;

/// The loop grid is eighths — two steps per beat ([LoopTiming.stepsPerBar] is
/// 8 per 4/4 bar).
const int kLoopStepsPerBeat = 2;

/// What a conversion had to give up, so the caller can say so rather than
/// silently hand back something smaller than the user chose.
class ScoreToLoopReport {
  const ScoreToLoopReport({
    required this.truncated,
    required this.quantized,
    required this.chordsFlattened,
    required this.totalSteps,
  });

  /// The piece was longer than the 2-bar grid and only its opening was kept.
  final bool truncated;

  /// At least one note was shorter than an eighth and got rounded onto the grid.
  final bool quantized;

  /// At least one chord was reduced to its top note.
  final bool chordsFlattened;

  /// How many eighth-steps the source actually needed.
  final int totalSteps;

  bool get isLossless => !truncated && !quantized && !chordsFlattened;
}

/// The part of [mp] that most likely carries the tune: the highest by MEAN
/// pitch among parts that have any notes at all.
///
/// Mean rather than max so one high grace note in a bass part cannot win, and
/// register rather than note count for the reason in the file header.
Score? melodyPartOf(MultiPartScore mp) {
  Score? best;
  var bestMean = double.negativeInfinity;
  for (final part in mp.parts) {
    var sum = 0;
    var count = 0;
    for (final measure in part.measures) {
      for (final element in measure.elements) {
        if (element is NoteElement && element.pitches.isNotEmpty) {
          // A chord contributes its TOP note, which is what the loop would
          // keep anyway — averaging the whole voicing would drag a
          // melody-over-chords part down toward its accompaniment.
          sum += _topMidi(element);
          count++;
        }
      }
    }
    if (count == 0) continue;
    final mean = sum / count;
    if (mean > bestMean) {
      bestMean = mean;
      best = part;
    }
  }
  return best;
}

/// The highest sounding pitch of [note].
int _topMidi(NoteElement note) {
  var top = note.pitches.first.midiNumber;
  for (final p in note.pitches) {
    if (p.midiNumber > top) top = p.midiNumber;
  }
  return top;
}

/// [score] as a per-eighth-step grid of absolute MIDI pitches (null = no fresh
/// trigger on that step; the previous note rings on, tracker-style).
///
/// A note shorter than one step still gets a step — dropping it would delete
/// the note outright, and a quantized note is a better answer than a missing
/// one. That collision is reported, not hidden.
({List<int?> rows, ScoreToLoopReport report}) midiRowsFromScore(
  Score score, {
  int steps = kPatternSteps,
}) {
  final rows = List<int?>.filled(steps, null);
  var pos = 0;
  var quantized = false;
  var chordsFlattened = false;
  // `tieToNext` is stated by the note BEFORE the continuation, so the walk has
  // to carry it forward. Without this a tied half note would re-strike on its
  // second half — one long note heard as two.
  var tiedIn = false;

  for (final measure in score.measures) {
    for (final element in measure.elements) {
      if (element is NoteElement) {
        final len = durationToSteps(element.duration, kLoopStepsPerBeat);
        if (len == 0) quantized = true;
        if (element.pitches.length > 1) chordsFlattened = true;
        if (pos < steps && !tiedIn && element.pitches.isNotEmpty) {
          rows[pos] = _topMidi(element);
        }
        tiedIn = element.tieToNext;
        pos += len == 0 ? 1 : len;
      } else if (element is RestElement) {
        final len = durationToSteps(element.duration, kLoopStepsPerBeat);
        tiedIn = false; // a rest ends any tie
        pos += len == 0 ? 1 : len;
      }
    }
  }
  return (
    rows: rows,
    report: ScoreToLoopReport(
      truncated: pos > steps,
      quantized: quantized,
      chordsFlattened: chordsFlattened,
      totalSteps: pos,
    ),
  );
}

/// [mp]'s melody as loop cells, ready for `LoopEngine.setUserTrack`.
///
/// Returns null when the score carries no sounding note at all — the caller
/// should say so rather than install a silent track.
({List<PatternCell> cells, ScoreToLoopReport report})? loopCellsFromScore(
  MultiPartScore mp, {
  int steps = kPatternSteps,
}) {
  final part = melodyPartOf(mp);
  if (part == null) return null;
  final walked = midiRowsFromScore(part, steps: steps);
  if (walked.rows.every((r) => r == null)) return null;
  return (
    cells: patternCellsFromMidiRows(walked.rows, steps: steps),
    report: walked.report,
  );
}
