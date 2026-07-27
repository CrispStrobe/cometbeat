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

import 'package:comet_beat/core/audio/crisp_dsp/biquad.dart';
import 'package:comet_beat/core/audio/crisp_dsp/modulated_delay.dart';
import 'package:comet_beat/core/audio/crisp_dsp/reverb.dart';
import 'package:comet_beat/core/audio/fx/fx_chain.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/loop_automation.dart';
import 'package:comet_beat/core/audio/loop_instrument_render.dart'
    show renderCellsWithInstrument;
import 'package:comet_beat/core/audio/loop_track_length.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:comet_beat/core/audio/tracker_instrument_codec.dart'
    show instrumentFromJson, instrumentToJson, isSerializableInstrument;
import 'package:comet_beat/core/audio/wav_io.dart';

/// An optional master send effect on the whole Loop Mixer output.
enum LoopSend { none, reverb, delay }

/// A5 — the two loop sends expressed in the shared [FxSpec] model, so a send
/// authored here can travel to the Audio Editor, Tracker, Instrument Builder or
/// Tab (and be tweaked or automated on the way).
///
/// Reproduces `_applySend`'s hardcoded params EXACTLY; `loop_send_fx_test.dart`
/// asserts that sample-for-sample. [LoopSend.none] has no spec — an empty chain
/// is dry.
FxSpec? fxForLoopSend(LoopSend send) => switch (send) {
      LoopSend.none => null,
      // No 'decay' key: reverbFx falls back to roomSize when it is absent, and
      // roomSize 0.6 / damping 0.4 are reverbFx's own defaults, which is what
      // `reverbFx(f, mix: 0.28)` has always used.
      LoopSend.reverb => const FxSpec(
          type: FxType.reverb,
          params: {'roomSize': 0.6, 'damping': 0.4, 'mix': 0.28},
        ),
      LoopSend.delay => const FxSpec(
          type: FxType.delay,
          params: {'delayMs': 300, 'feedback': 0.3, 'mix': 0.28},
        ),
    };

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

  // Snapped to the 10 ms grid: at 44.1 kHz a duration is a whole number of
  // samples iff its ms value is a multiple of 10 (ms × 44.1), and stepMs
  // (300/250/400) already is. Keeping the swing offset on the same grid makes
  // EVERY boundary land on an exact sample — otherwise a swung eighth truncates
  // up to one sample in renderSegmentsRaw and stems of different patterns drift
  // apart (measured ≤8 samples), breaking the sample-integrality invariant this
  // class promises. The ≤5 ms snap of the swing amount is imperceptible.
  int get _swingMs => (stepMs * swing / 10).round() * 10;

  /// Millisecond onset of [step] (0..[totalSteps] inclusive): odd eighths
  /// start late by the swing amount. Durations derived from boundary
  /// differences always sum back to [totalMs], and every boundary is an exact
  /// sample (see [_swingMs]).
  int boundaryMs(int step) => step * stepMs + (step.isOdd ? _swingMs : 0);
}

/// The step length every authored [LoopPattern] fills: the 2-bar vamp grid.
const kPatternSteps = LoopTiming.stepsPerBar * 2;

/// One melodic pattern cell: [midis] sounding for [steps] eighth-steps
/// (null or empty = rest). [velocity] is per-note dynamics 0..1 (1 = normal) —
/// soft/accent editing in the tune grid; it scales the note's synthesis gain.
///
/// Was a `({midis, steps})` record; promoted to a class to carry [velocity]
/// (and any future per-note attribute) while keeping value equality.
class PatternCell {
  const PatternCell({this.midis, required this.steps, this.velocity = 1.0});

  final List<int>? midis;
  final int steps;
  final double velocity;

  PatternCell copyWith({List<int>? midis, int? steps, double? velocity}) =>
      PatternCell(
        midis: midis ?? this.midis,
        steps: steps ?? this.steps,
        velocity: velocity ?? this.velocity,
      );

  @override
  bool operator ==(Object other) =>
      other is PatternCell &&
      other.steps == steps &&
      other.velocity == velocity &&
      _patternMidisEqual(other.midis, midis);

  @override
  int get hashCode =>
      Object.hash(steps, velocity, Object.hashAll(midis ?? const <int>[]));
}

