// lib/core/audio/loop_engine.dart
//
// Pure-Dart loop engine behind the Loop Mixer toy: a fixed set of 2-bar track
// patterns (all authored in C pentatonic, so any combination is consonant), an
// enabled set, and a mixdown of the enabled tracks to one seamless-looping WAV
// (offline-mix-then-loop: one player, one buffer → sample-accurate sync).
// Flutter-free, like synth.dart — unit-tested without a device.
//
// v2 (the groovebox ladder, PLAN.md): patterns are DATA (step grids), not
// closures — so variants, engraving, share tokens and generative variation all
// operate on one model. New: GrooveSpec (the whole groove as one serializable
// value), swing (off-eighth delay), per-track A/B/C variants, per-track
// levels, and a euclidean rhythm generator for drum patterns.
//
// Levels are combo-independent by design: each track carries an authored gain
// into mixStems' unit-peak-per-stem + soft-limiter mixdown, so toggling one
// card never changes how loud the others are. Renders are cached per spec so
// re-toggles are instant.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/modulated_delay.dart';
import 'package:comet_beat/core/audio/crisp_dsp/reverb.dart';
import 'package:comet_beat/core/audio/synth.dart';

/// An optional master send effect on the whole Loop Mixer output.
enum LoopSend { none, reverb, delay }

/// The musical clock the patterns render against: [bars] bars of 4/4 on an
/// eighth-note step grid (2 bars for the free vamp, 4 with a progression).
/// Supported tempos keep the step length an integral number of ms (and of
/// samples at 44.1 kHz), so every track's segments sum to exactly the same
/// sample count and the loop seam stays click-free.
///
/// [swing] (0..0.6) delays every off-eighth by that fraction of a step —
/// even steps lengthen, odd steps shorten, the loop length is unchanged.
class LoopTiming {
  const LoopTiming({required this.tempoBpm, this.swing = 0, this.bars = 2});

  final int tempoBpm;
  final double swing;
  final int bars;

  static const beatsPerBar = 4;

  /// Steps are eighths: 8 per bar.
  static const stepsPerBar = beatsPerBar * 2;

  int get totalSteps => stepsPerBar * bars;
  int get beatMs => 60000 ~/ tempoBpm;
  int get stepMs => beatMs ~/ 2;
  int get totalMs => stepMs * totalSteps;
  int get totalSamples => (totalMs * kSampleRate) ~/ 1000;
  Duration get loopLength => Duration(milliseconds: totalMs);

  int get _swingMs => (stepMs * swing).round();

  /// Millisecond onset of [step] (0..[totalSteps] inclusive): odd eighths
  /// start late by the swing amount. Durations derived from boundary
  /// differences always sum back to [totalMs].
  int boundaryMs(int step) => step * stepMs + (step.isOdd ? _swingMs : 0);
}

/// The step length every authored [LoopPattern] fills: the 2-bar vamp grid.
const kPatternSteps = LoopTiming.stepsPerBar * 2;

/// One melodic pattern cell: [midis] sounding for [steps] eighth-steps
/// (null or empty = rest).
typedef PatternCell = ({List<int>? midis, int steps});

/// A track's pattern for one 2-bar loop — data, renderable onto any timing.
sealed class LoopPattern {
  const LoopPattern();

  Float64List render(LoopTiming timing);
}

/// A pitched pattern: cells laid back-to-back on the step grid.
class MelodicPattern extends LoopPattern {
  const MelodicPattern(this.instrument, this.cells);

  final Instrument instrument;

  /// Cell step counts must sum to [LoopTiming.totalSteps].
  final List<PatternCell> cells;

  @override
  Float64List render(LoopTiming timing) {
    assert(
      cells.fold<int>(0, (sum, c) => sum + c.steps) == kPatternSteps,
      'pattern must fill the 2-bar grid exactly',
    );
    return renderCells(cells, instrument, timing);
  }
}

/// Renders pitched [cells] back-to-back on [timing]'s step grid (any length —
/// the progression path renders 4 bars, authored patterns 2). Cell durations
/// come from boundary differences, so swing is applied and totals stay exact.
Float64List renderCells(
  List<PatternCell> cells,
  Instrument instrument,
  LoopTiming timing,
) {
  var step = 0;
  final segments = <Segment>[];
  for (final cell in cells) {
    segments.add(
      (
        freqs: [
          for (final m in cell.midis ?? const <int>[]) midiToFrequency(m),
        ],
        ms: timing.boundaryMs(step + cell.steps) - timing.boundaryMs(step),
      ),
    );
    step += cell.steps;
  }
  return renderSegmentsRaw(segments, timbre: timbreFor(instrument));
}

/// An unpitched pattern: one boolean hit row per drum voice.
class DrumRowsPattern extends LoopPattern {
  const DrumRowsPattern(this.rows);

  /// Each row has [kPatternSteps] entries.
  final Map<Drum, List<bool>> rows;

  @override
  Float64List render(LoopTiming timing) => renderDrumPattern(
        [
          for (final MapEntry(key: drum, value: row) in rows.entries)
            for (var step = 0; step < row.length; step++)
              if (row[step]) (timing.boundaryMs(step), drum),
        ],
        totalMs: timing.totalMs,
      );
}

