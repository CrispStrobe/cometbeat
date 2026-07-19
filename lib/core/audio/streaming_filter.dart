// lib/core/audio/streaming_filter.dart
//
// A live, seam-continuous master filter for the Loop Mixer's streaming FX path
// (§C-1b). Unlike crisp_dsp's `Biquad` — which bakes its coefficients at
// construction and hides its state — this owns its Direct-Form-I biquad so the
// cutoff can be swept in real time while the filter state carries across process
// blocks (a swept cutoff must never click at a block boundary).
//
// One bipolar knob [cutoff] in -1..1: 0 is transparent, negative sweeps a
// low-pass down (an "underwater"/breakdown filter), positive sweeps a high-pass
// up (a thinning "riser" filter) — the DJ-filter gesture. Pure Dart, no Flutter,
// so it unit-tests against synth tones like synth.dart.

import 'dart:math' as math;
import 'dart:typed_data';

/// A stateful, live-tunable low-pass↔high-pass filter over a PCM stream.
class StreamingFilter {
  StreamingFilter({this.sampleRate = 44100, this.q = 0.9}) {
    setCutoff(0);
  }

  /// Samples per second the coefficients are computed for.
  final double sampleRate;

  /// Resonance/steepness. 0.707 is a flat Butterworth; a touch higher gives the
  /// filter a little DJ "bite" at the corner.
  final double q;

  // Direct-Form-I coefficients (normalised by a0). Identity by default.
  double _b0 = 1, _b1 = 0, _b2 = 0, _a1 = 0, _a2 = 0;
  // Filter memory, carried across [process] calls for seam continuity.
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  double _cutoff = 0;

  /// The current bipolar cutoff (-1..1).
  double get cutoff => _cutoff;

  /// Whether the filter is transparent (near the centre).
  bool get isBypassed => _cutoff.abs() < 0.02;

  /// Sets the bipolar cutoff (-1..1) and recomputes coefficients. Negative =
  /// low-pass sweeping down; positive = high-pass sweeping up; ~0 = transparent.
  /// The filter memory is untouched, so sweeping while [process]ing stays
  /// click-free.
  void setCutoff(double value) {
    _cutoff = value.clamp(-1.0, 1.0);
    if (isBypassed) {
      _b0 = 1;
      _b1 = _b2 = _a1 = _a2 = 0; // identity: y = x, state still tracks
      return;
    }
    final nyquist = sampleRate / 2;
    final lowpass = _cutoff < 0;
    // Exponential frequency map — the ear hears pitch logarithmically.
    final freq = lowpass
        ? 20000 * math.pow(200 / 20000, -_cutoff).toDouble() // 20 kHz → 200 Hz
        : 20 * math.pow(5000 / 20, _cutoff).toDouble(); // 20 Hz → 5 kHz
    _computeCoefficients(lowpass, freq.clamp(20.0, nyquist - 100), q);
  }

  void _computeCoefficients(bool lowpass, double freq, double qq) {
    final w0 = 2 * math.pi * freq / sampleRate;
    final cw = math.cos(w0), sw = math.sin(w0);
    final alpha = sw / (2 * (qq <= 0 ? 1e-4 : qq));
    final a0 = 1 + alpha;
    if (lowpass) {
      _b0 = (1 - cw) / 2 / a0;
      _b1 = (1 - cw) / a0;
      _b2 = (1 - cw) / 2 / a0;
    } else {
      _b0 = (1 + cw) / 2 / a0;
      _b1 = -(1 + cw) / a0;
      _b2 = (1 + cw) / 2 / a0;
    }
    _a1 = -2 * cw / a0;
    _a2 = (1 - alpha) / a0;
  }

  /// Filters [block] and returns a new buffer. The filter memory persists, so
  /// `process(a) + process(b)` equals `process(a ++ b)` — no seam click.
  Float64List process(Float64List block) {
    final out = Float64List(block.length);
    for (var i = 0; i < block.length; i++) {
      final x = block[i];
      final y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
      _x2 = _x1;
      _x1 = x;
      _y2 = _y1;
      _y1 = y;
      out[i] = y;
    }
    return out;
  }

  /// Clears the filter memory (e.g. before a fresh, unrelated stream).
  void reset() => _x1 = _x2 = _y1 = _y2 = 0;
}
