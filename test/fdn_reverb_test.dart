// Acceptance test for the clean-room FDN reverb (docs/FDN_REVERB_SPEC.md).
// Feeds a unit impulse through fdnReverb and asserts the reference-oracle
// character: a WIDE decorrelated tail (the whole point vs Freeverb), a plausible
// RT60, a diffuse non-metallic early response, working damping, and stability.
// Do not weaken these thresholds — fix the implementation.

// Cosmetic-only lints in this provided test (explicit default args kept for
// readability, minor style) — suppressed without touching any threshold/logic.
// ignore_for_file: avoid_redundant_argument_values, require_trailing_commas
// ignore_for_file: unnecessary_parenthesis

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/fdn_reverb.dart';
import 'package:flutter_test/flutter_test.dart';

const _sr = 44100;

/// A unit impulse followed by `tailSec` of silence for the tail to ring into.
Float64List _impulse({double tailSec = 5}) {
  final x = Float64List((tailSec * _sr).round());
  if (x.isNotEmpty) x[0] = 1.0;
  return x;
}

double _rms(List<double> x, int a, int b) {
  var s = 0.0;
  final e = min(b, x.length);
  for (var i = max(0, a); i < e; i++) {
    s += x[i] * x[i];
  }
  return sqrt(s / max(1, e - max(0, a)));
}

/// In-place iterative radix-2 FFT (length a power of two).
void _fft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      var t = re[i];
      re[i] = re[j];
      re[j] = t;
      t = im[i];
      im[i] = im[j];
      im[j] = t;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = -2 * pi / len;
    final wr = cos(ang), wi = sin(ang);
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final ur = re[i + k], ui = im[i + k];
        final vr = re[i + k + len ~/ 2] * cr - im[i + k + len ~/ 2] * ci;
        final vi = re[i + k + len ~/ 2] * ci + im[i + k + len ~/ 2] * cr;
        re[i + k] = ur + vr;
        im[i + k] = ui + vi;
        re[i + k + len ~/ 2] = ur - vr;
        im[i + k + len ~/ 2] = ui - vi;
        final ncr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = ncr;
      }
    }
  }
}

/// Welch-averaged spectral flatness of the impulse-response TAIL over
/// [200 Hz, 10 kHz]: geomean(P)/mean(P). →1 flat/noise-like (smooth reverb),
/// →0 peaky (a static-FDN comb colours the tail). Higher = less metallic.
double _tailFlatness(List<double> mono, int tailStart, int tailEnd) {
  const fftN = 8192;
  final hann = Float64List(fftN);
  for (var i = 0; i < fftN; i++) {
    hann[i] = 0.5 - 0.5 * cos(2 * pi * i / (fftN - 1));
  }
  final psd = Float64List(fftN ~/ 2);
  var wins = 0;
  for (var s = tailStart;
      s + fftN <= min(tailEnd, mono.length);
      s += fftN ~/ 2) {
    final re = Float64List(fftN), im = Float64List(fftN);
    for (var i = 0; i < fftN; i++) {
      re[i] = mono[s + i] * hann[i];
    }
    _fft(re, im);
    for (var k = 0; k < fftN ~/ 2; k++) {
      psd[k] += re[k] * re[k] + im[k] * im[k];
    }
    wins++;
  }
  if (wins == 0) return 0;
  final loBin = (200 * fftN / _sr).floor();
  final hiBin = (10000 * fftN / _sr).ceil();
  var logSum = 0.0, sum = 0.0, cnt = 0;
  for (var k = loBin; k <= hiBin && k < psd.length; k++) {
    final p = psd[k] / wins + 1e-20;
    logSum += log(p);
    sum += p;
    cnt++;
  }
  return exp(logSum / cnt) / (sum / cnt);
}

