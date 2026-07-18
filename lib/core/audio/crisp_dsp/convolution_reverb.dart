// Convolution reverb — a real-space reverb (convolve with an impulse response),
// complementary to the algorithmic Freeverb in reverb.dart. The IR is
// SYNTHESIZED (early reflections + an exponentially-decaying diffuse tail), so
// no audio asset is needed. Convolution is FFT overlap-add using the app's
// radix-2 `fft`. Flutter-free, deterministic (seeded RNG), same-length output
// (`mix == 0` is an exact identity copy).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart' show fft;

/// Inverse FFT (in place) via `conj(FFT(conj(x)))/n`.
void _ifft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 0; i < n; i++) {
    im[i] = -im[i];
  }
  fft(re, im);
  final inv = 1.0 / n;
  for (var i = 0; i < n; i++) {
    re[i] = re[i] * inv;
    im[i] = -im[i] * inv;
  }
}

int _nextPow2(int x) {
  var n = 1;
  while (n < x) {
    n <<= 1;
  }
  return n;
}

/// Synthesizes a reverb impulse response: an optional [predelayMs] gap, a few
/// sparse early reflections, then an exponentially-decaying diffuse noise tail
/// of length [seconds]. [decay] (0..1) stretches the tail; larger = longer.
/// Peak-normalized. Deterministic for a given [seed].
Float64List synthReverbIr({
  double sampleRate = 44100,
  double seconds = 1.5,
  double decay = 0.5,
  double predelayMs = 0,
  int seed = 1,
}) {
  final sr = sampleRate <= 0 ? 44100.0 : sampleRate;
  final len = math.max(1, (seconds.clamp(0.02, 10.0) * sr).round());
  final pre = math.max(0, (predelayMs * 0.001 * sr).round());
  final ir = Float64List(pre + len);
  final rng = math.Random(seed);
  // Time-constant of the exponential tail (bigger decay → slower fall).
  final tau = len * (0.15 + 0.85 * decay.clamp(0.0, 1.0));

  // Early reflections: a handful of decaying discrete taps.
  const earlyMs = [7.0, 11.0, 17.0, 23.0, 29.0, 37.0];
  for (var k = 0; k < earlyMs.length; k++) {
    final idx = pre + (earlyMs[k] * 0.001 * sr).round();
    if (idx < ir.length) {
      ir[idx] += (0.6 - 0.08 * k) * (rng.nextBool() ? 1 : -1);
    }
  }
  // Diffuse tail: white noise × exponential envelope.
  for (var i = 0; i < len; i++) {
    final env = math.exp(-i / tau);
    ir[pre + i] += (rng.nextDouble() * 2 - 1) * env;
  }
  // Peak-normalize.
  var peak = 0.0;
  for (final v in ir) {
    peak = math.max(peak, v.abs());
  }
  if (peak > 0) {
    for (var i = 0; i < ir.length; i++) {
      ir[i] /= peak;
    }
  }
  return ir;
}

/// Convolves [input] with impulse response [ir] (FFT overlap-add) and blends
/// [mix] wet/dry. Output is the same length as [input] (the reverb tail is
/// truncated at the input length, like the other effects). `mix == 0` is an
/// exact copy.
Float64List convolveFx(Float64List input, Float64List ir, {double mix = 1}) {
  final m = mix.clamp(0.0, 1.0);
  final out = Float64List(input.length);
  if (m == 0 || input.isEmpty || ir.isEmpty) {
    out.setAll(0, input);
    return out;
  }
  final n = input.length;
  final mLen = ir.length;

  // FFT size N; per-segment input block L = N - mLen + 1.
  final fftSize = _nextPow2(2 * mLen);
  final block = fftSize - mLen + 1;

  // Precompute the IR spectrum once.
  final irRe = Float64List(fftSize)..setRange(0, mLen, ir);
  final irIm = Float64List(fftSize);
  fft(irRe, irIm);

  final wet = Float64List(n);
  final segRe = Float64List(fftSize);
  final segIm = Float64List(fftSize);
  for (var start = 0; start < n; start += block) {
    final count = math.min(block, n - start);
    segRe.fillRange(0, fftSize, 0);
    segIm.fillRange(0, fftSize, 0);
    segRe.setRange(0, count, input, start);
    fft(segRe, segIm);
    // Complex multiply by the IR spectrum, in place.
    for (var i = 0; i < fftSize; i++) {
      final ar = segRe[i], ai = segIm[i];
      final br = irRe[i], bi = irIm[i];
      segRe[i] = ar * br - ai * bi;
      segIm[i] = ar * bi + ai * br;
    }
    _ifft(segRe, segIm);
    // Overlap-add into the (truncated) output.
    final limit = math.min(fftSize, n - start);
    for (var i = 0; i < limit; i++) {
      wet[start + i] += segRe[i];
    }
  }

  for (var i = 0; i < n; i++) {
    out[i] = (1 - m) * input[i] + m * wet[i];
  }
  return out;
}

/// Convolution reverb over [input] using a synthesized IR. See
/// [synthReverbIr] for [seconds]/[decay]/[predelayMs]/[seed]; [mix] blends
/// wet/dry (`mix == 0` = dry).
Float64List convolutionReverbFx(
  Float64List input, {
  required double sampleRate,
  double seconds = 1.5,
  double decay = 0.5,
  double predelayMs = 0,
  double mix = 0.35,
  int seed = 1,
}) =>
    convolveFx(
      input,
      synthReverbIr(
        sampleRate: sampleRate,
        seconds: seconds,
        decay: decay,
        predelayMs: predelayMs,
        seed: seed,
      ),
      mix: mix,
    );
