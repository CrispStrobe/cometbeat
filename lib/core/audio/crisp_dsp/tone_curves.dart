// Tone curves — the broad, musical shapes, as opposed to the surgical filters.
//
// The biquads answer "remove this frequency". These answer "make it darker",
// "make it sound right at this volume", "make it cut through" — questions about
// the WHOLE spectrum at once, which is why each is one or two knobs over a fixed
// shape rather than a frequency and a Q.
//
// Clean-room from published theory: complementary shelves for a tilt, the
// equal-loudness contours' well-known shape for loudness compensation, the
// standard 50/75 µs time constants for de-emphasis, and odd-symmetric
// waveshaping for presence.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/biquad.dart';

/// Tilt the whole spectrum around [pivotHz]: positive [tiltDb] lifts the treble
/// and drops the bass by the same amount, negative does the reverse.
///
/// One knob for "darker / brighter", which is the adjustment people actually
/// reach for, and it is a genuinely different thing from a low-pass: the top is
/// still there, it is just further down relative to the bottom. Implemented as a
/// complementary shelf PAIR so the pivot really holds still — a single shelf
/// moves the overall level as well as the balance, which is why one-knob tone
/// controls built from a single shelf always seem to need the fader afterwards.
Float64List tiltEqFx(
  Float64List input, {
  required double sampleRate,
  double tiltDb = 0,
  double pivotHz = 1000,
  double mix = 1,
}) {
  final out = Float64List(input.length);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0 || input.isEmpty || tiltDb == 0) {
    out.setAll(0, input);
    return out;
  }
  final half = tiltDb.clamp(-24.0, 24.0) / 2;
  final low = Biquad(
    BiquadKind.lowShelf,
    freq: pivotHz,
    sampleRate: sampleRate,
    gainDb: -half,
  );
  final high = Biquad(
    BiquadKind.highShelf,
    freq: pivotHz,
    sampleRate: sampleRate,
    gainDb: half,
  );
  for (var i = 0; i < input.length; i++) {
    final wet = high.process(low.process(input[i]));
    out[i] = (1 - m) * input[i] + m * wet;
  }
  return out;
}

/// Compensate for listening QUIETLY: lift the extremes as the level drops.
///
/// Hearing is not equally sensitive across the spectrum, and the imbalance gets
/// worse the quieter things are — bass falls away fastest, treble second. So a
/// mix that was balanced at a normal level sounds thin at a low one, and the
/// fix is not more volume but more of the ends.
///
/// [amount] is how far below a reference level you are listening, in dB, and the
/// compensation scales with it: at 0 this is a no-op, at 20 the bass comes up
/// several dB and the top a little. It is a broad approximation of the
/// equal-loudness contours, not a calibrated one — nothing here knows the
/// playback level, so a calibrated version would be a lie.
Float64List loudnessFx(
  Float64List input, {
  required double sampleRate,
  double amount = 10,
  double mix = 1,
}) {
  final out = Float64List(input.length);
  final m = mix.clamp(0.0, 1.0);
  final a = amount.clamp(0.0, 30.0);
  if (m == 0 || input.isEmpty || a == 0) {
    out.setAll(0, input);
    return out;
  }
  // The contours steepen at the bottom roughly twice as fast as at the top,
  // which is why the two shelves are not given the same gain.
  final bass = Biquad(
    BiquadKind.lowShelf,
    freq: 120,
    sampleRate: sampleRate,
    gainDb: a * 0.45,
  );
  final treble = Biquad(
    BiquadKind.highShelf,
    freq: 6000,
    sampleRate: sampleRate,
    gainDb: a * 0.2,
  );
  for (var i = 0; i < input.length; i++) {
    final wet = treble.process(bass.process(input[i]));
    out[i] = (1 - m) * input[i] + m * wet;
  }
  return out;
}

/// The standard de-emphasis curve — a fixed treble roll-off with time constant
/// [microseconds] (50 µs or 75 µs).
///
/// Pre-emphasis boosts the treble before storage or transmission and
/// de-emphasis undoes it afterwards, so the noise the medium added along the way
/// gets pulled down with it. Material that was pre-emphasised and never
/// de-emphasised sounds bright and harsh; this is the other half of that pair.
///
/// The shape is not a preference — it is a fixed −6 dB/octave shelf whose corner
/// is 1/(2π·τ), so the two time constants ARE the two curves and there is
/// nothing else to tune.
Float64List deEmphasisFx(
  Float64List input, {
  required double sampleRate,
  double microseconds = 50,
  double mix = 1,
}) {
  final out = Float64List(input.length);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0 || input.isEmpty) {
    out.setAll(0, input);
    return out;
  }
  final tau = microseconds.clamp(10.0, 200.0) * 1e-6;
  final corner = 1 / (2 * math.pi * tau);
  final sr = sampleRate <= 0 ? 44100.0 : sampleRate;
  final coefficient =
      math.exp(-2 * math.pi * corner.clamp(20, sr / 2 - 1) / sr);
  final k = 1 - coefficient;
  var state = 0.0;
  for (var i = 0; i < input.length; i++) {
    state = k * input[i] + coefficient * state;
    out[i] = (1 - m) * input[i] + m * state;
  }
  return out;
}

/// Presence — make a signal cut through without making it louder.
///
/// A gentle odd-symmetric waveshaping: the transfer curve is bent so that
/// mid-level material is pushed up slightly while the peaks stay where they are.
/// That adds low-order harmonics, and low-order harmonics of a note read as
/// "more of that note" rather than as distortion, so the part sits forward in a
/// mix at the same meter reading.
///
/// [amount] 0 is a no-op and 1 is as far as this should ever be pushed — past a
/// point the harmonics stop reading as presence and start reading as fuzz, which
/// is what the [distortion] effect is for and is a different intent.
Float64List contrastFx(
  Float64List input, {
  double amount = 0.5,
  double mix = 1,
}) {
  final out = Float64List(input.length);
  final m = mix.clamp(0.0, 1.0);
  final a = amount.clamp(0.0, 1.0);
  if (m == 0 || input.isEmpty || a == 0) {
    out.setAll(0, input);
    return out;
  }
  for (var i = 0; i < input.length; i++) {
    final x = input[i].clamp(-1.0, 1.0);
    // sin(π/2 · x) is the identity at ±1 and above it in between, so the peaks
    // are untouched and everything below them comes up. Blended by `a` so the
    // control sweeps from flat to fully bent.
    final bent = math.sin(x * math.pi / 2);
    final wet = x + (bent - x) * a;
    out[i] = (1 - m) * input[i] + m * wet;
  }
  return out;
}
