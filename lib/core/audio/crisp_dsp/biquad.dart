// Biquad filters (RBJ "Audio EQ Cookbook" coefficients) — the building block
// for a parametric EQ the app lacked. Flutter-free, deterministic, tested like
// the other crisp_dsp effects.
//
// Two levels of API:
//   • [Biquad] — a stateful single filter (`process` one sample) for use inside
//     a per-channel effect chain / a streaming graph later.
//   • [biquadFx] / [parametricEqFx] — same-length `Float64List → Float64List`
//     convenience transforms, matching the other effects. `mix == 0` is an exact
//     identity copy.

import 'dart:math' as math;
import 'dart:typed_data';

/// Filter response shapes (RBJ cookbook).
enum BiquadKind {
  lowpass,
  highpass,
  bandpass, // constant 0 dB peak
  notch,
  peaking, // bell — [gainDb] boosts/cuts around [freq]
  lowShelf, // [gainDb] below [freq]
  highShelf, // [gainDb] above [freq]
}

/// One EQ band for [parametricEqFx].
class EqBand {
  final BiquadKind kind;
  final double freq;
  final double q;
  final double gainDb;
  const EqBand(
    this.kind, {
    required this.freq,
    this.q = 0.707,
    this.gainDb = 0,
  });
}

/// A stateful Direct-Form-I biquad. Coefficients are computed once at
/// construction from ([kind], [freq], [sampleRate], [q], [gainDb]).
class Biquad {
  double _b0 = 1, _b1 = 0, _b2 = 0, _a1 = 0, _a2 = 0; // normalised by a0
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  final BiquadKind _kind;
  final double _sr, _q, _gainDb;

  Biquad(
    BiquadKind kind, {
    required double freq,
    required double sampleRate,
    double q = 0.707,
    double gainDb = 0,
  })  : _kind = kind,
        _sr = sampleRate <= 0 ? 44100.0 : sampleRate,
        _q = q,
        _gainDb = gainDb {
    setFreq(freq);
  }

  /// Retune the corner to [freq] in place, recomputing the coefficients WITHOUT
  /// clearing the filter memory — so the cutoff can sweep mid-note (an SF2
  /// mod-envelope → filter) click-free.
  void setFreq(double freq) {
    final kind = _kind;
    final sr = _sr;
    final q = _q;
    final gainDb = _gainDb;
    // Keep the corner strictly inside (0, Nyquist) so tan/sin stay finite.
    final f = freq.clamp(1.0, sr / 2 - 1);
    final qq = q <= 0 ? 1e-4 : q;
    final w0 = 2 * math.pi * f / sr;
    final cw = math.cos(w0);
    final sw = math.sin(w0);
    final alpha = sw / (2 * qq);
    final a =
        math.pow(10, gainDb / 40).toDouble(); // amplitude for shelves/peak
    final sqrtA = math.sqrt(a);

    double b0, b1, b2, a0, a1, a2;
    switch (kind) {
      case BiquadKind.lowpass:
        b0 = (1 - cw) / 2;
        b1 = 1 - cw;
        b2 = (1 - cw) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cw;
        a2 = 1 - alpha;
      case BiquadKind.highpass:
        b0 = (1 + cw) / 2;
        b1 = -(1 + cw);
        b2 = (1 + cw) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cw;
        a2 = 1 - alpha;
      case BiquadKind.bandpass:
        b0 = alpha;
        b1 = 0;
        b2 = -alpha;
        a0 = 1 + alpha;
        a1 = -2 * cw;
        a2 = 1 - alpha;
      case BiquadKind.notch:
        b0 = 1;
        b1 = -2 * cw;
        b2 = 1;
        a0 = 1 + alpha;
        a1 = -2 * cw;
        a2 = 1 - alpha;
      case BiquadKind.peaking:
        b0 = 1 + alpha * a;
        b1 = -2 * cw;
        b2 = 1 - alpha * a;
        a0 = 1 + alpha / a;
        a1 = -2 * cw;
        a2 = 1 - alpha / a;
      case BiquadKind.lowShelf:
        b0 = a * ((a + 1) - (a - 1) * cw + 2 * sqrtA * alpha);
        b1 = 2 * a * ((a - 1) - (a + 1) * cw);
        b2 = a * ((a + 1) - (a - 1) * cw - 2 * sqrtA * alpha);
        a0 = (a + 1) + (a - 1) * cw + 2 * sqrtA * alpha;
        a1 = -2 * ((a - 1) + (a + 1) * cw);
        a2 = (a + 1) + (a - 1) * cw - 2 * sqrtA * alpha;
      case BiquadKind.highShelf:
        b0 = a * ((a + 1) + (a - 1) * cw + 2 * sqrtA * alpha);
        b1 = -2 * a * ((a - 1) + (a + 1) * cw);
        b2 = a * ((a + 1) + (a - 1) * cw - 2 * sqrtA * alpha);
        a0 = (a + 1) - (a - 1) * cw + 2 * sqrtA * alpha;
        a1 = 2 * ((a - 1) - (a + 1) * cw);
        a2 = (a + 1) - (a - 1) * cw - 2 * sqrtA * alpha;
    }
    _b0 = b0 / a0;
    _b1 = b1 / a0;
    _b2 = b2 / a0;
    _a1 = a1 / a0;
    _a2 = a2 / a0;
  }

  /// Processes one sample.
  double process(double x) {
    final y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }

  /// Clears the filter memory.
  void reset() => _x1 = _x2 = _y1 = _y2 = 0;
}

/// Filters [input] through one biquad and blends [mix] wet/dry (`mix == 0` is an
/// exact copy). Same length as [input].
Float64List biquadFx(
  Float64List input, {
  BiquadKind kind = BiquadKind.lowpass,
  required double sampleRate,
  double freq = 1000,
  double q = 0.707,
  double gainDb = 0,
  double mix = 1,
}) {
  final m = mix.clamp(0.0, 1.0);
  final out = Float64List(input.length);
  if (m == 0) {
    out.setAll(0, input);
    return out;
  }
  final bq =
      Biquad(kind, freq: freq, sampleRate: sampleRate, q: q, gainDb: gainDb);
  for (var i = 0; i < input.length; i++) {
    final w = bq.process(input[i]);
    out[i] = (1 - m) * input[i] + m * w;
  }
  return out;
}

/// Chains [bands] into a parametric EQ over [input]. Empty bands → an exact
/// copy. Same length as [input].
Float64List parametricEqFx(
  Float64List input,
  List<EqBand> bands, {
  required double sampleRate,
}) {
  final out = Float64List(input.length)..setAll(0, input);
  if (bands.isEmpty) return out;
  final filters = [
    for (final b in bands)
      Biquad(
        b.kind,
        freq: b.freq,
        sampleRate: sampleRate,
        q: b.q,
        gainDb: b.gainDb,
      ),
  ];
  for (var i = 0; i < out.length; i++) {
    var s = out[i];
    for (final f in filters) {
      s = f.process(s);
    }
    out[i] = s;
  }
  return out;
}
