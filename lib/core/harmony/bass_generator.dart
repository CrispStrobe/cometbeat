// lib/core/harmony/bass_generator.dart
//
// BB-A3 — a bass line that walks INTO the next chord instead of restating this
// one.
//
// That sentence is the whole design. A bass part that plays the root of each
// chord is not a bass line, it is a chord chart read aloud; what makes a line
// sound like a player is that the last note of the bar is chosen for where it
// is GOING, not for where it is. So every mode here is given the next chord as
// well as this one, and the final beat is an approach note.
//
// Deterministic from a seed, like everything else in this arc: a shared chart
// must sound the same on two devices, and a golden test is worthless otherwise.
library;

import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:comet_beat/core/harmony/style_spec.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart' show Pitch;

/// One bass note.
class BassNote {
  const BassNote({
    required this.beat,
    required this.midi,
    required this.duration,
    this.velocity = 0.8,
  });

  /// Quarter-note beats from the start of the bar.
  final double beat;
  final int midi;

  /// In quarter-note beats.
  final double duration;
  final double velocity;

  @override
  String toString() => 'BassNote($beat, $midi, $duration)';
}

/// Where the bass may play. A real instrument's range, so a line cannot walk
/// off the bottom of the neck.
class BassRange {
  const BassRange({this.low = 28, this.high = 55});

  /// E1 on a 4-string bass.
  final int low;

  /// Roughly G3 — above that a bass line stops sounding like one.
  final int high;

  int clamp(int midi) {
    var m = midi;
    while (m < low) {
      m += 12;
    }
    while (m > high) {
      m -= 12;
    }
    return m;
  }

  bool contains(int midi) => midi >= low && midi <= high;
}

/// Generates one bar of bass.
///
/// [next] is the chord the bar is walking INTO — null only for the last bar of
/// the whole piece, where there is nothing to approach.
///
/// [previousMidi] keeps register continuity across the barline: without it a
/// line jumps an octave whenever the root does, which no player would do.
List<BassNote> generateBassBar({
  required ChordSpec chord,
  required ChordSpec? next,
  required double beats,
  required BassMode mode,
  BassRange range = const BassRange(),
  int? previousMidi,
  int seed = 0,
  int barIndex = 0,
}) {
  if (beats <= 0) return const [];

  final rootPc = _pc(chord.bass ?? chord.root);
  final root = _nearest(rootPc, previousMidi ?? 40, range);

  switch (mode) {
    case BassMode.pedal:
      return [BassNote(beat: 0, midi: root, duration: beats)];

    case BassMode.root:
      return [BassNote(beat: 0, midi: root, duration: beats)];

    case BassMode.rootFive:
      if (beats < 2) return [BassNote(beat: 0, midi: root, duration: beats)];
      final fifth = range.clamp(root + 7);
      final half = beats / 2;
      return [
        BassNote(beat: 0, midi: root, duration: half),
        BassNote(beat: half, midi: fifth, duration: beats - half),
      ];

    case BassMode.twoFeel:
      if (beats < 2) return [BassNote(beat: 0, midi: root, duration: beats)];
      final half = beats / 2;
      // The second half note approaches the next chord rather than sitting on
      // the fifth — that is the difference between two-feel and root-five.
      final second = next == null
          ? range.clamp(root + 7)
          : _approach(root, _pc(next.bass ?? next.root), range, chord, seed);
      return [
        BassNote(beat: 0, midi: root, duration: half),
        BassNote(beat: half, midi: second, duration: beats - half),
      ];

    case BassMode.walking:
      return _walk(
        chord: chord,
        next: next,
        beats: beats,
        root: root,
        range: range,
        seed: seed,
        barIndex: barIndex,
      );

    case BassMode.arpeggiated:
      return _arpeggio(chord, root, beats, range, ascending: true);

    case BassMode.alberti:
      return _arpeggio(chord, root, beats, range, ascending: false);

    case BassMode.tumbao:
      // The son figure: the "and" of 2 and the 4, with the root anticipated.
      if (beats < 4) return [BassNote(beat: 0, midi: root, duration: beats)];
      final fifth = range.clamp(root + 7);
      return [
        BassNote(beat: 0, midi: root, duration: 1.5, velocity: 0.85),
        BassNote(beat: 1.5, midi: fifth, duration: 1, velocity: 0.7),
        BassNote(beat: 3, midi: root, duration: beats - 3),
      ];
  }
}

