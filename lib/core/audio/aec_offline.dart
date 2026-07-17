// lib/core/audio/aec_offline.dart
//
// Offline / streaming glue around the pure-Dart [EchoCanceller] — the pieces a
// CLI needs to run acoustic echo cancellation over files or pipes, headlessly.
// This is the SAME linear canceller the native Tier-3b engine is a cleanroom
// port of (ERLE cross-checked, see docs/AEC_TIER3B.md), so exercising it here
// validates the algorithm the app's jam-mode AEC runs, with no device or FFI.
//
// Two entry points:
//   * [cancelEcho] — whole-signal cancellation with automatic delay estimation
//     (offline we have both signals, so we can cross-correlate to align them —
//     the alignment a real-time AEC must otherwise track continuously).
//   * [StreamingEchoCanceller] — block-by-block over interleaved stereo PCM16
//     (channel 0 = mic/near-end+echo, channel 1 = reference), for pipes.
//
// Pure Dart, no Flutter — unit-tested in test/aec_offline_test.dart.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart' show fft;
import 'package:comet_beat/core/audio/echo_canceller.dart';

// --- Quality metrics -------------------------------------------------------
//
// The metrics below are all objective and PATENT-FREE / freely usable — an
// explicit choice for this MIT-clean tree (docs/AEC_TIER3B.md). ERLE and
// segmental ERLE are standard engineering measures; SI-SDR is the modern,
// gain-invariant fidelity metric from source separation (Le Roux et al.,
// "SDR – half-baked or well done?", 2019). We deliberately DO NOT use PESQ
// (ITU-T P.862) or POLQA — both are license/patent-encumbered for commercial
// use — nor a neural MOS (AECMOS), which would need an ONNX runtime.
//
// Which metric when:
//   * far-end single-talk (echo only, near-end silent): ERLE / segmental ERLE
//     measure how deeply the echo is suppressed.
//   * double-talk (near-end present): ERLE is MISLEADING (preserving the
//     near-end keeps residual energy up), so use SI-SDR of the cleaned output
//     against the true near-end — how close the estimate is to the wanted
//     signal, invariant to overall gain.

/// Echo Return Loss Enhancement in dB over the first [length] samples (default:
/// all) — how much louder the mic was than the residual. Higher = more echo
/// removed. Meaningless below ~0; a good linear cancel is 20 dB+. Valid only
/// for far-end single-talk (echo only); under double-talk use [siSdrDb].
double erleDb(Float64List mic, Float64List cleaned, {int? length}) {
  final n = length ?? min(mic.length, cleaned.length);
  var micE = 0.0, outE = 0.0;
  for (var i = 0; i < n; i++) {
    micE += mic[i] * mic[i];
    outE += cleaned[i] * cleaned[i];
  }
  return 10 * (log((micE + 1e-12) / (outE + 1e-12)) / ln10);
}

/// Mean per-segment ERLE in dB — a truer picture than one global figure, since
/// cancellation varies over time (convergence, echo-path changes). Segments
/// whose mic energy is below [activityFloor] (silence) are skipped; each
/// segment's ERLE is clamped to [floorDb, ceilDb] so one near-perfect or one
/// pathological block can't dominate the mean. Standard AEC evaluation measure.
double segmentalErleDb(
  Float64List mic,
  Float64List cleaned, {
  int segment = 1024,
  double activityFloor = 1e-6,
  double floorDb = -10,
  double ceilDb = 60,
}) {
  final n = min(mic.length, cleaned.length);
  var sum = 0.0;
  var count = 0;
  for (var s = 0; s + segment <= n; s += segment) {
    var micE = 0.0, outE = 0.0;
    for (var i = s; i < s + segment; i++) {
      micE += mic[i] * mic[i];
      outE += cleaned[i] * cleaned[i];
    }
    if (micE / segment < activityFloor) continue; // silent input segment
    final erle = (10 * (log((micE + 1e-12) / (outE + 1e-12)) / ln10))
        .clamp(floorDb, ceilDb);
    sum += erle;
    count += 1;
  }
  return count == 0 ? 0 : sum / count;
}