void main() {
  test('empty in → empty out', () {
    final (l, r) = fdnReverb(Float64List(0));
    expect(l, isEmpty);
    expect(r, isEmpty);
  });

  test('no NaN/Inf and bounded for impulse, silence, and noise', () {
    void ok(Float64List inp) {
      final (l, r) = fdnReverb(inp);
      for (final ch in [l, r]) {
        for (final v in ch) {
          expect(v.isFinite, isTrue);
          expect(v.abs(), lessThan(8.0));
        }
      }
    }

    ok(_impulse(tailSec: 2));
    ok(Float64List((2 * _sr).round())); // silence → silent, finite
    final noise = Float64List((_sr).round());
    var seed = 12345; // deterministic pseudo-noise (no dart:math Random)
    for (var i = 0; i < noise.length; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      noise[i] = (seed / 0x3fffffff) - 1.0;
    }
    ok(noise);
  });

  test('WIDE but mono-SAFE tail (matches the oracle band, not anti-phase)', () {
    final (l, r) = fdnReverb(_impulse(), roomSize: 0.7, damping: 0.4);
    var mid = 0.0, side = 0.0, sll = 0.0, srr = 0.0, slr = 0.0;
    for (var i = 0; i < l.length; i++) {
      mid += pow((l[i] + r[i]) / 2, 2);
      side += pow((l[i] - r[i]) / 2, 2);
      sll += l[i] * l[i];
      srr += r[i] * r[i];
      slr += l[i] * r[i];
    }
    final corr = slr / (sqrt(sll) * sqrt(srr) + 1e-12);
    // The goal is to MATCH the reference (width 0.38, corr 0.55), not to
    // maximise width: a fully-decorrelated tail (width→1, corr→0) or an
    // anti-phase one (corr<0) is over-wide, phasey, and CANCELS in mono.
    expect(side / mid, greaterThan(0.25),
        reason:
            'the FDN tail must be wide (reference ≈ 0.38), unlike Freeverb');
    expect(side / mid, lessThan(0.9),
        reason: 'over-wide (reference ≈ 0.38): a fully-decorrelated tail is '
            'phasey and unnatural');
    expect(corr, lessThan(0.8), reason: 'L and R must be decorrelated');
    expect(corr, greaterThan(0.1),
        reason: 'L and R must stay POSITIVELY correlated (reference ≈ 0.55) — '
            'a negative/near-zero corr cancels on a mono speaker');
  });

  test('WIDE across the musical range (not just an impulse)', () {
    // A frequency-dependent (sign-pattern) decorrelation can be wide for a
    // broadband impulse yet collapse to near-mono on real tonal music at the
    // WRONG frequency (the reference oracle was ~0.05 wide on a ~1 kHz note
    // while an impulse read 0.33). Sweep tones across the range and require the
    // reverb to stay wide at EVERY one — i.e. broadband decorrelation.
    double widthOf(double hz) {
      final inp = Float64List((3 * _sr).round());
      for (var i = 0; i < (0.4 * _sr).round(); i++) {
        inp[i] = 0.5 * sin(2 * pi * hz * i / _sr);
      }
      final (l, r) = fdnReverb(inp, roomSize: 0.7, damping: 0.4);
      var mid = 0.0, side = 0.0;
      for (var i = 0; i < l.length; i++) {
        mid += pow((l[i] + r[i]) / 2, 2);
        side += pow((l[i] - r[i]) / 2, 2);
      }
      return side / (mid + 1e-12);
    }

    for (final hz in [220.0, 440.0, 700.0, 1046.0, 1500.0, 2200.0]) {
      final w = widthOf(hz);
      expect(w, greaterThan(0.12),
          reason: 'tail collapses to mono at ${hz.round()} Hz — the '
              'decorrelation must be broadband, not frequency-dependent');
      // …and must not BLOW UP at any single frequency either: a truly
      // broadband decorrelation clusters near the oracle (~0.38), it does not
      // swing from 0.27 to 3.6 across the sweep.
      expect(w, lessThan(1.5),
          reason: 'width explodes to $w at ${hz.round()} Hz — still frequency-'
              'dependent (over-wide/anti-phase), not a uniform oracle-like tail');
    }
  });

  test('RT60 is in a plausible room range [0.8, 2.6] s', () {
    final (l, r) = fdnReverb(_impulse(), roomSize: 0.7, damping: 0.4);
    final mono = [for (var i = 0; i < l.length; i++) (l[i] + r[i]) / 2];
    final w = (0.05 * _sr).round();
    var peak = 0.0, peakAt = 0;
    final env = <double>[];
    for (var i = 0; i + w < mono.length; i += w) {
      final e = _rms(mono, i, i + w);
      env.add(e);
      if (e > peak) {
        peak = e;
        peakAt = env.length - 1;
      }
    }
    var rt60 = -1.0;
    for (var i = peakAt; i < env.length; i++) {
      if (env[i] < peak / 1000) {
        rt60 = (i - peakAt) * 0.05;
        break;
      }
    }
    expect(rt60, greaterThan(0.8),
        reason: 'RT60 too short (reference ≈ 1.6 s)');
    expect(rt60, lessThan(2.6), reason: 'RT60 too long / not decaying');
  });

  test('diffuse, non-metallic early response (crest < 6)', () {
    final (l, r) = fdnReverb(_impulse(), roomSize: 0.7, damping: 0.4);
    final mono = [for (var i = 0; i < l.length; i++) (l[i] + r[i]) / 2];
    var peak = 0.0, onset = 0;
    for (var i = 0; i < mono.length; i++) {
      if (mono[i].abs() > peak) peak = mono[i].abs();
    }
    for (var i = 0; i < mono.length; i++) {
      if (mono[i].abs() > peak * 0.5) {
        onset = i;
        break;
      }
    }
    final early =
        mono.sublist(onset, min(onset + (0.06 * _sr).round(), mono.length));
    var ep = 0.0;
    for (final v in early) {
      if (v.abs() > ep) ep = v.abs();
    }
    final er = _rms(early, 0, early.length);
    expect(ep / (er + 1e-12), lessThan(6.0),
        reason: 'a metallic FDN spikes (reference crest ≈ 2.4)');
  });

  test('tail decays to < peak/100 before the buffer ends', () {
    final (l, r) = fdnReverb(_impulse(), roomSize: 0.7, damping: 0.4);
    final mono = [for (var i = 0; i < l.length; i++) (l[i] + r[i]) / 2];
    final n = mono.length;
    var peak = 0.0;
    for (final v in mono) {
      if (v.abs() > peak) peak = v.abs();
    }
    final endRms = _rms(mono, (n * 0.95).round(), n);
    expect(endRms, lessThan(peak / 100), reason: 'the tail must ring out');
  });

  test('damping darkens: high band decays faster than low when damping high',
      () {
    final (l, r) = fdnReverb(_impulse(), roomSize: 0.7, damping: 0.85);
    final mono = [for (var i = 0; i < l.length; i++) (l[i] + r[i]) / 2];
    // Crude high/low split via first-difference (HF) vs running-sum (LF) energy,
    // early (0.2–0.5 s) vs late (1.5–2.0 s). HF should fall MORE than LF.
    double hf(int a, int b) {
      var s = 0.0;
      for (var i = max(1, a); i < min(b, mono.length); i++) {
        final d = mono[i] - mono[i - 1];
        s += d * d;
      }
      return sqrt(s / max(1, b - a));
    }

    final hfEarly = hf((0.2 * _sr).round(), (0.5 * _sr).round());
    final hfLate = hf((1.5 * _sr).round(), (2.0 * _sr).round());
    final lfEarly = _rms(mono, (0.2 * _sr).round(), (0.5 * _sr).round());
    final lfLate = _rms(mono, (1.5 * _sr).round(), (2.0 * _sr).round());
    // HF decay ratio should be smaller (more decay) than LF decay ratio.
    expect((hfLate + 1e-9) / (hfEarly + 1e-9),
        lessThan((lfLate + 1e-9) / (lfEarly + 1e-9)),
        reason: 'damping must attenuate highs faster than lows');
  });

  // ------------------------------------------------------------------
  // ANTI-RINGING: a static FDN colours the tail — its fixed delay comb makes a
  // peaky (metallic) spectrum. The reference smears it by MODULATING its delay
  // lines and using shorter/denser delays. Spectral flatness of the tail
  // captures it: on identical input the reference reads ~2x flatter than our
  // static build. This is the audible defect on percussion.
  // ------------------------------------------------------------------
  test('tail is SPECTRALLY SMOOTH, not a metallic comb (flatness > 0.35)', () {
    final (l, r) = fdnReverb(_impulse(), roomSize: 0.7, damping: 0.4);
    final mono = [for (var i = 0; i < l.length; i++) (l[i] + r[i]) / 2];
    var peakAt = 0, peak = 0.0;
    for (var i = 0; i < mono.length; i++) {
      if (mono[i].abs() > peak) {
        peak = mono[i].abs();
        peakAt = i;
      }
    }
    final tailStart = min(mono.length - 1, peakAt + (0.2 * _sr).round());
    // Restrict to the ACTIVE decay region (down to ~-50 dB); trailing silence
    // would dilute the measure. Scan a block-RMS envelope for the last loud one.
    const block = 512;
    var tailEnd = tailStart + block;
    for (var s = tailStart; s + block <= mono.length; s += block) {
      if (_rms(mono, s, s + block) > peak * 0.003) tailEnd = s + block;
    }
    // A static FDN's fixed modal comb reads ~0.27; the reference reverb, on
    // identical input, is ~2x flatter (~0.36). Modulated + dense delays smooth
    // the tail. If this fails, the tail rings — add delay-line modulation and
    // shorten/densify the delays (do NOT weaken the threshold).
    expect(_tailFlatness(mono, tailStart, tailEnd), greaterThan(0.35),
        reason: 'tail spectrum is comb-coloured (metallic) — modulate the '
            'delay lines and densify them to smear the modal peaks');
  });
}