/// Euclidean rhythm E([hits], [steps]): distributes hits as evenly as
/// possible (Bjorklund). [rotation] shifts the pattern earlier by that many
/// steps, letting callers pin the first hit where they want it.
List<bool> euclid(int hits, int steps, {int rotation = 0}) => [
      for (var i = 0; i < steps; i++)
        (((i + rotation) % steps + steps) % steps + 1) * hits ~/ steps >
            ((i + rotation) % steps + steps) % steps * hits ~/ steps,
    ];

/// Parses a drum row from a step string: `x` = hit, anything else = rest.
/// Authoring aid — `'x...x...x...x..x'` reads like a drum machine.
List<bool> stepRow(String pattern) =>
    [for (final ch in pattern.split('')) ch == 'x'];

/// The inverse of [stepRow] — used to carry captured beat rows in the share
/// token in the same drum-machine notation the patterns are authored in.
String rowToString(List<bool> row) =>
    [for (final hit in row) hit ? 'x' : '.'].join();

// --- Harmony: the chord-progression lane ---

/// A harmonic degree of C major the groove can sit on.
enum ChordDegree {
  i(0, [0, 4, 7], 'I'),
  iv(5, [0, 4, 7], 'IV'),
  v(7, [0, 4, 7], 'V'),
  vi(9, [0, 3, 7], 'vi');

  const ChordDegree(this.rootOffset, this.triad, this.label);

  /// Semitones of the chord root above C.
  final int rootOffset;

  /// Chord-tone intervals above the root (major or minor triad).
  final List<int> triad;

  final String label;
}

/// A 4-chord progression: one bar per chord → a 4-bar loop. The labels are
/// roman numerals — language-neutral, no l10n needed.
class Progression {
  const Progression(this.id, this.degrees);

  final String id;
  final List<ChordDegree> degrees;

  String get label => degrees.map((d) => d.label).join('–');
}

/// The offered progressions (the axis family — C pentatonic melodies work
/// over all of them).
const kProgressions = [
  Progression(
    'axis',
    [ChordDegree.i, ChordDegree.v, ChordDegree.vi, ChordDegree.iv],
  ),
  Progression(
    'classic',
    [ChordDegree.i, ChordDegree.iv, ChordDegree.v, ChordDegree.i],
  ),
  Progression(
    'ballad',
    [ChordDegree.vi, ChordDegree.iv, ChordDegree.i, ChordDegree.v],
  ),
];

/// One bar of chord-relative cells: each cell's [tones] are chord-tone
/// indices (0 = root, 1 = third, 2 = fifth, 3 = root an octave up), resolved
/// per progression chord at render time. Step counts sum to one bar (8).
class ChordBar {
  const ChordBar(this.cells);

  final List<({List<int>? tones, int steps})> cells;

  /// Resolves this bar onto [degree] as absolute midi cells. [baseMidi] is
  /// the C the roots build on; roots that would land above [foldAbove] fold
  /// down an octave (keeps the vi chord voiced low, like the authored vamp).
  List<PatternCell> resolve(
    ChordDegree degree, {
    required int baseMidi,
    required int foldAbove,
  }) {
    var root = baseMidi + degree.rootOffset;
    if (root > foldAbove) root -= 12;
    return [
      for (final cell in cells)
        (
          midis: cell.tones == null
              ? null
              : [
                  for (final t in cell.tones!)
                    root + (t == 3 ? 12 : degree.triad[t]),
                ],
          steps: cell.steps,
        ),
    ];
  }
}

/// How a track plays in progression mode: chord-relative bar shapes (one per
/// variant) with its voicing register.
class ChordFollower {
  const ChordFollower({
    required this.instrument,
    required this.baseMidi,
    required this.foldAbove,
    required this.bars,
  });

  final Instrument instrument;
  final int baseMidi;
  final int foldAbove;

  /// One [ChordBar] per pattern variant (parallel to [LoopTrack.variants]).
  final List<ChordBar> bars;
}

/// One toggleable loop layer: an id (stable — used by l10n, tests and the
/// share token), an authored mix level, and its A/B/C pattern variants.
/// Tracks with a [chordFollower] re-voice per progression chord; the rest
/// tile their 2-bar pattern across the progression.
class LoopTrack {
  const LoopTrack({
    required this.id,
    required this.gain,
    required this.variants,
    this.chordFollower,
  });

  final String id;
  final double gain;

  /// At least one pattern; the card cycles through them (A → B → C → A).
  final List<LoopPattern> variants;

  final ChordFollower? chordFollower;
}

/// The whole groove as one small serializable value: what's enabled, which
/// variant and level each track uses, tempo and swing. The engine is a pure
/// The tempo range the engine will accept. `LoopTiming.beatMs` is
/// `60000 ~/ tempoBpm`, so an unvalidated tempo divides by whatever arrives:
/// 0 threw IntegerDivisionByZeroException, a negative gave a negative
/// `totalSamples` (RangeError when allocating the mix buffer), >60000 collapsed
/// `beatMs` — and so `totalMs` — to 0 (modulo-by-zero in the playback ticker),
/// and 1 bpm rendered an 8-minute ~42 MB WAV synchronously. A share token is
/// user-pasteable free text, so this is untrusted input; every OTHER spec field
/// is already validated on the way in ([GrooveSpec.fromJson] / [applySpec]).
/// The UI only ever offers 75/100/120 (the values that keep the step grid
/// integral in both ms and samples).
const kMinTempoBpm = 40;
const kMaxTempoBpm = 240;

