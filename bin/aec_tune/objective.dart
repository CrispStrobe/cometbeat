// bin/aec_tune/objective.dart
//
// The objective an automatic tuner maximizes — deliberately DOMAIN-appropriate,
// not the industry's speech-MOS. Per docs/LOOP_MIXER_FOLLOWUPS_HANDOVER.md we
// judge by the decoded outcome ("does the detector still hear the instrument?"),
// not by AEC-internal numbers. So a config's score combines:
//
//   * note-survival — after cancellation, does the pitch detector read the
//     near-end's true note over the double-talk region? This is the thing the
//     app actually needs, and the guardrail against a config that maximizes echo
//     removal by chewing the near-end.
//   * SI-SDR (dB) of the cleaned output vs the KNOWN true near-end over the
//     double-talk region — the gain-invariant fidelity of what survived.
//
// Score = mean SI-SDR + kNoteBonus * (fraction of scenarios whose note survived).
// Higher is better. SI-SDR carries the fine gradient; the note bonus dominates
// when a config starts destroying the signal, steering the search back.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/aec_offline.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';

import 'corpus.dart';

/// dB added to the score per scenario whose note survives — large enough that
/// losing a note always costs more than any plausible SI-SDR wobble.
const double kNoteBonus = 40.0;

class ObjectiveResult {
  ObjectiveResult(this.score, this.meanSiSdr, this.noteSurvival);

  /// The scalar to maximize.
  final double score;

  /// Mean double-talk SI-SDR (dB) across the corpus.
  final double meanSiSdr;

  /// Fraction of scenarios whose near-end note the detector still read.
  final double noteSurvival;

  @override
  String toString() => 'score ${score.toStringAsFixed(2)} '
      '(SI-SDR ${meanSiSdr.toStringAsFixed(1)} dB, '
      'notes ${(noteSurvival * 100).toStringAsFixed(0)}%)';
}

/// The dominant MIDI note of [signal] via the pitch detector over a centred
/// window, or -1 if none — reused from the CLI's note-survival check.
int _dominantMidi(Float64List signal, int rate) {
  final detector = PitchDetector(sampleRate: rate);
  final w = detector.windowSize;
  if (signal.length < w) return -1;
  final start = (signal.length - w) ~/ 2;
  final r = detector.analyze(Float64List.sublistView(signal, start, start + w));
  return r.hasPitch ? r.nearestMidi : -1;
}

/// Score [tuning] over [corpus]. [rate] is the sample rate the scenarios were
/// built at.
ObjectiveResult scoreTuning(
  AecTuning tuning,
  List<AecScenario> corpus, {
  int rate = 44100,
  bool residualSuppress = false,
}) {
  var sumSiSdr = 0.0;
  var survived = 0;
  for (final s in corpus) {
    // The scenarios are pre-aligned (delay lives inside the room IR, applied
    // causally), so cancel with delay 0 — the tuner is judging the filter, not
    // the delay estimator.
    final cleaned = cancelEcho(
      s.mic,
      s.ref,
      delay: 0,
      tuning: tuning,
      residualSuppress: residualSuppress,
    ).cleaned;
    final dt = s.doubleTalkFrom;
    // cancelEcho drops a trailing partial block, so clamp the window.
    final end = cleaned.length;
    sumSiSdr += siSdrDb(s.trueNear, cleaned, from: dt, length: end - dt);
    final heard =
        _dominantMidi(Float64List.sublistView(cleaned, dt, end), rate);
    if (heard == s.nearMidi) survived += 1;
  }
  final meanSiSdr = sumSiSdr / corpus.length;
  final noteSurvival = survived / corpus.length;
  return ObjectiveResult(
    meanSiSdr + kNoteBonus * noteSurvival,
    meanSiSdr,
    noteSurvival,
  );
}
