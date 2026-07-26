// lib/core/audio/crisp_dsp/lfo.dart
//
// A tiny, shared low-frequency-oscillator shape — the one modulation primitive
// both the tracker replayer (vibrato/tremolo/panbrello, selected by E4x/E7x/S5x)
// and the FX rack's swept effects (the auto-wah) need. It lived inside
// `tracker_replayer.dart` as `trackerLfo`; extracting it here lets the FX rack
// reuse the exact same shape without importing the whole ~3600-line replayer.
//
// Pure Dart, no Flutter, no state — `phase` (radians) in, value in [-1, 1] out —
// so it unit-tests trivially and is byte-identical wherever it is called.

import 'dart:math' as math;

/// The tracker LFO shape in [-1, 1], selected by [waveform]:
/// 0 = sine, 1 = ramp-down (sawtooth), 2 = square. Anything else (including the
/// classic "random", 3) falls back to sine so the trajectory stays
/// deterministic. [phase] is in radians.
///
/// This is the canonical definition; `trackerLfo` in the replayer delegates to
/// it, so the vibrato/tremolo/panbrello shapes and the auto-wah sweep share one
/// source of truth.
double lfoValue(int waveform, double phase) {
  switch (waveform & 3) {
    case 1: // ramp down: +1 at the start of a cycle, sloping to −1
      final t = ((phase / (2 * math.pi)) % 1.0 + 1.0) % 1.0;
      return 1.0 - 2.0 * t;
    case 2: // square
      return math.sin(phase) >= 0 ? 1.0 : -1.0;
    default: // 0 sine (and 3 random ≈ sine, kept deterministic)
      return math.sin(phase);
  }
}
