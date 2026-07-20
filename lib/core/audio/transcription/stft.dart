// lib/core/audio/transcription/stft.dart
//
// STFT / iSTFT matching torch.stft/istft (Hann window, centered with reflect
// padding, COLA-normalised overlap-add) — the DSP front/back end for source
// separation (feed a model a magnitude spectrogram, apply its mask, reconstruct
// audio). Uses the app's radix-2 FFT (n_fft must be a power of two).
//
// WEB-SAFE: pure Dart (`dart:math`/`dart:typed_data` + the app FFT).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart' show fft;

/// An STFT with `nFft`-point frames, `hop` stride, and a periodic Hann window.
///
/// With [center] true (the default) it matches `torch.stft(center=True,
/// pad_mode='reflect')` — the Open-Unmix front-end. With [center] false it
/// matches `torch.stft(center=False)` / kaldi-native-fbank's `knf.Stft`
/// (no padding, frame `t` covers `signal[t*hop .. t*hop+nFft)`) — the Spleeter
/// front-end.
class Stft {
  Stft(this.nFft, this.hop, {this.center = true})
      : nFreq = nFft ~/ 2 + 1,
        window = _hann(nFft) {
    assert(nFft & (nFft - 1) == 0, 'nFft must be a power of two');
  }

  final int nFft;
  final int hop;
  final bool center;
  final int nFreq; // nFft/2 + 1
  final Float64List window;

  static Float64List _hann(int n) {
    final w = Float64List(n);
    for (var i = 0; i < n; i++) {
      w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / n); // periodic Hann
    }
    return w;
  }

  /// Forward STFT. Returns `(re, im, nFrames)` with `re`/`im` row-major
  /// `[nFrames × nFreq]` (`[t*nFreq + f]`).
  (Float64List, Float64List, int) forward(Float64List signal) {
    final len = signal.length;

    // center=false (Spleeter / knf.Stft): no padding, frame `t` reads the raw
    // signal at `[t*hop .. t*hop+nFft)`; nFrames = 1 + (len-nFft)/hop.
    if (!center) {
      final nFrames = len < nFft ? 0 : 1 + (len - nFft) ~/ hop;
      final re = Float64List(nFrames * nFreq);
      final im = Float64List(nFrames * nFreq);
      final fr = Float64List(nFft), fi = Float64List(nFft);
      for (var t = 0; t < nFrames; t++) {
        final s = t * hop;
        for (var i = 0; i < nFft; i++) {
          fr[i] = signal[s + i] * window[i];
          fi[i] = 0.0;
        }
        fft(fr, fi);
        final o = t * nFreq;
        for (var f = 0; f < nFreq; f++) {
          re[o + f] = fr[f];
          im[o + f] = fi[f];
        }
      }
      return (re, im, nFrames);
    }

    final half = nFft ~/ 2;
    final padded = Float64List(len + nFft)..setRange(half, half + len, signal);
    // reflect-center like torch.stft.
    int refl(int i) {
      if (len <= 1) return 0;
      var j = i;
      while (j < 0 || j >= len) {
        if (j < 0) j = -j;
        if (j >= len) j = 2 * (len - 1) - j;
      }
      return j;
    }

    for (var i = 0; i < half; i++) {
      padded[i] = signal[refl(i - half)];
      padded[half + len + i] = signal[refl(len + i)];
    }

    final nFrames = 1 + len ~/ hop;
    final re = Float64List(nFrames * nFreq);
    final im = Float64List(nFrames * nFreq);
    final fr = Float64List(nFft), fi = Float64List(nFft);
    for (var t = 0; t < nFrames; t++) {
      final s = t * hop;
      for (var i = 0; i < nFft; i++) {
        fr[i] = padded[s + i] * window[i];
        fi[i] = 0.0;
      }
      fft(fr, fi);
      final o = t * nFreq;
      for (var f = 0; f < nFreq; f++) {
        re[o + f] = fr[f];
        im[o + f] = fi[f];
      }
    }
    return (re, im, nFrames);
  }

  /// Inverse STFT of a complex spectrogram (`re`/`im` row-major `[nFrames ×
  /// nFreq]`) → a real signal of [length] samples. Matches torch.istft:
  /// `OLA(ifft(X)·window) / OLA(window²)`, trimmed by `nFft/2` (center).
  Float64List inverse(
    Float64List re,
    Float64List im,
    int nFrames,
    int length,
  ) {
    final half = nFft ~/ 2;
    final total = (nFrames - 1) * hop + nFft;
    final out = Float64List(total);
    final wsum = Float64List(total);
    final fr = Float64List(nFft), fi = Float64List(nFft);
    for (var t = 0; t < nFrames; t++) {
      final o = t * nFreq;
      // Rebuild the full nFft spectrum via Hermitian symmetry.
      for (var f = 0; f < nFreq; f++) {
        fr[f] = re[o + f];
        fi[f] = -im[o + f]; // conj for the ifft-via-fft trick
      }
      for (var f = 1; f < nFreq - 1; f++) {
        fr[nFft - f] = re[o + f];
        fi[nFft - f] = im[o + f]; // conj of conj
      }
      fft(fr, fi); // forward FFT of conj(X)
      // ifft(X) = conj(fft(conj(X)))/N → real part = fr/N.
      final s = t * hop;
      for (var i = 0; i < nFft; i++) {
        final x = fr[i] / nFft;
        out[s + i] += x * window[i];
        wsum[s + i] += window[i] * window[i];
      }
    }
    for (var i = 0; i < total; i++) {
      if (wsum[i] > 1e-8) out[i] /= wsum[i];
    }
    // center=false (knf.IStft): the OLA buffer already starts at sample 0 — no
    // half-frame trim. center=true (torch.istft): drop the nFft/2 pad.
    final offset = center ? half : 0;
    final result = Float64List(length);
    for (var i = 0; i < length; i++) {
      final s = offset + i;
      result[i] = s < total ? out[s] : 0.0;
    }
    return result;
  }
}
