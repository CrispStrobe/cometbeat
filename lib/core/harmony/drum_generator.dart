// lib/core/harmony/drum_generator.dart
//
// BB-A4 — a kit that plays the feel, marks the form, and fills into it.
//
// The groove itself is DATA (a `RolePattern` from the style); what lives here is
// everything the data cannot say: where a fill goes, how a count-in is spelled,
// what the last bar does, and how a bar is cut to fit a meter the pattern was
// not written for.
//
// ⚠️ THREE RENDERER CONSTRAINTS, verified, that shape this file. Do not
// rediscover them — they are recorded here and in CLAUDE.md.
//
//   (a) `enum Drum` (core/audio/synth.dart) is an ORDER-LOCKED ordinal palette:
//       `interop/drum_tracker.dart` uses the ordinal AS a MIDI note. New voices
//       must be APPENDED. Nothing here invents a voice index; it only uses
//       0..11, and a style supplies which.
//   (b) The SFZ loader parses no `group`/`off_by`, so THERE IS NO HI-HAT CHOKE
//       — an open hat is not cut off by the closed hat after it. So an open hat
//       is placed only where it can ring (the end of a bar or a fill), never
//       mid-bar where a real kit would choke it.
//   (c) `midi_render.dart` SUMS every zone covering a key+velocity, so two hits
//       on the same voice at the same instant render N× louder and comb-
//       filtered rather than once. `_dedupe` guarantees one hit per (voice,
//       beat) — a style CAN legitimately double a voice (the swing ride and hat
//       both land on 1) but never the same voice twice.
library;

import 'package:comet_beat/core/harmony/style_spec.dart';

/// Ordinals of `Drum` in `core/audio/synth.dart`. Named so a reader does not
/// have to count, and so a future append is a one-line change here.
const int kDrumKick = 0;
const int kDrumSnare = 1;
const int kDrumHat = 2;
const int kDrumOpenHat = 3;
const int kDrumTom = 5;
const int kDrumCrash = 8;
const int kDrumLowTom = 10;
const int kDrumHighTom = 11;

/// One kit hit.
class DrumHit {
  const DrumHit({
    required this.beat,
    required this.voice,
    this.velocity = 0.8,
  });

  /// Quarter-note beats from the start of the bar.
  final double beat;

  /// A `Drum` ordinal.
  final int voice;
  final double velocity;

  @override
  String toString() => 'DrumHit($beat, v$voice)';
}

/// Where a bar sits in the form, which is all the generator needs to know to
/// decide whether to play the groove or a fill.
class DrumContext {
  const DrumContext({
    required this.barIndex,
    required this.beats,
    this.isPhraseEnd = false,
    this.isSectionEnd = false,
    this.isLastBar = false,
    this.intensity = 1,
  });

  /// Index in the realised timeline.
  final int barIndex;

  /// Quarter-note beats in this bar.
  final double beats;

  /// The last bar of a 4- or 8-bar phrase.
  final bool isPhraseEnd;

  /// The last bar before a new section.
  final bool isSectionEnd;

  /// The last bar of the whole piece.
  final bool isLastBar;

  final int intensity;
}

/// One bar of kit.
///
/// [pattern] is the style's groove for this intensity; null means the style has
/// no drums at this level, which is a legitimate arrangement choice (level 0 of
/// several styles) rather than a gap to fill in.
List<DrumHit> generateDrumBar({
  required RolePattern? pattern,
  required DrumContext context,
  int seed = 0,
}) {
  if (context.beats <= 0) return const [];

  // The ending is a statement, not a groove: a crash on the downbeat and let it
  // ring. A groove that simply stops sounds like a dropped connection.
  if (context.isLastBar) {
    return [
      const DrumHit(beat: 0, voice: kDrumCrash, velocity: 0.9),
      const DrumHit(beat: 0, voice: kDrumKick, velocity: 0.9),
    ];
  }

  if (pattern == null || pattern.hits.isEmpty) return const [];

  final groove = _truncate(pattern.hits, context.beats);

  if (context.isPhraseEnd || context.isSectionEnd) {
    return _dedupe(_withFill(groove, context, seed));
  }
  return _dedupe(groove);
}

