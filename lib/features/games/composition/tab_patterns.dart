// Generative tab authoring: turn a chord or a scale into a run of TabColumns —
// strum it, arpeggiate it in a common picking pattern, or lay a scale across
// the fretboard. Pure + testable; the Tab Workshop inserts the result at the
// cursor. The note VALUE (quarter/eighth/…) plus the editor's playback BPM give
// the "same shape at different tempi" the patterns are for.

import 'package:comet_beat/features/games/composition/tab_chords.dart';
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

/// Fingerstyle / strum patterns over a chord. Unlike a plain arpeggio these
/// carry their OWN intrinsic rhythm (an eighth- or quarter-note grid), so the
/// pattern's shape is fixed and the editor's playback BPM sets the tempo.
enum PickPattern { travis, boomChuck, strumEighths, islandStrum }

TabColumn _patternCol(
  ChordDiagram c,
  NoteDuration d,
  List<int> strings,
) =>
    // An empty [strings] → an empty column → a rest of length [d].
    TabColumn(frets: {for (final s in strings) s: c.frets[s]}, duration: d);

/// Expand a chord into a named fingerstyle/strum [pattern]. Bass = the chord's
/// lowest sounding string, alternating with the next one up; treble picks come
/// off the two highest strings; a "strum" sounds every voice at once.
List<TabColumn> patternColumns(ChordDiagram c, PickPattern pattern) {
  final voices = chordVoices(c); // high-pitch → low-pitch (index order)
  if (voices.isEmpty) return const [];
  final bass = voices.last; // lowest-pitched string
  final altBass = voices.length >= 2 ? voices[voices.length - 2] : bass;
  final t0 = voices.first; // highest-pitched string
  final t1 = voices.length >= 2 ? voices[1] : t0;
  const e = NoteDuration.eighth;
  const q = NoteDuration.quarter;
  switch (pattern) {
    case PickPattern.travis:
      // Alternating-thumb bass (1 & 3 → root, 2 & 4 → alt bass) with treble
      // pinches on the off-beats — the classic eight-eighth Travis roll.
      return [
        _patternCol(c, e, [bass]),
        _patternCol(c, e, [t0]),
        _patternCol(c, e, [altBass]),
        _patternCol(c, e, [t1]),
        _patternCol(c, e, [bass]),
        _patternCol(c, e, [t0]),
        _patternCol(c, e, [altBass]),
        _patternCol(c, e, [t1]),
      ];
    case PickPattern.boomChuck:
      // "boom-chuck": bass on 1 & 3, full chord strum on 2 & 4 (quarters).
      return [
        _patternCol(c, q, [bass]),
        _patternCol(c, q, voices),
        _patternCol(c, q, [altBass]),
        _patternCol(c, q, voices),
      ];
    case PickPattern.strumEighths:
      // Eight straight down/up eighth strums.
      return [for (var i = 0; i < 8; i++) _patternCol(c, e, voices)];
    case PickPattern.islandStrum:
      // Syncopated pop/reggae feel: D · D U · U D U (· = rest).
      const hits = [true, false, true, true, false, true, true, true];
      return [
        for (final on in hits) _patternCol(c, e, on ? voices : const []),
      ];
  }
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

/// Every way the sheet can voice a single chord — a strum, one of the four
/// arpeggio directions, or a named fingerstyle/strum pattern. Lets one code
/// path drive both a single chord and each chord of a progression.
enum ChordStyle {
  strum,
  up,
  down,
  upDown,
  downUp,
  travis,
  boomChuck,
  strumEighths,
  island,
}

/// Voice chord [c] as [style]. Arpeggio/strum honour [dur]; the named patterns
/// carry their own rhythm and ignore it.
List<TabColumn> chordStyleColumns(
  ChordDiagram c,
  ChordStyle style,
  NoteDuration dur,
) =>
    switch (style) {
      ChordStyle.strum => strumColumns(c, dur),
      ChordStyle.up => arpeggioColumns(c, ArpStyle.up, dur),
      ChordStyle.down => arpeggioColumns(c, ArpStyle.down, dur),
      ChordStyle.upDown => arpeggioColumns(c, ArpStyle.upDown, dur),
      ChordStyle.downUp => arpeggioColumns(c, ArpStyle.downUp, dur),
      ChordStyle.travis => patternColumns(c, PickPattern.travis),
      ChordStyle.boomChuck => patternColumns(c, PickPattern.boomChuck),
      ChordStyle.strumEighths => patternColumns(c, PickPattern.strumEighths),
      ChordStyle.island => patternColumns(c, PickPattern.islandStrum),
    };

/// Common chord progressions, as sequences of [kGuitarChords] names so every
/// chord resolves to a real open shape. Named by their feel + the chords used.
const Map<String, List<String>> kProgressions = {
  'Pop (C–G–Am–F)': ['C', 'G', 'Am', 'F'],
  'Pop (G–D–Em–C)': ['G', 'D', 'Em', 'C'],
  'I–IV–V (G–C–D)': ['G', 'C', 'D'],
  '50s (C–Am–F–G)': ['C', 'Am', 'F', 'G'],
  'Doo-wop (G–Em–C–D)': ['G', 'Em', 'C', 'D'],
  'ii–V–I (Dm–G–C)': ['Dm', 'G', 'C'],
  'ii–V–I (Am–D7–G)': ['Am', 'D7', 'G'],
  'Andalusian (Am–G–F–E)': ['Am', 'G', 'F', 'E'],
  'Turnaround (G–E7–A7–D7)': ['G', 'E7', 'A7', 'D7'],
  'Blues in A (12-bar)': [
    'A', 'A', 'A', 'A', //
    'D', 'D', 'A', 'A', //
    'E', 'D', 'A', 'E', //
  ],
  'Blues in E (12-bar)': [
    'E', 'E', 'E', 'E', //
    'A', 'A', 'E', 'E', //
    'B7', 'A', 'E', 'B7', //
  ],
  'Blues in G (12-bar)': [
    'G7', 'G7', 'G7', 'G7', //
    'C7', 'C7', 'G7', 'G7', //
    'D7', 'C7', 'G7', 'D7', //
  ],
};

/// Expand a chord-name progression into columns: each chord voiced as [style],
/// the whole sequence repeated [repeat] times. Chords absent from [library] are
/// skipped (every column is freshly built, so repeats never share instances).
List<TabColumn> progressionColumns(
  List<String> chordNames,
  Map<String, ChordDiagram> library,
  ChordStyle style,
  NoteDuration dur, {
  int repeat = 1,
}) {
  final out = <TabColumn>[];
  for (var r = 0; r < repeat; r++) {
    for (final name in chordNames) {
      final c = library[name];
      if (c == null) continue;
      out.addAll(chordStyleColumns(c, style, dur));
    }
  }
  return out;
}

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