/// `spec → WAV` render (cached), which makes share tokens, save slots and
/// seam-swap scheduling trivial.
class GrooveSpec {
  const GrooveSpec({
    this.enabled = const {},
    this.variants = const {},
    this.levels = const {},
    this.tempoBpm = 100,
    this.swing = 0,
    this.progressionId,
    this.userCells,
    this.userInstrument,
    this.beatRows,
  });

  final Set<String> enabled;
  final Map<String, int> variants;
  final Map<String, double> levels;
  final int tempoBpm;
  final double swing;

  /// A [kProgressions] id, or null for the free 2-bar vamp.
  final String? progressionId;

  /// The sung user track's cells (see groove_capture.dart), if one exists —
  /// so a share token carries the singer's melody too.
  final List<PatternCell>? userCells;

  /// [Instrument] name the user track renders with.
  final String? userInstrument;

  /// The beatboxed drum rows (see beat_capture.dart) as step strings keyed
  /// by drum name — a share token carries the captured beat too.
  final Map<Drum, List<bool>>? beatRows;

  factory GrooveSpec.fromJson(Map<String, dynamic> json) => GrooveSpec(
        enabled: {...(json['e'] as List? ?? const []).cast<String>()},
        variants: {
          ...(json['v'] as Map? ?? const {})
              .cast<String, num>()
              .map((k, v) => MapEntry(k, v.toInt())),
        },
        levels: {
          ...(json['l'] as Map? ?? const {})
              .cast<String, num>()
              .map((k, v) => MapEntry(k, v.toDouble())),
        },
        // Untrusted: a hand-edited token must not divide the timing math by 0
        // (or by a negative). Clamped like `levels`/`swing` already are.
        tempoBpm: (json['t'] as num? ?? 100)
            .toInt()
            .clamp(kMinTempoBpm, kMaxTempoBpm),
        swing: (json['s'] as num? ?? 0).toDouble(),
        progressionId: json['p'] as String?,
        userCells:
            json['u'] is Map ? _cellsFromJson((json['u'] as Map)['c']) : null,
        userInstrument:
            json['u'] is Map ? (json['u'] as Map)['i'] as String? : null,
        beatRows: _beatRowsFromJson(json['b']),
      );

  /// Compact json (defaults omitted) — the share token payload.
  Map<String, dynamic> toJson() => {
        'e': enabled.toList()..sort(),
        if (variants.values.any((v) => v != 0))
          'v': {
            for (final e in variants.entries)
              if (e.value != 0) e.key: e.value,
          },
        if (levels.values.any((l) => l != 1.0))
          'l': {
            for (final e in levels.entries)
              if (e.value != 1.0)
                e.key: double.parse(e.value.toStringAsFixed(2)),
          },
        't': tempoBpm,
        if (swing != 0) 's': double.parse(swing.toStringAsFixed(2)),
        if (progressionId != null) 'p': progressionId,
        if (userCells != null)
          'u': {
            'c': _cellsToJson(userCells!),
            if (userInstrument != null) 'i': userInstrument,
          },
        if (beatRows != null)
          'b': {
            for (final e in beatRows!.entries) e.key.name: rowToString(e.value),
          },
      };

  /// Canonical identity — the render-cache key.
  String get cacheKey => jsonEncode(toJson());
}

List<dynamic> _cellsToJson(List<PatternCell> cells) => [
      for (final c in cells) [c.midis, c.steps],
    ];

/// Parses cells from token json; null on any structural violation (foreign
/// tokens must never crash or smuggle absurd data in).
List<PatternCell>? _cellsFromJson(dynamic json) {
  if (json is! List) return null;
  final cells = <PatternCell>[];
  var total = 0;
  for (final entry in json) {
    if (entry is! List || entry.length != 2) return null;
    final [midisRaw, steps] = entry;
    if (steps is! int || steps < 1) return null;
    List<int>? midis;
    if (midisRaw != null) {
      if (midisRaw is! List) return null;
      midis = [];
      for (final m in midisRaw) {
        if (m is! int || m < 0 || m > 127) return null;
        midis.add(m);
      }
    }
    cells.add((midis: midis, steps: steps));
    total += steps;
  }
  return total == kPatternSteps ? cells : null;
}

/// Parses beat rows from token json; null on any structural violation.
Map<Drum, List<bool>>? _beatRowsFromJson(dynamic json) {
  if (json is! Map) return null;
  final rows = <Drum, List<bool>>{};
  for (final MapEntry(:key, :value) in json.entries) {
    final drum = Drum.values.asNameMap()[key];
    if (drum == null || value is! String || value.length != kPatternSteps) {
      return null;
    }
    rows[drum] = stepRow(value);
  }
  return rows.isEmpty ? null : rows;
}

/// Groove share token: `KU1.` + url-safe base64 of the spec's compact json.
/// Small enough to paste into any chat, fully serverless (matches the app's
/// everything-on-device stance).
String encodeGrooveToken(GrooveSpec spec) =>
    'KU1.${base64UrlEncode(utf8.encode(jsonEncode(spec.toJson())))}';

/// Parses a share token back to a [GrooveSpec]; null for anything invalid
/// (wrong prefix, broken base64/json) — never throws on foreign input.
GrooveSpec? decodeGrooveToken(String token) {
  final trimmed = token.trim();
  if (!trimmed.startsWith('KU1.')) return null;
  try {
    final json = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(trimmed.substring(4)))),
    );
    if (json is! Map<String, dynamic>) return null;
    return GrooveSpec.fromJson(json);
  } catch (_) {
    return null;
  }
}

