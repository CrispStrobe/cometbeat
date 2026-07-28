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

/// WS-A9 — how much history the waveform-similarity search gets to look at.
///
/// ⚠️ **I scoped this expecting a material trade-off — "short frames keep drum
/// hits sharp, long frames are smooth on held notes" — and the measurements
/// only support half of it.** Recorded here so nobody rebuilds the half that
/// is not real:
///
///   * **The pitch floor is real, large and exactly predictable.** WSOLA aligns
///     frames by correlating the overlap region, and a correlation window
///     shorter than one period of the material cannot find the right
///     alignment — so the stretch locks onto a *sub-harmonic* and the note
///     comes out at the wrong pitch, not merely rougher. Measured breaking
///     points: 768 → ~85 Hz, 1024 → ~64 Hz, 2048 → ~38 Hz, each within ~25% of
///     the analytic `sampleRate / overlap`.
///   * **The transient advantage of a short frame did NOT reproduce.** Across
///     768/1024/2048 the crest factor of a stretched drum pattern is flat to
///     within noise, and at a factor of 2 every setting doubles the hits
///     equally (8 in, 15 out) — that is WSOLA repeating material, which frame
///     length does not fix. Only past a factor of ~2.5 does the longest frame
///     smear measurably more.
///
/// So the setting is named for the axis that measurement supports: **how low
/// the material goes.** A longer frame is better for pitch and costs time (the
/// search is O(overlap x tolerance)); it is not a different flavour.
enum StretchQuality {
  /// Shortest frame, cheapest search. Fine for drums, most voices and guitar —
  /// but it cannot hold anything below roughly 85 Hz, which includes the bottom
  /// of a bass and the fundamental of a kick.
  light(768, 192),

  /// The default, and exactly what every stretch did before this setting
  /// existed. Holds down to roughly 64 Hz.
  balanced(1024, 256),

  /// Longest frame. The only setting that survives BASS: it holds down to
  /// roughly 38 Hz, below the open E of a bass guitar. Costs about four times
  /// the search of [light], and smears slightly more at stretch factors past
  /// about 2.5.
  deep(2048, 512);

  const StretchQuality(this.frameSize, this.tolerance);

  /// WSOLA analysis/synthesis frame length in samples.
  final int frameSize;

  /// How far the waveform-similarity search may wander, in samples.
  final int tolerance;

  /// Synthesis hop — 75% overlap, as the contract above describes.
  int get hop => frameSize ~/ 4;

  /// The overlap region the similarity search compares. This is the number
  /// that sets the pitch floor.
  int get overlap => frameSize - hop;

  /// The lowest frequency this setting can hold without dropping to a
  /// sub-harmonic, at [sampleRate].
  ///
  /// The correlation window must span at least one period, so the analytic
  /// floor is `sampleRate / overlap`. The 1.5 is measured, not chosen: a window
  /// of *exactly* one period still correlates ambiguously, and the real floors
  /// sit at 1.31–1.48x the analytic one across the three settings. 1.4 was
  /// tried first and put `deep`'s advertised floor exactly ON its measured one,
  /// where it failed — this number is a PROMISE about what survives, so it
  /// needs margin, and erring conservative is the only safe direction.
  double lowestReliableHz([double sampleRate = 44100]) =>
      1.5 * sampleRate / overlap;
}

/// Time-stretches [input] by [factor] (>1 longer/slower, <1 shorter/faster),
/// preserving pitch. [sampleRate] is accepted for future rate-dependent tuning.
Float64List timeStretch(
  Float64List input,
  double factor, {
  int sampleRate = kSampleRate,
  StretchQuality quality = StretchQuality.balanced,
}) {
  if (factor <= 0 || input.isEmpty) return Float64List(0);

  final n = input.length;
  final targetLen = (n * factor).round();
  if (targetLen <= 0) return Float64List(0);

  final frameSize = quality.frameSize;
  final hs = quality.hop;
  final ha = hs / factor; // nominal analysis hop

  final window = _hann(frameSize);
  final out = Float64List(targetLen + frameSize);
  final winSum = Float64List(targetLen + frameSize);

  var prevOffset = 0; // chosen input offset of the previous frame

  for (var k = 0;; k++) {
    final synPos = k * hs;
    if (synPos >= targetLen) break;

    final nominal = (k * ha).round();
    if (nominal >= n) break;

    int offset;
    if (k == 0) {
      offset = _clampOffset(nominal, n, frameSize);
    } else {
      // Target: samples that naturally follow the previous chosen frame —
      // the previous input offset advanced by one synthesis hop.
      final targetStart = prevOffset + hs;
      offset = _bestOffset(input, nominal, targetStart, n, quality);
    }

    // Window the chosen input frame and overlap-add into the output.
    for (var i = 0; i < frameSize; i++) {
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
  StretchQuality quality = StretchQuality.balanced,
}) =>
    (
      left: timeStretch(left, factor, sampleRate: sampleRate, quality: quality),
      right:
          timeStretch(right, factor, sampleRate: sampleRate, quality: quality),
    );

/// Finds the input offset in [nominal - tolerance, nominal + tolerance]
/// (clamped) whose leading [_overlap] samples best cross-correlate (normalized
/// dot product) with the natural continuation beginning at [targetStart].
int _bestOffset(
  Float64List input,
  int nominal,
  int targetStart,
  int n,
  StretchQuality quality,
) {
  final frameSize = quality.frameSize;
  final overlap = quality.overlap;
  final lo = _clampOffset(nominal - quality.tolerance, n, frameSize);
  final hi = _clampOffset(nominal + quality.tolerance, n, frameSize);

  var bestOffset = _clampOffset(nominal, n, frameSize);
  var bestScore = double.negativeInfinity;

  for (var off = lo; off <= hi; off++) {
    var dot = 0.0;
    var candEnergy = 0.0;
    for (var i = 0; i < overlap; i++) {
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

int _clampOffset(int off, int n, int frameSize) {
  final maxStart = math.max(0, n - frameSize);
  return math.min(math.max(off, 0), maxStart);
}

Float64List _hann(int size) {
  final w = Float64List(size);
  for (var i = 0; i < size; i++) {
    w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (size - 1));
  }
  return w;
}
