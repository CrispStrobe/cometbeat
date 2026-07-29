// lib/core/games/highway/highway_library.dart
//
// The built-in pieces the highway ships with, so every instrument has real
// content the moment the tile is opened — before anyone imports a score.
//
// CONTENT RULES (see docs/CORPUS_LICENSING.md): everything here is either a
// long-public-domain melody (Beethoven, traditional) or an exercise written
// for this app. Nothing is transcribed from a copyrighted arrangement. Real
// repertoire comes from the Song Book, which is rights-gated already.
//
// Charts are authored in beats, polyphonically, with `voice` separating the
// hands — so a piano piece really does fall in two colours like a two-hand
// score, instead of being a melody with a label on it.

import 'package:comet_beat/core/games/highway/highway_chart.dart';
import 'package:comet_beat/core/games/highway/highway_grooves.dart';
import 'package:comet_beat/core/games/highway/highway_instrument.dart';

/// Concatenated voices, put back into time order — the charts below are
/// written one hand at a time because that is how they are read, but every
/// consumer wants them interleaved.
List<HighwayEvent> _merged(List<List<HighwayEvent>> voices) => [
      for (final v in voices) ...v,
    ]..sort((a, b) => a.startBeat.compareTo(b.startBeat));

/// One playable item in the highway's built-in library.
class HighwayPiece {
  const HighwayPiece({
    required this.id,
    required this.chart,
    required this.instruments,
    this.level = 1,
  });

  /// Stable id (progress, spaced repetition).
  final String id;

  final HighwayChart chart;

  /// Which instruments this piece makes sense on.
  final Set<HighwayInstrument> instruments;

  /// Rough ordering hint, 1 = first thing to try.
  final int level;

  String get title => chart.name;
}

/// `(midi, startBeat, beats)` → blocks on one voice.
List<HighwayEvent> _line(
  List<(int, double, double)> notes, {
  int voice = 0,
}) =>
    [
      for (final (midi, start, beats) in notes)
        HighwayEvent(startBeat: start, beats: beats, midi: midi, voice: voice),
    ];

/// `(pitches, startBeat, beats)` → chord blocks on one voice.
List<HighwayEvent> _chords(
  List<(List<int>, double, double)> chords, {
  int voice = 1,
}) =>
    [
      for (final (pitches, start, beats) in chords)
        for (final midi in pitches)
          HighwayEvent(
            startBeat: start,
            beats: beats,
            midi: midi,
            voice: voice,
          ),
    ];

/// One chord struck once per beat for [bars] beats from [start] — a strum, and
/// the reason a guitar highway lights six lanes at a time.
List<HighwayEvent> _strum(
  List<int> pitches,
  double start,
  int beats, {
  int voice = 0,
}) =>
    [
      for (var b = 0; b < beats; b++)
        for (final midi in pitches)
          HighwayEvent(
            startBeat: start + b,
            beats: 0.9,
            midi: midi,
            voice: voice,
          ),
    ];

// --- Level 1: the first rung -----------------------------------------------
//
// The library had nothing below "a C major scale in both hands at 92". The drum
// ladder taught the lesson: a first piece is three notes, slowly, one hand. All
// of these are traditional melodies or exercises written here, never anyone's
// arrangement.

/// Three notes, one hand, one per beat. The oldest first lesson there is.
final _threeNotes = _line([
  (60, 0, 1), (62, 1, 1), (64, 2, 1), (62, 3, 1), //
  (60, 4, 1), (60, 5, 1), (60, 6, 2),
  (62, 8, 1), (62, 9, 1), (62, 10, 2),
  (64, 12, 1), (62, 13, 1), (60, 14, 2),
]);

/// "Hot cross buns" (traditional) — three notes, and a tune a child knows.
final _hotCrossBuns = _line([
  (64, 0, 1), (62, 1, 1), (60, 2, 2), //
  (64, 4, 1), (62, 5, 1), (60, 6, 2),
  (60, 8, 0.5), (60, 8.5, 0.5), (60, 9, 0.5), (60, 9.5, 0.5),
  (62, 10, 0.5), (62, 10.5, 0.5), (62, 11, 0.5), (62, 11.5, 0.5),
  (64, 12, 1), (62, 13, 1), (60, 14, 2),
]);