/// The first sample offset at which per-segment ERLE reaches [targetDb] — the
/// convergence point of the adaptive filter — or -1 if it never does. Divide by
/// the sample rate for a time; a good linear AEC converges in tens of ms.
int convergenceSample(
  Float64List mic,
  Float64List cleaned, {
  int segment = 1024,
  double targetDb = 15,
}) {
  final n = min(mic.length, cleaned.length);
  for (var s = 0; s + segment <= n; s += segment) {
    var micE = 0.0, outE = 0.0;
    for (var i = s; i < s + segment; i++) {
      micE += mic[i] * mic[i];
      outE += cleaned[i] * cleaned[i];
    }
    final erle = 10 * (log((micE + 1e-12) / (outE + 1e-12)) / ln10);
    if (erle >= targetDb) return s;
  }
  return -1;
}

/// Scale-invariant signal-to-distortion ratio (dB) of [estimate] against the
/// target [reference] over `[from, from+length)`. The gain-invariant fidelity
/// metric (Le Roux et al. 2019): it projects the estimate onto the reference,
/// so an overall level difference doesn't count as distortion — only the shape
/// does. Under double-talk, `reference` = the true near-end: higher = the
/// cleaned output is closer to the wanted signal (residual echo far below it).
double siSdrDb(
  Float64List reference,
  Float64List estimate, {
  int from = 0,
  int? length,
}) {
  final n = length ?? (min(reference.length, estimate.length) - from);
  var dot = 0.0, refE = 0.0;
  for (var i = from; i < from + n; i++) {
    dot += estimate[i] * reference[i];
    refE += reference[i] * reference[i];
  }
  final scale = dot / (refE + 1e-12);
  var targetE = 0.0, noiseE = 0.0;
  for (var i = from; i < from + n; i++) {
    final t = scale * reference[i];
    final e = estimate[i] - t;
    targetE += t * t;
    noiseE += e * e;
  }
  return 10 * (log((targetE + 1e-12) / (noiseE + 1e-12)) / ln10);
}

/// A bundle of the far-end-single-talk metrics for a cancellation pass — what a
/// CLI / test prints for "how good was this?". Under double-talk pair it with
/// [siSdrDb] against the known near-end.
class AecMetrics {
  const AecMetrics({
    required this.erle,
    required this.segErle,
    required this.convergedAtSample,
  });

  /// Global ERLE (dB).
  final double erle;

  /// Mean per-segment ERLE (dB).
  final double segErle;

  /// Sample offset where ERLE first reached the convergence target (-1 = never).
  final int convergedAtSample;

  /// Measures [mic] vs [cleaned] (an echo-only pass; near-end must be absent
  /// for ERLE to mean echo suppression).
  factory AecMetrics.measure(
    Float64List mic,
    Float64List cleaned, {
    int segment = 1024,
    double convergenceTargetDb = 15,
  }) =>
      AecMetrics(
        erle: erleDb(mic, cleaned),
        segErle: segmentalErleDb(mic, cleaned, segment: segment),
        convergedAtSample: convergenceSample(
          mic,
          cleaned,
          segment: segment,
          targetDb: convergenceTargetDb,
        ),
      );

  String report({int sampleRate = 44100}) {
    final conv = convergedAtSample < 0
        ? 'never'
        : '${(convergedAtSample * 1000 / sampleRate).toStringAsFixed(0)} ms';
    return 'ERLE ${erle.toStringAsFixed(1)} dB · '
        'segmental ${segErle.toStringAsFixed(1)} dB · '
        'converged $conv';
  }
}

/// FFT cross-correlation: the lag (in samples) at which [mic] best matches
/// [ref] — i.e. how far the captured echo trails the played reference. Offline
/// only (needs the whole signal); a streaming AEC must track this continuously.
int estimateEchoDelay(Float64List mic, Float64List ref) {
  final seg = min(mic.length, min(ref.length, 1 << 17));
  var n = 1;
  while (n < seg) {
    n <<= 1;
  }
  final mre = Float64List(n), mim = Float64List(n);
  final rre = Float64List(n), rim = Float64List(n);
  for (var i = 0; i < seg; i++) {
    mre[i] = mic[i];
    rre[i] = ref[i];
  }
  fft(mre, mim);
  fft(rre, rim);
  // MIC * conj(REF)
  final xre = Float64List(n), xim = Float64List(n);
  for (var k = 0; k < n; k++) {
    xre[k] = mre[k] * rre[k] + mim[k] * rim[k];
    xim[k] = -(mim[k] * rre[k] - mre[k] * rim[k]); // conjugate for inverse
  }
  fft(xre, xim); // inverse (scale irrelevant for argmax)
  var best = 0;
  var bestVal = -double.infinity;
  for (var lag = 0; lag < n ~/ 2; lag++) {
    if (xre[lag] > bestVal) {
      bestVal = xre[lag];
      best = lag;
    }
  }
  return best;
}