// --- The authored content: everything in C pentatonic (C D E G A) ---

const _c2 = 36, _e2 = 40, _g2 = 43, _a2 = 45, _c3 = 48, _g3 = 55, _a3 = 57;
const _c4 = 60, _d4 = 62, _e4 = 64, _g4 = 67, _a4 = 69;
const _g5 = 79, _a5 = 81, _c6 = 84;

const _aMin = [_a3, _c4, _e4];
const _cMaj = [_c4, _e4, _g4];

/// The Loop Mixer's built-in band. Order = display order on the screen.
final List<LoopTrack> kLoopMixerTracks = [
  LoopTrack(
    id: 'drums',
    gain: 0.50,
    variants: [
      // A — straight backbeat with a pickup kick leaning into the wrap.
      DrumRowsPattern({
        Drum.kick: stepRow('x...x...x...x..x'),
        Drum.snare: stepRow('..x...x...x...x.'),
        Drum.hat: stepRow('.x.x.x.x.x.x.x.x'),
      }),
      // B — euclidean kick E(3,8) per bar under running hats.
      DrumRowsPattern({
        Drum.kick: [
          ...euclid(3, 8, rotation: 2),
          ...euclid(3, 8, rotation: 2),
        ],
        Drum.snare: stepRow('....x.......x...'),
        Drum.hat: stepRow('xxxxxxxxxxxxxxxx'),
      }),
      // C — half-time: wide kick/snare, quarter-note hats.
      DrumRowsPattern({
        Drum.kick: stepRow('x.........x.....'),
        Drum.snare: stepRow('........x.......'),
        Drum.hat: stepRow('x.x.x.x.x.x.x.x.'),
      }),
    ],
  ),
  const LoopTrack(
    id: 'bass',
    gain: 0.55,
    // In progression mode the bass re-voices per chord: root motion (A),
    // octave pump (B), syncopated root+fifth (C) — mirrors the vamp variants.
    chordFollower: ChordFollower(
      instrument: Instrument.cello,
      baseMidi: 36, // C2 register
      foldAbove: 45, // keep every root at or below A2
      bars: [
        ChordBar([
          (tones: [0], steps: 2),
          (tones: [0], steps: 2),
          (tones: [2], steps: 2),
          (tones: [0], steps: 2),
        ]),
        ChordBar([
          (tones: [0], steps: 1),
          (tones: [3], steps: 1),
          (tones: [0], steps: 1),
          (tones: [3], steps: 1),
          (tones: [0], steps: 1),
          (tones: [3], steps: 1),
          (tones: [0], steps: 1),
          (tones: [3], steps: 1),
        ]),
        ChordBar([
          (tones: [0], steps: 3),
          (tones: null, steps: 1),
          (tones: [2], steps: 2),
          (tones: [0], steps: 2),
        ]),
      ],
    ),
    variants: [
      // A — root-motion quarters.
      MelodicPattern(Instrument.cello, [
        (midis: [_c2], steps: 2),
        (midis: [_c2], steps: 2),
        (midis: [_g2], steps: 2),
        (midis: [_a2], steps: 2),
        (midis: [_e2], steps: 2),
        (midis: [_g2], steps: 2),
        (midis: [_a2], steps: 2),
        (midis: [_g2], steps: 2),
      ]),
      // B — octave-pump eighths.
      MelodicPattern(Instrument.cello, [
        (midis: [_c2], steps: 1),
        (midis: [_c3], steps: 1),
        (midis: [_c2], steps: 1),
        (midis: [_c3], steps: 1),
        (midis: [_g2], steps: 1),
        (midis: [_g3], steps: 1),
        (midis: [_a2], steps: 1),
        (midis: [_a3], steps: 1),
        (midis: [_a2], steps: 1),
        (midis: [_a3], steps: 1),
        (midis: [_a2], steps: 1),
        (midis: [_a3], steps: 1),
        (midis: [_g2], steps: 1),
        (midis: [_g3], steps: 1),
        (midis: [_e2], steps: 1),
        (midis: [_g2], steps: 1),
      ]),
      // C — syncopated dotted-quarter feel.
      MelodicPattern(Instrument.cello, [
        (midis: [_c2], steps: 3),
        (midis: null, steps: 1),
        (midis: [_g2], steps: 2),
        (midis: [_a2], steps: 2),
        (midis: [_c2], steps: 3),
        (midis: null, steps: 1),
        (midis: [_a2], steps: 2),
        (midis: [_g2], steps: 2),
      ]),
    ],
  ),
  const LoopTrack(
    id: 'chords',
    gain: 0.30,
    // Progression mode: the pad/stabs/arpeggio re-voice on each chord.
    chordFollower: ChordFollower(
      instrument: Instrument.flute,
      baseMidi: 60, // C4 register
      foldAbove: 67, // vi folds down to A3, like the authored vamp voicing
      bars: [
        ChordBar([
          (tones: [0, 1, 2], steps: 8),
        ]),
        ChordBar([
          (tones: null, steps: 1),
          (tones: [0, 1, 2], steps: 1),
          (tones: null, steps: 2),
          (tones: [0, 1, 2], steps: 1),
          (tones: null, steps: 3),
        ]),
        ChordBar([
          (tones: [0], steps: 1),
          (tones: [1], steps: 1),
          (tones: [2], steps: 1),
          (tones: [1], steps: 1),
          (tones: [0], steps: 1),
          (tones: [1], steps: 1),
          (tones: [2], steps: 1),
          (tones: [1], steps: 1),
        ]),
      ],
    ),
    variants: [
      // A — held pads: C major, then A minor.
      MelodicPattern(Instrument.flute, [
        (midis: _cMaj, steps: 8),
        (midis: _aMin, steps: 8),
      ]),
      // B — off-beat stabs.
      MelodicPattern(Instrument.piano, [
        (midis: null, steps: 1),
        (midis: _cMaj, steps: 1),
        (midis: null, steps: 2),
        (midis: _cMaj, steps: 1),
        (midis: null, steps: 3),
        (midis: null, steps: 1),
        (midis: _aMin, steps: 1),
        (midis: null, steps: 2),
        (midis: _aMin, steps: 1),
        (midis: null, steps: 3),
      ]),
      // C — arpeggiated eighths.
      MelodicPattern(Instrument.piano, [
        (midis: [_c4], steps: 1),
        (midis: [_e4], steps: 1),
        (midis: [_g4], steps: 1),
        (midis: [_e4], steps: 1),
        (midis: [_c4], steps: 1),
        (midis: [_e4], steps: 1),
        (midis: [_g4], steps: 1),
        (midis: [_e4], steps: 1),
        (midis: [_a3], steps: 1),
        (midis: [_c4], steps: 1),
        (midis: [_e4], steps: 1),
        (midis: [_c4], steps: 1),
        (midis: [_a3], steps: 1),
        (midis: [_c4], steps: 1),
        (midis: [_e4], steps: 1),
        (midis: [_c4], steps: 1),
      ]),
    ],
  ),
  const LoopTrack(
    id: 'melody',
    gain: 0.40,
    variants: [
      // A — the v1 riff.
      MelodicPattern(Instrument.piano, [
        (midis: [_e4], steps: 1),
        (midis: [_g4], steps: 1),
        (midis: [_a4], steps: 1),
        (midis: null, steps: 1),
        (midis: [_g4], steps: 1),
        (midis: [_e4], steps: 1),
        (midis: [_d4], steps: 2),
        (midis: [_c4], steps: 1),
        (midis: [_d4], steps: 1),
        (midis: [_e4], steps: 1),
        (midis: [_g4], steps: 1),
        (midis: [_a4], steps: 2),
        (midis: [_g4], steps: 1),
        (midis: [_e4], steps: 1),
      ]),
      // B — an answering phrase with held notes.
      MelodicPattern(Instrument.piano, [
        (midis: [_g4], steps: 2),
        (midis: [_a4], steps: 1),
        (midis: [_g4], steps: 1),
        (midis: [_e4], steps: 2),
        (midis: [_d4], steps: 2),
        (midis: [_e4], steps: 1),
        (midis: [_d4], steps: 1),
        (midis: [_c4], steps: 2),
        (midis: [_d4], steps: 2),
        (midis: [_e4], steps: 2),
      ]),
      // C — a sparse call.
      MelodicPattern(Instrument.piano, [
        (midis: [_e4], steps: 1),
        (midis: null, steps: 3),
        (midis: [_g4], steps: 1),
        (midis: null, steps: 3),
        (midis: [_a4], steps: 1),
        (midis: null, steps: 3),
        (midis: [_g4], steps: 1),
        (midis: null, steps: 3),
      ]),
    ],
  ),
  LoopTrack(
    id: 'sparkle',
    gain: 0.28,
    variants: [
      // A — rare high dings.
      const MelodicPattern(Instrument.musicBox, [
        (midis: null, steps: 2),
        (midis: [_c6], steps: 1),
        (midis: null, steps: 3),
        (midis: [_a5], steps: 1),
        (midis: null, steps: 1),
        (midis: null, steps: 2),
        (midis: [_g5], steps: 1),
        (midis: null, steps: 3),
        (midis: [_c6], steps: 1),
        (midis: null, steps: 1),
      ]),
      // B — a running high arpeggio.
      MelodicPattern(Instrument.musicBox, [
        for (var i = 0; i < 4; i++) ...const [
          (midis: [_c6], steps: 1),
          (midis: [_a5], steps: 1),
          (midis: [_g5], steps: 1),
          (midis: [_a5], steps: 1),
        ],
      ]),
      // C — one ding per bar.
      const MelodicPattern(Instrument.musicBox, [
        (midis: null, steps: 7),
        (midis: [_c6], steps: 1),
        (midis: null, steps: 7),
        (midis: [_g5], steps: 1),
      ]),
    ],
  ),
];

