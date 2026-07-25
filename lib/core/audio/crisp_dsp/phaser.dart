// Phaser — the swirling "jet" sweep, the one classic modulation effect the DSP
// set was missing (chorus and flanger are delay-based; a phaser is not).
//
// A cascade of first-order ALL-PASS filters, each of which passes every
// frequency at full level but rotates its phase. Summed back with the dry
// signal, the frequencies whose phase has rotated to ~180° cancel, so the
// spectrum grows a comb of notches. An LFO sweeps the all-pass corner up and
// down, so those notches slide through the sound — unlike a flanger, whose
// notches are harmonically spaced because they come from a delay.
//
// Pure Dart, deterministic, allocation-light. Flutter-free.

import 'dart:math' as math;
import 'dart:typed_data';

/// One first-order all-pass section: `H(z) = (c + z⁻¹) / (1 + c·z⁻¹)`.
/// The coefficient is recomputed as the LFO moves, so it keeps only its own
/// one-sample memory.
class _AllPass {
  double _x1 = 0;
  double _y1 = 0;

  double process(double x, double c) {
    final y = c * x + _x1 - c * _y1;
    _x1 = x;
    _y1 = y;
    return y;
  }
}

/// Sweeps [stages] all-pass sections over [input] and mixes them back with the
/// dry signal.
///
/// [rateHz] is the LFO speed; the sweep runs between [minFreq] and [maxFreq]
/// (the notches' range). [depth] scales how much of the phase-shifted path is
/// summed in (0 = dry, 1 = equal mix — the deepest notches). [feedback] routes
/// the last stage back into the first for a sharper, more resonant sweep;
/// it's clamped below 1 so it can't run away. [stages] must be even for the
/// notches to land in the audible sweet spot — 4 is the classic voicing.
///
/// Same length as [input]; `depth == 0` returns an exact copy.
Float64List phaserFx(
  Float64List input, {
  required double sampleRate,
  double rateHz = 0.5,
  double depth = 0.7,
  double feedback = 0.3,
  double minFreq = 200,
  double maxFreq = 2000,
  int stages = 4,
}) {
  final out = Float64List(input.length);
  final d = depth.clamp(0.0, 1.0);
  if (input.isEmpty || d == 0) {
    out.setAll(0, input);
    return out;
  }

  final n = stages.clamp(1, 12).toInt();
  final fb = feedback.clamp(-0.95, 0.95).toDouble();
  final lo = math.min(minFreq, maxFreq).clamp(20.0, sampleRate / 2 - 100);
  final hi = math.max(minFreq, maxFreq).clamp(lo + 1, sampleRate / 2 - 50);
  final filters = List.generate(n, (_) => _AllPass());

  final lfoInc = 2 * math.pi * rateHz / sampleRate;
  var lfo = 0.0;
  var last = 0.0; // the feedback memory

  for (var i = 0; i < input.length; i++) {
    // Sweep the corner frequency logarithmically — that's how the ear hears
    // pitch, so the sweep sounds even rather than bunched up at the top.
    final t = 0.5 * (1 + math.sin(lfo)); // 0..1
    final freq = lo * math.pow(hi / lo, t);
    // Bilinear-transform coefficient for a first-order all-pass at [freq].
    final tanned = math.tan(math.pi * freq / sampleRate);
    final c = (tanned - 1) / (tanned + 1);

    var s = input[i] + last * fb;
    for (final f in filters) {
      s = f.process(s, c);
    }
    last = s;
    // Equal-gain sum: at depth 1 the dry and shifted paths are equal, which is
    // what makes the notches actually null instead of merely dipping.
    out[i] = input[i] * (1 - d * 0.5) + s * (d * 0.5);
    lfo += lfoInc;
    if (lfo > 2 * math.pi) lfo -= 2 * math.pi;
  }
  return out;
}