/// In-place inverse FFT via the conjugate trick (the shared [fft] is forward-
/// only): ifft(x) = conj(fft(conj(x)))/n.
void _ifft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 0; i < n; i++) {
    im[i] = -im[i];
  }
  fft(re, im);
  for (var i = 0; i < n; i++) {
    re[i] /= n;
    im[i] = -im[i] / n;
  }
}

/// Residual echo suppression (RES): a classic Wiener-style spectral post-filter
/// on what the linear canceller leaves behind (filter misadjustment, the echo
/// tail beyond the filter, mild nonlinearity). Patent-free — the short-time
/// spectral-gain approach is decades old; this copies no specific encumbered
/// implementation (notably not WebRTC AEC3's statistical model).
///
/// Framing reuses the canceller's own overlap-save structure — a 2·[blockSize]
/// frame of `[previous ; current]`, spectrally gained, keeping the last block —
/// so there's no window/COLA bookkeeping and it drops straight into the block
/// loop.
///
/// Per bin: the residual echo power is estimated as `λ(k)·|Ŷ(k)|²`, where Ŷ is
/// the canceller's echo estimate and λ is the smoothed **echo leakage** — how
/// much echo survives into the residual. λ is learned ONLY on far-end
/// single-talk (pass `updateLeak: false` when the double-talk detector says the
/// near-end is present), because during double-talk the near-end inflates the
/// residual and would drive λ — and thus the suppression — far too high.
///
/// [gainFloor] bounds the attenuation (a suppressor chews the wanted signal if
/// let loose), and [overSubtract] scales aggressiveness.
class ResidualEchoSuppressor {
  ResidualEchoSuppressor({
    this.blockSize = 1024,
    this.overSubtract = 1.0,
    this.gainFloor = 0.1,
    this.powerSmoothing = 0.8,
    this.leakSmoothing = 0.95,
    this.eps = 1e-12,
  })  : _n = 2 * blockSize,
        _prevCleaned = Float64List(blockSize),
        _prevEcho = Float64List(blockSize),
        _pe = Float64List(2 * blockSize),
        _py = Float64List(2 * blockSize),
        _leak = Float64List(2 * blockSize);

  final int blockSize;

  /// Scales the subtracted residual-echo estimate (higher = more aggressive).
  final double overSubtract;

  /// Minimum per-bin gain — the suppression floor (0 = mute, 1 = untouched).
  final double gainFloor;

  /// Per-bin power smoothing for the residual/echo spectra.
  final double powerSmoothing;

  /// Per-bin smoothing for the leakage estimate λ.
  final double leakSmoothing;

  final double eps;

  final int _n;
  final Float64List _prevCleaned;
  final Float64List _prevEcho;
  final Float64List _pe; // smoothed residual power
  final Float64List _py; // smoothed echo-estimate power
  final Float64List _leak; // λ per bin

