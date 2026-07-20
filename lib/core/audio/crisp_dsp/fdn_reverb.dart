// Feedback-Delay-Network (FDN) reverb — a wide, smooth late-reverberator and a
// drop-in alternative to the Freeverb in reverb.dart. Pure Dart, Flutter-free,
// deterministic (no Random/DateTime), zero dependencies.
//
// The algorithm is standard, public DSP (Jot & Chaigne 1991; Stautner &
// Puckette; Julius O. Smith, *Physical Audio Signal Processing*, "Feedback
// Delay Networks"):
//
//   • N parallel delay lines whose lengths are mutually co-prime (primes), so
//     the echo pattern never repeats → a dense, non-metallic tail.
//   • A single UNITARY feedback matrix mixes every line's output back into every
//     line's input, so energy is conserved (stable) and the reverberation is
//     diffuse. We use a Householder reflection A = I − (2/N)·1·1ᵀ, evaluated on
//     the fly as y[i] = x[i] − (2/N)·Σx — no matrix storage, all lines coupled.
//   • The feedback is scaled by a global gain g < 1 that sets the decay time
//     (RT60), and each line is low-passed by a one-pole before feedback so highs
//     decay faster than lows — the "damping" of a real room's air/surfaces.
//   • The mono input is injected into all lines. The stereo output blends a
//     SHARED (mono) sum of all lines with a per-channel DECORRELATED component
//     (a disjoint, all-pass-phase-shifted half of the lines): out = a·mono +
//     b·decorr. The a:b ratio tunes the L/R correlation to the reference's
//     moderate, mono-SAFE width — WIDE but positively correlated, not phasey or
//     cancelling in mono (the whole point of an FDN over a mono reverb).
//   • Each delay line's READ position is slowly MODULATED by a per-line LFO and
//     read at a FRACTIONAL position via a first-order ALL-PASS interpolator
//     (unity magnitude, phase only). A static FDN has a fixed modal comb → a
//     metallic, ringing tail; continuously de-tuning each line's length
//     decorrelates successive round-trips so the comb peaks smear into a smooth
//     (spectrally flat) tail (the "chorused" FDN; Dattorro 1997, *Effect
//     Design*; Julius O. Smith, PASP). Each LFO runs at its own slow rate and
//     phase so the lines never move in lockstep; modulation is magnitude-neutral
//     on average, so RT60/width are preserved.

import 'dart:math' as math;
import 'dart:typed_data';

/// The eight co-prime delay-line lengths at 44.1 kHz (samples). Primes ⇒
/// pairwise co-prime; spread across ~1000–3400. A wide spread of longer lines
/// packs MANY overlapping resonant modes into the band, so the summed comb is
/// dense to begin with — the modulation below then smears the residual peaks. (A
/// short 8-line set would leave a SPARSE comb with deep notches — fewer modes,
/// LESS flat — so density here comes from length + count, then modulation.)
const List<int> _kDelays44k = [1009, 1129, 1381, 1663, 1993, 2377, 2851, 3407];

/// Delay-line modulation (the anti-ringing fix). Each line's read position is
/// swept by a sine LFO and read at a FRACTIONAL position via a first-order
/// ALL-PASS interpolator (unity magnitude — phase only, so it neither tilts the
/// spectrum nor touches RT60/damping; linear interpolation would low-pass the
/// tail and, ironically, make it LESS flat). The lines share a slow rate range
/// but each runs at its own rate (spread across [_kModRateLoHz, _kModRateHiHz])
/// and its own phase, so they never de-tune in lockstep — the fixed modal comb
/// keeps shifting and smears into a spectrally-flat (non-metallic) tail. The
/// depth is a peak read-offset in samples at 44.1 kHz; modulation is
/// magnitude-neutral on average, so width/RT60 are preserved.
const double _kModRateLoHz = 0.7;
const double _kModRateHiHz = 1.5;
const double _kModDepth44k = 24.0;

/// Per-channel DECORRELATOR taps: each channel sums a DISJOINT, interleaved half
/// of the delay lines (L ← lines 0,2,4,6; R ← lines 1,3,5,7). Because the two
/// halves are different-length delays, decorrL and decorrR are genuinely
/// different signals — decorrelated at EVERY frequency, not just for a broadband
/// impulse. Interleaving (rather than short-half vs long-half) gives each side a
/// similar delay spread, so the decorrelation is *uniform* across the band
/// instead of swinging from near-mono to anti-phase at particular frequencies.
const List<double> _kDecorrL = [1, 0, 1, 0, 1, 0, 1, 0];
const List<double> _kDecorrR = [0, 1, 0, 1, 0, 1, 0, 1];

/// Stereo blend: each output is a shared (mono, correlated) component plus a
/// per-channel decorrelated one — `out = a·monoSum + b·decorr`. The a:b ratio
/// sets the L/R correlation; these land the impulse tail near the reference band
/// (side/mid ≈ 0.35–0.5, corr ≈ 0.4–0.6) — wide but mono-SAFE (a fully
/// decorrelated or anti-phase tail is phasey and partly cancels summed to mono).
const double _kShared = 0.40;
const double _kDecorr = 0.80;

