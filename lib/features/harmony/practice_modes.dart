// lib/features/harmony/practice_modes.dart
//
// BB-T3 — the practice trainer: the reason to open this instead of a
// metronome.
//
// Practice plays the chart's form round and round. Each time round is a PASS,
// and every practice mode is a rule from (pass, bar) to what the band does —
// all of it known before the pass begins, so a pass is just another plan the
// streamed band prepares ahead and swaps in at the loop's wrap (a splice point
// already). Nothing here renders, times or plays; it only answers questions.
//
//   * tempo ramp   — +N BPM a pass, or ramp to a target over K passes;
//   * key cycling  — chromatic, round the cycle of fourths, or a random new
//                    key each pass, each SPELLED for its key (≤ 6 accidentals);
//   * harmony fade — drop the comp, then the bass, then everything but a click,
//                    so the changes must be heard rather than heard played;
//   * drop-outs    — a seeded share of bars go silent: keep time yourself;
//   * density taper — the band thins out a level each pass.
library;

import 'dart:math';

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_transpose.dart';
import 'package:comet_beat/features/harmony/streamed_band.dart';

enum KeyCycle {
  none,

  /// Up a semitone each pass.
  chromatic,

  /// Round the cycle of fourths (C F B♭ E♭ …) — how jazz players drill.
  fourths,

  /// A different random key each pass (seeded).
  random,
}

class PracticeConfig {
  const PracticeConfig({
    this.tempoStep = 0,
    this.tempoTarget,
    this.rampPasses = 4,
    this.keyCycle = KeyCycle.none,
    this.harmonyFade = false,
    this.dropOut = 0,
    this.densityTaper = false,
    this.seed = 0,
  });

  /// BPM added each pass (ignored when [tempoTarget] is set).
  final int tempoStep;

  /// Ramp from the chart's tempo to this over [rampPasses] passes, then hold.
  final int? tempoTarget;
  final int rampPasses;

  final KeyCycle keyCycle;
  final bool harmonyFade;

  /// Share of bars silenced, 0–1.
  final double dropOut;

  final bool densityTaper;
  final int seed;

  /// Nothing changes from pass to pass: plain looping.
  bool get isOff =>
      tempoStep == 0 &&
      tempoTarget == null &&
      keyCycle == KeyCycle.none &&
      !harmonyFade &&
      dropOut <= 0 &&
      !densityTaper;
}

/// What one pass plays.
class PassPlan {
  const PassPlan({
    required this.chart,
    required this.silent,
    required this.kit,
    required this.clickOnly,
    required this.intensity,
  });

  /// The chart for this pass: its tempo and key already applied.
  final Chart chart;

  /// Roles silenced for the whole pass (harmony fade).
  final Set<BandRole> silent;

  /// Whether the drum kit plays (false on the last fade step).
  final bool kit;

  /// The last fade step: nothing but a click.
  final bool clickOnly;

  /// The form's base intensity for this pass (density taper), 0–3.
  final int intensity;
}

/// The tempo of pass [pass] (0 = the first time through).
int passTempo(PracticeConfig c, int baseBpm, int pass) {
  final target = c.tempoTarget;
  final int bpm;
  if (target != null) {
    final k = c.rampPasses < 1 ? 1 : c.rampPasses;
    final t = min(pass, k) / k;
    bpm = (baseBpm + (target - baseBpm) * t).round();
  } else {
    bpm = baseBpm + c.tempoStep * pass;
  }
  return bpm.clamp(30, 320);
}

/// The key signature of pass [pass], spelled conventionally for its tonic.
int passKeyFifths(PracticeConfig c, Chart chart, int pass) {
  final pc = chart.tonicPitchClass;
  final int target;
  switch (c.keyCycle) {
    case KeyCycle.none:
      return chart.keyFifths;
    case KeyCycle.chromatic:
      target = pc + pass;
    case KeyCycle.fourths:
      target = pc + 5 * pass;
    case KeyCycle.random:
      if (pass == 0) return chart.keyFifths;
      // A new key each pass, never the one just played.
      final previous = _randomPc(c.seed, pass - 1, pc);
      var next = _randomPc(c.seed, pass, pc);
      if (next == previous) next = (next + 7) % 12;
      target = next;
  }
  if (pass == 0) return chart.keyFifths; // start where the chart is written
  return conventionalFifths(target, minor: chart.minor);
}

int _randomPc(int seed, int pass, int startPc) =>
    pass == 0 ? startPc : Random(seed * 7919 + pass).nextInt(12);

/// Everything pass [pass] plays.
PassPlan passPlan(
  PracticeConfig c,
  Chart chart,
  int pass, {
  int baseIntensity = 2,
}) {
  var out = chart;
  final fifths = passKeyFifths(c, chart, pass);
  if (fifths != chart.keyFifths) out = transposeChartToKey(out, fifths);
  final bpm = passTempo(c, chart.tempoBpm, pass);
  if (bpm != out.tempoBpm) out = _withTempo(out, bpm);

  final fade = c.harmonyFade ? min(pass, 3) : 0;
  return PassPlan(
    chart: out,
    silent: {
      if (fade >= 1) BandRole.comp,
      if (fade >= 2) BandRole.bass,
    },
    kit: fade < 3,
    clickOnly: fade >= 3,
    intensity:
        c.densityTaper ? (baseIntensity - pass).clamp(0, 3) : baseIntensity,
  );
}

/// Whether bar [bar] of pass [pass] drops out. Reproducible for a seed; never
/// on the first pass (you need to hear it once).
bool isDropOut(PracticeConfig c, int pass, int bar) {
  if (c.dropOut <= 0 || pass == 0) return false;
  final r = Random(c.seed * 104729 + pass * 7919 + bar).nextDouble();
  return r < c.dropOut;
}

Chart _withTempo(Chart chart, int bpm) => Chart(
      title: chart.title,
      composer: chart.composer,
      keyFifths: chart.keyFifths,
      minor: chart.minor,
      meter: chart.meter,
      tempoBpm: bpm,
      styleId: chart.styleId,
      pickupBeats: chart.pickupBeats,
      extra: chart.extra,
      sections: chart.sections,
    );