bool _patternMidisEqual(List<int>? a, List<int>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A track's pattern for one 2-bar loop — data, renderable onto any timing.
sealed class LoopPattern {
  const LoopPattern();

  /// Render onto [timing]; pitched patterns shift every note by [transpose]
  /// semitones (drums ignore it), drum patterns render in [kit]'s timbre
  /// (pitched patterns ignore it).
  Float64List render(
    LoopTiming timing, {
    int transpose = 0,
    DrumKit kit = kDrumKitClean,
  });
}

/// A pitched pattern: cells laid back-to-back on the step grid.
class MelodicPattern extends LoopPattern {
  const MelodicPattern(this.instrument, this.cells);

  final Instrument instrument;

  /// Cell step counts must sum to [LoopTiming.totalSteps].
  final List<PatternCell> cells;

  @override
  Float64List render(
    LoopTiming timing, {
    int transpose = 0,
    DrumKit kit = kDrumKitClean,
  }) {
    assert(
      cells.fold<int>(0, (sum, c) => sum + c.steps) == kPatternSteps,
      'pattern must fill the 2-bar grid exactly',
    );
    return renderCells(cells, instrument, timing, transpose: transpose);
  }
}

/// Renders pitched [cells] back-to-back on [timing]'s step grid (any length —
/// the progression path renders 4 bars, authored patterns 2). Cell durations
/// come from boundary differences, so swing is applied and totals stay exact.
Float64List renderCells(
  List<PatternCell> cells,
  Instrument instrument,
  LoopTiming timing, {
  int transpose = 0,
}) {
  var step = 0;
  final segments = <Segment>[];
  for (final cell in cells) {
    segments.add(
      (
        freqs: [
          for (final m in cell.midis ?? const <int>[])
            midiToFrequency(m + transpose),
        ],
        ms: timing.boundaryMs(step + cell.steps) - timing.boundaryMs(step),
      ),
    );
    step += cell.steps;
  }
  final buffer = renderSegmentsRaw(segments, timbre: timbreFor(instrument));
  applyCellVelocities(buffer, cells, segments);
  return buffer;
}

/// Scales each cell's rendered samples by its [PatternCell.velocity] (per-note
/// dynamics). A note softer than its neighbours reads as quieter within the
/// stem; a uniform velocity is a no-op after the mixer's per-stem unit-peak
/// normalization (dynamics are relative). Shared by the plain and instrument
/// render paths so voiced tracks respect velocity too.
void applyCellVelocities(
  Float64List buffer,
  List<PatternCell> cells,
  List<Segment> segments,
) {
  var off = 0;
  for (var i = 0; i < segments.length && i < cells.length; i++) {
    final n = (segments[i].ms * kSampleRate) ~/ 1000;
    final v = cells[i].velocity.clamp(0.0, 1.0);
    if (v != 1.0) {
      final end = off + n < buffer.length ? off + n : buffer.length;
      for (var j = off; j < end; j++) {
        buffer[j] *= v;
      }
    }
    off += n;
  }
}

/// An unpitched pattern: one boolean hit row per drum voice.
class DrumRowsPattern extends LoopPattern {
  const DrumRowsPattern(this.rows, {this.velocities});

  /// Each row has [kPatternSteps] entries.
  final Map<Drum, List<bool>> rows;

  /// Optional per-hit dynamics 0..1 (1 = normal, lower = ghost), parallel to
  /// [rows]. Null (or a missing lane/step) = full — so a plain on/off pattern
  /// is unchanged and pre-accent share tokens/specs stay byte-identical.
  final Map<Drum, List<double>>? velocities;

  double _velAt(Drum drum, int step) {
    final v = velocities?[drum];
    if (v == null || step >= v.length) return 1.0;
    return v[step];
  }

  @override
  Float64List render(
    LoopTiming timing, {
    int transpose = 0,
    DrumKit kit = kDrumKitClean,
  }) {
    final hits = <(int, Drum)>[];
    final gains = <double>[];
    for (final MapEntry(key: drum, value: row) in rows.entries) {
      for (var step = 0; step < row.length; step++) {
        if (row[step]) {
          hits.add((timing.boundaryMs(step), drum));
          gains.add(_velAt(drum, step));
        }
      }
    }
    return renderDrumPattern(
      hits,
      totalMs: timing.totalMs,
      kit: kit,
      gains: gains,
    );
  }
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
  ii(2, [0, 3, 7], 'ii'),
  iii(4, [0, 3, 7], 'iii'),
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
  // A pentatonic melody stays consonant over all of these (the chords are
  // diatonic to C major); labels come from the roman numerals, so no l10n.
  Progression(
    'doowop',
    [ChordDegree.i, ChordDegree.vi, ChordDegree.iv, ChordDegree.v],
  ),
  Progression(
    'fifties',
    [ChordDegree.i, ChordDegree.vi, ChordDegree.ii, ChordDegree.v],
  ),
  Progression(
    'pachelbel',
    [ChordDegree.i, ChordDegree.v, ChordDegree.vi, ChordDegree.iii],
  ),
  Progression(
    'jazz',
    [ChordDegree.ii, ChordDegree.v, ChordDegree.i, ChordDegree.i],
  ),
  Progression(
    'blues',
    [ChordDegree.i, ChordDegree.iv, ChordDegree.i, ChordDegree.v],
  ),
  Progression(
    'emotional',
    [ChordDegree.i, ChordDegree.iii, ChordDegree.vi, ChordDegree.iv],
  ),
  Progression(
    'anthem',
    [ChordDegree.i, ChordDegree.iv, ChordDegree.vi, ChordDegree.v],
  ),
  Progression(
    'dreamy',
    [ChordDegree.iv, ChordDegree.i, ChordDegree.v, ChordDegree.vi],
  ),
  Progression(
    'cycle',
    [ChordDegree.vi, ChordDegree.ii, ChordDegree.v, ChordDegree.i],
  ),
  Progression(
    'rise',
    [ChordDegree.i, ChordDegree.ii, ChordDegree.iii, ChordDegree.iv],
  ),
  Progression(
    'epic',
    [ChordDegree.vi, ChordDegree.v, ChordDegree.iv, ChordDegree.v],
  ),
  Progression(
    'calm',
    [ChordDegree.i, ChordDegree.iii, ChordDegree.iv, ChordDegree.i],
  ),
  Progression(
    'wistful',
    [ChordDegree.vi, ChordDegree.iii, ChordDegree.iv, ChordDegree.i],
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
        PatternCell(
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
/// The pitch collection the pitched stems play in. Minor pentatonic reuses the
/// relative-major set (the same five notes a minor third up), so a groove in
/// minor is a rigid transposition of the authored C-major-pentatonic content —
/// every layer stays consonant for free (the "colour melody" rule).
enum GrooveScale { majorPentatonic, minorPentatonic }

class GrooveSpec {
  const GrooveSpec({
    this.enabled = const {},
    this.variants = const {},
    this.levels = const {},
    this.pans = const {},
    this.tempoBpm = 100,
    this.swing = 0,
    this.progressionId,
    this.key = 0,
    this.scale = GrooveScale.majorPentatonic,
    this.kitId = 'clean',
    this.styleId = 'default',
    this.userCells,
    this.userInstrument,
    this.beatRows,
    this.beatVels,
    this.trackOverrides,
    this.drumOverrides,
    this.drumOverrideVels,
    this.trackVoices,
  });

  final Set<String> enabled;
  final Map<String, int> variants;
  final Map<String, double> levels;

  /// Per-track stereo pan −1..1 (missing/0 = centre). Travels with save slots
  /// and share tokens like [levels].
  final Map<String, double> pans;
  final int tempoBpm;
  final double swing;

  /// Root pitch-class the groove is transposed to (0 = C … 11 = B).
  final int key;

  /// Major or minor pentatonic (minor = the relative-major set, +3 semitones).
  final GrooveScale scale;

  /// The drum-kit timbre id (a [kDrumKits] entry; 'clean' = the synth kit).
  final String kitId;

  /// The band-flavour id (a [kGrooveStyles] entry; 'default' = the original).
  final String styleId;

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

  /// Optional per-hit dynamics for [beatRows] (parallel lists, 1 = normal).
  /// Only serialized when some hit is a ghost, so pre-accent tokens are
  /// byte-identical.
  final Map<Drum, List<double>>? beatVels;

  /// Symbolic edits replacing built-in pitched tracks. These must travel with
  /// save slots and share tokens just like the captured user tracks.
  final Map<String, List<PatternCell>>? trackOverrides;

  /// Edited hit-grids replacing built-in DRUM tracks (e.g. the 'drums' card),
  /// keyed by track id → drum-name → step string. Travels like [trackOverrides].
  final Map<String, Map<Drum, List<bool>>>? drumOverrides;

  /// Optional per-hit dynamics for [drumOverrides] (parallel lists, 1 = normal).
  final Map<String, Map<Drum, List<double>>>? drumOverrideVels;

  /// Serializable per-track instrument overrides. SoundFont references are
  /// intentionally omitted because their source file is not embedded here.
  final Map<String, TrackerInstrument>? trackVoices;

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
        pans: {
          ...(json['pn'] as Map? ?? const {})
              .cast<String, num>()
              .map((k, v) => MapEntry(k, v.toDouble().clamp(-1.0, 1.0))),
        },
        // Untrusted: a hand-edited token must not divide the timing math by 0
        // (or by a negative). Clamped like `levels`/`swing` already are.
        tempoBpm: (json['t'] as num? ?? 100)
            .toInt()
            .clamp(kMinTempoBpm, kMaxTempoBpm),
        swing: (json['s'] as num? ?? 0).toDouble(),
        progressionId: json['p'] as String?,
        // Untrusted token: wrap the root into 0..11 rather than trust it.
        key: (((json['k'] as num? ?? 0).toInt() % 12) + 12) % 12,
        scale: json['sc'] == 'min'
            ? GrooveScale.minorPentatonic
            : GrooveScale.majorPentatonic,
        kitId: json['kt'] as String? ?? 'clean',
        styleId: json['st'] as String? ?? 'default',
        userCells:
            json['u'] is Map ? _cellsFromJson((json['u'] as Map)['c']) : null,
        userInstrument:
            json['u'] is Map ? (json['u'] as Map)['i'] as String? : null,
        beatRows: _beatRowsFromJson(json['b']),
        beatVels: _drumVelsFromJson(json['bv']),
        trackOverrides: _trackOverridesFromJson(json['o']),
        drumOverrides: _drumOverridesFromJson(json['dr']),
        drumOverrideVels: _drumOverrideVelsFromJson(json['drv']),
        trackVoices: _trackVoicesFromJson(json['iv']),
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
        // Omitted at centre so pre-pan `KU1.` tokens stay byte-identical.
        if (pans.values.any((p) => p != 0.0))
          'pn': {
            for (final e in pans.entries)
              if (e.value != 0.0)
                e.key: double.parse(e.value.toStringAsFixed(2)),
          },
        't': tempoBpm,
        if (swing != 0) 's': double.parse(swing.toStringAsFixed(2)),
        if (progressionId != null) 'p': progressionId,
        // Omitted at defaults so pre-key `KU1.` tokens stay byte-identical.
        if (key != 0) 'k': key,
        if (scale == GrooveScale.minorPentatonic) 'sc': 'min',
        if (kitId != 'clean') 'kt': kitId,
        if (styleId != 'default') 'st': styleId,
        if (userCells != null)
          'u': {
            'c': _cellsToJson(userCells!),
            if (userInstrument != null) 'i': userInstrument,
          },
        if (beatRows != null)
          'b': {
            for (final e in beatRows!.entries) e.key.name: rowToString(e.value),
          },
        if (beatVels != null && _drumVelsHaveGhost(beatVels!))
          'bv': _drumVelsToJson(beatVels!),
        if (trackOverrides != null && trackOverrides!.isNotEmpty)
          'o': {
            for (final id in trackOverrides!.keys.toList()..sort())
              id: _cellsToJson(trackOverrides![id]!),
          },
        if (drumOverrides != null && drumOverrides!.isNotEmpty)
          'dr': {
            for (final id in drumOverrides!.keys.toList()..sort())
              id: {
                for (final e in drumOverrides![id]!.entries)
                  e.key.name: rowToString(e.value),
              },
          },
        if (drumOverrideVels != null &&
            drumOverrideVels!.values.any(_drumVelsHaveGhost))
          'drv': {
            for (final id in drumOverrideVels!.keys.toList()..sort())
              if (_drumVelsHaveGhost(drumOverrideVels![id]!))
                id: _drumVelsToJson(drumOverrideVels![id]!),
          },
        if (trackVoices != null && trackVoices!.isNotEmpty)
          'iv': {
            for (final id in trackVoices!.keys.toList()..sort())
              id: instrumentToJson(trackVoices![id]!),
          },
      };

  /// Canonical identity — the render-cache key.
  String get cacheKey => jsonEncode(toJson());
}

List<dynamic> _cellsToJson(List<PatternCell> cells) => [
      // 2-element [midis, steps] at full velocity keeps pre-velocity tokens
      // byte-identical; a soft/accent note adds a 3rd velocity element.
      for (final c in cells)
        if (c.velocity == 1.0)
          [c.midis, c.steps]
        else
          [c.midis, c.steps, double.parse(c.velocity.toStringAsFixed(2))],
    ];

/// Parses cells from token json; null on any structural violation (foreign
/// tokens must never crash or smuggle absurd data in).
List<PatternCell>? _cellsFromJson(dynamic json) {
  if (json is! List) return null;
  final cells = <PatternCell>[];
  var total = 0;
  for (final entry in json) {
    if (entry is! List || entry.length < 2 || entry.length > 3) return null;
    final midisRaw = entry[0];
    final steps = entry[1];
    if (steps is! int || steps < 1) return null;
    var velocity = 1.0;
    if (entry.length == 3) {
      final v = entry[2];
      if (v is num) velocity = v.toDouble().clamp(0.0, 1.0);
    }
    List<int>? midis;
    if (midisRaw != null) {
      if (midisRaw is! List) return null;
      midis = [];
      for (final m in midisRaw) {
        if (m is! int || m < 0 || m > 127) return null;
        midis.add(m);
      }
    }
    cells.add(PatternCell(midis: midis, steps: steps, velocity: velocity));
    total += steps;
  }
  return total == kPatternSteps ? cells : null;
}

/// Parses built-in track overrides; malformed individual entries are ignored
/// so a damaged optional edit cannot invalidate an otherwise usable token.
Map<String, List<PatternCell>>? _trackOverridesFromJson(dynamic json) {
  if (json is! Map) return null;
  final overrides = <String, List<PatternCell>>{};
  for (final MapEntry(:key, :value) in json.entries) {
    if (key is! String || key.isEmpty) continue;
    final cells = _cellsFromJson(value);
    if (cells != null) overrides[key] = cells;
  }
  return overrides.isEmpty ? null : overrides;
}

/// Parses embedded track voices defensively. Unsupported or malformed voices
/// are skipped; a share token must remain usable even if it came from a newer
/// app version with an instrument type this build cannot decode.
Map<String, TrackerInstrument>? _trackVoicesFromJson(dynamic json) {
  if (json is! Map) return null;
  final voices = <String, TrackerInstrument>{};
  for (final MapEntry(:key, :value) in json.entries) {
    if (key is! String || key.isEmpty || value is! Map) continue;
    try {
      voices[key] = instrumentFromJson(value.cast<String, dynamic>());
    } catch (_) {
      // Ignore one unavailable voice rather than rejecting the whole groove.
    }
  }
  return voices.isEmpty ? null : voices;
}

/// True if any lane carries a non-full (ghost/accent) hit — the gate for
/// emitting velocity json at all, so a plain on/off beat stays byte-identical.
bool _drumVelsHaveGhost(Map<Drum, List<double>> vels) =>
    vels.values.any((row) => row.any((v) => v != 1.0));

/// Per-lane velocity lists → json, dropping lanes that are all-normal.
Map<String, dynamic> _drumVelsToJson(Map<Drum, List<double>> vels) => {
      for (final e in vels.entries)
        if (e.value.any((v) => v != 1.0))
          e.key.name: [
            for (final v in e.value) double.parse(v.toStringAsFixed(2)),
          ],
    };

/// Parses per-lane velocity lists from token json; null on structural
/// violation (a foreign token must never crash or smuggle data). Values are
/// clamped to 0..1.
Map<Drum, List<double>>? _drumVelsFromJson(dynamic json) {
  if (json is! Map) return null;
  final out = <Drum, List<double>>{};
  for (final MapEntry(:key, :value) in json.entries) {
    final drum = Drum.values.asNameMap()[key];
    if (drum == null || value is! List) return null;
    out[drum] = [
      for (final v in value)
        if (v is num) v.toDouble().clamp(0.0, 1.0) else 1.0,
    ];
  }
  return out.isEmpty ? null : out;
}

/// Per-track drum-override velocities from token json (id → {drum: [vels]}).
Map<String, Map<Drum, List<double>>>? _drumOverrideVelsFromJson(dynamic json) {
  if (json is! Map) return null;
  final out = <String, Map<Drum, List<double>>>{};
  for (final MapEntry(:key, :value) in json.entries) {
    if (key is! String) return null;
    final vels = _drumVelsFromJson(value);
    if (vels != null) out[key] = vels;
  }
  return out.isEmpty ? null : out;
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

/// Per-track drum overrides from token json (id → {drum: stepString}); null on
/// any structural violation (a foreign token must never crash or smuggle data).
Map<String, Map<Drum, List<bool>>>? _drumOverridesFromJson(dynamic json) {
  if (json is! Map) return null;
  final out = <String, Map<Drum, List<bool>>>{};
  for (final MapEntry(:key, :value) in json.entries) {
    if (key is! String) return null;
    final rows = _beatRowsFromJson(value);
    if (rows != null) out[key] = rows;
  }
  return out.isEmpty ? null : out;
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
      // D — busy syncopated kick under running 16th hats.
      DrumRowsPattern({
        Drum.kick: stepRow('x..x..x.x..x..x.'),
        Drum.snare: stepRow('....x.......x...'),
        Drum.hat: stepRow('xxxxxxxxxxxxxxxx'),
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
        PatternCell(midis: [_c2], steps: 2),
        PatternCell(midis: [_c2], steps: 2),
        PatternCell(midis: [_g2], steps: 2),
        PatternCell(midis: [_a2], steps: 2),
        PatternCell(midis: [_e2], steps: 2),
        PatternCell(midis: [_g2], steps: 2),
        PatternCell(midis: [_a2], steps: 2),
        PatternCell(midis: [_g2], steps: 2),
      ]),
      // B — octave-pump eighths.
      MelodicPattern(Instrument.cello, [
        PatternCell(midis: [_c2], steps: 1),
        PatternCell(midis: [_c3], steps: 1),
        PatternCell(midis: [_c2], steps: 1),
        PatternCell(midis: [_c3], steps: 1),
        PatternCell(midis: [_g2], steps: 1),
        PatternCell(midis: [_g3], steps: 1),
        PatternCell(midis: [_a2], steps: 1),
        PatternCell(midis: [_a3], steps: 1),
        PatternCell(midis: [_a2], steps: 1),
        PatternCell(midis: [_a3], steps: 1),
        PatternCell(midis: [_a2], steps: 1),
        PatternCell(midis: [_a3], steps: 1),
        PatternCell(midis: [_g2], steps: 1),
        PatternCell(midis: [_g3], steps: 1),
        PatternCell(midis: [_e2], steps: 1),
        PatternCell(midis: [_g2], steps: 1),
      ]),
      // C — syncopated dotted-quarter feel.
      MelodicPattern(Instrument.cello, [
        PatternCell(midis: [_c2], steps: 3),
        PatternCell(steps: 1),
        PatternCell(midis: [_g2], steps: 2),
        PatternCell(midis: [_a2], steps: 2),
        PatternCell(midis: [_c2], steps: 3),
        PatternCell(steps: 1),
        PatternCell(midis: [_a2], steps: 2),
        PatternCell(midis: [_g2], steps: 2),
      ]),
      // D — a rising-then-falling pentatonic walk in steady quarters.
      MelodicPattern(Instrument.cello, [
        PatternCell(midis: [_c2], steps: 2),
        PatternCell(midis: [_e2], steps: 2),
        PatternCell(midis: [_g2], steps: 2),
        PatternCell(midis: [_a2], steps: 2),
        PatternCell(midis: [_g2], steps: 2),
        PatternCell(midis: [_e2], steps: 2),
        PatternCell(midis: [_c2], steps: 2),
        PatternCell(midis: [_g2], steps: 2),
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
        PatternCell(midis: _cMaj, steps: 8),
        PatternCell(midis: _aMin, steps: 8),
      ]),
      // B — off-beat stabs.
      MelodicPattern(Instrument.piano, [
        PatternCell(steps: 1),
        PatternCell(midis: _cMaj, steps: 1),
        PatternCell(steps: 2),
        PatternCell(midis: _cMaj, steps: 1),
        PatternCell(steps: 3),
        PatternCell(steps: 1),
        PatternCell(midis: _aMin, steps: 1),
        PatternCell(steps: 2),
        PatternCell(midis: _aMin, steps: 1),
        PatternCell(steps: 3),
      ]),
      // C — arpeggiated eighths.
      MelodicPattern(Instrument.piano, [
        PatternCell(midis: [_c4], steps: 1),
        PatternCell(midis: [_e4], steps: 1),
        PatternCell(midis: [_g4], steps: 1),
        PatternCell(midis: [_e4], steps: 1),
        PatternCell(midis: [_c4], steps: 1),
        PatternCell(midis: [_e4], steps: 1),
        PatternCell(midis: [_g4], steps: 1),
        PatternCell(midis: [_e4], steps: 1),
        PatternCell(midis: [_a3], steps: 1),
        PatternCell(midis: [_c4], steps: 1),
        PatternCell(midis: [_e4], steps: 1),
        PatternCell(midis: [_c4], steps: 1),
        PatternCell(midis: [_a3], steps: 1),
        PatternCell(midis: [_c4], steps: 1),
        PatternCell(midis: [_e4], steps: 1),
        PatternCell(midis: [_c4], steps: 1),
      ]),
    ],
  ),
  const LoopTrack(
    id: 'melody',
    gain: 0.40,
    variants: [
      // A — the v1 riff.
      MelodicPattern(Instrument.piano, [
        PatternCell(midis: [_e4], steps: 1),
        PatternCell(midis: [_g4], steps: 1),
        PatternCell(midis: [_a4], steps: 1),
        PatternCell(steps: 1),
        PatternCell(midis: [_g4], steps: 1),
        PatternCell(midis: [_e4], steps: 1),
        PatternCell(midis: [_d4], steps: 2),
        PatternCell(midis: [_c4], steps: 1),
        PatternCell(midis: [_d4], steps: 1),
        PatternCell(midis: [_e4], steps: 1),
        PatternCell(midis: [_g4], steps: 1),
        PatternCell(midis: [_a4], steps: 2),
        PatternCell(midis: [_g4], steps: 1),
        PatternCell(midis: [_e4], steps: 1),
      ]),
      // B — an answering phrase with held notes.
      MelodicPattern(Instrument.piano, [
        PatternCell(midis: [_g4], steps: 2),
        PatternCell(midis: [_a4], steps: 1),
        PatternCell(midis: [_g4], steps: 1),
        PatternCell(midis: [_e4], steps: 2),
        PatternCell(midis: [_d4], steps: 2),
        PatternCell(midis: [_e4], steps: 1),
        PatternCell(midis: [_d4], steps: 1),
        PatternCell(midis: [_c4], steps: 2),
        PatternCell(midis: [_d4], steps: 2),
        PatternCell(midis: [_e4], steps: 2),
      ]),
      // C — a sparse call.
      MelodicPattern(Instrument.piano, [
        PatternCell(midis: [_e4], steps: 1),
        PatternCell(steps: 3),
        PatternCell(midis: [_g4], steps: 1),
        PatternCell(steps: 3),
        PatternCell(midis: [_a4], steps: 1),
        PatternCell(steps: 3),
        PatternCell(midis: [_g4], steps: 1),
        PatternCell(steps: 3),
      ]),
    ],
  ),
  LoopTrack(
    id: 'sparkle',
    gain: 0.28,
    variants: [
      // A — rare high dings.
      const MelodicPattern(Instrument.musicBox, [
        PatternCell(steps: 2),
        PatternCell(midis: [_c6], steps: 1),
        PatternCell(steps: 3),
        PatternCell(midis: [_a5], steps: 1),
        PatternCell(steps: 1),
        PatternCell(steps: 2),
        PatternCell(midis: [_g5], steps: 1),
        PatternCell(steps: 3),
        PatternCell(midis: [_c6], steps: 1),
        PatternCell(steps: 1),
      ]),
      // B — a running high arpeggio.
      MelodicPattern(Instrument.musicBox, [
        for (var i = 0; i < 4; i++) ...const [
          PatternCell(midis: [_c6], steps: 1),
          PatternCell(midis: [_a5], steps: 1),
          PatternCell(midis: [_g5], steps: 1),
          PatternCell(midis: [_a5], steps: 1),
        ],
      ]),
      // C — one ding per bar.
      const MelodicPattern(Instrument.musicBox, [
        PatternCell(steps: 7),
        PatternCell(midis: [_c6], steps: 1),
        PatternCell(steps: 7),
        PatternCell(midis: [_g5], steps: 1),
      ]),
    ],
  ),
];

// --- Styles: alternate whole-band pattern sets ("many flavours") ---
//
// A [GrooveStyle] re-points the five cards at a different pattern set and biases
// the tempo/swing/kit/scale toward that flavour. Every style keeps the SAME
// track ids (so enabled/variant/level state carries across a switch) and every
// pitched note stays in the C-pentatonic set, so any combination is consonant —
// the same guarantee the key/scale transposition then preserves.

/// A driving four-on-the-floor band: kick every beat, octave-pump bass, stabby
/// pad, bright hook.
final List<LoopTrack> _fourTracks = [
  LoopTrack(
    id: 'drums',
    gain: 0.50,
    variants: [
      DrumRowsPattern({
        Drum.kick: stepRow('x.x.x.x.x.x.x.x.'),
        Drum.snare: stepRow('..x...x...x...x.'),
        Drum.hat: stepRow('.x.x.x.x.x.x.x.x'),
      }),
      DrumRowsPattern({
        Drum.kick: stepRow('x.x.x.x.x.x.x.x.'),
        Drum.clap: stepRow('..x...x...x...x.'),
        Drum.hat: stepRow('xxxxxxxxxxxxxxxx'),
      }),
    ],
  ),
  const LoopTrack(
    id: 'bass',
    gain: 0.55,
    chordFollower: ChordFollower(
      instrument: Instrument.cello,
      baseMidi: 36,
      foldAbove: 45,
      bars: [
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
      ],
    ),
    variants: [
      MelodicPattern(Instrument.cello, [
        PatternCell(midis: [_c2], steps: 1),
        PatternCell(midis: [_c3], steps: 1), //
        PatternCell(midis: [_c2], steps: 1),
        PatternCell(midis: [_c3], steps: 1),
        PatternCell(midis: [_g2], steps: 1),
        PatternCell(midis: [_g3], steps: 1),
        PatternCell(midis: [_g2], steps: 1),
        PatternCell(midis: [_g3], steps: 1),
        PatternCell(midis: [_a2], steps: 1),
        PatternCell(midis: [_a3], steps: 1),
        PatternCell(midis: [_a2], steps: 1),
        PatternCell(midis: [_a3], steps: 1),
        PatternCell(midis: [_g2], steps: 1),
        PatternCell(midis: [_g3], steps: 1),
        PatternCell(midis: [_e2], steps: 1),
        PatternCell(midis: [_g2], steps: 1),
      ]),
      MelodicPattern(Instrument.cello, [
        PatternCell(midis: [_c2], steps: 2),
        PatternCell(midis: [_c2], steps: 2), //
        PatternCell(midis: [_g2], steps: 2),
        PatternCell(midis: [_a2], steps: 2),
        PatternCell(midis: [_c2], steps: 2),
        PatternCell(midis: [_c2], steps: 2),
        PatternCell(midis: [_a2], steps: 2),
        PatternCell(midis: [_g2], steps: 2),
      ]),
    ],
  ),
  const LoopTrack(
    id: 'chords',
    gain: 0.30,
    chordFollower: ChordFollower(
      instrument: Instrument.flute,
      baseMidi: 60,
      foldAbove: 67,
      bars: [
        ChordBar([
          (tones: [0, 1, 2], steps: 2),
          (tones: null, steps: 2),
          (tones: [0, 1, 2], steps: 2),
          (tones: null, steps: 2),
        ]),
      ],
    ),
    variants: [
      MelodicPattern(Instrument.flute, [
        PatternCell(midis: [_c4, _e4, _g4], steps: 2),
        PatternCell(steps: 2), //
        PatternCell(midis: [_c4, _e4, _g4], steps: 2),
        PatternCell(steps: 2),
        PatternCell(midis: [_a3, _c4, _e4], steps: 2),
        PatternCell(steps: 2),
        PatternCell(midis: [_a3, _c4, _e4], steps: 2),
        PatternCell(steps: 2),
      ]),
      MelodicPattern(Instrument.flute, [
        PatternCell(midis: [_c4, _e4, _g4], steps: 8),
        PatternCell(midis: [_a3, _c4, _e4], steps: 8),
      ]),
    ],
  ),
  const LoopTrack(
    id: 'melody',
    gain: 0.34,
    variants: [
      MelodicPattern(Instrument.piano, [
        PatternCell(midis: [_e4], steps: 2),
        PatternCell(midis: [_g4], steps: 2), //
        PatternCell(midis: [_a4], steps: 2),
        PatternCell(midis: [_g4], steps: 2),
        PatternCell(midis: [_e4], steps: 2),
        PatternCell(midis: [_c4], steps: 2),
        PatternCell(midis: [_d4], steps: 2),
        PatternCell(midis: [_e4], steps: 2),
      ]),
      MelodicPattern(Instrument.piano, [
        PatternCell(midis: [_g4], steps: 4),
        PatternCell(midis: [_a4], steps: 4), //
        PatternCell(midis: [_g4], steps: 4),
        PatternCell(midis: [_e4], steps: 4),
      ]),
    ],
  ),
  LoopTrack(
    id: 'sparkle',
    gain: 0.26,
    variants: [
      const MelodicPattern(Instrument.musicBox, [
        PatternCell(midis: [_c6], steps: 1),
        PatternCell(steps: 3), //
        PatternCell(midis: [_a5], steps: 1), PatternCell(steps: 3),
        PatternCell(midis: [_g5], steps: 1), PatternCell(steps: 3),
        PatternCell(midis: [_c6], steps: 1), PatternCell(steps: 3),
      ]),
      MelodicPattern(Instrument.musicBox, [
        for (var i = 0; i < 4; i++) ...[
          const PatternCell(midis: [_c6], steps: 1),
          const PatternCell(midis: [_a5], steps: 1), //
          const PatternCell(midis: [_g5], steps: 1),
          const PatternCell(midis: [_a5], steps: 1),
        ],
      ]),
    ],
  ),
];

/// A laid-back lo-fi band: sparse kick, long mellow roots, warm pad, gentle
/// sparse melody.
final List<LoopTrack> _chillTracks = [
  LoopTrack(
    id: 'drums',
    gain: 0.46,
    variants: [
      DrumRowsPattern({
        Drum.kick: stepRow('x.......x..x....'),
        Drum.snare: stepRow('....x.......x...'),
        Drum.hat: stepRow('x.x.x.x.x.x.x.x.'),
      }),
      DrumRowsPattern({
        Drum.kick: stepRow('x.......x.......'),
        Drum.rim: stepRow('....x.......x...'),
        Drum.hat: stepRow('..x...x...x...x.'),
      }),
    ],
  ),
  const LoopTrack(
    id: 'bass',
    gain: 0.52,
    chordFollower: ChordFollower(
      instrument: Instrument.cello,
      baseMidi: 36,
      foldAbove: 45,
      bars: [
        ChordBar([
          (tones: [0], steps: 4),
          (tones: [2], steps: 4),
        ]),
      ],
    ),
    variants: [
      MelodicPattern(Instrument.cello, [
        PatternCell(midis: [_c2], steps: 4),
        PatternCell(midis: [_g2], steps: 4), //
        PatternCell(midis: [_a2], steps: 4),
        PatternCell(midis: [_g2], steps: 4),
      ]),
      MelodicPattern(Instrument.cello, [
        PatternCell(midis: [_c2], steps: 6),
        PatternCell(steps: 2), //
        PatternCell(midis: [_a2], steps: 6), PatternCell(steps: 2),
      ]),
    ],
  ),
  const LoopTrack(
    id: 'chords',
    gain: 0.28,
    chordFollower: ChordFollower(
      instrument: Instrument.flute,
      baseMidi: 60,
      foldAbove: 67,
      bars: [
        ChordBar([
          (tones: [0, 1, 2], steps: 8),
        ]),
      ],
    ),
    variants: [
      MelodicPattern(Instrument.flute, [
        PatternCell(midis: [_c4, _e4, _g4], steps: 8),
        PatternCell(midis: [_a3, _c4, _e4], steps: 8),
      ]),
      MelodicPattern(Instrument.flute, [
        PatternCell(midis: [_e4, _g4], steps: 8),
        PatternCell(midis: [_c4, _e4], steps: 8),
      ]),
    ],
  ),
  const LoopTrack(
    id: 'melody',
    gain: 0.32,
    variants: [
      MelodicPattern(Instrument.musicBox, [
        PatternCell(midis: [_g4], steps: 4),
        PatternCell(midis: [_e4], steps: 4), //
        PatternCell(midis: [_a4], steps: 4),
        PatternCell(midis: [_g4], steps: 4),
      ]),
      MelodicPattern(Instrument.musicBox, [
        PatternCell(steps: 2),
        PatternCell(midis: [_e4], steps: 2), //
        PatternCell(midis: [_g4], steps: 4),
        PatternCell(steps: 2), PatternCell(midis: [_a4], steps: 2),
        PatternCell(midis: [_g4], steps: 4),
      ]),
    ],
  ),
  const LoopTrack(
    id: 'sparkle',
    gain: 0.24,
    variants: [
      MelodicPattern(Instrument.musicBox, [
        PatternCell(steps: 7),
        PatternCell(midis: [_c6], steps: 1), //
        PatternCell(steps: 7), PatternCell(midis: [_g5], steps: 1),
      ]),
      MelodicPattern(Instrument.musicBox, [
        PatternCell(midis: [_a5], steps: 4),
        PatternCell(steps: 4), //
        PatternCell(midis: [_g5], steps: 4), PatternCell(steps: 4),
      ]),
    ],
  ),
];

/// A section/scene snapshot for the arrangement grid (§G-1): just which layers
/// are on and their variants, so tapping a scene relaunches that whole layer
/// set at once.
class GrooveScene {
  const GrooveScene(this.enabled, this.variants);
  final Set<String> enabled;
  final Map<String, int> variants;
}

/// One selectable band flavour: a whole-band [tracks] set plus the tempo /
/// swing / kit / scale it defaults to.
class GrooveStyle {
  const GrooveStyle(
    this.id, {
    required this.tracks,
    this.tempoBpm = 100,
    this.swing = 0,
    this.kitId = 'clean',
    this.scale = GrooveScale.majorPentatonic,
  });

  final String id;
  final List<LoopTrack> tracks;
  final int tempoBpm;
  final double swing;
  final String kitId;
  final GrooveScale scale;
}

/// The offered styles. `default` is the original band; ids are stable (they go
/// in the share token). Adding a style is pure data — author its `tracks`.
final List<GrooveStyle> kGrooveStyles = [
  GrooveStyle('default', tracks: kLoopMixerTracks),
  GrooveStyle('four', tracks: _fourTracks, tempoBpm: 120, kitId: 'deep'),
  GrooveStyle(
    'chill',
    tracks: _chillTracks,
    tempoBpm: 75,
    swing: 0.33,
    kitId: 'lofi',
  ),
];

/// Resolve a style id to its band (unknown ids → the default style).
GrooveStyle grooveStyleById(String id) =>
    kGrooveStyles.firstWhere((s) => s.id == id, orElse: () => kGrooveStyles[0]);

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

  List<LoopTrack> _baseTracks;
  String _styleId = 'default';
  LoopTrack? _userTrack;
  LoopTrack? _userBeatTrack;

  /// Per-track pitched cell overrides (LM-UX4c): when set, a built-in stem
  /// plays these authored-C cells (transposed at render) instead of its variant
  /// / progression shape — so the kid's edit replaces that part. A 2-bar
  /// pattern that tiles across a progression, like the plain stem path.
  final Map<String, List<PatternCell>> _cellOverrides = {};

  /// The current override for [id], or null. Seeds the tune editor.
  List<PatternCell>? trackCellsOverride(String id) => _cellOverrides[id];

  /// Replace a built-in track's pattern with [cells] (authored-C). Empty clears.
  void setTrackCells(String id, List<PatternCell> cells) {
    if (cells.isEmpty || cells.every((c) => c.midis == null)) {
      _cellOverrides.remove(id);
    } else {
      _cellOverrides[id] = List.of(cells);
    }
    _clearRenderCaches();
  }

  void clearTrackCells(String id) {
    if (_cellOverrides.remove(id) != null) _clearRenderCaches();
  }

  /// Per-track DRUM-row overrides: when set, a built-in drum stem (e.g. the
  /// 'drums' card) plays the kid's edited hit-grid instead of its variant
  /// pattern — the drum twin of [setTrackCells], so the beat editor edits the
  /// actual card rather than a parallel overlay. Travels with the spec.
  final Map<String, DrumRowsPattern> _drumOverrides = {};

  /// The current drum override for [id], or null. Seeds the beat editor.
  DrumRowsPattern? trackDrumsOverride(String id) => _drumOverrides[id];

  /// The drum hit-grid a drum track currently plays: its override if edited,
  /// else its active variant pattern. Null if [id] isn't a drum track. Seeds
  /// the beat editor so the kid edits from what's actually sounding.
  DrumRowsPattern? drumRowsFor(String id) {
    final override = _drumOverrides[id];
    if (override != null) return override;
    for (final track in tracks) {
      if (track.id != id) continue;
      final pat = track.variants[_variantOf(track)];
      return pat is DrumRowsPattern ? pat : null;
    }
    return null;
  }

  /// Replace a built-in drum track's pattern with [rows]. An all-empty grid
  /// clears the override (back to the variant pattern).
  void setTrackDrums(String id, DrumRowsPattern? rows) {
    if (rows == null || rows.rows.values.every((r) => r.every((h) => !h))) {
      _drumOverrides.remove(id);
    } else {
      _drumOverrides[id] = rows;
    }
    _clearRenderCaches();
  }

  /// The selected band flavour ([kGrooveStyles]). Setting it re-points the five
  /// cards at that style's pattern set and biases the tempo/swing/kit/scale
  /// toward the flavour; enabled/variant/level state carries across (same ids).
  String get styleId => _styleId;
  set styleId(String id) {
    final style = grooveStyleById(id);
    if (style.id == _styleId) return;
    _styleId = style.id;
    _baseTracks = style.tracks;
    _tempoBpm = style.tempoBpm.clamp(kMinTempoBpm, kMaxTempoBpm);
    _swing = style.swing;
    _kit = drumKitById(style.kitId);
    _scale = style.scale;
    _clearRenderCaches();
  }

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

  /// The user beat track's pattern, if one is installed — so a caller can share
  /// the current beat (e.g. via the shared-groove bridge). Null when the beat is
  /// only the style's built-in groove.
  DrumRowsPattern? get userBeatPattern =>
      _userBeatTrack?.variants.first as DrumRowsPattern?;

  /// The user melodic ("voice") track's cells, if installed — read by the Loop
  /// Mixer's tune editor (the pitched twin of [userBeatPattern]).
  List<PatternCell>? get userTrackCells =>
      (_userTrack?.variants.first as MelodicPattern?)?.cells;

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

  /// Per-track stereo pan −1 (hard left) … 0 (centre) … +1 (hard right).
  /// Missing = 0 = centre. The whole loop renders mono (byte-identical to the
  /// pre-pan path) until at least one enabled track is panned off centre, at
  /// which point [renderLoop]/[renderVariedLoop] switch to the stereo mixdown.
  final Map<String, double> pans = {};

  /// The pan of [id] (0 = centre).
  double panOf(String id) => pans[id] ?? 0.0;

  /// Sets the pan of [id] (clamped −1..1). Centre (0) is stored so the value
  /// round-trips through the spec; the render still folds to mono when NO
  /// enabled track is panned.
  void setPan(String id, double value) {
    pans[id] = value.clamp(-1.0, 1.0);
  }

  /// Whether any currently-enabled track is panned off centre — the switch
  /// between the mono and stereo mixdown.
  bool get _anyPanned =>
      tracks.any((t) => enabled.contains(t.id) && (pans[t.id] ?? 0) != 0);

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

  int _key = 0;
  int get key => _key;
  set key(int value) {
    final wrapped = ((value % 12) + 12) % 12;
    if (wrapped == _key) return;
    _key = wrapped;
    _clearRenderCaches();
  }

  GrooveScale _scale = GrooveScale.majorPentatonic;
  GrooveScale get scale => _scale;
  set scale(GrooveScale value) {
    if (value == _scale) return;
    _scale = value;
    _clearRenderCaches();
  }

  DrumKit _kit = kDrumKitClean;
  DrumKit get kit => _kit;
  String get kitId => _kit.id;
  set kitId(String id) {
    final next = drumKitById(id);
    if (next.id == _kit.id) return;
    _kit = next;
    _clearRenderCaches();
  }

  /// Semitones every pitched note is shifted by. Minor pentatonic borrows the
  /// relative-major set (+3), so the authored C-major-pentatonic content lands
  /// on the requested key's pentatonic collection either way — consonant for
  /// free. The five sounding pitch-classes are `{0,2,4,7,9} + pitchTranspose`.
  int get pitchTranspose =>
      _key + (_scale == GrooveScale.minorPentatonic ? 3 : 0);

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

  /// Automation lanes — a per-track value that MOVES across the loop.
  ///
  /// A2 renders [AutomationParam.level] only; pan and filter follow on the same
  /// seam. Empty = no automation anywhere, which is the case that must stay
  /// byte-identical to a build without this feature.
  final AutomationLanes _automation = {};

  /// [id]'s lane for [param], or null when it has none.
  AutomationLane? automationFor(String id, AutomationParam param) =>
      _automation[id]?[param];

  /// Sets or clears [id]'s lane for [param].
  void setAutomation(String id, AutomationParam param, AutomationLane? lane) {
    final byParam = _automation[id];
    if (lane == null) {
      if (byParam == null || byParam.remove(param) == null) return;
      if (byParam.isEmpty) _automation.remove(id);
    } else {
      if (byParam != null && byParam[param] == lane) return;
      (_automation[id] ??= {})[param] = lane;
    }
    _clearRenderCaches();
  }

  /// True when any track has any lane — the fast path out of every automation
  /// cost when a groove does not use it.
  bool get hasAutomation => _automation.isNotEmpty;

  /// [id]'s lane for [param] sampled to one value per SAMPLE, or null.
  ///
  /// Null rather than a flat array when there is no lane, so the mixer can skip
  /// the work entirely and the render stays byte-identical.
  Float64List? _envelope(String id, AutomationParam param) {
    final lane = automationFor(id, param);
    if (lane == null || lane.isEmpty) return null;
    final samples = timing.totalSamples;
    final steps = timing.totalSteps;
    final out = Float64List(samples);
    for (var i = 0; i < samples; i++) {
      // Which eighth-step this sample falls in; the lane wraps, so a lane
      // shorter than the loop repeats across it.
      out[i] = param.valueAt(lane.at((i * steps) ~/ samples));
    }
    return out;
  }

  /// [id]'s level lane sampled to one multiplier per SAMPLE, or null.
  ///
  /// Null rather than a flat array when there is no lane, so the mixer can skip
  /// the multiply entirely and the render stays byte-identical.
  Float64List? _levelEnvelope(String id) =>
      _envelope(id, AutomationParam.level);

  /// Per-track swing (absent = the groove's global swing).
  ///
  /// Giving one track its own shuffle while the rest stay straight is how a
  /// groove gets a human feel — a swung hat over a straight bass.
  final Map<String, double> _trackSwing = {};

  /// [id]'s swing, or the global one.
  double trackSwing(String id) => _trackSwing[id] ?? _swing;

  /// Whether [id] carries its own swing rather than following the groove's.
  /// Distinct from `trackSwing(id) == swing`, which is also true when a track
  /// has deliberately been set to the same value.
  bool hasOwnSwing(String id) => _trackSwing.containsKey(id);

  /// Sets [id]'s swing, or clears it back to the global value with null.
  void setTrackSwing(String id, double? value) {
    if (value == null) {
      if (_trackSwing.remove(id) == null) return;
    } else {
      // Same range as the global `swing` setter above.
      final v = value.clamp(0.0, 0.6);
      if (_trackSwing[id] == v) return;
      _trackSwing[id] = v;
    }
    _clearRenderCaches();
  }

  /// [timing], but swung the way this track asks.
  ///
  /// Safe to vary per track because swing does NOT change a stem's length:
  /// `boundaryMs` only delays ODD steps, and a loop spans an even number of
  /// them, so every stem still ends on the same sample. That is the invariant
  /// keeping stems aligned and the seam click-free — if a future swing model
  /// moved the final boundary, per-track swing would have to go.
  LoopTiming _timingFor(String id) {
    final own = trackSwing(id);
    if (own == _swing) return timing;
    return LoopTiming(
      tempoBpm: _tempoBpm,
      swing: own,
      bars: timing.bars,
    );
  }

  /// Per-track pattern length in eighth-steps (absent = the full 2-bar grid).
  ///
  /// A shorter track loops sooner than the rest — the groovebox move where a
  /// 3-step hat walks around a 4-step bass.
  final Map<String, int> _trackSteps = {};

  /// [id]'s loop length in steps, or the full grid.
  int trackSteps(String id) => _trackSteps[id] ?? kPatternSteps;

  /// Sets [id]'s loop length. A value outside [kLoopTrackLengths] is refused
  /// rather than clamped: the allowed set is what bounds the render buffer, and
  /// quietly rounding 5 to 4 would be a lie about what is playing.
  bool setTrackSteps(String id, int steps) {
    if (!isLoopTrackLength(steps)) return false;
    if (trackSteps(id) == steps) return true;
    if (steps == kPatternSteps) {
      _trackSteps.remove(id);
    } else {
      _trackSteps[id] = steps;
    }
    _clearRenderCaches();
    return true;
  }

  /// Steps the loop must span for every track length to land whole — see
  /// [loopRenderSteps]. With no shortened track this is the 2-bar grid, so an
  /// ordinary groove is unchanged.
  int get _loopSteps => loopRenderSteps(kPatternSteps, _trackSteps.values);

  /// [cells] cut to this track's length and repeated across the loop.
  /// Returns the input untouched when nothing is shortened.
  List<PatternCell> _fitCells(String id, List<PatternCell> cells) {
    final len = trackSteps(id);
    if (len == kPatternSteps && _loopSteps == kPatternSteps) return cells;
    return tileCellsTo(takeSteps(cells, len), _loopSteps);
  }

  /// The drum-row equivalent of [_fitCells].
  DrumRowsPattern _fitRows(String id, DrumRowsPattern pattern) {
    final len = trackSteps(id);
    if (len == kPatternSteps && _loopSteps == kPatternSteps) return pattern;
    final vels = pattern.velocities;
    return DrumRowsPattern(
      {
        for (final MapEntry(key: drum, value: row) in pattern.rows.entries)
          drum: tileRowTo(row.take(len).toList(), _loopSteps),
      },
      velocities: vels == null
          ? null
          : {
              for (final MapEntry(key: drum, value: row) in vels.entries)
                drum: tileValuesTo(row.take(len).toList(), _loopSteps),
            },
    );
  }

  LoopTiming get timing => LoopTiming(
        tempoBpm: _tempoBpm,
        swing: _swing,
        // Polymeter lengthens the rendered loop so a short track is never cut
        // off at the seam. Under a progression the loop is the progression's,
        // and per-track lengths do not apply (yet).
        bars: _progression == null
            ? _loopSteps ~/ LoopTiming.stepsPerBar
            : _progression!.degrees.length,
      );

  /// The 2-bar grid authored patterns render on (tiled in progression mode).
  LoopTiming get _vampTiming => LoopTiming(tempoBpm: _tempoBpm, swing: _swing);

  /// Snapshot of the whole groove (serializable — share token, save slots).
  GrooveSpec get spec => GrooveSpec(
        enabled: {...enabled},
        variants: {...variants},
        levels: {...levels},
        pans: {
          for (final e in pans.entries)
            if (e.value != 0.0) e.key: e.value,
        },
        tempoBpm: _tempoBpm,
        swing: _swing,
        progressionId: _progression?.id,
        key: _key,
        scale: _scale,
        kitId: _kit.id,
        styleId: _styleId,
        userCells: (_userTrack?.variants.first as MelodicPattern?)?.cells,
        userInstrument: _userTrack == null
            ? null
            : (_userTrack!.variants.first as MelodicPattern).instrument.name,
        beatRows: (_userBeatTrack?.variants.first as DrumRowsPattern?)?.rows,
        beatVels:
            (_userBeatTrack?.variants.first as DrumRowsPattern?)?.velocities,
        trackOverrides: {
          for (final entry in _cellOverrides.entries)
            entry.key: List<PatternCell>.of(entry.value),
        },
        drumOverrides: {
          for (final entry in _drumOverrides.entries)
            entry.key: {
              for (final r in entry.value.rows.entries)
                r.key: List<bool>.of(r.value),
            },
        },
        drumOverrideVels: {
          for (final entry in _drumOverrides.entries)
            if (entry.value.velocities != null)
              entry.key: {
                for (final r in entry.value.velocities!.entries)
                  r.key: List<double>.of(r.value),
              },
        },
        trackVoices: {
          for (final entry in _trackVoices.entries)
            if (isSerializableInstrument(entry.value)) entry.key: entry.value,
        },
      );

  /// Restores a snapshot (unknown track ids are dropped defensively).
  void applySpec(GrooveSpec next) {
    // Select the style FIRST (swaps the pattern set + applies its tempo/swing/
    // kit/scale bias); the explicit fields below then override that bias, so a
    // saved groove restores its exact tempo/kit/etc. rather than the default.
    styleId = next.styleId;
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
      setUserBeatTrack(DrumRowsPattern(beatRows, velocities: next.beatVels));
    } else {
      _userBeatTrack = null;
    }
    final known = tracks.map((t) => t.id).toSet();
    final overrideEntries = next.trackOverrides?.entries ??
        const <MapEntry<String, List<PatternCell>>>[];
    _cellOverrides
      ..clear()
      ..addAll({
        for (final entry in overrideEntries)
          if (known.contains(entry.key) &&
              entry.key != userTrackId &&
              entry.key != beatTrackId)
            entry.key: List<PatternCell>.of(entry.value),
      });
    _drumOverrides
      ..clear()
      ..addAll({
        for (final entry in next.drumOverrides?.entries ??
            const <MapEntry<String, Map<Drum, List<bool>>>>[])
          if (known.contains(entry.key) &&
              entry.key != userTrackId &&
              entry.key != beatTrackId)
            entry.key: DrumRowsPattern(
              {
                for (final r in entry.value.entries)
                  r.key: List<bool>.of(r.value),
              },
              velocities: next.drumOverrideVels?[entry.key],
            ),
      });
    _trackVoices
      ..clear()
      ..addAll({
        for (final entry in next.trackVoices?.entries ??
            const <MapEntry<String, TrackerInstrument>>[])
          if (known.contains(entry.key) && entry.key != beatTrackId)
            entry.key: entry.value,
      });
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
    pans
      ..clear()
      ..addAll({
        for (final e in next.pans.entries)
          if (known.contains(e.key)) e.key: e.value.clamp(-1.0, 1.0),
      });
    tempoBpm = next.tempoBpm;
    swing = next.swing;
    key = next.key;
    scale = next.scale;
    kitId = next.kitId;
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

  /// Per-track voice override: render this pitched track's cells through a saved
  /// [TrackerInstrument] (a formula OR sampled/soundbank voice) instead of its
  /// built-in [Instrument] timbre — the same notes-on-a-grid the tracker plays.
  /// A live control (not in the share token). Drums are unaffected.
  final Map<String, TrackerInstrument> _trackVoices = {};

  void setTrackVoice(String trackId, TrackerInstrument? voice) {
    if (voice == null) {
      _trackVoices.remove(trackId);
    } else {
      _trackVoices[trackId] = voice;
    }
    _clearRenderCaches();
  }

  TrackerInstrument? trackVoice(String trackId) => _trackVoices[trackId];

  /// A master send effect on the whole mix (a live control; not persisted in the
  /// spec/share token). Different sends cache to different WAV keys.
  LoopSend send = LoopSend.none;

  /// A5 — the master bus insert chain in the shared [FxSpec] model, i.e. the
  /// same effects the Audio Editor, Tracker, Instrument Builder and Tab use.
  ///
  /// When non-empty this REPLACES [send], so a groove with no chain renders
  /// through exactly the old two-preset path and stays byte-identical. Like
  /// [send] and [masterFilter] it is a LIVE control outside the spec, so the
  /// `KU1.` share token is untouched — but it is part of the cache key, so
  /// changing it re-renders.
  List<FxSpec> masterFxChain = <FxSpec>[];

  /// One-knob master filter (a live "make it sound produced" sweep, not
  /// persisted): −1 = full low-pass (dark/muffled, for a breakdown) … 0 = off …
  /// +1 = full high-pass (thin/opened-up, for a drop). Clamped on set.
  double _masterFilter = 0;
  double get masterFilter => _masterFilter;
  set masterFilter(double value) => _masterFilter = value.clamp(-1.0, 1.0);

  // Cache-key suffix for the master bus (send + filter) — both are live controls
  // outside the spec, so the WAV cache must distinguish them.
  String get _masterBusKey {
    final fxHash = Object.hashAll([
      for (final fx in masterFxChain) fx.cacheKey,
    ]);
    final fxKey = masterFxChain.isEmpty ? '' : '#fx:$fxHash';
    return (send == LoopSend.none ? '' : '#send:${send.name}') +
        fxKey +
        (_masterFilter == 0 ? '' : '#filt:${_masterFilter.toStringAsFixed(2)}');
  }

  /// A5 test hook: the master-bus cache-key suffix. The send / FX chain /
  /// filter are LIVE controls outside the spec, so if one of them failed to
  /// reach this key a tweak would silently serve a stale WAV from cache — worth
  /// asserting directly rather than inferring from rendered audio.
  ///
  /// (Named `...ForTest` rather than annotated `@visibleForTesting`: this file
  /// is deliberately Flutter-free and `meta` is not a direct dependency.)
  String get wavCacheKeySuffixForTest => _masterBusKey;

  /// A5 test hook: the master-bus processing (send / FX chain / filter) applied
  /// to one mixed loop buffer, including the two-copy seam warm-up.
  Int16List applySendForTest(Int16List pcm) => _applySend(pcm);

  // The mix-bus cutoff for the current knob: a log sweep so the move feels even.
  Float64List _applyMasterFilter(Float64List f) {
    final v = _masterFilter;
    if (v == 0) return f;
    const sr = kSampleRate * 1.0;
    if (v < 0) {
      // Low-pass from ~18 kHz (barely there) down to ~250 Hz (deep muffle).
      final cutoff = 18000 * pow(250 / 18000, -v).toDouble();
      return biquadFx(f, sampleRate: sr, freq: cutoff, q: 0.9);
    }
    // High-pass from ~20 Hz (open) up to ~3.5 kHz (thin).
    final cutoff = 20 * pow(3500 / 20, v).toDouble();
    return biquadFx(
      f,
      kind: BiquadKind.highpass,
      sampleRate: sr,
      freq: cutoff,
      q: 0.9,
    );
  }

  /// Applies the [send] effect + the master filter to a mixed [pcm] via a
  /// Float64 round-trip.
  Int16List _applySend(Int16List pcm) {
    if (send == LoopSend.none && masterFxChain.isEmpty && _masterFilter == 0) {
      return pcm;
    }
    final n = pcm.length;
    // Pre-roll one full loop: reverb/delay start with zero-initialized state and
    // truncate the tail at the buffer end, so a single-pass render is NOT the
    // steady state of a REPEATING signal — the first ~300 ms of every iteration
    // would be echo-free and the echoes sounding at the loop end would vanish at
    // the wrap (an audible "delay drops out on the downbeat"). Effecting two
    // copies and keeping the SECOND gives the effect the previous iteration's
    // history, i.e. the periodic steady state. One loop of warmup fully covers
    // these settings (a 300 ms / fb 0.3 delay decays to 0.3^16 over a 4.8 s loop).
    final f = Float64List(n * 2);
    for (var i = 0; i < n; i++) {
      final s = pcm[i] / 32768.0;
      f[i] = s;
      f[n + i] = s;
    }
    // A hand-built chain wins over the two presets. It runs on the SAME
    // two-copy buffer, so an arbitrary chain inherits the periodic-steady-state
    // guarantee above for free — that is why this is here and not around the
    // call.
    var wet = masterFxChain.isNotEmpty
        ? applyFxChain(f, masterFxChain, kSampleRate)
        : switch (send) {
            LoopSend.reverb => reverbFx(f, mix: 0.28),
            LoopSend.delay =>
              delayFx(f, delayMs: 300, feedback: 0.3, mix: 0.28),
            LoopSend.none => f,
          };
    // The filter runs on the two-copy buffer too, so its state has converged by
    // the second copy — the seam stays click-free.
    wet = _applyMasterFilter(wet);
    final out = Int16List(n);
    for (var i = 0; i < n; i++) {
      // The second copy is the converged, seam-continuous loop.
      out[i] = (wet[n + i] * 32768).round().clamp(-32768, 32767);
    }
    return out;
  }

  /// Stereo counterpart of [_applySend]: splits the interleaved (L,R) buffer,
  /// runs the SAME per-channel reverb/delay + master filter (so the seam-safe
  /// two-copy trick and click-free convergence carry over), and re-interleaves.
  /// The two channels get independent effect state — a naturally decorrelated,
  /// wider tail — which is exactly right for a panned mix.
  Int16List _applySendStereo(Int16List interleaved) {
    if (send == LoopSend.none && masterFxChain.isEmpty && _masterFilter == 0) {
      return interleaved;
    }
    final frames = interleaved.length ~/ 2;
    final left = Int16List(frames);
    final right = Int16List(frames);
    for (var i = 0; i < frames; i++) {
      left[i] = interleaved[i * 2];
      right[i] = interleaved[i * 2 + 1];
    }
    final wetL = _applySend(left);
    final wetR = _applySend(right);
    final out = Int16List(frames * 2);
    for (var i = 0; i < frames; i++) {
      out[i * 2] = wetL[i];
      out[i * 2 + 1] = wetR[i];
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

  /// A lightweight snapshot of just the live layer state (enabled set +
  /// variants), for the section/scene grid (§G-1). Cheaper than a full spec —
  /// a scene launch swaps the layers, not the tempo/key/style.
  GrooveScene captureScene() => GrooveScene({...enabled}, {...variants});

  /// Render a section arrangement (§G-2): play each of [scenes] for
  /// [loopsPerScene] loops back-to-back and concatenate into one mono buffer —
  /// the "it's just one loop" → "a whole arranged track" export. Only the layer
  /// set changes per section (tempo/key/kit/etc. stay), so every section is the
  /// same loop length. Restores the pre-call layer state; empty in → empty out.
  /// Renders [scenes] end to end. [repeats] gives each scene its own number of
  /// passes (A×4, B×2, A×4); when it is null every scene plays [loopsPerScene]
  /// times, which is the older whole-arrangement behaviour.
  Float64List renderArrangement(
    List<GrooveScene> scenes, {
    int loopsPerScene = 2,
    List<int>? repeats,
  }) {
    if (scenes.isEmpty || loopsPerScene < 1) return Float64List(0);
    final saved = captureScene();
    final sections = <Float64List>[];
    var total = 0;
    for (var s = 0; s < scenes.length; s++) {
      final scene = scenes[s];
      applyScene(scene);
      final mono = wavToMonoFloat(readWavPcm16(renderLoop()));
      final passes = (repeats != null && s < repeats.length)
          ? (repeats[s] < 1 ? 1 : repeats[s])
          : loopsPerScene;
      for (var i = 0; i < passes; i++) {
        sections.add(mono);
        total += mono.length;
      }
    }
    applyScene(saved);
    final out = Float64List(total);
    var offset = 0;
    for (final section in sections) {
      out.setRange(offset, offset + section.length, section);
      offset += section.length;
    }
    return out;
  }

  /// Apply a [scene]: replace the enabled set + variants with its snapshot
  /// (unknown ids dropped defensively). Tempo/key/style/etc. are untouched.
  void applyScene(GrooveScene scene) {
    final known = tracks.map((t) => t.id).toSet();
    enabled
      ..clear()
      ..addAll(scene.enabled.where(known.contains));
    variants
      ..clear()
      ..addAll({
        for (final e in scene.variants.entries)
          if (known.contains(e.key)) e.key: e.value,
      });
  }

  /// Advances [id] to its next pattern variant; returns the new index.
  int cycleVariant(String id) {
    final track = _track(id);
    final next = ((variants[id] ?? 0) + 1) % track.variants.length;
    variants[id] = next;
    return next;
  }

  /// Rolls [id] to a RANDOM variant, preferring a different one from the current
  /// when there's a choice; returns the new index. (Per-card "roll" — a fresh
  /// in-style take for just this stem.)
  int rollVariant(String id, {Random? rng}) {
    final track = _track(id);
    final count = track.variants.length;
    if (count <= 1) return 0;
    final r = rng ?? Random();
    final current = variants[id] ?? 0;
    var next = r.nextInt(count);
    if (next == current) next = (next + 1) % count; // guarantee a change
    variants[id] = next;
    return next;
  }

  int _variantOf(LoopTrack track) =>
      (variants[track.id] ?? 0).clamp(0, track.variants.length - 1);

  /// The pitched cells the groove currently plays for [id] (progression-
  /// resolved and tiled in progression mode), or null for unpitched patterns.
  /// Powers the live engraving.
  List<PatternCell>? cellsFor(String id) {
    final override = _cellOverrides[id];
    if (override != null) return override;
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

  /// [cellsFor] transposed into the current [key]/[scale] — what actually
  /// sounds. The live engraving, the follow-along target and the Song-Book
  /// export use this so the written notes match the heard ones. ([cellsFor]
  /// itself stays authored-C, since the render paths transpose at synthesis.)
  List<PatternCell>? engravedCellsFor(String id) {
    final cells = cellsFor(id);
    final t = pitchTranspose;
    if (cells == null || t == 0) return cells;
    return [
      for (final c in cells)
        PatternCell(midis: c.midis?.map((m) => m + t).toList(), steps: c.steps),
    ];
  }

  Float64List _stemFor(LoopTrack track) {
    final variant = _variantOf(track);
    final voice = _trackVoices[track.id]?.id ?? '';
    // The drum override is keyed by object identity (a new edited pattern is a
    // new instance), so a fresh edit never reads a stale cached stem.
    final drumOv = _drumOverrides[track.id];
    final ov = drumOv != null ? '#do${identityHashCode(drumOv)}' : '';
    final key = '${track.id}#$variant#${_progression?.id ?? 'vamp'}#$voice$ov'
        '#len${trackSteps(track.id)}#loop$_loopSteps'
        '#sw${trackSwing(track.id).toStringAsFixed(3)}';
    return _stemCache[key] ??= _renderStem(track, variant);
  }

  Float64List _renderStem(LoopTrack track, int variant) {
    // A saved-instrument voice override renders this track's cells through the
    // instrument instead of its built-in timbre (drums have no midi cells, so
    // they fall through to the default render).
    final voice = _trackVoices[track.id];
    final prog = _progression;
    final t = pitchTranspose;

    // A per-track DRUM override plays the kid's edited hit-grid for a built-in
    // drum stem (e.g. the 'drums' card). Tiled under a progression like the
    // plain drum path (drums don't re-voice per chord).
    final drumOverride = _drumOverrides[track.id];
    if (drumOverride != null) {
      if (prog == null) {
        return _fitRows(track.id, drumOverride)
            .render(_timingFor(track.id), kit: _kit);
      }
      final twoBars = drumOverride.render(_vampTiming, kit: _kit);
      final reps = prog.degrees.length ~/ 2;
      final out = Float64List(twoBars.length * reps);
      for (var r = 0; r < reps; r++) {
        out.setAll(r * twoBars.length, twoBars);
      }
      return out;
    }

    // A per-track cell override (LM-UX4c) plays the kid's edited pattern instead
    // of the variant/progression shape — a 2-bar pattern that tiles under a
    // progression, exactly like the plain stem path below.
    final cellsOverride = _cellOverrides[track.id];
    if (cellsOverride != null) {
      final inst = track.chordFollower?.instrument ??
          (track.variants[variant] is MelodicPattern
              ? (track.variants[variant] as MelodicPattern).instrument
              : Instrument.flute);
      Float64List one(LoopTiming tm, List<PatternCell> cs) => voice != null
          ? renderCellsWithInstrument(cs, voice, tm, transpose: t)
          : renderCells(cs, inst, tm, transpose: t);
      if (prog == null) {
        return one(_timingFor(track.id), _fitCells(track.id, cellsOverride));
      }
      final twoBars = one(_vampTiming, cellsOverride);
      final reps = prog.degrees.length ~/ 2;
      final out = Float64List(twoBars.length * reps);
      for (var r = 0; r < reps; r++) {
        out.setAll(r * twoBars.length, twoBars);
      }
      return out;
    }

    if (prog == null) {
      final tm = _timingFor(track.id);
      final pat = track.variants[variant];
      if (voice != null && pat is MelodicPattern) {
        return renderCellsWithInstrument(
          _fitCells(track.id, pat.cells),
          voice,
          tm,
          transpose: t,
        );
      }
      // A shortened (or lengthened-loop) track cannot go through
      // LoopPattern.render: MelodicPattern asserts its cells fill the 2-bar
      // grid exactly, which is the very thing polymeter breaks. Render the
      // fitted cells directly instead; an untouched track still takes the
      // original path and is byte-identical.
      if (trackSteps(track.id) != kPatternSteps ||
          _loopSteps != kPatternSteps) {
        if (pat is MelodicPattern) {
          return renderCells(
            _fitCells(track.id, pat.cells),
            pat.instrument,
            tm,
            transpose: t,
          );
        }
        if (pat is DrumRowsPattern) {
          return _fitRows(track.id, pat).render(tm, kit: _kit);
        }
      }
      return pat.render(tm, transpose: t, kit: _kit);
    }

    final follower = track.chordFollower;
    if (follower != null) {
      // Re-voice the bar shape on each progression chord.
      final bar = follower.bars[variant.clamp(0, follower.bars.length - 1)];
      final cells = [
        for (final degree in prog.degrees)
          ...bar.resolve(
            degree,
            baseMidi: follower.baseMidi,
            foldAbove: follower.foldAbove,
          ),
      ];
      return voice != null
          ? renderCellsWithInstrument(cells, voice, timing, transpose: t)
          : renderCells(cells, follower.instrument, timing, transpose: t);
    }

    // Everything else tiles its 2-bar pattern across the progression —
    // exact, because the swung step grid is periodic per bar.
    final pat = track.variants[variant];
    final twoBars = (voice != null && pat is MelodicPattern)
        ? renderCellsWithInstrument(pat.cells, voice, _vampTiming, transpose: t)
        : pat.render(_vampTiming, transpose: t, kit: _kit);
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
    final key = '${spec.cacheKey}${filling ? '#fill' : ''}$_masterBusKey';
    return _wavCache[key] ??= _renderMix(
      stem: (track) => filling && track.id == 'drums'
          ? _fillStemFor(track)
          : _stemFor(track),
    );
  }

  /// Mixes the enabled tracks' [stem]s into one loop WAV. Renders MONO — exactly
  /// the pre-pan path — unless a track is panned off centre ([_anyPanned]), in
  /// which case it renders INTERLEAVED STEREO with a constant-power pan law; the
  /// master send/filter is applied per channel either way.
  Uint8List _renderMix({required Float64List Function(LoopTrack) stem}) {
    final total = timing.totalSamples;
    if (_anyPanned) {
      final panned = [
        for (final track in tracks)
          if (enabled.contains(track.id)) track,
      ];
      return wavBytesStereo(
        _applySendStereo(
          mixStemsStereo(
            [
              for (final track in tracks)
                if (enabled.contains(track.id))
                  (
                    samples: stem(track),
                    gain:
                        track.gain * (levels[track.id] ?? 1.0).clamp(0.0, 1.0),
                    pan: (pans[track.id] ?? 0.0).clamp(-1.0, 1.0),
                  ),
            ],
            totalSamples: total,
            // Same rule as the mono path: null unless something is automated,
            // so the stereo mixer's inner loop is untouched otherwise.
            envelopes: hasAutomation
                ? [for (final t in panned) _levelEnvelope(t.id)]
                : null,
            pans: hasAutomation
                ? [
                    for (final t in panned)
                      _envelope(t.id, AutomationParam.pan),
                  ]
                : null,
          ),
        ),
      );
    }
    final mixed = [
      for (final track in tracks)
        if (enabled.contains(track.id)) track,
    ];
    return wavBytes(
      _applySend(
        mixStems(
          [
            for (final track in mixed)
              (
                samples: stem(track),
                gain: track.gain * (levels[track.id] ?? 1.0).clamp(0.0, 1.0),
              ),
          ],
          totalSamples: total,
          // Null when nothing is automated, so the mixer's inner loop is
          // untouched and the render is byte-identical to before.
          envelopes: hasAutomation
              ? [for (final track in mixed) _levelEnvelope(track.id)]
              : null,
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
  /// sounding chord, a pentatonic scale tone, or outside. Both sets shift with
  /// the current [key]/[scale] (via [pitchTranspose]) so grading matches what
  /// actually sounds.
  JamFit jamFit(int midi, {required int bar}) {
    final degree = chordAtBar(bar);
    final t = pitchTranspose;
    final pc = midi % 12;
    for (final interval in degree.triad) {
      if ((degree.rootOffset + interval + t) % 12 == pc) {
        return JamFit.chordTone;
      }
    }
    for (final p in const [0, 2, 4, 7, 9]) {
      if ((p + t) % 12 == pc) return JamFit.scaleTone;
    }
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
    return _renderMix(
      stem: (track) => switch (track.id) {
        'drums' => filling ? _fillStemFor(track) : _variedDrumStem(track, rng),
        'melody' => _variedMelodyStem(track, rng),
        _ => _stemFor(track),
      },
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
              // Extended kit voices (open hat, clap, tom, rim, cowbell) pass
              // through the jam variation unchanged — authored as placed.
              _ => row[step],
            },
        ],
    };
    final stem = DrumRowsPattern(varied).render(_vampTiming, kit: _kit);
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
          PatternCell(midis: cell.midis, steps: 1),
          PatternCell(
            midis: [_pentatonicNeighbour(cell.midis!.single, rng)],
            steps: 1,
          ),
        ] else
          cell,
    ];
    return renderCells(
      varied,
      pattern.instrument,
      timing,
      transpose: pitchTranspose,
    );
  }

  /// The drum stem for a fill iteration. Vamp mode: the 2-bar fill pattern.
  /// Progression mode: bars 1–2 keep the groove, bars 3–4 play the fill —
  /// a real mini-arrangement instead of filling every other bar.
  Float64List _fillStemFor(LoopTrack track) {
    final prog = _progression;
    if (prog == null) {
      return _stemCache['drums#fill#vamp'] ??=
          kDrumFillPattern.render(timing, kit: _kit);
    }
    final variant = _variantOf(track);
    return _stemCache['drums#fill#$variant#${prog.id}'] ??= () {
      final groove = track.variants[variant].render(_vampTiming, kit: _kit);
      final fill = kDrumFillPattern.render(_vampTiming, kit: _kit);
      final out = Float64List(groove.length + fill.length);
      out
        ..setAll(0, groove)
        ..setAll(groove.length, fill);
      return out;
    }();
  }
}