/// "Merrily we roll along" (traditional) — five notes, still one hand.
final _merrily = _line([
  (64, 0, 1), (62, 1, 1), (60, 2, 1), (62, 3, 1), //
  (64, 4, 1), (64, 5, 1), (64, 6, 2),
  (62, 8, 1), (62, 9, 1), (62, 10, 2),
  (64, 12, 1), (67, 13, 1), (67, 14, 2),
]);

/// Open strings, in order, one per beat — the first thing a string player does,
/// and the only piece that needs no left hand at all.
List<HighwayEvent> _openStrings(List<int> pitches) => _line([
      for (var i = 0; i < pitches.length; i++) (pitches[i], i * 2.0, 2.0),
      for (var i = 0; i < pitches.length; i++)
        (pitches[pitches.length - 1 - i], (pitches.length + i) * 2.0, 2.0),
    ]);

/// One string, three frets — a melody a beginner can play without moving.
final _oneStringTune = _line([
  (64, 0, 1), (66, 1, 1), (67, 2, 2), //
  (64, 4, 1), (66, 5, 1), (67, 6, 2),
  (67, 8, 1), (66, 9, 1), (64, 10, 2),
  (66, 12, 1), (64, 13, 1), (64, 14, 2),
]);

/// Two chords, one bar each — the first change anyone learns.
final _twoChords = [
  ..._strum(_emShape, 0, 4),
  ..._strum(_gShape, 4, 4),
  ..._strum(_emShape, 8, 4),
  ..._strum(_gShape, 12, 4),
];

// --- Piano ------------------------------------------------------------------

// "Ode to Joy" (Beethoven, public domain), melody in C with a left hand of
// open fifths — the smallest accompaniment that still teaches two hands.
final _odeMelody = _line([
  (64, 0, 1), (64, 1, 1), (65, 2, 1), (67, 3, 1), //
  (67, 4, 1), (65, 5, 1), (64, 6, 1), (62, 7, 1),
  (60, 8, 1), (60, 9, 1), (62, 10, 1), (64, 11, 1),
  (64, 12, 1.5), (62, 13.5, 0.5), (62, 14, 2),
]);

final _odeLeft = _chords([
  ([48, 55], 0, 2), ([48, 55], 2, 2), //
  ([43, 50], 4, 2), ([43, 50], 6, 2),
  ([48, 55], 8, 2), ([48, 55], 10, 2),
  ([43, 50], 12, 2), ([48, 55], 14, 2),
]);

final _twinkleMelody = _line([
  (60, 0, 1), (60, 1, 1), (67, 2, 1), (67, 3, 1), //
  (69, 4, 1), (69, 5, 1), (67, 6, 2),
  (65, 8, 1), (65, 9, 1), (64, 10, 1), (64, 11, 1),
  (62, 12, 1), (62, 13, 1), (60, 14, 2),
]);

final _twinkleLeft = _chords([
  ([48, 52, 55], 0, 2), ([48, 52, 55], 2, 2), //
  ([53, 57, 60], 4, 2), ([48, 52, 55], 6, 2),
  ([53, 57, 60], 8, 2), ([48, 52, 55], 10, 2),
  ([43, 47, 50], 12, 2), ([48, 52, 55], 14, 2),
]);

/// Both hands in parallel octaves — the exercise that teaches the eye to read
/// two lanes at once before either hand has to do anything of its own.
final _parallelScale = _merged([
  _line([
    for (var i = 0; i < 8; i++)
      ([60, 62, 64, 65, 67, 69, 71, 72][i], i.toDouble(), 1.0),
    for (var i = 0; i < 7; i++)
      ([71, 69, 67, 65, 64, 62, 60][i], 8.0 + i, i == 6 ? 2.0 : 1.0),
  ]),
  _line(
    [
      for (var i = 0; i < 8; i++)
        ([48, 50, 52, 53, 55, 57, 59, 60][i], i.toDouble(), 1.0),
      for (var i = 0; i < 7; i++)
        ([59, 57, 55, 53, 52, 50, 48][i], 8.0 + i, i == 6 ? 2.0 : 1.0),
    ],
    voice: 1,
  ),
]);

// --- Guitar / plucked -------------------------------------------------------

