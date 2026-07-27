// lib/core/audio/daw_edits.dart
//
// The Multitrack editor's DESTRUCTIVE edits, as pure functions — the "bake"
// operations (normalize · amplify · invert · remove-DC · trim-silence), clip
// statistics, the signal generator, and the range surgery (crop / silence).
//
// These live here rather than in DawService so the same code runs three ways:
// in the app (the service is a thin undo/notify wrapper), in headless unit
// tests, and from `bin/dawedit.dart` on a real WAV. Flutter-free and
// deterministic — no clocks, no randomness that isn't seeded.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/sample_edit.dart'
    show peakMagnitude, removeDcOffset, trimPcm;
import 'package:comet_beat/core/audio/daw_timeline.dart' show Clip;

/// What a destructive edit produced: the new channel data (right is null for a
/// mono clip) plus how far the take's start moved. `startShiftMs > 0` means
/// audio was cut off the FRONT, so the caller slides the clip that much later
/// and the surviving audio keeps its place in the arrangement.
typedef BakedTake = ({
  Float64List left,
  Float64List? right,
  double startShiftMs,
});

/// A take that stays where it is — the common case.
BakedTake bakedTake(Float64List left, [Float64List? right]) =>
    (left: left, right: right, startShiftMs: 0);

/// A new buffer with every sample of [pcm] scaled by [g].
Float64List scalePcm(Float64List pcm, double g) {
  final out = Float64List(pcm.length);
  for (var i = 0; i < pcm.length; i++) {
    out[i] = pcm[i] * g;
  }
  return out;
}

/// **Normalize** to [targetPeak] of full scale. The gain comes from the loudest
/// sample across BOTH channels, so the stereo image is preserved rather than
/// each side being scaled independently. Silence is returned unchanged.
BakedTake normalizeTake(
  Float64List left,
  Float64List? right, {
  double targetPeak = 0.98,
}) {
  final peak = math.max(
    peakMagnitude(left),
    right == null ? 0.0 : peakMagnitude(right),
  );
  if (peak == 0) return bakedTake(left, right);
  final g = targetPeak / peak;
  return bakedTake(
    scalePcm(left, g),
    right == null ? null : scalePcm(right, g),
  );
}

/// **Amplify** by [db]. Not clamped — a later limiter still catches an
/// over-loud result, and the honest number is more useful than a silent clamp.
BakedTake amplifyTake(Float64List left, Float64List? right, double db) {
  final g = math.pow(10, db / 20).toDouble();
  return bakedTake(
    scalePcm(left, g),
    right == null ? null : scalePcm(right, g),
  );
}

/// **Invert phase** (× −1). Inaudible alone; flips cancellation when layered.
BakedTake invertTake(Float64List left, Float64List? right) =>
    bakedTake(scalePcm(left, -1), right == null ? null : scalePcm(right, -1));

/// **Remove the DC offset** — centre each channel on zero.
BakedTake removeDcTake(Float64List left, Float64List? right) => bakedTake(
      removeDcOffset(left),
      right == null ? null : removeDcOffset(right),
    );

/// **Trim silence** from both edges: everything quieter than [threshold]
/// (fraction of full scale) before the first and after the last audible sample
/// goes. A stereo take is judged on BOTH channels at once so they stay
/// sample-aligned. The returned [BakedTake.startShiftMs] is exactly the leading
/// silence, so the surviving audio can keep its place. An all-silent take
/// yields an empty left — callers treat that as "leave the clip alone".
BakedTake trimSilenceTake(
  Float64List left,
  Float64List? right, {
  double threshold = 0.01,
  required int sampleRate,
}) {
  final n = left.length;
  bool audible(int i) =>
      left[i].abs() >= threshold ||
      (right != null && i < right.length && right[i].abs() >= threshold);
  var lo = 0;
  while (lo < n && !audible(lo)) {
    lo++;
  }
  if (lo == n) return bakedTake(Float64List(0));
  var hi = n;
  while (hi > lo && !audible(hi - 1)) {
    hi--;
  }
  if (lo == 0 && hi == n) return bakedTake(left, right);
  return (
    left: trimPcm(left, lo, hi),
    right: right == null ? null : trimPcm(right, lo, hi),
    startShiftMs: lo * 1000 / sampleRate,
  );
}

