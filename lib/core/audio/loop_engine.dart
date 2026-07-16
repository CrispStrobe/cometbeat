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
import 'dart:typed_data';

import 'package:klang_universum/core/audio/synth.dart';

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
  });

  final Set<String> enabled;
  final Map<String, int> variants;
  final Map<String, double> levels;
  final int tempoBpm;
  final double swing;

  /// A [kProgressions] id, or null for the free 2-bar vamp.
  final String? progressionId;

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
        tempoBpm: (json['t'] as num? ?? 100).toInt(),
        swing: (json['s'] as num? ?? 0).toDouble(),
        progressionId: json['p'] as String?,
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
      };

  /// Canonical identity — the render-cache key.
  String get cacheKey => jsonEncode(toJson());
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

/// Holds the groove state and renders the current spec to a loopable WAV.
class LoopEngine {
  LoopEngine({List<LoopTrack>? tracks, int tempoBpm = 100})
      : tracks = tracks ?? kLoopMixerTracks,
        _tempoBpm = tempoBpm;

  final List<LoopTrack> tracks;
  final Set<String> enabled = {};

  /// Active variant index per track (missing = 0 = variant A).
  final Map<String, int> variants = {};

  /// Per-track level 0..1 multiplied onto the authored gain (missing = 1).
  final Map<String, double> levels = {};

  int _tempoBpm;
  int get tempoBpm => _tempoBpm;
  set tempoBpm(int bpm) {
    if (bpm == _tempoBpm) return;
    _tempoBpm = bpm;
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
      );

  /// Restores a snapshot (unknown track ids are dropped defensively).
  void applySpec(GrooveSpec next) {
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
    final key = '${spec.cacheKey}${filling ? '#fill' : ''}';
    return _wavCache[key] ??= wavBytes(
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
    );
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