// Open-position chords, low string first. Standard shapes, nothing arranged.
const _emShape = [40, 47, 52, 55, 59, 64];
const _gShape = [43, 47, 50, 55, 59, 67];
const _dShape = [50, 57, 62, 66];
const _cShape = [48, 52, 55, 60, 64];

final _strumSong = _merged([
  _strum(_emShape, 0, 4),
  _strum(_gShape, 4, 4),
  _strum(_dShape, 8, 4),
  _strum(_cShape, 12, 4),
]);

/// Alternating bass and treble over two chords — the first fingerstyle shape
/// most players learn, written out rather than transcribed.
final _arpeggioStudy = _line([
  (40, 0, 0.5), (55, 0.5, 0.5), (59, 1, 0.5), (64, 1.5, 0.5), //
  (59, 2, 0.5), (55, 2.5, 0.5), (52, 3, 1),
  (43, 4, 0.5), (55, 4.5, 0.5), (59, 5, 0.5), (67, 5.5, 0.5),
  (59, 6, 0.5), (55, 6.5, 0.5), (50, 7, 1),
  (48, 8, 0.5), (55, 8.5, 0.5), (60, 9, 0.5), (64, 9.5, 0.5),
  (60, 10, 0.5), (55, 10.5, 0.5), (52, 11, 1),
  (50, 12, 0.5), (57, 12.5, 0.5), (62, 13, 0.5), (66, 13.5, 0.5),
  (62, 14, 1), (50, 15, 1),
]);

final _pentatonicRiff = _line([
  (52, 0, 1), (55, 1, 1), (57, 2, 1), (59, 3, 1), //
  (62, 4, 2), (59, 6, 1), (57, 7, 1), (55, 8, 2), (52, 10, 2),
]);

final _bassLine = _line([
  (40, 0, 1), (40, 1, 1), (47, 2, 1), (40, 3, 1), //
  (43, 4, 1), (43, 5, 1), (50, 6, 1), (43, 7, 1),
  (45, 8, 1), (45, 9, 1), (52, 10, 1), (45, 11, 1),
  (43, 12, 1), (45, 13, 1), (40, 14, 2),
]);

// Ukulele chords in the instrument's own register (its lowest string is C4).
const _ukeC = [60, 64, 67, 72];
const _ukeF = [60, 65, 69, 72];
const _ukeG = [62, 67, 71, 74];
const _ukeAm = [60, 64, 69, 72];

final _ukeSong = _merged([
  _strum(_ukeC, 0, 4),
  _strum(_ukeAm, 4, 4),
  _strum(_ukeF, 8, 4),
  _strum(_ukeG, 12, 4),
]);

/// A root-fifth bass line — two notes, four bars, the shape under most songs.
final _bassRootFifth = _line([
  (40, 0, 1), (47, 1, 1), (40, 2, 1), (47, 3, 1), //
  (45, 4, 1), (52, 5, 1), (45, 6, 1), (52, 7, 1),
  (43, 8, 1), (50, 9, 1), (43, 10, 1), (50, 11, 1),
  (40, 12, 2), (40, 14, 2),
]);

/// A bass scale walk, one octave up and back.
final _bassScale = _line([
  (40, 0, 1), (42, 1, 1), (44, 2, 1), (45, 3, 1), //
  (47, 4, 1), (49, 5, 1), (51, 6, 1), (52, 7, 2),
  (51, 9, 1), (49, 10, 1), (47, 11, 1), (45, 12, 1),
  (44, 13, 1), (42, 14, 1), (40, 15, 2),
]);

/// Ukulele: two chords, then the melody most beginners try first.
final _ukeTwoChords = [
  ..._strum(_ukeC, 0, 4),
  ..._strum(_ukeF, 4, 4),
  ..._strum(_ukeC, 8, 4),
  ..._strum(_ukeG, 12, 4),
];

final _ukeMelody = _line([
  (60, 0, 1), (62, 1, 1), (64, 2, 1), (60, 3, 1), //
  (64, 4, 1), (60, 5, 1), (64, 6, 2),
  (62, 8, 1), (64, 9, 1), (65, 10, 2),
  (64, 12, 1), (62, 13, 1), (60, 14, 2),
]);

// --- Cello ------------------------------------------------------------------

final _firstPositionWalk = _line([
  (50, 0, 2), (52, 2, 2), (54, 4, 2), (55, 6, 2), //
  (57, 8, 4), (55, 12, 2), (54, 14, 2), (52, 16, 2), (50, 18, 4),
]);