/// What the inspector shows about a clip's audio.
typedef ClipStats = ({
  double peak, // linear, 0..1+
  double peakDb, // dBFS ([silenceDb] when silent)
  double rms, // linear
  double rmsDb, // dBFS
  double durationMs,
  int clippedSamples, // |sample| >= 1.0, across all channels
  int channels,
});

/// The dBFS reported for digital silence — a floor, since log(0) is −infinity.
const double silenceDb = -160;

/// Amplitude (0..1) as dBFS, floored at [silenceDb].
double amplitudeToDb(double amplitude) => amplitude <= 0
    ? silenceDb
    : math.max(silenceDb, 20 * math.log(amplitude) / math.ln10);

/// Peak / RMS / duration / clipped-sample count over a clip's window. RMS is
/// taken across all channels together (one number for the clip, not per side).
ClipStats clipStatsOf(
  Float64List left,
  Float64List? right, {
  required int sampleRate,
}) {
  var peak = 0.0;
  var sumSquares = 0.0;
  var clipped = 0;
  var count = 0;
  void scan(Float64List pcm) {
    for (final v in pcm) {
      final a = v.abs();
      if (a > peak) peak = a;
      if (a >= 1.0) clipped++;
      sumSquares += v * v;
      count++;
    }
  }

  scan(left);
  if (right != null) scan(right);
  final rms = count == 0 ? 0.0 : math.sqrt(sumSquares / count);
  return (
    peak: peak,
    peakDb: amplitudeToDb(peak),
    rms: rms,
    rmsDb: amplitudeToDb(rms),
    durationMs: left.length * 1000 / sampleRate,
    clippedSamples: clipped,
    channels: right == null ? 1 : 2,
  );
}

/// The shapes [generateWave] can synthesize.
enum GeneratorShape {
  sine,
  square,
  saw,
  triangle,
  whiteNoise,
  pinkNoise,
  silence
}

/// A steady (un-enveloped) test / building-block signal: [samples] long at
/// [sampleRate], peaking at [amp] (exactly, for the noises — they're scaled by
/// the peak they actually produced). Tones use [freq]; the noises are seeded by
/// [seed] so a generated clip is reproducible. Deliberately raw — the caller
/// gives the clip a short fade so the hard edges don't click.
///
/// (The pink filter is the standard Paul Kellet one, as in `sfxr.dart`; that
/// copy stays private to its envelope path.)
Float64List generateWave({
  required GeneratorShape shape,
  required int samples,
  required int sampleRate,
  double freq = 440,
  double amp = 0.5,
  int seed = 0,
}) {
  final out = Float64List(samples <= 0 ? 0 : samples);
  if (out.isEmpty || shape == GeneratorShape.silence) return out;

  if (shape == GeneratorShape.whiteNoise || shape == GeneratorShape.pinkNoise) {
    final r = math.Random(seed);
    var b0 = 0.0, b1 = 0.0, b2 = 0.0;
    for (var i = 0; i < samples; i++) {
      final white = r.nextDouble() * 2 - 1;
      if (shape == GeneratorShape.whiteNoise) {
        out[i] = white;
      } else {
        b0 = 0.99886 * b0 + white * 0.0555179;
        b1 = 0.99332 * b1 + white * 0.0750759;
        b2 = 0.96900 * b2 + white * 0.1538520;
        out[i] = b0 + b1 + b2 + white * 0.3104856;
      }
    }
    // Noise has no fixed bound (the pink filter's sum in particular overshoots
    // ~3x white by a varying margin), so scale by the peak actually produced
    // rather than a nominal constant — otherwise a loud generated clip clips.
    final peak = peakMagnitude(out);
    if (peak == 0) return out;
    final g = amp / peak;
    for (var i = 0; i < samples; i++) {
      out[i] *= g;
    }
    return out;
  }

  if (freq <= 0) return out;
  final inc = freq / sampleRate; // cycles per sample
  var phase = 0.0; // 0..1
  for (var i = 0; i < samples; i++) {
    out[i] = amp *
        switch (shape) {
          GeneratorShape.sine => math.sin(2 * math.pi * phase),
          GeneratorShape.square => phase < 0.5 ? 1.0 : -1.0,
          GeneratorShape.saw => 2 * phase - 1,
          GeneratorShape.triangle =>
            phase < 0.5 ? 4 * phase - 1 : 3 - 4 * phase,
          _ => 0.0,
        };
    phase += inc;
    if (phase >= 1.0) phase -= 1.0;
  }
  return out;
}