  /// Suppress residual echo in one [cleaned] block, given the canceller's
  /// [echoEst] for the same block (`mic − cleaned`). Both must be [blockSize]
  /// long. Set [updateLeak] false during double-talk. Returns the suppressed
  /// block (a fresh list).
  Float64List process(
    Float64List cleaned,
    Float64List echoEst, {
    bool updateLeak = true,
  }) {
    assert(cleaned.length == blockSize && echoEst.length == blockSize);
    final b = blockSize;

    // Overlap-save frames: [previous ; current].
    final eRe = Float64List(_n), eIm = Float64List(_n);
    final yRe = Float64List(_n), yIm = Float64List(_n);
    for (var i = 0; i < b; i++) {
      eRe[i] = _prevCleaned[i];
      eRe[b + i] = cleaned[i];
      yRe[i] = _prevEcho[i];
      yRe[b + i] = echoEst[i];
    }
    fft(eRe, eIm);
    fft(yRe, yIm);

    for (var k = 0; k < _n; k++) {
      final pe = eRe[k] * eRe[k] + eIm[k] * eIm[k];
      final py = yRe[k] * yRe[k] + yIm[k] * yIm[k];
      _pe[k] = powerSmoothing * _pe[k] + (1 - powerSmoothing) * pe;
      _py[k] = powerSmoothing * _py[k] + (1 - powerSmoothing) * py;

      // Leakage λ = residual power / echo-estimate power, learned on far-end
      // single-talk only, and never above 1 (the residual can't exceed the echo
      // it came from — a higher ratio means near-end, not leakage).
      if (updateLeak && _py[k] > eps) {
        final ratio = (_pe[k] / (_py[k] + eps)).clamp(0.0, 1.0);
        _leak[k] = leakSmoothing * _leak[k] + (1 - leakSmoothing) * ratio;
      }

      // Wiener-style gain: subtract the estimated residual echo power.
      final residual = overSubtract * _leak[k] * _py[k];
      final gain =
          (1 - residual / (_pe[k] + eps)).clamp(gainFloor, 1.0).toDouble();
      eRe[k] *= gain;
      eIm[k] *= gain;
    }

    _ifft(eRe, eIm);

    // Overlap-save: the last block is the valid output.
    final out = Float64List(b);
    for (var i = 0; i < b; i++) {
      out[i] = eRe[b + i];
    }
    _prevCleaned.setAll(0, cleaned);
    _prevEcho.setAll(0, echoEst);
    return out;
  }
}

/// The result of an offline [cancelEcho] pass.
class AecResult {
  const AecResult({
    required this.cleaned,
    required this.erleDb,
    required this.delay,
    this.frozenBlocks = 0,
  });

  /// The cleaned near-end estimate (length = whole blocks × blockSize).
  final Float64List cleaned;

  /// Echo return loss enhancement over [cleaned], in dB.
  final double erleDb;

  /// The reference→mic delay used to align (given or estimated), in samples.
  final int delay;

  /// How many blocks the double-talk detector froze the filter (0 when the DTD
  /// is off) — a rough "how much near-end was present" indicator.
  final int frozenBlocks;
}

/// A double-talk detector: decides, per block, whether to FREEZE the adaptive
/// filter because near-end speech is present (adapting on it would corrupt the
/// filter). Patent-free, and it reuses what the canceller already produces — no
/// echo-path-gain threshold to tune (unlike a Geigel detector).
///
/// Statistic: the normalized correlation between the mic and the filter's echo
/// estimate (`echoEst = mic − cleaned = W·x`). Far-end single-talk → the
/// estimate tracks the mic → correlation ≈ 1. Double-talk → the near-end enters
/// the mic but not the estimate → correlation drops. A warmup guard lets the
/// filter converge first (the estimate is poor early), and a hangover holds the
/// freeze through brief correlation dips so it doesn't flap.
class DoubleTalkDetector {
  DoubleTalkDetector({
    this.threshold = 0.9,
    this.hangoverBlocks = 8,
    this.warmupBlocks = 12,
    this.farEndFloor = 1e-5,
  });

  /// Correlation below this ⇒ double-talk.
  final double threshold;

  /// Hold the freeze this many blocks after a double-talk decision.
  final int hangoverBlocks;

  /// Always adapt for this many blocks first, so the filter can converge.
  final int warmupBlocks;

  /// Below this per-sample reference power the far-end is silent (no echo to
  /// protect against) — the DTD stays out of the way.
  final double farEndFloor;

  int _block = 0;
  int _hangover = 0;

  /// Whether the NEXT [EchoCanceller.process] call should freeze (`adapt:
  /// false`). Read before processing a block, then call [update] after.
  bool get freeze => _hangover > 0;

