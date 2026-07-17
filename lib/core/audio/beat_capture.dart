// lib/core/audio/beat_capture.dart
//
// "Beatbox a beat": turns a raw mic feature trace into a Loop Mixer drum
// pattern. The screen records ~2 bars of PitchReadings (which carry rms +
// zcr on every frame); this finds onsets (energy jumps), classifies each hit
// as kick / snare / hat by brightness + low pitch, and quantizes onto the
// eighth-step grid. Pure Dart, headless-testable — the classification
// thresholds are calibrated against synth.dart's own renderDrum one-shots
// run through the real PitchDetector (kick zcr≈0.005 pitched-low ·
// snare≈0.45 · hat≈0.67; see test/beat_capture_test.dart).

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart';

/// One capture frame: elapsed ms, energy, brightness, and whether the
/// detector heard a LOW pitch (a hummed "boom" reads as a pitched bass note).
typedef BeatFrame = ({double ms, double rms, double zcr, bool pitchedLow});

/// Which drum a single hit's timbre is closest to.
Drum classifyHit({required double zcr, required bool pitchedLow}) {
  if (pitchedLow || zcr < 0.15) return Drum.kick;
  if (zcr >= 0.55) return Drum.hat;
  return Drum.snare;
}

/// Onsets: an energy jump over both an absolute floor and a rise factor vs.
/// the previous frame, with a refractory window so one hit isn't counted
/// across adjacent analysis frames.
const _rmsFloor = 0.015;
const _riseFactor = 1.8;
const _refractoryMs = 110.0;

/// Quantizes beatboxed [frames] (spanning [totalMs]) into a drum pattern:
/// detected hits land on their nearest eighth step, classified per hit from
/// the loudest frame of the attack. Returns null when nothing was heard.
DrumRowsPattern? quantizeToBeat(
  List<BeatFrame> frames, {
  required int totalMs,
  int steps = kPatternSteps,
}) {
  if (frames.isEmpty || totalMs <= 0) return null;
  final stepMs = totalMs / steps;

  final rows = {
    for (final drum in Drum.values) drum: List<bool>.filled(steps, false),
  };
  var any = false;
  var lastOnsetMs = -_refractoryMs;
  var prevRms = 0.0;

  for (var i = 0; i < frames.length; i++) {
    final f = frames[i];
    final isOnset = f.rms > _rmsFloor &&
        f.rms > prevRms * _riseFactor &&
        f.ms - lastOnsetMs >= _refractoryMs;
    prevRms = f.rms;
    if (!isOnset) continue;
    lastOnsetMs = f.ms;

    // Classify from the BRIGHTEST sufficiently-loud frame of the attack:
    // the onset window straddles the hit's leading silence, which dilutes
    // zcr (a half-covered hat reads like a snare) — dilution only ever
    // lowers zcr, so the max over the attack frames is the honest timbre.
    var brightest = f.zcr;
    var pitchedLow = f.pitchedLow;
    for (var j = i; j < frames.length && j <= i + 3; j++) {
      final g = frames[j];
      if (g.rms < _rmsFloor) continue;
      if (g.zcr > brightest) brightest = g.zcr;
      pitchedLow = pitchedLow || g.pitchedLow;
    }
    final drum = classifyHit(zcr: brightest, pitchedLow: pitchedLow);
    final step = (f.ms / stepMs).round() % steps;
    rows[drum]![step] = true;
    any = true;
  }
  return any ? DrumRowsPattern(rows) : null;
}