/// Per-channel decorrelating all-pass lengths at 44.1 kHz (samples), applied to
/// the decorr component ONLY. Any fixed disjoint grouping has a frequency where
/// its two half-sums align (→ a mono null); giving each channel its own short,
/// co-prime all-pass adds different frequency-dependent phase so the two sides
/// never coincide — lifting the nulls into a uniform, mono-safe decorrelation.
/// All-pass = unity magnitude, so RT60/damping are untouched.
const List<int> _kDecorrApL44k = [43, 113];
const List<int> _kDecorrApR44k = [67, 149];

/// Short, co-prime Schroeder all-pass diffuser lengths at 44.1 kHz (samples).
/// A series of these smears the raw input into a dense, exponentially-decaying
/// cluster BEFORE it enters the FDN, so the early reflections are diffuse (low
/// crest) rather than a few isolated spikes — a lossless (unity-gain) stage.
const List<int> _kDiffusers44k = [67, 113, 167, 223, 281, 349];

/// A stereo Feedback-Delay-Network reverb: mono in → stereo (left, right) out.
/// Returns ONLY the wet signal (the caller mixes it with the dry). [roomSize]
/// 0..1 lengthens the tail; [damping] 0..1 darkens it. Same length as [input].
(Float64List left, Float64List right) fdnReverb(
  Float64List input, {
  double roomSize = 0.7,
  double damping = 0.4,
  int sampleRate = 44100,
}) {
  final n = input.length;
  if (n == 0) return (Float64List(0), Float64List(0));

  final room = _finite(roomSize).clamp(0.0, 1.0);
  final damp = _finite(damping).clamp(0.0, 1.0);
  final sr = sampleRate <= 0 ? 44100 : sampleRate;
  final scale = sr / 44100.0;

  const lines = 8;

  // Delay-line lengths scaled to the actual sample rate (kept ≥ 2).
  final len = List<int>.generate(
    lines,
    (i) => math.max(2, (_kDelays44k[i] * scale).round()),
  );

  // roomSize → RT60 (seconds). A cubic curve spans ~0.5 s … 4 s and lands on the
  // reference ≈ 1.6 s at the default roomSize 0.7 (0.5 + 3.5·0.7³ ≈ 1.7 s).
  final rt60 = 0.5 + 3.5 * room * room * room;

  // Standard RT60 ↔ feedback-gain relation on the MEAN delay length: a line of
  // Dmean seconds fed back with gain g reaches −60 dB (×0.001) after RT60, so
  // g = 10^(−3·Dmean / RT60). Clamp g < 1 for stability.
  var meanLen = 0.0;
  for (final l in len) {
    meanLen += l;
  }
  meanLen /= lines;
  final dMeanSec = meanLen / sr;
  final g = math.min(0.9995, math.pow(10.0, -3.0 * dMeanSec / rt60).toDouble());

  // damping → one-pole low-pass coefficient d ∈ [0, 0.7] (0 = bright, no HF loss).
  final d = damp * 0.7;

  // Injecting the impulse into all N lines and feeding an energy-preserving
  // matrix back at gain g would build up loudly; a small input gain keeps the
  // summed tail well bounded.
  const inputGain = 0.18;

  // Delay-line modulation: peak read-offset (samples) plus a per-line LFO phase
  // increment (each line at its own rate, spread across the Lo..Hi range) and a
  // per-line phase offset spread over 360°/N, so no two lines modulate in
  // lockstep. Deterministic — driven by the sample index t, never Random.
  final modDepth = _kModDepth44k * scale;
  final phaseInc = List<double>.generate(
    lines,
    (i) =>
        2.0 *
        math.pi *
        (_kModRateLoHz + (_kModRateHiHz - _kModRateLoHz) * i / (lines - 1)) /
        sr,
  );
  final phaseOff = List<double>.generate(
    lines,
    (i) => 2.0 * math.pi * i / lines,
  );

  // Circular delay buffers, per-line WRITE cursors, per-line damping state, and
  // per-line all-pass interpolator state. Buffers carry headroom (base length +
  // modulation depth + interpolation slack) so the modulated read can reach a
  // few samples PAST the base delay.
  final bufLen = List<int>.generate(
    lines,
    (i) => len[i] + modDepth.ceil() + 2,
  );
  final bufs = [for (var i = 0; i < lines; i++) Float64List(bufLen[i])];
  final pos = List<int>.filled(lines, 0);
  final lpState = List<double>.filled(lines, 0.0);
  final apState = List<double>.filled(lines, 0.0);

  // Input diffusion: a chain of Schroeder all-passes (unity gain, k = 0.6).
  final diffLen = [
    for (final m in _kDiffusers44k) math.max(1, (m * scale).round()),
  ];
  final diffBufs = [for (final m in diffLen) Float64List(m)];
  final diffPos = List<int>.filled(diffLen.length, 0);
  const diffK = 0.6;

  // Per-channel decorrelating all-passes (phase-only) on the decorr component.
  final decApLLen = [
    for (final m in _kDecorrApL44k) math.max(1, (m * scale).round()),
  ];
  final decApRLen = [
    for (final m in _kDecorrApR44k) math.max(1, (m * scale).round()),
  ];
  final decApLBuf = [for (final m in decApLLen) Float64List(m)];
  final decApRBuf = [for (final m in decApRLen) Float64List(m)];
  final decApLPos = List<int>.filled(decApLLen.length, 0);
  final decApRPos = List<int>.filled(decApRLen.length, 0);
  const decApK = 0.6;

  final outL = Float64List(n);
  final outR = Float64List(n);

  // Scratch reused each sample to avoid per-sample allocation.
  final damped = List<double>.filled(lines, 0.0);
  final oneMinusD = 1.0 - d;
  const twoOverN = 2.0 / lines;

  for (var t = 0; t < n; t++) {
    // Diffuse the raw input through the all-pass chain, then scale for injection.
    var xd = _finite(input[t]);
    for (var k = 0; k < diffBufs.length; k++) {
      final p = diffPos[k];
      final v = diffBufs[k][p];
      final w = xd + diffK * v;
      diffBufs[k][p] = w;
      xd = v - diffK * w;
      final np = p + 1;
      diffPos[k] = np == diffLen[k] ? 0 : np;
    }
    final x = xd * inputGain;

    // Read each delay's output at its MODULATED, fractional position (linear
    // interpolation), accumulate the shared (mono) sum and the two disjoint
    // decorrelator half-sums, and low-pass each line (one-pole "damping") ready
    // for feedback. The slow per-line LFO de-tunes the delay by a few samples so
    // the modal comb smears → a smooth (non-metallic) tail.
    var monoSum = 0.0;
    var decL = 0.0;
    var decR = 0.0;
    var dampedSum = 0.0;
    for (var i = 0; i < lines; i++) {
      final delay = len[i] + modDepth * math.sin(phaseInc[i] * t + phaseOff[i]);
      final bl = bufLen[i];
      // First-order all-pass fractional read: split the modulated delay into an
      // integer part M (sample at delay M = s0, at M+1 = s1) and a fraction, and
      // interpolate with a = (1−frac)/(1+frac). Unity magnitude → no HF tilt, so
      // the tail stays spectrally flat and RT60/damping are untouched.
      final m = delay.floor();
      final frac = delay - m;
      var a0 = pos[i] - m;
      while (a0 < 0) {
        a0 += bl;
      }
      var a1 = a0 - 1;
      if (a1 < 0) a1 += bl;
      final a = (1.0 - frac) / (1.0 + frac);
      final v = a * bufs[i][a0] + bufs[i][a1] - a * apState[i];
      apState[i] = v;
      monoSum += v;
      decL += _kDecorrL[i] * v;
      decR += _kDecorrR[i] * v;
      final dv = oneMinusD * v + d * lpState[i];
      lpState[i] = dv;
      damped[i] = dv;
      dampedSum += dv;
    }
    // Phase-decorrelate each channel's decorr component through its own all-pass
    // chain (unity gain), then blend it with the shared component so L and R are
    // wide but stay POSITIVELY correlated (mono-safe).
    for (var k = 0; k < decApLBuf.length; k++) {
      final p = decApLPos[k];
      final v = decApLBuf[k][p];
      final w = decL + decApK * v;
      decApLBuf[k][p] = w;
      decL = v - decApK * w;
      final np = p + 1;
      decApLPos[k] = np == decApLLen[k] ? 0 : np;
    }
    for (var k = 0; k < decApRBuf.length; k++) {
      final p = decApRPos[k];
      final v = decApRBuf[k][p];
      final w = decR + decApK * v;
      decApRBuf[k][p] = w;
      decR = v - decApK * w;
      final np = p + 1;
      decApRPos[k] = np == decApRLen[k] ? 0 : np;
    }
    outL[t] = _kShared * monoSum + _kDecorr * decL;
    outR[t] = _kShared * monoSum + _kDecorr * decR;

    // Unitary Householder mix of the damped outputs (y[i] = damped[i] − (2/N)·Σ)
    // then write input + g·feedback back into each delay.
    final hs = twoOverN * dampedSum;
    for (var i = 0; i < lines; i++) {
      bufs[i][pos[i]] = x + g * (damped[i] - hs);
      final p = pos[i] + 1;
      pos[i] = p == bufLen[i] ? 0 : p;
    }
  }

  return (outL, outR);
}

/// Replaces a non-finite sample with 0 so NaN/Inf can never enter the network.
double _finite(double v) => v.isFinite ? v : 0.0;