  /// Feed a just-processed block (its [reference], [mic] and [cleaned] output)
  /// to update the freeze state for subsequent blocks.
  void update(Float64List reference, Float64List mic, Float64List cleaned) {
    _block += 1;
    var refMs = 0.0;
    for (var i = 0; i < reference.length; i++) {
      refMs += reference[i] * reference[i];
    }
    if (refMs / reference.length >= farEndFloor && _block > warmupBlocks) {
      var dot = 0.0, mm = 0.0, ee = 0.0;
      for (var i = 0; i < mic.length; i++) {
        final e = mic[i] - cleaned[i]; // echo estimate W·x
        dot += mic[i] * e;
        mm += mic[i] * mic[i];
        ee += e * e;
      }
      final rho = dot / (sqrt(mm * ee) + 1e-12);
      if (rho < threshold) _hangover = hangoverBlocks;
    }
    if (_hangover > 0) _hangover -= 1;
  }

  void reset() {
    _block = 0;
    _hangover = 0;
  }
}

/// Every numeric knob of the AEC chain, in one object, so a caller can tune the
/// whole thing without reaching into the three stages separately.
///
/// The stages ([EchoCanceller], [DoubleTalkDetector], [ResidualEchoSuppressor])
/// each carry their own defaults; this mirrors them so [cancelEcho] and
/// [StreamingEchoCanceller] have something to forward. Defaults here are the
/// stage defaults — `const AecTuning()` is the untuned chain.
///
/// The `res*` / `dtd*` knobs only bite when the corresponding stage is enabled
/// (`residualSuppress` / `doubleTalkDetect`); they're inert otherwise.
class AecTuning {
  const AecTuning({
    this.blockSize = 1024,
    this.mu = 0.7,
    this.powerSmoothing = 0.9,
    this.eps = 1e-6,
    this.farEndFloor = 1e-5,
    this.regFactor = 1.0,
    this.leak = 1e-3,
    this.dtdThreshold = 0.9,
    this.dtdHangoverBlocks = 8,
    this.dtdWarmupBlocks = 12,
    this.dtdFarEndFloor = 1e-5,
    this.resOverSubtract = 1.0,
    this.resGainFloor = 0.1,
    this.resPowerSmoothing = 0.8,
    this.resLeakSmoothing = 0.95,
    this.resEps = 1e-12,
  });

  /// Samples per processed block, shared by the canceller and the suppressor —
  /// also the adaptive filter's echo-tail length. A power of two.
  final int blockSize;

  // --- Linear canceller (see [EchoCanceller] for what each one does). ---
  final double mu;
  final double powerSmoothing;
  final double eps;
  final double farEndFloor;
  final double regFactor;
  final double leak;

  // --- Double-talk detector (see [DoubleTalkDetector]). ---
  final double dtdThreshold;
  final int dtdHangoverBlocks;
  final int dtdWarmupBlocks;
  final double dtdFarEndFloor;

  // --- Residual suppressor (see [ResidualEchoSuppressor]). ---
  final double resOverSubtract;
  final double resGainFloor;
  final double resPowerSmoothing;
  final double resLeakSmoothing;
  final double resEps;

  EchoCanceller createCanceller() => EchoCanceller(
        blockSize: blockSize,
        mu: mu,
        powerSmoothing: powerSmoothing,
        eps: eps,
        farEndFloor: farEndFloor,
        regFactor: regFactor,
        leak: leak,
      );

  DoubleTalkDetector createDetector() => DoubleTalkDetector(
        threshold: dtdThreshold,
        hangoverBlocks: dtdHangoverBlocks,
        warmupBlocks: dtdWarmupBlocks,
        farEndFloor: dtdFarEndFloor,
      );

  ResidualEchoSuppressor createSuppressor() => ResidualEchoSuppressor(
        blockSize: blockSize,
        overSubtract: resOverSubtract,
        gainFloor: resGainFloor,
        powerSmoothing: resPowerSmoothing,
        leakSmoothing: resLeakSmoothing,
        eps: resEps,
      );

