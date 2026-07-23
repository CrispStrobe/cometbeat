// lib/core/audio/crisp_dsp/time_stretch.dart
//
// WSOLA time-stretch — change a clip's DURATION without changing its PITCH (the
// dual of the granular pitch shifter). Lets a recorded voice be slowed or sped up
// while staying in tune — the flagship record-your-voice toy gains a "slow/fast"
// knob. Pure Dart, deterministic, Flutter-free (tested like sample_dsp_test.dart).
// Ported from voicelab's TimeStretcher (MIT). See docs/FX_HANDOVER.md #3.
//
// ─── Contract (WSOLA: Waveform-Similarity Overlap-Add) ───────────────────────
// timeStretch(input, factor): output plays `factor`× as long — factor > 1 slower/
// longer, factor < 1 faster/shorter — at the SAME pitch. Output length ≈
// round(input.length * factor) (± one frame).
//   • Overlap-add Hann-windowed frames. `frameSize` ≈ 1024 samples (≈ 23 ms at
//     44.1 kHz); synthesis hop `Hs = frameSize ~/ 4` (75% overlap); nominal
//     analysis hop `Ha = Hs / factor` (so factor>1 advances the input slower →
//     longer output).
//   • WSOLA alignment: for each frame, search input offsets in a small window
//     (±`tolerance`, e.g. 256 samples) around the nominal analysis position for
//     the offset whose frame best cross-correlates with the "natural
//     continuation" of what's already been synthesized (the overlap region), and
//     use that offset — this keeps successive frames waveform-aligned so the
//     overlap-add doesn't phase-cancel or warble. (A plain OLA without the search
//     still preserves pitch but sounds rougher; the search is what makes it clean.)
//   • Normalize the overlap-add by the summed window energy so the level is even.
//   • Deterministic (no RNG/clock); finite; bounded (a normalized input stays
//     ~[-1, 1]). factor <= 0 or empty input → an empty buffer. factor == 1 returns
//     ~the input (length preserved, pitch preserved).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;

const int _frameSize = 1024;
const int _hs = _frameSize ~/ 4; // synthesis hop (75% overlap) = 256
const int _overlap = _frameSize - _hs; // 768
const int _tolerance = 256; // WSOLA search radius

/// Time-stretches [input] by [factor] (>1 longer/slower, <1 shorter/faster),
/// preserving pitch. [sampleRate] is accepted for future rate-dependent tuning.
Float64List timeStretch(
  Float64List input,
  double factor, {
  int sampleRate = kSampleRate,
}) {
  if (factor <= 0 || input.isEmpty) return Float64List(0);

  final n = input.length;
  final targetLen = (n * factor).round();
  if (targetLen <= 0) return Float64List(0);

  final ha = _hs / factor; // nominal analysis hop

  final window = _hann(_frameSize);
  final out = Float64List(targetLen + _frameSize);
  final winSum = Float64List(targetLen + _frameSize);

  var prevOffset = 0; // chosen input offset of the previous frame

  for (var k = 0;; k++) {
    final synPos = k * _hs;
    if (synPos >= targetLen) break;

    final nominal = (k * ha).round();
    if (nominal >= n) break;

    int offset;
    if (k == 0) {
      offset = _clampOffset(nominal, n);
    } else {
      // Target: samples that naturally follow the previous chosen frame —
      // the previous input offset advanced by one synthesis hop.
      final targetStart = prevOffset + _hs;
      offset = _bestOffset(input, nominal, targetStart, n);
    }

    // Window the chosen input frame and overlap-add into the output.
    for (var i = 0; i < _frameSize; i++) {
      final src = offset + i;
      if (src < 0 || src >= n) continue;
      final w = window[i];
      out[synPos + i] += input[src] * w;
      winSum[synPos + i] += w;
    }

    prevOffset = offset;
  }

  // Normalize by summed window energy.
  const eps = 1e-6;
  for (var i = 0; i < out.length; i++) {
    final s = winSum[i];
    if (s > eps) {
      out[i] = out[i] / s;
    } else {
      out[i] = 0.0;
    }
  }

  // Trim to the target length.
  return Float64List.sublistView(out, 0, targetLen);
}

/// Time-stretches both channels with identical WSOLA settings so a stereo
/// recording keeps its authored duration and shared timing relationship.
({Float64List left, Float64List right}) timeStretchStereo(
  Float64List left,
  Float64List right,
  double factor, {
  int sampleRate = kSampleRate,
}) =>
    (
      left: timeStretch(left, factor, sampleRate: sampleRate),
      right: timeStretch(right, factor, sampleRate: sampleRate),
    );

/// Finds the input offset in [nominal - tolerance, nominal + tolerance]
/// (clamped) whose leading [_overlap] samples best cross-correlate (normalized
/// dot product) with the natural continuation beginning at [targetStart].
int _bestOffset(Float64List input, int nominal, int targetStart, int n) {
  final lo = _clampOffset(nominal - _tolerance, n);
  final hi = _clampOffset(nominal + _tolerance, n);

  var bestOffset = _clampOffset(nominal, n);
  var bestScore = double.negativeInfinity;

  for (var off = lo; off <= hi; off++) {
    var dot = 0.0;
    var candEnergy = 0.0;
    for (var i = 0; i < _overlap; i++) {
      final c = off + i;
      final t = targetStart + i;
      final cv = (c >= 0 && c < n) ? input[c] : 0.0;
      final tv = (t >= 0 && t < n) ? input[t] : 0.0;
      dot += cv * tv;
      candEnergy += cv * cv;
    }
    // Normalized cross-correlation (target energy is constant across
    // candidates, so it does not affect the argmax; normalize by the
    // candidate energy to avoid biasing toward louder regions).
    final score = candEnergy > 1e-12 ? dot / math.sqrt(candEnergy) : dot;
    if (score > bestScore) {
      bestScore = score;
      bestOffset = off;
    }
  }
  return bestOffset;
}

int _clampOffset(int off, int n) {
  final maxStart = math.max(0, n - _frameSize);
  return math.min(math.max(off, 0), maxStart);
}

Float64List _hann(int size) {
  final w = Float64List(size);
  for (var i = 0; i < size; i++) {
    w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (size - 1));
  }
  return w;
}
