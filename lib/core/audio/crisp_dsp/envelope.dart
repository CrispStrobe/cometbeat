// lib/core/audio/crisp_dsp/envelope.dart
//
// A per-note ADSR volume envelope for the Tracker's sampled instruments (recorded
// voice, borrowed module samples). A raw sample played per note otherwise starts
// and stops abruptly — a click; an envelope ramps it in and fades it out, and can
// shape the note (soft attack, decay to a sustain level). Pure Dart, deterministic.
// From OpenMPT/IT instrument envelopes (the idea), simplified. See FX_HANDOVER.md #4.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;

/// An attack/decay/sustain/release gain shape over a note's buffer. [attack],
/// [decay], [release] are in SECONDS; [sustain] is the 0..1 hold level.
class Envelope {
  const Envelope({
    this.attack = 0.004,
    this.decay = 0.0,
    this.sustain = 1.0,
    this.release = 0.012,
    this.pitchStart = 0.0,
    this.pitchTime = 0.04,
  });

  /// No shaping — a flat gain of 1 (identity).
  static const none = Envelope(attack: 0, release: 0);

  /// A gentle attack+release just long enough to declick a sampled note — the
  /// class defaults.
  static const declick = Envelope();

  final double attack, decay, sustain, release;

  /// A pitch envelope for sampled instruments: the note starts [pitchStart]
  /// semitones off (a scoop/fall — positive = starts sharp then falls, negative
  /// = starts flat then rises) and glides to true pitch over [pitchTime] seconds.
  /// 0 = no pitch glide. Handled by the instrument's resampler, not [applyEnvelope].
  final double pitchStart, pitchTime;

  /// True when the VOLUME envelope is flat (a gain of 1); [applyEnvelope] skips it.
  bool get isIdentity =>
      attack <= 0 && decay <= 0 && release <= 0 && sustain >= 1;
}

/// Applies [env] as a per-sample gain over [buf], returning a new buffer (same
/// length). The attack ramps 0→1, decay 1→sustain, then a sustain hold, then the
/// release fades sustain→0 over the tail. If attack+decay+release exceeds the
/// buffer, the three stages are scaled down proportionally to fit.
Float64List applyEnvelope(
  Float64List buf,
  Envelope env, {
  int sampleRate = kSampleRate,
  int? sustainSamples,
}) {
  final n = buf.length;
  if (n == 0 || env.isIdentity) return Float64List.fromList(buf);

  final sustain = env.sustain.clamp(0.0, 1.0);
  var a = (env.attack * sampleRate).round().clamp(0, n);
  var d = (env.decay * sampleRate).round().clamp(0, n);
  var r = (env.release * sampleRate).round();

  int relStart;
  if (sustainSamples != null) {
    // Synthesizer behavior: sustain until Note Cut
    relStart = sustainSamples.clamp(0, n);
    if (a + d > relStart) {
      final scale = relStart > 0 ? relStart / (a + d) : 0.0;
      a = (a * scale).floor();
      d = (d * scale).floor();
    }
  } else {
    // Legacy / One-shot behavior: fit release at the end of the buffer
    r = r.clamp(0, n);
    final total = a + d + r;
    if (total > n && total > 0) {
      final scale = n / total;
      a = (a * scale).floor();
      d = (d * scale).floor();
      r = (r * scale).floor();
    }
    relStart = n - r;
  }

  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    double g;
    if (i < a) {
      g = a > 0 ? i / a : 1.0;
    } else if (i < a + d) {
      g = 1 - (1 - sustain) * ((i - a) / d);
    } else if (i < relStart) {
      g = sustain;
    } else {
      g = r > 0 ? sustain * max(0.0, 1.0 - (i - relStart) / r) : 0.0;
    }
    out[i] = buf[i] * g;
  }
  return out;
}