  /// One line naming only what differs from the defaults — for a CLI/test print
  /// that has to say which point in the parameter space produced a number.
  String describe() {
    const d = AecTuning();
    final parts = <String>[
      if (blockSize != d.blockSize) 'block=$blockSize',
      if (mu != d.mu) 'mu=$mu',
      if (powerSmoothing != d.powerSmoothing) 'powerSmoothing=$powerSmoothing',
      if (eps != d.eps) 'eps=$eps',
      if (farEndFloor != d.farEndFloor) 'farEndFloor=$farEndFloor',
      if (regFactor != d.regFactor) 'reg=$regFactor',
      if (leak != d.leak) 'leak=$leak',
      if (dtdThreshold != d.dtdThreshold) 'dtdThreshold=$dtdThreshold',
      if (dtdHangoverBlocks != d.dtdHangoverBlocks)
        'dtdHangover=$dtdHangoverBlocks',
      if (dtdWarmupBlocks != d.dtdWarmupBlocks) 'dtdWarmup=$dtdWarmupBlocks',
      if (dtdFarEndFloor != d.dtdFarEndFloor) 'dtdFarEndFloor=$dtdFarEndFloor',
      if (resOverSubtract != d.resOverSubtract) 'resOverSub=$resOverSubtract',
      if (resGainFloor != d.resGainFloor) 'resGainFloor=$resGainFloor',
      if (resPowerSmoothing != d.resPowerSmoothing)
        'resPowerSmoothing=$resPowerSmoothing',
      if (resLeakSmoothing != d.resLeakSmoothing)
        'resLeakSmoothing=$resLeakSmoothing',
      if (resEps != d.resEps) 'resEps=$resEps',
    ];
    return parts.isEmpty ? 'defaults' : parts.join(' ');
  }
}

/// Cancels the echo of [ref] from [mic] over the whole signal. Aligns [ref] to
/// [mic] by [delay] samples (estimated with [estimateEchoDelay] when null),
/// then runs the [EchoCanceller] block by block. The trailing partial block is
/// dropped (the cleaned length is `mic.length ~/ blockSize * blockSize`).
AecResult cancelEcho(
  Float64List mic,
  Float64List ref, {
  int? delay,
  AecTuning tuning = const AecTuning(),
  bool doubleTalkDetect = false,
  bool residualSuppress = false,
}) {
  final blockSize = tuning.blockSize;
  final d = delay ?? estimateEchoDelay(mic, ref);
  final aligned = Float64List(mic.length);
  for (var i = 0; i < mic.length; i++) {
    final j = i - d;
    aligned[i] = (j >= 0 && j < ref.length) ? ref[j] : 0;
  }
  final aec = tuning.createCanceller();
  final dtd = doubleTalkDetect ? tuning.createDetector() : null;
  final res = residualSuppress ? tuning.createSuppressor() : null;
  final blocks = mic.length ~/ blockSize;
  final out = Float64List(blocks * blockSize);
  var frozen = 0;
  for (var bi = 0; bi < blocks; bi++) {
    final from = bi * blockSize;
    final refBlock = Float64List.sublistView(aligned, from, from + blockSize);
    final micBlock = Float64List.sublistView(mic, from, from + blockSize);
    final adapt = dtd == null || !dtd.freeze;
    if (!adapt) frozen += 1;
    final cleaned = aec.process(refBlock, micBlock, adapt: adapt);
    dtd?.update(refBlock, micBlock, cleaned);
    var block = cleaned;
    if (res != null) {
      // echoEst = mic − cleaned = W·x; don't learn the leakage on double-talk.
      final echoEst = Float64List(blockSize);
      for (var i = 0; i < blockSize; i++) {
        echoEst[i] = micBlock[i] - cleaned[i];
      }
      block = res.process(cleaned, echoEst, updateLeak: adapt);
    }
    out.setRange(from, from + blockSize, block);
  }
  return AecResult(
    cleaned: out,
    erleDb: erleDb(mic, out, length: blocks * blockSize),
    delay: d,
    frozenBlocks: frozen,
  );
}

/// Streaming echo canceller for a pipe. Feed interleaved stereo PCM16 (channel
/// 0 = mic/near-end+echo, channel 1 = reference) as it arrives; get cleaned
/// mono PCM16 back one block at a time. Identical output to [cancelEcho] for
/// the same aligned input — the state lives in one [EchoCanceller].
///
/// Streaming can't cross-correlate the whole signal, so alignment is a fixed
/// [refDelay] (samples the reference trails the mic); 0 suits a pre-aligned
/// full-duplex / loopback capture.
class StreamingEchoCanceller {
  StreamingEchoCanceller({
    this.tuning = const AecTuning(),
    this.refDelay = 0,
    bool doubleTalkDetect = false,
    bool residualSuppress = false,
  })  : assert(refDelay >= 0),
        _aec = tuning.createCanceller(),
        _dtd = doubleTalkDetect ? tuning.createDetector() : null,
        _res = residualSuppress ? tuning.createSuppressor() : null,
        // Seed the reference with `refDelay` zeros so ref[i] lines up with
        // mic[i-refDelay] — the reference arriving delayed relative to the mic.
        _ref = List<double>.filled(refDelay, 0, growable: true);