/// Split [clips] at both ends of the range, then drop the segments on one side:
/// `removeInside: true` cuts the marked range OUT (leaving a hole, with nothing
/// rippling left), `false` CROPS to it (keeping only what plays inside).
///
/// [durationOf] gives a clip's played length — the caller owns the render cache
/// that answer needs. A sliver shorter than [minSplitMs] from a bound can't be
/// split, so it's decided by its midpoint and lands on whichever side it mostly
/// belongs to; [minSplitMs] has no default because the caller's split policy has
/// to match the one it uses elsewhere. Mutates [clips] in place; returns how
/// many were removed.
int editClipsAroundRange(
  List<Clip> clips,
  double rangeStart,
  double rangeEnd, {
  required bool removeInside,
  required double Function(Clip clip) durationOf,
  required double minSplitMs,
}) {
  bool canSplit(Clip clip, double atMs) {
    final offset = atMs - clip.startMs;
    return offset > minSplitMs && offset < durationOf(clip) - minSplitMs;
  }

  void splitAt(int index, double atMs) {
    final clip = clips[index];
    final offset = atMs - clip.startMs; // ms into the played window
    final cut = clip.trimStartMs + offset; // the split point in source ms
    clips[index] = clip.copyWith(trimEndMs: cut, fadeOutMs: 0);
    clips.insert(
      index + 1,
      clip.copyWith(
        startMs: clip.startMs + offset,
        trimStartMs: cut,
        fadeInMs: 0,
      ),
    );
  }

  var index = 0;
  while (index < clips.length) {
    final clip = clips[index];
    final duration = durationOf(clip);
    if (clip.startMs + duration <= rangeStart || clip.startMs >= rangeEnd) {
      index++;
      continue;
    }
    if (canSplit(clip, rangeStart)) {
      splitAt(index, rangeStart);
      index++;
      continue;
    }
    if (canSplit(clip, rangeEnd)) splitAt(index, rangeEnd);
    index++;
  }

  var removed = 0;
  for (var i = clips.length - 1; i >= 0; i--) {
    final mid = clips[i].startMs + durationOf(clips[i]) / 2;
    final inside = mid > rangeStart && mid < rangeEnd;
    if (inside == removeInside) {
      clips.removeAt(i);
      removed++;
    }
  }
  return removed;
}

// ---------------------------------------------------------------------------
// B1/B3 — the editor operations that are not same-length transforms.
//
// An FX chain maps N samples to N samples, which is why the rack can be a list
// of modules. These change the LENGTH or the structure — insert silence, repeat
// a take, find where the gaps are, join two takes — so they cannot be effects
// and live here beside the other destructive edits, as pure functions the
// service, the CLI and the tests all call.
// ---------------------------------------------------------------------------

/// Insert [leadMs] of silence before the audio and [tailMs] after it.
///
/// The "give it room" op: a take that starts on its first sample has nowhere for
/// a fade-in to live, and one that ends on its last has nowhere for a reverb
/// tail to ring out. Negative values are treated as zero — trimming is
/// [trimSilenceTake]'s job, and quietly reinterpreting a pad as a cut would be a
/// surprising way to lose audio.
BakedTake padTake(
  Float64List left,
  Float64List? right, {
  double leadMs = 0,
  double tailMs = 0,
  required int sampleRate,
}) {
  final lead = (math.max(0, leadMs) * sampleRate / 1000).round();
  final tail = (math.max(0, tailMs) * sampleRate / 1000).round();
  if (lead == 0 && tail == 0) return bakedTake(left, right);

  Float64List pad(Float64List source) {
    final out = Float64List(lead + source.length + tail);
    out.setRange(lead, lead + source.length, source);
    return out;
  }

  // The audio itself moves later by exactly the lead, so a caller placing this
  // on a timeline can slide the clip back and keep it where it sounded.
  return (
    left: pad(left),
    right: right == null ? null : pad(right),
    startShiftMs: -lead * 1000 / sampleRate,
  );
}