/// The drum fill that replaces the drum track every 4th loop (any variant):
/// bar 1 stays a groove, bar 2 opens up and lands a snare run into the wrap.
final DrumRowsPattern kDrumFillPattern = DrumRowsPattern({
  Drum.kick: stepRow('x...x...x.......'),
  Drum.snare: stepRow('..x...x...x.xxxx'),
  Drum.hat: stepRow('.x.x.x.x.x.x....'),
});

/// How a live note relates to the groove's harmony (jam mode feedback).
enum JamFit { chordTone, scaleTone, outside }

/// Holds the groove state and renders the current spec to a loopable WAV.
class LoopEngine {
  LoopEngine({List<LoopTrack>? tracks, int tempoBpm = 100})
      : _baseTracks = tracks ?? kLoopMixerTracks,
        // The field initializer bypasses the clamping setter, so clamp here too.
        _tempoBpm = tempoBpm < kMinTempoBpm
            ? kMinTempoBpm
            : (tempoBpm > kMaxTempoBpm ? kMaxTempoBpm : tempoBpm);

  /// The sung layer's track id.
  static const userTrackId = 'voice';

  /// The beatboxed layer's track id.
  static const beatTrackId = 'beat';

  final List<LoopTrack> _baseTracks;
  LoopTrack? _userTrack;
  LoopTrack? _userBeatTrack;