/// Quarter notes that arrive on the next root by step or by fifth.
///
/// Chord tones on the strong beats, an approach on the last — the standard
/// skeleton. Weak beats are filled from the chord's own tones and, where a gap
/// needs it, a passing tone, so eight bars of one chord are not eight identical
/// bars.
List<BassNote> _walk({
  required ChordSpec chord,
  required ChordSpec? next,
  required double beats,
  required int root,
  required BassRange range,
  required int seed,
  required int barIndex,
}) {
  final count = beats.floor().clamp(1, 8);
  if (count == 1) return [BassNote(beat: 0, midi: root, duration: beats)];

  final tones = _chordTones(chord, root, range);
  final out = <BassNote>[BassNote(beat: 0, midi: root, duration: 1)];

  // A per-bar rotation so a repeated chord does not repeat its line verbatim.
  // Seeded, so the same chart replays identically.
  final rotation = (seed + barIndex * 7) % (tones.isEmpty ? 1 : tones.length);

  var current = root;
  for (var i = 1; i < count - 1; i++) {
    final pick =
        tones.isEmpty ? root : tones[(i - 1 + rotation) % tones.length];
    current = _closest(pick, current, range);
    out.add(BassNote(beat: i.toDouble(), midi: current, duration: 1));
  }

  // The last beat belongs to the NEXT chord.
  final lastBeat = (count - 1).toDouble();
  final target = next == null
      ? root
      : _approach(current, _pc(next.bass ?? next.root), range, chord, seed);
  out.add(
    BassNote(beat: lastBeat, midi: target, duration: beats - lastBeat),
  );
  return out;
}

/// A note a semitone, a whole tone or a fifth away from [targetPc].
///
/// The card's acceptance is exactly this: every bar-final note must be one of
/// those three from the next bar's root. Chromatic-from-below is the default
/// because it is the strongest pull; the alternatives keep a repeated
/// progression from sounding mechanical.
int _approach(
  int from,
  int targetPc,
  BassRange range,
  ChordSpec chord,
  int seed,
) {
  final target = _nearest(targetPc, from, range);
  final candidates = <int>[
    target - 1, // chromatic below
    target + 1, // chromatic above
    target - 2, // scalar below
    range.clamp(target + 7), // the dominant fifth above
  ];
  // Deterministic choice, biased to the chromatic approach below.
  final pick = candidates[(seed + from) % 4 == 0 ? 3 : 0];
  final clamped = range.clamp(pick);
  // Never hand back something out of range, and never a note more than a fifth
  // from where the line already is — that is a leap, not a walk.
  if ((clamped - from).abs() > 7) return _closest(clamped % 12, from, range);
  return clamped;
}

List<BassNote> _arpeggio(
  ChordSpec chord,
  int root,
  double beats,
  BassRange range, {
  required bool ascending,
}) {
  final tones = _chordTones(chord, root, range);
  if (tones.isEmpty) return [BassNote(beat: 0, midi: root, duration: beats)];
  final order = ascending
      ? tones
      // Alberti: low, high, middle, high.
      : [
          tones.first,
          tones.last,
          tones.length > 1 ? tones[1] : tones.first,
          tones.last,
        ];
  final count = beats.floor().clamp(1, 8);
  return [
    for (var i = 0; i < count; i++)
      BassNote(
        beat: i.toDouble(),
        midi: order[i % order.length],
        duration: 1,
        velocity: i == 0 ? 0.85 : 0.7,
      ),
  ];
}

/// The chord's tones as absolute notes near [root], ascending and unique.
List<int> _chordTones(ChordSpec chord, int root, BassRange range) {
  final rootPc = _pc(chord.root);
  final seen = <int>{};
  final out = <int>[];
  for (final interval in chord.intervals) {
    final pc = (rootPc + interval) % 12;
    final midi = _nearest(pc, root, range);
    if (seen.add(midi)) out.add(midi);
  }
  out.sort();
  return out;
}

/// The instance of [pc] closest to [near], inside [range].
int _nearest(int pc, int near, BassRange range) {
  var best = range.low + ((pc - range.low) % 12 + 12) % 12;
  var bestDistance = (best - near).abs();
  for (var m = best; m <= range.high; m += 12) {
    final d = (m - near).abs();
    if (d < bestDistance) {
      best = m;
      bestDistance = d;
    }
  }
  return range.clamp(best);
}

int _closest(int pcOrMidi, int near, BassRange range) =>
    _nearest(((pcOrMidi % 12) + 12) % 12, near, range);

int _pc(Pitch pitch) => (pitch.midiNumber % 12 + 12) % 12;