/// Repeat the take [times] in total (1 = unchanged, 0 = empty).
BakedTake repeatTake(Float64List left, Float64List? right, int times) {
  final n = times < 0 ? 0 : times;
  if (n == 1) return bakedTake(left, right);

  Float64List repeat(Float64List source) {
    final out = Float64List(source.length * n);
    for (var i = 0; i < n; i++) {
      out.setRange(i * source.length, (i + 1) * source.length, source);
    }
    return out;
  }

  return bakedTake(repeat(left), right == null ? null : repeat(right));
}

/// A silent stretch found by [findSilences].
typedef SilentRange = ({double startMs, double endMs});

/// Every stretch quieter than [threshold] for at least [minLengthMs].
///
/// Unlike [trimSilenceTake], which only looks at the two ENDS, this finds gaps
/// anywhere — which is what makes "split this take into its phrases" possible,
/// and what makes a long recording navigable at all.
///
/// [minLengthMs] is what keeps it useful: without it every zero crossing of a
/// quiet passage is a "silence", and the answer is thousands of ranges that mean
/// nothing. A gap has to last before it counts as one.
List<SilentRange> findSilences(
  Float64List left,
  Float64List? right, {
  double threshold = 0.01,
  double minLengthMs = 200,
  required int sampleRate,
}) {
  final out = <SilentRange>[];
  if (left.isEmpty) return out;
  final minSamples = (minLengthMs * sampleRate / 1000).round();
  bool quiet(int i) =>
      left[i].abs() < threshold &&
      (right == null || i >= right.length || right[i].abs() < threshold);

  var start = -1;
  for (var i = 0; i <= left.length; i++) {
    final isQuiet = i < left.length && quiet(i);
    if (isQuiet) {
      if (start < 0) start = i;
    } else if (start >= 0) {
      if (i - start >= minSamples) {
        out.add(
          (
            startMs: start * 1000 / sampleRate,
            endMs: i * 1000 / sampleRate,
          ),
        );
      }
      start = -1;
    }
  }
  return out;
}

/// The audible stretches BETWEEN the silences — one entry per phrase.
///
/// The complement of [findSilences], returned separately because it is what a
/// caller actually places on a timeline: a long take becomes one clip per
/// phrase, each keeping the position it was recorded at.
List<SilentRange> findPhrases(
  Float64List left,
  Float64List? right, {
  double threshold = 0.01,
  double minLengthMs = 200,
  required int sampleRate,
}) {
  final total = left.length * 1000 / sampleRate;
  final silences = findSilences(
    left,
    right,
    threshold: threshold,
    minLengthMs: minLengthMs,
    sampleRate: sampleRate,
  );
  final out = <SilentRange>[];
  var cursor = 0.0;
  for (final gap in silences) {
    if (gap.startMs > cursor) {
      out.add((startMs: cursor, endMs: gap.startMs));
    }
    cursor = gap.endMs;
  }
  if (cursor < total) out.add((startMs: cursor, endMs: total));
  return out;
}

/// Which crossfade shape [spliceTakes] uses at the join.
///
/// There is no universally right answer, which is why both exist — the choice
/// depends on whether the two takes are CORRELATED:
///
/// * [equalPower] (sin/cos) keeps the total POWER constant, which is what holds
///   the level when the takes are unrelated — two different performances, a
///   join between different material. This is the usual case for a splice and
///   the default. On perfectly correlated takes (two copies of the same audio)
///   it reads about +3 dB at the join, because the amplitudes add rather than
///   the powers.
/// * [linear] keeps the total AMPLITUDE constant, which is right for exactly
///   that correlated case — joining the same performance to itself, or two
///   takes that track each other closely.
enum SpliceCurve { equalPower, linear }