  /// The built-in band plus the captured user tracks (voice / beatbox).
  List<LoopTrack> get tracks => [
        ..._baseTracks,
        if (_userTrack != null) _userTrack!,
        if (_userBeatTrack != null) _userBeatTrack!,
      ];

  /// Installs (or replaces) the beatboxed layer from a captured pattern
  /// (beat_capture.dart) — a normal drum track from here on.
  void setUserBeatTrack(DrumRowsPattern pattern) {
    _userBeatTrack = LoopTrack(
      id: beatTrackId,
      gain: 0.5,
      variants: [pattern],
    );
    _clearRenderCaches();
  }

  void clearUserBeatTrack() {
    _userBeatTrack = null;
    enabled.remove(beatTrackId);
    _clearRenderCaches();
  }

  /// Installs (or replaces) the sung layer from captured cells
  /// (groove_capture.dart) — a normal track from here on: toggleable,
  /// level-able, engraved, tokenized.
  void setUserTrack(
    List<PatternCell> cells, {
    Instrument instrument = Instrument.flute,
  }) {
    _userTrack = LoopTrack(
      id: userTrackId,
      gain: 0.5,
      variants: [MelodicPattern(instrument, cells)],
    );
    _clearRenderCaches();
  }

  void clearUserTrack() {
    _userTrack = null;
    enabled.remove(userTrackId);
    _clearRenderCaches();
  }

  final Set<String> enabled = {};

  /// Active variant index per track (missing = 0 = variant A).
  final Map<String, int> variants = {};

  /// Per-track level 0..1 multiplied onto the authored gain (missing = 1).
  final Map<String, double> levels = {};

  int _tempoBpm;
  int get tempoBpm => _tempoBpm;
  set tempoBpm(int bpm) {
    // Clamped like [swing]: `beatMs` divides by this, so 0/negative/absurd
    // values break the timing math rather than just sounding odd. See
    // [kMinTempoBpm].
    final clamped = bpm.clamp(kMinTempoBpm, kMaxTempoBpm);
    if (clamped == _tempoBpm) return;
    _tempoBpm = clamped;
    _clearRenderCaches();
  }

  double _swing = 0;
  double get swing => _swing;
  set swing(double value) {
    final clamped = value.clamp(0.0, 0.6);
    if (clamped == _swing) return;
    _swing = clamped;
    _clearRenderCaches();
  }

  Progression? _progression;
  Progression? get progression => _progression;

  /// null = the free 2-bar vamp; a [kProgressions] entry = a 4-bar song loop
  /// where chord-following tracks re-voice per bar.
  set progression(Progression? value) {
    if (value?.id == _progression?.id) return;
    assert(
      value == null || value.degrees.length == 4,
      'progressions are one bar per chord × 4',
    );
    _progression = value;
    _clearRenderCaches();
  }

  LoopTiming get timing => LoopTiming(
        tempoBpm: _tempoBpm,
        swing: _swing,
        bars: _progression == null ? 2 : _progression!.degrees.length,
      );

  /// The 2-bar grid authored patterns render on (tiled in progression mode).
  LoopTiming get _vampTiming => LoopTiming(tempoBpm: _tempoBpm, swing: _swing);

  /// Snapshot of the whole groove (serializable — share token, save slots).
  GrooveSpec get spec => GrooveSpec(
        enabled: {...enabled},
        variants: {...variants},
        levels: {...levels},
        tempoBpm: _tempoBpm,
        swing: _swing,
        progressionId: _progression?.id,
        userCells: (_userTrack?.variants.first as MelodicPattern?)?.cells,
        userInstrument: _userTrack == null
            ? null
            : (_userTrack!.variants.first as MelodicPattern).instrument.name,
        beatRows: (_userBeatTrack?.variants.first as DrumRowsPattern?)?.rows,
      );

  /// Restores a snapshot (unknown track ids are dropped defensively).
  void applySpec(GrooveSpec next) {
    // Install the sung layer first so 'voice' counts as a known id below.
    final userCells = next.userCells;
    if (userCells != null) {
      setUserTrack(
        userCells,
        instrument: Instrument.values.asNameMap()[next.userInstrument] ??
            Instrument.flute,
      );
    } else {
      _userTrack = null;
    }
    final beatRows = next.beatRows;
    if (beatRows != null) {
      setUserBeatTrack(DrumRowsPattern(beatRows));
    } else {
      _userBeatTrack = null;
    }
    final known = tracks.map((t) => t.id).toSet();
    enabled
      ..clear()
      ..addAll(next.enabled.where(known.contains));
    variants
      ..clear()
      ..addAll({
        for (final e in next.variants.entries)
          if (known.contains(e.key)) e.key: e.value,
      });
    levels
      ..clear()
      ..addAll({
        for (final e in next.levels.entries)
          if (known.contains(e.key)) e.key: e.value.clamp(0.0, 1.0),
      });
    tempoBpm = next.tempoBpm;
    swing = next.swing;
    Progression? found;
    for (final p in kProgressions) {
      if (p.id == next.progressionId) found = p;
    }
    progression = found;
  }