  final AecTuning tuning;
  int get blockSize => tuning.blockSize;
  final int refDelay;
  final EchoCanceller _aec;
  final DoubleTalkDetector? _dtd;
  final ResidualEchoSuppressor? _res;
  final _mic = <double>[];
  final List<double> _ref;

  /// How many blocks the double-talk detector has frozen the filter.
  int frozenBlocks = 0;

  /// Leftover bytes of a partial stereo frame carried to the next chunk (input
  /// need not arrive on frame boundaries — a pipe can split anywhere).
  final _byteRem = BytesBuilder(copy: false);

  var _micEnergy = 0.0;
  var _residualEnergy = 0.0;

  /// Running echo return loss enhancement (dB) over everything processed so far.
  double get erleDb =>
      10 * (log((_micEnergy + 1e-12) / (_residualEnergy + 1e-12)) / ln10);

  /// Feed interleaved stereo PCM16 (LE) bytes; returns cleaned mono PCM16 (LE)
  /// for every block that completed. Odd trailing bytes/samples are buffered.
  Uint8List addInterleavedPcm16(Uint8List stereo) {
    _byteRem.add(stereo);
    final buf = _byteRem.toBytes();
    final frames = buf.length ~/ 4; // 2ch × 2 bytes
    final view = ByteData.sublistView(buf);
    for (var f = 0; f < frames; f++) {
      _mic.add(view.getInt16(f * 4, Endian.little) / 32768.0);
      _ref.add(view.getInt16(f * 4 + 2, Endian.little) / 32768.0);
    }
    // Carry the partial trailing frame (0..3 bytes) to the next call.
    _byteRem.clear();
    if (buf.length % 4 != 0) {
      _byteRem.add(Uint8List.sublistView(buf, frames * 4));
    }
    return _drain();
  }

  /// Process the trailing partial block (zero-padded) so no audio is lost.
  Uint8List flush() {
    if (_mic.isEmpty) return Uint8List(0);
    while (_mic.length < blockSize) {
      _mic.add(0);
    }
    while (_ref.length < blockSize) {
      _ref.add(0);
    }
    return _drain();
  }

  Uint8List _drain() {
    final builder = BytesBuilder(copy: false);
    while (_mic.length >= blockSize && _ref.length >= blockSize) {
      final micBlock = Float64List(blockSize);
      final refBlock = Float64List(blockSize);
      for (var i = 0; i < blockSize; i++) {
        micBlock[i] = _mic[i];
        refBlock[i] = _ref[i];
      }
      final adapt = _dtd == null || !_dtd.freeze;
      if (!adapt) frozenBlocks += 1;
      final cleaned = _aec.process(refBlock, micBlock, adapt: adapt);
      _dtd?.update(refBlock, micBlock, cleaned);
      var block = cleaned;
      final res = _res;
      if (res != null) {
        final echoEst = Float64List(blockSize);
        for (var i = 0; i < blockSize; i++) {
          echoEst[i] = micBlock[i] - cleaned[i];
        }
        block = res.process(cleaned, echoEst, updateLeak: adapt);
      }
      final bytes = Uint8List(blockSize * 2);
      final out = ByteData.sublistView(bytes);
      for (var i = 0; i < blockSize; i++) {
        final c = block[i];
        out.setInt16(
          i * 2,
          (c.clamp(-1.0, 1.0) * 32767).round(),
          Endian.little,
        );
        _micEnergy += micBlock[i] * micBlock[i];
        _residualEnergy += c * c;
      }
      builder.add(bytes);
      _mic.removeRange(0, blockSize);
      _ref.removeRange(0, blockSize);
    }
    return builder.toBytes();
  }
}
