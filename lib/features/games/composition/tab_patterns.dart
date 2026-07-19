// Generative tab authoring: turn a chord or a scale into a run of TabColumns —
// strum it, arpeggiate it in a common picking pattern, or lay a scale across
// the fretboard. Pure + testable; the Tab Workshop inserts the result at the
// cursor. The note VALUE (quarter/eighth/…) plus the editor's playback BPM give
// the "same shape at different tempi" the patterns are for.

import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:crisp_notation/crisp_notation.dart';

/// The string indices a chord actually sounds (fret ≥ 0). Index 0 = the top tab
/// line = the highest-pitched string, so this list runs high-pitch → low-pitch.
List<int> chordVoices(ChordDiagram c) => [
      for (var i = 0; i < c.frets.length; i++)
        if (c.frets[i] >= 0) i,
    ];

/// One strum: every sounding string in a single column, with the chord diagram
/// attached (so it also shows above the column).
List<TabColumn> strumColumns(ChordDiagram c, NoteDuration duration) => [
      TabColumn(
        frets: {for (final s in chordVoices(c)) s: c.frets[s]},
        duration: duration,
        chord: c,
      ),
    ];

/// Common picking directions for an arpeggio.
enum ArpStyle { up, down, upDown, downUp }

/// Arpeggiate a chord: one string per column, following [style]. `up` ascends
/// in PITCH (thick/low string → thin/high string); `down` descends; the bounce
/// styles turn at the top/bottom without repeating the turning note.
List<TabColumn> arpeggioColumns(
  ChordDiagram c,
  ArpStyle style,
  NoteDuration duration,
) {
  final descending = chordVoices(c); // high-pitch → low-pitch (index order)
  final ascending = descending.reversed.toList(); // low-pitch → high-pitch
  final order = switch (style) {
    ArpStyle.up => ascending,
    ArpStyle.down => descending,
    ArpStyle.upDown => [...ascending, ...descending.skip(1)],
    ArpStyle.downUp => [...descending, ...ascending.skip(1)],
  };
  return [
    for (final s in order)
      TabColumn(frets: {s: c.frets[s]}, duration: duration),
  ];
}

/// Scale interval sets (semitones from the root), named for the picker.
const Map<String, List<int>> kScales = {
  'Major': [0, 2, 4, 5, 7, 9, 11],
  'Natural minor': [0, 2, 3, 5, 7, 8, 10],
  'Major pentatonic': [0, 2, 4, 7, 9],
  'Minor pentatonic': [0, 3, 5, 7, 10],
  'Blues': [0, 3, 5, 6, 7, 10],
  'Dorian': [0, 2, 3, 5, 7, 9, 10],
  'Mixolydian': [0, 2, 4, 5, 7, 9, 10],
};

/// A scale run over [octaves] (capped by the root an octave up), each note laid
/// on [tuning] at its lowest fret; notes unreachable on the tuning are skipped.
/// [descending] reverses the run. One note per column at [duration].
List<TabColumn> scaleColumns(
  Tuning tuning,
  int rootMidi,
  List<int> intervals,
  NoteDuration duration, {
  int octaves = 1,
  bool descending = false,
}) {
  final midis = <int>[
    for (var o = 0; o < octaves; o++)
      for (final iv in intervals) rootMidi + 12 * o + iv,
    rootMidi + 12 * octaves, // land on the octave to finish the run
  ];
  final run = descending ? midis.reversed : midis;
  final cols = <TabColumn>[];
  for (final m in run) {
    final placement = tuning.fretFor(pitchFromMidi(m));
    if (placement == null) continue; // off the fretboard on this tuning
    cols.add(
      TabColumn(frets: {placement.$1: placement.$2}, duration: duration),
    );
  }
  return cols;
}