final _dArpeggio = _line([
  (50, 0, 1), (54, 1, 1), (57, 2, 1), (62, 3, 1), //
  (57, 4, 1), (54, 5, 1), (50, 6, 2),
  (55, 8, 1), (59, 9, 1), (62, 10, 1), (67, 11, 1),
  (62, 12, 1), (59, 13, 1), (55, 14, 2),
]);

/// The groove ladder as playable pieces, easiest first.
///
/// It does NOT reuse the Drum Kit's starter presets any more: those are four
/// patterns for BUILDING a beat, all of them hats-on-every-eighth, which as an
/// exercise means three hat taps a second before you have played a bar. A
/// highway needs a ladder — see `highway_grooves.dart`.
List<HighwayPiece> _drumPieces() => [
      for (final groove in kHighwayGrooves)
        HighwayPiece(
          id: 'highway_groove_${groove.name.toLowerCase().replaceAll(' ', '_')}',
          level: groove.level,
          instruments: const {HighwayInstrument.drums},
          chart: highwayChartFromDrumRows(
            groove.steps,
            lanes: kHighwayDrumLanes,
            name: groove.name,
            bpm: groove.bpm,
            // A short groove needs more passes to be an exercise; a long one
            // fewer, so every piece lasts roughly the same.
            repeats: groove.rows.values.first.length <= 12 ? 6 : 4,
          ),
        ),
    ];

/// The built-in repertoire, grouped by what it is playable on.
class HighwayLibrary {
  const HighwayLibrary._();

