// lib/core/audio/crisp_dsp/reverb.dart
//
// A Schroeder/Freeverb-style **reverb** for the Tracker channel chain and Loop
// Mixer / SFX sends. Pure Dart, deterministic, a SAME-LENGTH transform
// (`Float64List → Float64List`) so an effected stem still lines up for mixStems.
// Flutter-free, tested like sample_dsp_test.dart. See docs/FX_HANDOVER.md #1.
//
// Implementation contract (classic Freeverb topology, mono):
//   • 8 parallel **lowpass-feedback comb filters** summed, then 4 **series
//     allpass filters** — the standard Freeverb tunings (comb delays 1116, 1188,
//     1277, 1356, 1422, 1491, 1557, 1617; allpass delays 556, 441, 341, 225),
//     given at 44.1 kHz; scale each delay by `sampleRate / 44100` (round, min 1).
//   • Each comb: `y[n] = x[n] + feedback * filtered(y[n-delay])`, where the
//     feedback path is one-pole lowpassed — `store = y[n-delay]*(1-damp) +
//     store*damp` — so higher `damping` = darker, faster-decaying tail. Map
//     `roomSize`∈[0,1] → comb feedback ≈ 0.7 + 0.28*roomSize (keep < 1), and
//     `damping`∈[0,1] → damp coefficient (≈ 0.2 + 0.6*damping is fine).
//   • Each allpass: `bufOut = buf[n-delay]; y = -x + bufOut; buf[n] = x +
//     bufOut*0.5` (allpass feedback 0.5).
//   • Blend: `out = (1-mix)*dry + mix*wet`. mix == 0 MUST be an exact dry copy.
//   • Output length == input length (the tail is truncated at the buffer end).
//   • Deterministic (no RNG/clock), finite, bounded (no NaN/Inf; a normalized
//     input stays roughly in range — a small output gain to tame the comb sum is
//     fine). Guard params (clamp roomSize/damping/mix to [0,1]).
//
// The key audible property (and the test's anchor): an impulse spreads into a
// decaying tail — there is significant energy well AFTER the input impulse.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:klang_universum/core/audio/synth.dart' show kSampleRate;

// Freeverb comb/allpass tunings at 44.1 kHz (mono set).
const List<int> _kCombTuning = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
const List<int> _kAllpassTuning = [556, 441, 341, 225];

// Small fixed output gain to tame the 8-comb sum (Freeverb's fixed gain range).
const double _kFixedGain = 0.015;

double _clamp01(double v) => v.isNaN ? 0.0 : math.max(0.0, math.min(1.0, v));

int _scaleDelay(int base, int sampleRate) {
  final scaled = (base * sampleRate / 44100).round();
  return math.max(1, scaled);
}

/// A lowpass-feedback comb filter with its own delay buffer.
class _Comb {
  _Comb(int len)
      : _buf = Float64List(len),
        _len = len;

  final Float64List _buf;
  final int _len;
  int _pos = 0;
  double _store = 0.0;

  double process(double x, double feedback, double damp) {
    final out = _buf[_pos];
    _store = out * (1 - damp) + _store * damp;
    _buf[_pos] = x + _store * feedback;
    _pos++;
    if (_pos >= _len) _pos = 0;
    return out;
  }
}

/// A series allpass filter (feedback 0.5) with its own delay buffer.
class _Allpass {
  _Allpass(int len)
      : _buf = Float64List(len),
        _len = len;

  final Float64List _buf;
  final int _len;
  int _pos = 0;

  double process(double x) {
    final bufOut = _buf[_pos];
    final y = -x + bufOut;
    _buf[_pos] = x + bufOut * 0.5;
    _pos++;
    if (_pos >= _len) _pos = 0;
    return y;
  }
}

/// Applies a Freeverb-style reverb to [input]. [roomSize] (0..1) lengthens the
/// tail, [damping] (0..1) darkens it, [mix] (0..1) is the wet/dry blend.
Float64List reverbFx(
  Float64List input, {
  double roomSize = 0.6,
  double damping = 0.4,
  double mix = 0.3,
  int sampleRate = kSampleRate,
}) {
  final n = input.length;
  final out = Float64List(n);

  final m = _clamp01(mix);
  // mix == 0 is an exact dry copy.
  if (m == 0.0) {
    out.setRange(0, n, input);
    return out;
  }

  final room = _clamp01(roomSize);
  final damp = 0.2 + 0.6 * _clamp01(damping);
  final feedback = 0.7 + 0.28 * room; // < 1

  final combs = [
    for (final base in _kCombTuning) _Comb(_scaleDelay(base, sampleRate)),
  ];
  final allpasses = [
    for (final base in _kAllpassTuning) _Allpass(_scaleDelay(base, sampleRate)),
  ];

  final dryGain = 1 - m;
  for (var i = 0; i < n; i++) {
    final dry = input[i];
    final x = dry * _kFixedGain;

    // 8 parallel combs summed.
    var summed = 0.0;
    for (final c in combs) {
      summed += c.process(x, feedback, damp);
    }

    // 4 series allpasses.
    var wet = summed;
    for (final a in allpasses) {
      wet = a.process(wet);
    }

    out[i] = dryGain * dry + m * wet;
  }

  return out;
}