/// Join two takes with a crossfade of [crossfadeMs], shaped by [curve].
///
/// See [SpliceCurve] for which shape to want; the default suits joining two
/// different takes, which is what a splice usually is.
BakedTake spliceTakes(
  Float64List firstLeft,
  Float64List? firstRight,
  Float64List secondLeft,
  Float64List? secondRight, {
  double crossfadeMs = 20,
  SpliceCurve curve = SpliceCurve.equalPower,
  required int sampleRate,
}) {
  final fade = math.min(
    (math.max(0, crossfadeMs) * sampleRate / 1000).round(),
    math.min(firstLeft.length, secondLeft.length),
  );
  final length = firstLeft.length + secondLeft.length - fade;

  Float64List join(Float64List a, Float64List b) {
    final out = Float64List(length);
    for (var i = 0; i < a.length; i++) {
      out[i] = a[i];
    }
    final start = a.length - fade;
    for (var i = 0; i < b.length; i++) {
      final at = start + i;
      if (at >= out.length) break;
      if (i < fade) {
        final t = (i + 0.5) / fade;
        final (outGoing, inComing) = switch (curve) {
          SpliceCurve.equalPower => (
              math.cos(t * math.pi / 2),
              math.sin(t * math.pi / 2),
            ),
          SpliceCurve.linear => (1 - t, t),
        };
        out[at] = out[at] * outGoing + b[i] * inComing;
      } else {
        out[at] = b[i];
      }
    }
    return out;
  }

  final stereo = firstRight != null || secondRight != null;
  return bakedTake(
    join(firstLeft, secondLeft),
    stereo ? join(firstRight ?? firstLeft, secondRight ?? secondLeft) : null,
  );
}

/// The full measurement set — what a mastering engineer asks of a file.
typedef FullStats = ({
  ClipStats basic,
  double dcOffset, // mean sample value; anything but ~0 is a defect
  double crestFactorDb, // peak-to-RMS: how much transient is left
  int effectiveBits, // the resolution actually in use
  int zeroCrossings, // a rough brightness/noisiness proxy
});

/// Peak/RMS/duration (via [clipStatsOf]) plus the measurements that say whether
/// a file is HEALTHY rather than how loud it is.
///
/// * **DC offset** — a non-zero mean is always a defect: it eats headroom and
///   makes edits click, and it is invisible on a level meter.
/// * **Crest factor** — peak over RMS. High means the transients survive; a
///   crest factor collapsing toward 0 dB is the signature of over-compression,
///   which no loudness number will tell you.
/// * **Effective bit depth** — the resolution actually in use. A 24-bit file
///   whose samples all land on 16-bit boundaries was converted, not recorded,
///   and knowing that changes what you do with it.
FullStats fullStatsOf(
  Float64List left,
  Float64List? right, {
  required int sampleRate,
}) {
  final basic = clipStatsOf(left, right, sampleRate: sampleRate);

  var sum = 0.0;
  var count = 0;
  var crossings = 0;
  var previous = 0.0;
  void scan(Float64List pcm, {required bool countCrossings}) {
    for (var i = 0; i < pcm.length; i++) {
      sum += pcm[i];
      count++;
      if (countCrossings && i > 0 && (pcm[i] >= 0) != (previous >= 0)) {
        crossings++;
      }
      previous = pcm[i];
    }
  }

  scan(left, countCrossings: true);
  if (right != null) scan(right, countCrossings: false);

  // The smallest quantisation step every sample is a multiple of. Tested
  // against the common depths rather than solved for, because that is the
  // question being asked: WHICH depth is this, not what is the GCD.
  var effectiveBits = 32;
  for (final bits in [8, 12, 16, 20, 24]) {
    final step = 2.0 / (1 << bits);
    var fits = true;
    for (final pcm in [left, if (right != null) right]) {
      for (final v in pcm) {
        final steps = v / step;
        if ((steps - steps.roundToDouble()).abs() > 1e-6) {
          fits = false;
          break;
        }
      }
      if (!fits) break;
    }
    if (fits) {
      effectiveBits = bits;
      break;
    }
  }

  return (
    basic: basic,
    dcOffset: count == 0 ? 0.0 : sum / count,
    crestFactorDb: basic.rms <= 0
        ? 0.0
        : amplitudeToDb(basic.peak) - amplitudeToDb(basic.rms),
    effectiveBits: effectiveBits,
    zeroCrossings: crossings,
  );
}