/// A count-in: one bar of the pulse, so a player knows the tempo before bar 1.
List<DrumHit> countInBar(double beats, {int voice = kDrumHat}) => [
      for (var i = 0; i < beats.floor(); i++)
        DrumHit(
          beat: i.toDouble(),
          voice: voice,
          // The downbeat is accented, or a count-in does not tell you where 1 is.
          velocity: i == 0 ? 0.9 : 0.55,
        ),
    ];

/// The groove with a fill in its second half.
///
/// The first half keeps the groove so the bar still belongs to the phrase; the
/// fill takes over from the midpoint, which is what a drummer actually does at
/// a 2-bar-to-go turnaround. A whole bar of fill is a solo, not a fill.
List<DrumHit> _withFill(List<DrumHit> groove, DrumContext context, int seed) {
  final beats = context.beats;
  final from = beats / 2;
  final kept = [
    for (final hit in groove)
      if (hit.beat < from) hit,
  ];

  // Four shapes, chosen deterministically so a shared chart reproduces exactly
  // while a repeated 8-bar phrase does not fill identically every time.
  //
  // ⚠️ NOT `(seed + barIndex) % 4`, which is what this was and which is
  // DEGENERATE here: fills land on phrase ends, phrases are 4 or 8 bars, so the
  // bar index at every fill is congruent mod 4 and the "varying" shape is
  // always the same one. Caught by the test asserting bars 7/15/23/31 differ —
  // they were all shape 3. A mixing hash has no such resonance with the phrase
  // length.
  final shape = _shapeIndex(seed, context.barIndex) % 4;
  final toms = switch (shape) {
    0 => [kDrumSnare, kDrumSnare, kDrumHighTom, kDrumLowTom],
    1 => [kDrumSnare, kDrumHighTom, kDrumTom, kDrumLowTom],
    2 => [kDrumHighTom, kDrumHighTom, kDrumTom, kDrumTom],
    _ => [kDrumSnare, kDrumTom, kDrumSnare, kDrumLowTom],
  };

  // Eighth notes across the second half of the bar.
  final steps = ((beats - from) / 0.5).floor().clamp(1, 8);
  final fill = <DrumHit>[
    for (var i = 0; i < steps; i++)
      DrumHit(
        beat: from + i * 0.5,
        voice: toms[i % toms.length],
        // A fill rises into the downbeat that follows it.
        velocity: (0.6 + 0.05 * i).clamp(0.0, 1.0),
      ),
  ];

  // A section boundary gets an open hat to mark it — placed on the LAST eighth
  // so nothing follows that a real kit would choke (constraint (b)).
  if (context.isSectionEnd && beats >= 2) {
    fill.add(
      DrumHit(beat: beats - 0.5, voice: kDrumOpenHat, velocity: 0.6),
    );
  }
  return [...kept, ...fill];
}

/// A deterministic mix of seed and bar with no common factor with the phrase
/// length — see the warning at its call site. Knuth's multiplicative constant,
/// folded so the low bits carry the high ones.
int _shapeIndex(int seed, int barIndex) {
  var h = (seed * 2654435761 + barIndex * 40503) & 0x7fffffff;
  h ^= h >> 13;
  h = (h * 1274126177) & 0x7fffffff;
  return h ^ (h >> 16);
}

/// Drops anything that would not fit a [beats]-long bar.
///
/// A style pattern is written for its longest meter (see `style_spec.dart`) and
/// truncated here, which is why a 4/4 pattern can serve a 3/4 chart at all.
List<DrumHit> _truncate(List<StyleHit> hits, double beats) => [
      for (final hit in hits)
        if (hit.beat < beats)
          DrumHit(beat: hit.beat, voice: hit.voice, velocity: hit.velocity),
    ];

/// One hit per (voice, beat).
///
/// Constraint (c): the renderer SUMS overlapping zones, so the same voice twice
/// at the same instant is not louder-by-design, it is a comb filter. Different
/// voices at the same instant are fine and musically normal (the swing ride and
/// hat both land on beat 1), so the key is the pair, not the beat.
List<DrumHit> _dedupe(List<DrumHit> hits) {
  final seen = <String>{};
  final out = <DrumHit>[];
  for (final hit in hits) {
    // Beats are authored at eighth/triplet resolution; rounding to 1e-4 keeps
    // 1.6666 and 1.6667 from counting as two hits.
    final key = '${hit.voice}@${(hit.beat * 10000).round()}';
    if (seen.add(key)) out.add(hit);
  }
  out.sort((a, b) => a.beat.compareTo(b.beat));
  return out;
}