  static final List<HighwayPiece> pieces = [
    ..._drumPieces(),
    HighwayPiece(
      id: 'highway_three_notes',
      instruments: const {HighwayInstrument.piano, HighwayInstrument.pads},
      chart: HighwayChart(
        name: 'Three notes',
        bpm: 56,
        events: _threeNotes,
      ),
    ),
    HighwayPiece(
      id: 'highway_hot_cross_buns',
      instruments: const {HighwayInstrument.piano, HighwayInstrument.pads},
      chart: HighwayChart(
        name: 'Hot cross buns',
        bpm: 60,
        events: _hotCrossBuns,
      ),
    ),
    HighwayPiece(
      id: 'highway_merrily',
      level: 2,
      instruments: const {HighwayInstrument.piano, HighwayInstrument.pads},
      chart: HighwayChart(
        name: 'Merrily we roll along',
        bpm: 64,
        events: _merrily,
      ),
    ),
    HighwayPiece(
      id: 'highway_open_strings_guitar',
      instruments: const {HighwayInstrument.guitar},
      chart: HighwayChart(
        name: 'Open strings',
        bpm: 56,
        events: _openStrings(const [40, 45, 50, 55, 59, 64]),
      ),
    ),
    HighwayPiece(
      id: 'highway_one_string_tune',
      level: 2,
      instruments: const {HighwayInstrument.guitar},
      chart: HighwayChart(
        name: 'One string, three frets',
        bpm: 60,
        events: _oneStringTune,
      ),
    ),
    HighwayPiece(
      id: 'highway_two_chords',
      level: 3,
      instruments: const {HighwayInstrument.guitar},
      chart: HighwayChart(
        name: 'Two chords: Em G',
        bpm: 60,
        events: _twoChords,
      ),
    ),
    HighwayPiece(
      id: 'highway_open_strings_cello',
      instruments: const {HighwayInstrument.cello},
      chart: HighwayChart(
        name: 'Open strings',
        bpm: 56,
        events: _openStrings(const [36, 43, 50, 57]),
      ),
    ),
    HighwayPiece(
      id: 'highway_open_strings_bass',
      instruments: const {HighwayInstrument.bass},
      chart: HighwayChart(
        name: 'Open strings',
        bpm: 56,
        events: _openStrings(const [28, 33, 38, 43]),
      ),
    ),
    HighwayPiece(
      id: 'highway_uke_open',
      instruments: const {HighwayInstrument.ukulele},
      chart: HighwayChart(
        name: 'Open strings',
        bpm: 56,
        events: _openStrings(const [67, 60, 64, 69]),
      ),
    ),
    HighwayPiece(
      id: 'highway_parallel_scale',
      level: 3,
      instruments: const {HighwayInstrument.piano, HighwayInstrument.pads},
      chart: HighwayChart(
        name: 'Two hands: C major',
        bpm: 66,
        events: _parallelScale,
      ),
    ),
    HighwayPiece(
      id: 'highway_ode',
      level: 4,
      instruments: const {HighwayInstrument.piano, HighwayInstrument.pads},
      chart: HighwayChart(
        name: 'Ode to Joy',
        bpm: 76,
        events: _merged([_odeMelody, _odeLeft]),
      ),
    ),
    HighwayPiece(
      id: 'highway_twinkle',
      level: 3,
      instruments: const {HighwayInstrument.piano, HighwayInstrument.pads},
      chart: HighwayChart(
        name: 'Twinkle, Twinkle',
        bpm: 72,
        events: _merged([_twinkleMelody, _twinkleLeft]),
      ),
    ),
    HighwayPiece(
      id: 'highway_strum',
      level: 4,
      instruments: const {HighwayInstrument.guitar, HighwayInstrument.pads},
      chart: HighwayChart(
        name: 'Four chords: Em G D C',
        bpm: 68,
        events: _strumSong,
      ),
    ),
    HighwayPiece(
      id: 'highway_uke_chords',
      level: 4,
      instruments: const {HighwayInstrument.ukulele, HighwayInstrument.pads},
      chart: HighwayChart(
        name: 'Ukulele: C Am F G',
        bpm: 68,
        events: _ukeSong,
      ),
    ),
    HighwayPiece(
      id: 'highway_arpeggio',
      level: 5,
      instruments: const {HighwayInstrument.guitar},
      chart: HighwayChart(
        name: 'Arpeggio study',
        bpm: 64,
        events: _arpeggioStudy,
      ),
    ),
    HighwayPiece(
      id: 'highway_pentatonic',
      level: 3,
      instruments: const {HighwayInstrument.guitar, HighwayInstrument.pads},
      chart: HighwayChart(
        name: 'Pentatonic riff',
        bpm: 66,
        events: _pentatonicRiff,
      ),
    ),
    HighwayPiece(
      id: 'highway_bass_root_fifth',
      level: 2,
      instruments: const {HighwayInstrument.bass},
      chart: HighwayChart(
        name: 'Root and fifth',
        bpm: 62,
        events: _bassRootFifth,
      ),
    ),
    HighwayPiece(
      id: 'highway_bass_scale',
      level: 4,
      instruments: const {HighwayInstrument.bass},
      chart: HighwayChart(
        name: 'Bass scale walk',
        bpm: 66,
        events: _bassScale,
      ),
    ),
    HighwayPiece(
      id: 'highway_uke_two_chords',
      level: 3,
      instruments: const {HighwayInstrument.ukulele},
      chart: HighwayChart(
        name: 'Two chords: C F',
        bpm: 62,
        events: _ukeTwoChords,
      ),
    ),
    HighwayPiece(
      id: 'highway_uke_melody',
      level: 2,
      instruments: const {HighwayInstrument.ukulele},
      chart: HighwayChart(
        name: 'First melody',
        bpm: 62,
        events: _ukeMelody,
      ),
    ),
    HighwayPiece(
      id: 'highway_bassline',
      level: 3,
      instruments: const {HighwayInstrument.bass, HighwayInstrument.pads},
      chart: HighwayChart(
        name: 'Walking bass',
        bpm: 68,
        events: _bassLine,
      ),
    ),
    HighwayPiece(
      id: 'highway_first_position',
      level: 2,
      instruments: const {HighwayInstrument.cello},
      chart: HighwayChart(
        name: 'First position walk',
        bpm: 60,
        events: _firstPositionWalk,
      ),
    ),
    HighwayPiece(
      id: 'highway_d_arpeggio',
      level: 3,
      instruments: const {HighwayInstrument.cello, HighwayInstrument.piano},
      chart: HighwayChart(
        name: 'D major arpeggios',
        bpm: 64,
        events: _dArpeggio,
      ),
    ),
  ];

  /// Everything playable on [instrument], easiest first.
  static List<HighwayPiece> forInstrument(HighwayInstrument instrument) => [
        for (final p in pieces)
          if (p.instruments.contains(instrument)) p,
      ]..sort((a, b) => a.level.compareTo(b.level));
}
