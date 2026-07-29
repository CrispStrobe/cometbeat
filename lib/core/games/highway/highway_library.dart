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

import 'package:comet_beat/core/audio/drum_presets.dart' show kDrumPresets;
import 'package:comet_beat/core/games/highway/highway_chart.dart';
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

/// The Drum Kit's own starter grooves, on the highway. Reusing `kDrumPresets`
/// rather than authoring beats again means the groove a child builds in the
/// Drum Kit and the one falling here are the same music, and a new preset shows
/// up in both places at once.
List<HighwayPiece> _drumPieces() => [
      for (var i = 0; i < kDrumPresets.length && i < 4; i++)
        HighwayPiece(
          id: 'highway_beat_${kDrumPresets[i].name.toLowerCase()}',
          level: i + 1,
          instruments: const {HighwayInstrument.drums},
          chart: highwayChartFromDrumRows(
            kDrumPresets[i].pattern.rows,
            lanes: kHighwayDrumLanes,
            name: kDrumPresets[i].name,
            bpm: 92,
          ),
        ),
    ];

/// The built-in repertoire, grouped by what it is playable on.
class HighwayLibrary {
  const HighwayLibrary._();

  static final List<HighwayPiece> pieces = [
    ..._drumPieces(),
    HighwayPiece(
      id: 'highway_parallel_scale',
      instruments: const {HighwayInstrument.piano, HighwayInstrument.pads},
      chart: HighwayChart(
        name: 'Two hands: C major',
        bpm: 92,
        events: _parallelScale,
      ),
    ),
    HighwayPiece(
      id: 'highway_ode',
      level: 2,
      instruments: const {HighwayInstrument.piano, HighwayInstrument.pads},
      chart: HighwayChart(
        name: 'Ode to Joy',
        bpm: 100,
        events: _merged([_odeMelody, _odeLeft]),
      ),
    ),
    HighwayPiece(
      id: 'highway_twinkle',
      level: 2,
      instruments: const {HighwayInstrument.piano, HighwayInstrument.pads},
      chart: HighwayChart(
        name: 'Twinkle, Twinkle',
        bpm: 96,
        events: _merged([_twinkleMelody, _twinkleLeft]),
      ),
    ),
    HighwayPiece(
      id: 'highway_strum',
      instruments: const {HighwayInstrument.guitar, HighwayInstrument.pads},
      chart: HighwayChart(
        name: 'Four chords: Em G D C',
        bpm: 84,
        events: _strumSong,
      ),
    ),
    HighwayPiece(
      id: 'highway_uke_chords',
      instruments: const {HighwayInstrument.ukulele, HighwayInstrument.pads},
      chart: HighwayChart(
        name: 'Ukulele: C Am F G',
        bpm: 88,
        events: _ukeSong,
      ),
    ),
    HighwayPiece(
      id: 'highway_arpeggio',
      level: 3,
      instruments: const {HighwayInstrument.guitar},
      chart: HighwayChart(
        name: 'Arpeggio study',
        bpm: 76,
        events: _arpeggioStudy,
      ),
    ),
    HighwayPiece(
      id: 'highway_pentatonic',
      level: 2,
      instruments: const {HighwayInstrument.guitar, HighwayInstrument.pads},
      chart: HighwayChart(
        name: 'Pentatonic riff',
        bpm: 80,
        events: _pentatonicRiff,
      ),
    ),
    HighwayPiece(
      id: 'highway_bassline',
      instruments: const {HighwayInstrument.bass, HighwayInstrument.pads},
      chart: HighwayChart(
        name: 'Walking bass',
        bpm: 88,
        events: _bassLine,
      ),
    ),
    HighwayPiece(
      id: 'highway_first_position',
      instruments: const {HighwayInstrument.cello},
      chart: HighwayChart(
        name: 'First position walk',
        bpm: 60,
        events: _firstPositionWalk,
      ),
    ),
    HighwayPiece(
      id: 'highway_d_arpeggio',
      level: 2,
      instruments: const {HighwayInstrument.cello, HighwayInstrument.piano},
      chart: HighwayChart(
        name: 'D major arpeggios',
        bpm: 72,
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