  // Rendered stems per (track, variant) at the current tempo/swing, and
  // mixed WAVs per spec — synthesis is the expensive part, so a re-toggle
  // or a variant flip back is instant.
  final Map<String, Float64List> _stemCache = {};
  final Map<String, Uint8List> _wavCache = {};

  void _clearRenderCaches() {
    _stemCache.clear();
    _wavCache.clear();
  }

  /// A master send effect on the whole mix (a live control; not persisted in the
  /// spec/share token). Different sends cache to different WAV keys.
  LoopSend send = LoopSend.none;

  /// Applies the [send] effect to a mixed [pcm] via a Float64 round-trip.
  Int16List _applySend(Int16List pcm) {
    if (send == LoopSend.none) return pcm;
    final f = Float64List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      f[i] = pcm[i] / 32768.0;
    }
    final wet = switch (send) {
      LoopSend.reverb => reverbFx(f, mix: 0.28),
      LoopSend.delay => delayFx(f, delayMs: 300, feedback: 0.3, mix: 0.28),
      LoopSend.none => f,
    };
    final out = Int16List(pcm.length);
    for (var i = 0; i < wet.length && i < out.length; i++) {
      out[i] = (wet[i] * 32768).round().clamp(-32768, 32767);
    }
    return out;
  }

  LoopTrack _track(String id) => tracks.firstWhere((t) => t.id == id);

  /// Toggles [id]; returns true if the track is now enabled.
  bool toggle(String id) {
    assert(tracks.any((t) => t.id == id), 'unknown track "$id"');
    if (!enabled.remove(id)) {
      enabled.add(id);
      return true;
    }
    return false;
  }

  /// Advances [id] to its next pattern variant; returns the new index.
  int cycleVariant(String id) {
    final track = _track(id);
    final next = ((variants[id] ?? 0) + 1) % track.variants.length;
    variants[id] = next;
    return next;
  }

  int _variantOf(LoopTrack track) =>
      (variants[track.id] ?? 0).clamp(0, track.variants.length - 1);

  /// The pitched cells the groove currently plays for [id] (progression-
  /// resolved and tiled in progression mode), or null for unpitched patterns.
  /// Powers the live engraving.
  List<PatternCell>? cellsFor(String id) {
    final track = _track(id);
    final variant = _variantOf(track);
    final prog = _progression;
    if (prog != null && track.chordFollower != null) {
      final follower = track.chordFollower!;
      final bar = follower.bars[variant.clamp(0, follower.bars.length - 1)];
      return [
        for (final degree in prog.degrees)
          ...bar.resolve(
            degree,
            baseMidi: follower.baseMidi,
            foldAbove: follower.foldAbove,
          ),
      ];
    }
    final pattern = track.variants[variant];
    if (pattern is! MelodicPattern) return null;
    if (prog == null) return pattern.cells;
    return [
      for (var r = 0; r < prog.degrees.length ~/ 2; r++) ...pattern.cells,
    ];
  }

  Float64List _stemFor(LoopTrack track) {
    final variant = _variantOf(track);
    final key = '${track.id}#$variant#${_progression?.id ?? 'vamp'}';
    return _stemCache[key] ??= _renderStem(track, variant);
  }

  Float64List _renderStem(LoopTrack track, int variant) {
    final prog = _progression;
    if (prog == null) return track.variants[variant].render(timing);

    final follower = track.chordFollower;
    if (follower != null) {
      // Re-voice the bar shape on each progression chord.
      final bar = follower.bars[variant.clamp(0, follower.bars.length - 1)];
      return renderCells(
        [
          for (final degree in prog.degrees)
            ...bar.resolve(
              degree,
              baseMidi: follower.baseMidi,
              foldAbove: follower.foldAbove,
            ),
        ],
        follower.instrument,
        timing,
      );
    }

    // Everything else tiles its 2-bar pattern across the progression —
    // exact, because the swung step grid is periodic per bar.
    final twoBars = track.variants[variant].render(_vampTiming);
    final reps = prog.degrees.length ~/ 2;
    final out = Float64List(twoBars.length * reps);
    for (var r = 0; r < reps; r++) {
      out.setAll(r * twoBars.length, twoBars);
    }
    return out;
  }

  /// The current groove as one loop-ready WAV (an empty enabled set renders
  /// silence of the full loop length). With [fill], the drum track (if
  /// enabled) plays [kDrumFillPattern] instead of its variant — the seam
  /// scheduler uses this every 4th loop.
  Uint8List renderLoop({bool fill = false}) {
    final filling = fill && enabled.contains('drums');
    final sendKey = send == LoopSend.none ? '' : '#send:${send.name}';
    final key = '${spec.cacheKey}${filling ? '#fill' : ''}$sendKey';
    return _wavCache[key] ??= wavBytes(
      _applySend(
        mixStems(
          [
            for (final track in tracks)
              if (enabled.contains(track.id))
                (
                  samples: filling && track.id == 'drums'
                      ? _fillStemFor(track)
                      : _stemFor(track),
                  gain: track.gain * (levels[track.id] ?? 1.0).clamp(0.0, 1.0),
                ),
          ],
          totalSamples: timing.totalSamples,
        ),
      ),
    );
  }

  // --- Jam mode: harmony fit for a live played/sung note ---

  /// The chord sounding in bar [bar] of the loop: the progression's degree,
  /// or the vamp's C↔Am alternation.
  ChordDegree chordAtBar(int bar) {
    final prog = _progression;
    if (prog != null) return prog.degrees[bar % prog.degrees.length];
    return bar.isEven ? ChordDegree.i : ChordDegree.vi;
  }

  /// How a played/sung [midi] fits the groove at [bar]: a tone of the
  /// sounding chord, a C-pentatonic scale tone, or outside.
  JamFit jamFit(int midi, {required int bar}) {
    final degree = chordAtBar(bar);
    final pc = midi % 12;
    for (final interval in degree.triad) {
      if ((degree.rootOffset + interval) % 12 == pc) return JamFit.chordTone;
    }
    if (const [0, 2, 4, 7, 9].contains(pc)) return JamFit.scaleTone;
    return JamFit.outside;
  }

  // --- Infinite mode: seeded per-iteration variation ---

  /// Renders the groove with a deterministic per-[iteration] mutation:
  /// hats drop in and out, snare ghosts appear, and 2-step melody notes
  /// occasionally split into an ornament with a pentatonic neighbour. Same
  /// (spec, iteration) → identical bytes (the seam scheduler relies on it);
  /// bass/chords/sparkle reuse their cached stems, so the per-seam cost is
  /// one drum placement + at most one melody render.
  Uint8List renderVariedLoop(int iteration, {bool fill = false}) {
    if (enabled.isEmpty) return renderLoop();
    final rng = Random(spec.cacheKey.hashCode ^ (iteration * 2654435761));
    final filling = fill && enabled.contains('drums');
    return wavBytes(
      _applySend(
        mixStems(
          [
            for (final track in tracks)
              if (enabled.contains(track.id))
                (
                  samples: switch (track.id) {
                    'drums' => filling
                        ? _fillStemFor(track)
                        : _variedDrumStem(track, rng),
                    'melody' => _variedMelodyStem(track, rng),
                    _ => _stemFor(track),
                  },
                  gain: track.gain * (levels[track.id] ?? 1.0).clamp(0.0, 1.0),
                ),
          ],
          totalSamples: timing.totalSamples,
        ),
      ),
    );
  }

  Float64List _variedDrumStem(LoopTrack track, Random rng) {
    final pattern = track.variants[_variantOf(track)];
    if (pattern is! DrumRowsPattern) return _stemFor(track);
    final varied = <Drum, List<bool>>{
      for (final MapEntry(key: drum, value: row) in pattern.rows.entries)
        drum: [
          for (var step = 0; step < row.length; step++)
            switch (drum) {
              // The kick anchors the groove — never mutated.
              Drum.kick => row[step],
              // Hats breathe: drop some, sprinkle new ones on off-eighths.
              Drum.hat => row[step]
                  ? rng.nextDouble() > 0.18
                  : step.isOdd && rng.nextDouble() < 0.12,
              // Occasional snare ghosts on the bar's back half.
              Drum.snare => row[step] ||
                  (step % LoopTiming.stepsPerBar >= 5 &&
                      !row[step] &&
                      rng.nextDouble() < 0.06),
            },
        ],
    };
    final stem = DrumRowsPattern(varied).render(_vampTiming);
    final prog = _progression;
    if (prog == null) return stem;
    final reps = prog.degrees.length ~/ 2;
    final out = Float64List(stem.length * reps);
    for (var r = 0; r < reps; r++) {
      out.setAll(r * stem.length, stem);
    }
    return out;
  }

  // C-pentatonic pitch classes, for ornament neighbours.
  static const _pentatonic = [0, 2, 4, 7, 9];

  int _pentatonicNeighbour(int midi, Random rng) {
    final up = rng.nextBool();
    for (var candidate = midi + (up ? 1 : -1);
        (candidate - midi).abs() <= 4;
        candidate += up ? 1 : -1) {
      if (_pentatonic.contains(candidate % 12)) return candidate;
    }
    return midi;
  }

  Float64List _variedMelodyStem(LoopTrack track, Random rng) {
    final cells = cellsFor(track.id);
    final pattern = track.variants[_variantOf(track)];
    if (cells == null || pattern is! MelodicPattern) return _stemFor(track);
    final varied = <PatternCell>[
      for (final cell in cells)
        if (cell.midis?.length == 1 &&
            cell.steps == 2 &&
            rng.nextDouble() < 0.35) ...[
          // Split a 2-step note into note + pentatonic neighbour ornament.
          (midis: cell.midis, steps: 1),
          (
            midis: [_pentatonicNeighbour(cell.midis!.single, rng)],
            steps: 1,
          ),
        ] else
          cell,
    ];
    return renderCells(varied, pattern.instrument, timing);
  }

  /// The drum stem for a fill iteration. Vamp mode: the 2-bar fill pattern.
  /// Progression mode: bars 1–2 keep the groove, bars 3–4 play the fill —
  /// a real mini-arrangement instead of filling every other bar.
  Float64List _fillStemFor(LoopTrack track) {
    final prog = _progression;
    if (prog == null) {
      return _stemCache['drums#fill#vamp'] ??= kDrumFillPattern.render(timing);
    }
    final variant = _variantOf(track);
    return _stemCache['drums#fill#$variant#${prog.id}'] ??= () {
      final groove = track.variants[variant].render(_vampTiming);
      final fill = kDrumFillPattern.render(_vampTiming);
      final out = Float64List(groove.length + fill.length);
      out
        ..setAll(0, groove)
        ..setAll(groove.length, fill);
      return out;
    }();
  }
}
