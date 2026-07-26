// A tiny data-driven chord builder for the Tab Editor: pick a ROOT (C, C♯, …)
// and a QUALITY (maj, m7, sus4, …) and get a playable [ChordDiagram] voiced on
// the current tuning — so the picker isn't limited to the ~15 stock guitar
// shapes but can voice any root × quality on any tuning.
//
// Pure Dart (no Flutter) so the voicing logic is unit-testable.

import 'package:crisp_notation/crisp_notation.dart';

/// The twelve chromatic roots, sharp-spelled, index = pitch class (0 = C).
const List<String> kChordRoots = [
  'C',
  'C♯',
  'D',
  'D♯',
  'E',
  'F',
  'F♯',
  'G',
  'G♯',
  'A',
  'A♯',
  'B',
];

/// The chord qualities the builder offers, each `(label, intervals)` where the
/// intervals are semitones above the root. Data-driven — add a row to offer a
/// new quality; the label is appended to the root for the chord name.
const List<(String, List<int>)> kChordQualities = [
  ('maj', [0, 4, 7]),
  ('m', [0, 3, 7]),
  ('5', [0, 7]), // power chord
  ('7', [0, 4, 7, 10]),
  ('maj7', [0, 4, 7, 11]),
  ('m7', [0, 3, 7, 10]),
  ('m7♭5', [0, 3, 6, 10]), // half-diminished
  ('dim', [0, 3, 6]),
  ('dim7', [0, 3, 6, 9]),
  ('aug', [0, 4, 8]),
  ('sus2', [0, 2, 7]),
  ('sus4', [0, 5, 7]),
  ('6', [0, 4, 7, 9]),
  ('m6', [0, 3, 7, 9]),
  ('add9', [0, 4, 7, 14]),
  ('9', [0, 4, 7, 10, 14]),
  ('m9', [0, 3, 7, 10, 14]),
];

/// The display name for [rootPc] (0 = C) + a quality [label] — e.g. `C♯m7`.
/// A bare `maj` triad is written as just the root (`C`), the common convention.
String chordName(int rootPc, String label) {
  final root = kChordRoots[rootPc % 12];
  return label == 'maj' ? root : '$root$label';
}

/// Builds a playable [ChordDiagram] for [rootPc] (0 = C) + [intervals] on
/// [tuning]. Each string takes the LOWEST fret (0..[maxFret]) that sounds a
/// chord tone, so every sounded string is in the chord; then, to avoid an
/// accidental inversion, the strings below the lowest root are muted so the
/// root sits in the bass — but only while that leaves at least three strings
/// sounding (else the fuller, inverted voicing is kept).
ChordDiagram chordVoicing(
  Tuning tuning,
  int rootPc,
  List<int> intervals, {
  required String name,
  int maxFret = 12,
}) {
  final pcs = <int>{for (final iv in intervals) (rootPc + iv) % 12};
  final n = tuning.stringCount;
  final frets = List<int>.filled(n, -1);
  for (var s = 0; s < n; s++) {
    final openPc = tuning.strings[s].midiNumber % 12;
    for (var f = 0; f <= maxFret; f++) {
      if (pcs.contains((openPc + f) % 12)) {
        frets[s] = f;
        break;
      }
    }
  }
  // Put the root in the bass: find the lowest-pitched string (highest index)
  // that already sounds the root, and mute the strings below it.
  int? rootBass;
  for (var s = n - 1; s >= 0; s--) {
    if (frets[s] >= 0 &&
        (tuning.strings[s].midiNumber + frets[s]) % 12 == rootPc % 12) {
      rootBass = s;
      break;
    }
  }
  if (rootBass != null && rootBass < n - 1) {
    final wouldSound = frets.take(rootBass + 1).where((f) => f >= 0).length;
    if (wouldSound >= 3) {
      for (var s = rootBass + 1; s < n; s++) {
        frets[s] = -1;
      }
    }
  }
  return ChordDiagram(frets, name: name);
}
