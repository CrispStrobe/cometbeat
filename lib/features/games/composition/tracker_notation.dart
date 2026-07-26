// lib/features/games/composition/tracker_notation.dart
//
// The notation bridge (Tracker → Score): turns a tracker channel's pattern into
// a real crisp_notation Score, so the grid can be shown as staff notation — the
// "score view" of the tracker (and the link to the Workshop). Reuses the
// grid_composer idea (grid → Score) generalized to the tracker's held notes and
// step resolution.
//
// Fidelity: a channel is monophonic, so this is near-lossless — held runs become
// tied notes decomposed into standard values, split at 4/4 bar lines. The
// reverse (Score → Tracker) is inherently partial (quantize + monophonic-per-
// channel + scale-snap) and is a later slice.

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/shared/midi_pitch.dart';
import 'package:comet_beat/shared/step_duration.dart';
import 'package:crisp_notation/crisp_notation.dart';

// B1 — `pitchFromMidi` used to be copy-pasted into five files (two spelled via a
// pitch-class table, two via natural-below-plus-sharp; all four agreed with the
// canonical one). It now lives once in `lib/shared/midi_pitch.dart` and is
// re-exported here, so this file's existing consumers are unaffected.
export 'package:comet_beat/shared/midi_pitch.dart' show pitchFromMidi;

// B2 — `durationToSteps` / the duration ladder / the greedy decomposition used
// to be a verbatim copy here and in the other step-grid mode. They live once in
// `lib/shared/step_duration.dart` now and are re-exported so this file's
// consumers are unaffected.
export 'package:comet_beat/shared/step_duration.dart'
    show decomposeSteps, durationLadder, durationToSteps;

/// Builds a single-voice [Score] from [channel]'s pattern. Held runs become
/// tied notes; notes are decomposed into standard values and split at 4/4 bar
/// lines (with a tie across the line). An empty channel yields a single bar of
/// rests.
///
/// A Note Cut (key-off) ends the note and the rows after it become RESTS. This
/// reads [noteRuns] rather than [cellRuns] to see that: `cellRuns` adds the
/// release phase back onto the sustain, which is right for "how long until the
/// next trigger" but wrong for notation — it drew a note running through the
/// silence the module actually plays, so a cut-off phrase came out as one long
/// held note and a score round trip grew notes that were never written.
Score trackerChannelToScore(
  TrackerChannel channel,
  TrackerTiming timing, {
  Clef clef = Clef.treble,
}) {
  final ladder = durationLadder(timing.stepsPerBeat);
  final barSteps = timing.stepsPerBeat * 4; // 4/4
  final measures = <Measure>[];
  var current = <MusicElement>[];
  var posInBar = 0;

  void closeBar() {
    measures.add(Measure(current));
    current = [];
    posInBar = 0;
  }

  /// Lays [steps] of [midi] (null = silence) onto the bar grid.
  void emit(int? midi, int steps) {
    var rem = steps;
    while (rem > 0) {
      final avail = barSteps - posInBar;
      final take = rem < avail ? rem : avail;
      final pieces = decomposeSteps(take, ladder);
      for (var i = 0; i < pieces.length; i++) {
        // The run ends only when this take exhausts it AND it's the last piece.
        final lastOfRun = rem - take == 0 && i == pieces.length - 1;
        if (midi == null) {
          current.add(RestElement(pieces[i]));
        } else {
          current.add(
            NoteElement.note(
              pitchFromMidi(midi),
              pieces[i],
              tieToNext: !lastOfRun,
            ),
          );
        }
      }
      posInBar += take;
      rem -= take;
      if (posInBar >= barSteps) closeBar();
    }
  }

  for (final (midi, sustain, release) in noteRuns(channel.cells)) {
    emit(midi, sustain);
    emit(null, release); // the note is off — this is silence, not more note
  }
  if (current.isNotEmpty) closeBar();

  return Score(clef: clef, measures: measures);
}

// ---------------------------------------------------------------------------
// Score → Tracker (the partial reverse direction)
// ---------------------------------------------------------------------------

const _pentaPcs = [0, 2, 4, 7, 9]; // C D E G A

/// Snaps [midi] to the nearest C-pentatonic note (ties go to the lower note) —
/// so an imported chromatic melody lands on the Sandbox grid.
int snapToPentatonic(int midi) {
  var best = midi;
  var bestDist = 1 << 30;
  final octaveBase = (midi ~/ 12) * 12;
  for (final pc in _pentaPcs) {
    for (final cand in [
      octaveBase + pc - 12,
      octaveBase + pc,
      octaveBase + pc + 12,
    ]) {
      final dist = (cand - midi).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = cand;
      }
    }
  }
  return best;
}

