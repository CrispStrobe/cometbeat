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

import 'package:crisp_notation/crisp_notation.dart';
import 'package:klang_universum/core/audio/tracker_engine.dart';

// Sharp spelling for each pitch class → (Step, alter).
const _pcSpelling = <(Step, int)>[
  (Step.c, 0), (Step.c, 1), (Step.d, 0), (Step.d, 1), // C C# D D#
  (Step.e, 0), (Step.f, 0), (Step.f, 1), (Step.g, 0), // E F F# G
  (Step.g, 1), (Step.a, 0), (Step.a, 1), (Step.b, 0), // G# A A# B
];

/// A [Pitch] for a MIDI note (sharp spelling; C4 = 60).
Pitch pitchFromMidi(int midi) {
  final (step, alter) = _pcSpelling[midi % 12];
  return Pitch(step, alter: alter, octave: (midi ~/ 12) - 1);
}

/// The note values available at [stepsPerBeat] resolution, largest first, as
/// (duration, lengthInSteps) — only those spanning a whole number of steps in
/// 4/4 (so e.g. a dotted-eighth is dropped when a step is an eighth).
List<(NoteDuration, int)> _durationLadder(int stepsPerBeat) {
  final stepsPerWhole = stepsPerBeat * 4; // 4/4
  const candidates = <(NoteDuration, double)>[
    (NoteDuration(DurationBase.whole), 1.0),
    (NoteDuration(DurationBase.half, dots: 1), 0.75),
    (NoteDuration(DurationBase.half), 0.5),
    (NoteDuration(DurationBase.quarter, dots: 1), 0.375),
    (NoteDuration(DurationBase.quarter), 0.25),
    (NoteDuration(DurationBase.eighth, dots: 1), 0.1875),
    (NoteDuration(DurationBase.eighth), 0.125),
    (NoteDuration(DurationBase.sixteenth, dots: 1), 0.09375),
    (NoteDuration(DurationBase.sixteenth), 0.0625),
  ];
  final out = <(NoteDuration, int)>[];
  for (final (dur, frac) in candidates) {
    final steps = frac * stepsPerWhole;
    if ((steps - steps.roundToDouble()).abs() < 1e-9) {
      out.add((dur, steps.round()));
    }
  }
  return out; // already largest-first
}

/// Greedily decomposes [steps] into note values (largest first).
List<NoteDuration> _decompose(int steps, List<(NoteDuration, int)> ladder) {
  final out = <NoteDuration>[];
  var rem = steps;
  while (rem > 0) {
    final piece = ladder.firstWhere((d) => d.$2 <= rem);
    out.add(piece.$1);
    rem -= piece.$2;
  }
  return out;
}

/// Builds a single-voice [Score] from [channel]'s pattern. Held runs become
/// tied notes; notes are decomposed into standard values and split at 4/4 bar
/// lines (with a tie across the line). An empty channel yields a single bar of
/// rests.
Score trackerChannelToScore(
  TrackerChannel channel,
  TrackerTiming timing, {
  Clef clef = Clef.treble,
}) {
  final ladder = _durationLadder(timing.stepsPerBeat);
  final barSteps = timing.stepsPerBeat * 4; // 4/4
  final measures = <Measure>[];
  var current = <MusicElement>[];
  var posInBar = 0;

  void closeBar() {
    measures.add(Measure(current));
    current = [];
    posInBar = 0;
  }

  for (final (midi, steps) in cellRuns(channel.cells)) {
    var rem = steps;
    while (rem > 0) {
      final avail = barSteps - posInBar;
      final take = rem < avail ? rem : avail;
      final pieces = _decompose(take, ladder);
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
  if (current.isNotEmpty) closeBar();

  return Score(clef: clef, measures: measures);
}