/// Imports [score] into a channel's cells (length [TrackerTiming.rows]). This is
/// **partial by nature**: durations quantize to the step grid, a chord keeps only
/// its top note (channels are monophonic), tied notes merge into one held note,
/// content past the grid is truncated, and — when [snapToScale] — pitches snap to
/// C-pentatonic so they land on the Sandbox grid. Note onsets go in the cell;
/// held steps stay empty (the tracker's "let it ring").
List<TrackerCell> scoreToTrackerCells(
  Score score,
  TrackerTiming timing, {
  bool snapToScale = true,
}) {
  final cells = List<TrackerCell>.filled(
    timing.rows,
    TrackerCell.empty,
    growable: true,
  );
  final elements = [for (final m in score.measures) ...m.elements];

  var i = 0;
  var step = 0;
  while (i < elements.length && step < timing.rows) {
    final el = elements[i];
    if (el is RestElement) {
      step += durationToSteps(el.duration, timing.stepsPerBeat);
      i++;
      continue;
    }
    if (el is NoteElement) {
      var steps = durationToSteps(el.duration, timing.stepsPerBeat);
      // Top note of a chord (monophonic channel).
      int? top;
      for (final p in el.pitches) {
        if (top == null || p.midiNumber > top) top = p.midiNumber;
      }
      // Merge tied continuations into one held note.
      var cur = el;
      while (cur.tieToNext &&
          i + 1 < elements.length &&
          elements[i + 1] is NoteElement) {
        final next = elements[i + 1] as NoteElement;
        steps += durationToSteps(next.duration, timing.stepsPerBeat);
        cur = next;
        i++;
      }
      if (top != null && step < timing.rows) {
        cells[step] =
            TrackerCell(midi: snapToScale ? snapToPentatonic(top) : top);
      }
      step += steps;
      i++;
      continue;
    }
    i++; // barlines / other elements — skip
  }
  return cells;
}

// ---------------------------------------------------------------------------
// Maximal fidelity: multi-channel bridges (both directions)
// ---------------------------------------------------------------------------

/// One [Score] per PITCHED channel that has notes — the full-band "score view".
/// Empty channels and [PercussionInstrument] channels are skipped (drums have no
/// pitch to notate). The channel with `id == 'bass'` is drawn in [Clef.bass];
/// every other part uses [Clef.treble]. Each part reuses [trackerChannelToScore],
/// so it inherits the same held-run → tied-note decomposition and bar splitting.
List<Score> trackerToScoreParts(
  List<TrackerChannel> channels,
  TrackerTiming timing,
) {
  final parts = <Score>[];
  for (final channel in channels) {
    if (!channel.hasAnyNote) continue;
    if (channel.instrument is PercussionInstrument) continue;
    final clef = channel.id == 'bass' ? Clef.bass : Clef.treble;
    parts.add(trackerChannelToScore(channel, timing, clef: clef));
  }
  return parts;
}

/// Splits a polyphonic [score] across [channelCount] monophonic tracker channels.
/// For each element its pitches are sorted HIGH→LOW and dealt out to channels
/// 0, 1, 2, … (channel 0 = the top voice); a monophonic note fills only channel 0
/// and extra voices beyond [channelCount] are dropped. Durations quantize to the
/// step grid and — when [snapToScale] — pitches snap to C-pentatonic, exactly as
/// [scoreToTrackerCells] does. Returns exactly [channelCount] cell-lists, each of
/// length [TrackerTiming.rows].
List<List<TrackerCell>> scoreToChannels(
  Score score,
  TrackerTiming timing, {
  int channelCount = 4,
  bool snapToScale = true,
}) {
  final channels = [
    for (var c = 0; c < channelCount; c++)
      List<TrackerCell>.filled(timing.rows, TrackerCell.empty, growable: true),
  ];
  final elements = [for (final m in score.measures) ...m.elements];

  var i = 0;
  var step = 0;
  while (i < elements.length && step < timing.rows) {
    final el = elements[i];
    if (el is RestElement) {
      step += durationToSteps(el.duration, timing.stepsPerBeat);
      i++;
      continue;
    }
    if (el is NoteElement) {
      var steps = durationToSteps(el.duration, timing.stepsPerBeat);
      // Top voice first (high → low).
      final voices = [for (final p in el.pitches) p.midiNumber]
        ..sort((a, b) => b.compareTo(a));
      // Merge tied continuations into one held note (element-level, matching
      // scoreToTrackerCells).
      var cur = el;
      while (cur.tieToNext &&
          i + 1 < elements.length &&
          elements[i + 1] is NoteElement) {
        final next = elements[i + 1] as NoteElement;
        steps += durationToSteps(next.duration, timing.stepsPerBeat);
        cur = next;
        i++;
      }
      if (step < timing.rows) {
        for (var v = 0; v < voices.length && v < channelCount; v++) {
          final midi = snapToScale ? snapToPentatonic(voices[v]) : voices[v];
          channels[v][step] = TrackerCell(midi: midi);
        }
      }
      step += steps;
      i++;
      continue;
    }
    i++; // barlines / other elements — skip
  }
  return channels;
}

/// A short original C-pentatonic tune (one 4/4 bar of quarters, C D E G) offered
/// as a starting melody to remix — proves the Score→Tracker direction end-to-end
/// and gives a kid something to build on. Lands exactly on the melody channel's
/// treble grid.
final Score kTrackerDemoTune = Score(
  clef: Clef.treble,
  measures: [
    Measure([
      NoteElement.note(const Pitch(Step.c), NoteDuration.quarter),
      NoteElement.note(const Pitch(Step.d), NoteDuration.quarter),
      NoteElement.note(const Pitch(Step.e), NoteDuration.quarter),
      NoteElement.note(const Pitch(Step.g), NoteDuration.quarter),
    ]),
  ],
);
