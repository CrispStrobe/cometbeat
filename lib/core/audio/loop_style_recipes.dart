// lib/core/audio/loop_style_recipes.dart
//
// Generative style catalog for Loop Studio: a [StyleRecipe] describes a genre's
// RULES (tempo, feel, kit, progression pool, drum templates, bass/comping/
// melody shapes, instruments, gains) — never its notes. [generateRecipeTracks]
// turns (recipe, seed) into the same five [LoopTrack]s the hand-authored styles
// use (`drums`, `bass`, `chords`, `melody`, `sparkle`), so the engine renders a
// generated band through exactly the paths it already has: tiled drum rows,
// chord-following pitched parts, unit-peak stems through `mixStems`.
//
// Why this shape:
//
// * Everything pitched is a [ChordBar] (chord-tone indices, plus optional
//   pentatonic neighbour steps on OFF-beats). The SAME bar is used twice: as the
//   track's chord follower in progression mode, and resolved over the vamp's
//   implied C | Am to make the 2-bar [MelodicPattern] variants. One source,
//   so the vamp and the song loop can never disagree about harmony — and a
//   chord tone is a chord tone of whatever chord sounds, so any seed is
//   consonant by construction (the guardrail is structural, not a filter).
// * Bass: the first note of every bar is the root, and a note on a strong beat
//   (beat 1 or 3) is root, fifth or octave. Melody: every note on a beat is a
//   pure chord tone; only off-beat eighths may step to a pentatonic neighbour.
//   Drums: hits are a subset of the template — `x` always, `g` always (quiet),
//   `o` only by chance. Tests enforce all three for every recipe × seed.
// * Determinism: our own xorshift32 + FNV hash, NOT `dart:math` Random, so a
//   (recipe, seed) renders identically on the VM, on the web and in the isolate
//   — the share token carries only (recipeId, seed), so the band must be a pure
//   function of them. Integer ops stay inside 32 bits (JS-safe).
// * Tempos come only from [kValidLoopTempos]: the ones whose eighth-step is an
//   integral number of ms AND of samples at 44.1 kHz (60000/bpm/2 a multiple of
//   10 ms), which is what keeps stems aligned and the seam click-free.
library;

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart';

/// Tempos a recipe may pick: 3000/bpm is an integer (step = 30000/bpm ms is a
/// multiple of 10 ms → a whole number of samples at 44.1 kHz). The full set in
/// 40..240 is {40, 50, 60, 75, 100, 120, 125, 150, 200}; these are the musical
/// ones. Recipes stay on 75/100/120 (the chips the mixer offers) except where
/// the genre really wants otherwise.
const kValidLoopTempos = [60, 75, 100, 120, 150];

/// Whether [bpm] keeps the eighth-step grid integral in ms and samples.
bool isGridTempo(int bpm) {
  if (bpm <= 0 || 30000 % bpm != 0) return false;
  final stepMs = 60000 ~/ bpm ~/ 2;
  return stepMs % 10 == 0;
}

/// Gallery grouping.
enum StyleGenre { popRock, groove, world, classic }

/// The card's feel tag.
enum StyleFeel { straight, driving, swung, shuffle, laidBack, gentle }

/// One drum template: per voice a 16-step (2-bar) row. `x` = always hit,
/// `g` = always, quiet (ghost), `o` = optional (included by chance, at a
/// slightly lower velocity), `.` = never. Generated rows are always a subset.
class DrumTemplate {
  const DrumTemplate(this.rows);
  final Map<Drum, String> rows;
}

/// A genre's rules. Pure data — adding a style never needs new code.
class StyleRecipe {
  const StyleRecipe({
    required this.id,
    required this.genre,
    required this.feel,
    required this.tempos,
    this.swing = 0,
    required this.kits,
    this.scale = GrooveScale.majorPentatonic,
    required this.progressions,
    required this.drums,
    this.drumDensity = 0.5,
    required this.bassBars,
    this.bassInstrument = Instrument.cello,
    required this.chordBars,
    this.chordInstrument = Instrument.piano,
    this.invertChance = 0.3,
    required this.melodyRhythms,
    this.melodyInstrument = Instrument.piano,
    this.neighbourChance = 0.4,
    this.maxLeap = 2,
    required this.sparkleBars,
    this.gains = const {},
  });

  final String id;
  final StyleGenre genre;
  final StyleFeel feel;

  /// Candidate tempos (each a [kValidLoopTempos] entry).
  final List<int> tempos;
  final double swing;

  /// Candidate drum kit ids ([kDrumKits]).
  final List<String> kits;
  final GrooveScale scale;

  /// Candidate [kProgressions] ids.
  final List<String> progressions;

  final List<DrumTemplate> drums;

  /// Probability that an optional (`o`) hit sounds.
  final double drumDensity;

  /// Bass bar shapes, chord-relative tokens (see [parseChordBar]).
  final List<String> bassBars;
  final Instrument bassInstrument;

  /// Comping bar shapes.
  final List<String> chordBars;
  final Instrument chordInstrument;

  /// Chance a comping variant uses the first inversion (`012` → `123`).
  final double invertChance;

  /// One-bar melody rhythms, 8 chars: `n` onset, `-` hold, `.` rest.
  final List<String> melodyRhythms;
  final Instrument melodyInstrument;

  /// Chance an OFF-beat melody note steps to a pentatonic neighbour.
  final double neighbourChance;

  /// Largest chord-tone-index jump between melody notes (contour smoothness).
  final int maxLeap;

  /// High music-box ornament bars.
  final List<String> sparkleBars;

  /// Per-track mix gains (missing → [_defaultGains]).
  final Map<String, double> gains;

  double gainOf(String track) => gains[track] ?? _defaultGains[track] ?? 0.4;
}

const _defaultGains = {
  'drums': 0.50,
  'bass': 0.55,
  'chords': 0.30,
  'melody': 0.40,
  'sparkle': 0.26,
};

/// The five generated track ids — the same as every hand-authored style.
const kRecipeTrackIds = ['drums', 'bass', 'chords', 'melody', 'sparkle'];

/// A track pinned to a specific (recipe, track-seed): what a lock or a
/// per-track dice roll stores. Serialized as `recipeId:seed`.
class RecipePin {
  const RecipePin(this.recipeId, this.seed);
  final String recipeId;
  final int seed;

  @override
  String toString() => '$recipeId:$seed';

  /// Parses `recipeId:seed`; null for anything malformed or unknown.
  static RecipePin? tryParse(Object? raw) {
    if (raw is! String || raw.length > 48) return null;
    final i = raw.lastIndexOf(':');
    if (i <= 0) return null;
    final id = raw.substring(0, i);
    final seed = int.tryParse(raw.substring(i + 1));
    if (seed == null || seed < 0 || seed > kMaxRecipeSeed) return null;
    if (styleRecipeById(id) == null) return null;
    return RecipePin(id, seed);
  }

  @override
  bool operator ==(Object other) =>
      other is RecipePin && other.recipeId == recipeId && other.seed == seed;

  @override
  int get hashCode => Object.hash(recipeId, seed);
}

/// Seeds live in 0..2^31-1 (fits a JSON int everywhere).
const kMaxRecipeSeed = 0x7fffffff;

// ---------------------------------------------------------------------------
// Deterministic randomness (platform-independent)
// ---------------------------------------------------------------------------

/// FNV-1a over [s], 32-bit. The multiply is split (16777619 = 2^24 + 403) so
/// no intermediate exceeds 2^53 — identical on the VM and in JS.
int fnv32(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = (h ^ c) & 0xffffffff;
    h = (((h << 24) & 0xffffffff) + h * 403) & 0xffffffff;
  }
  return h;
}

/// The per-track seed a groove seed implies for [trackId] under [recipeId].
int deriveTrackSeed(String recipeId, int seed, String trackId) =>
    fnv32('$recipeId/$trackId/$seed') & kMaxRecipeSeed;

/// xorshift32. Small, fast, and bit-exact across platforms.
class SeededRng {
  SeededRng(int seed) : _s = (fnv32('rng$seed') | 1) & 0xffffffff;
  int _s;

  int _next() {
    var x = _s;
    x = (x ^ ((x << 13) & 0xffffffff)) & 0xffffffff;
    x = x ^ (x >> 17);
    x = (x ^ ((x << 5) & 0xffffffff)) & 0xffffffff;
    _s = x;
    return x;
  }

  /// 0..max-1.
  int nextInt(int max) => max <= 1 ? 0 : _next() % max;

  /// 0..1 (exclusive).
  double nextDouble() => _next() / 4294967296.0;

  bool chance(double p) => nextDouble() < p;

  T pick<T>(List<T> items) => items[nextInt(items.length)];
}

// ---------------------------------------------------------------------------
// Bar-shape parsing
// ---------------------------------------------------------------------------

/// Parses chord-relative tokens: `TONES:STEPS` separated by spaces. TONES is
/// one digit per chord tone (0 root, 1 third, 2 fifth, 3 octave root) or `.`
/// for a rest. Steps must sum to one bar (8).
ChordBar parseChordBar(String shape) {
  final cells = <({List<int>? tones, int steps})>[];
  var total = 0;
  for (final tok in shape.trim().split(RegExp(r'\s+'))) {
    final parts = tok.split(':');
    final steps = int.parse(parts[1]);
    final tones = parts[0] == '.'
        ? null
        : [for (final ch in parts[0].split('')) int.parse(ch)];
    cells.add((tones: tones, steps: steps));
    total += steps;
  }
  if (total != LoopTiming.stepsPerBar) {
    throw ArgumentError('bar "$shape" fills $total steps, not 8');
  }
  return ChordBar(cells);
}

/// Step offset of each cell's onset in [bar].
List<int> chordBarOnsets(ChordBar bar) {
  final out = <int>[];
  var s = 0;
  for (final c in bar.cells) {
    out.add(s);
    s += c.steps;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------

/// Registers per track (C the roots build on, and the fold point).
const _bassBase = 36, _bassFold = 45;
const _chordBase = 60, _chordFold = 67;
const _melodyBase = 72, _melodyFold = 76;
const _sparkleBase = 84, _sparkleFold = 88;

/// The groove-level choices a seed makes (tempo, kit, progression).
class RecipeBias {
  const RecipeBias({
    required this.tempoBpm,
    required this.swing,
    required this.kitId,
    required this.scale,
    required this.progressionId,
  });
  final int tempoBpm;
  final double swing;
  final String kitId;
  final GrooveScale scale;
  final String progressionId;
}

RecipeBias recipeBias(StyleRecipe r, int seed) {
  final rng = SeededRng(fnv32('${r.id}/bias/$seed'));
  return RecipeBias(
    tempoBpm: rng.pick(r.tempos),
    swing: r.swing,
    kitId: rng.pick(r.kits),
    scale: r.scale,
    progressionId: rng.pick(r.progressions),
  );
}

/// The whole generated band for (recipe, seed). [pins] override individual
/// tracks with their own (recipe, track-seed) — locks and per-track dice.
List<LoopTrack> generateRecipeTracks(
  StyleRecipe recipe,
  int seed, {
  Map<String, RecipePin> pins = const {},
}) =>
    [
      for (final id in kRecipeTrackIds)
        () {
          final pin = pins[id];
          final r =
              pin == null ? recipe : (styleRecipeById(pin.recipeId) ?? recipe);
          final s = pin?.seed ?? deriveTrackSeed(recipe.id, seed, id);
          return generateRecipeTrack(r, id, s);
        }(),
    ];

/// One track of [recipe] from its own [trackSeed].
LoopTrack generateRecipeTrack(StyleRecipe recipe, String id, int trackSeed) {
  final rng = SeededRng(trackSeed);
  switch (id) {
    case 'drums':
      return LoopTrack(
        id: id,
        gain: recipe.gainOf(id),
        variants: [for (var v = 0; v < 3; v++) _drumVariant(recipe, v, rng)],
      );
    case 'bass':
      return _follower(
        id,
        recipe.gainOf(id),
        recipe.bassInstrument,
        _bassBase,
        _bassFold,
        [for (var v = 0; v < 3; v++) _bassBar(recipe, v, rng)],
      );
    case 'chords':
      return _follower(
        id,
        recipe.gainOf(id),
        recipe.chordInstrument,
        _chordBase,
        _chordFold,
        [for (var v = 0; v < 3; v++) _chordBar(recipe, v, rng)],
      );
    case 'melody':
      return _follower(
        id,
        recipe.gainOf(id),
        recipe.melodyInstrument,
        _melodyBase,
        _melodyFold,
        [for (var v = 0; v < 3; v++) _melodyBar(recipe, v, rng)],
      );
    default:
      return _follower(
        id,
        recipe.gainOf(id),
        Instrument.musicBox,
        _sparkleBase,
        _sparkleFold,
        [for (var v = 0; v < 3; v++) _pickBar(recipe.sparkleBars, v, rng)],
      );
  }
}

/// A chord-following track whose vamp variants are the same bars resolved
/// over the vamp's implied C | Am (see [LoopEngine.chordAtBar]).
LoopTrack _follower(
  String id,
  double gain,
  Instrument instrument,
  int base,
  int fold,
  List<ChordBar> bars,
) =>
    LoopTrack(
      id: id,
      gain: gain,
      chordFollower: ChordFollower(
        instrument: instrument,
        baseMidi: base,
        foldAbove: fold,
        bars: bars,
      ),
      variants: [
        for (final bar in bars)
          MelodicPattern(instrument, [
            ...bar.resolve(ChordDegree.i, baseMidi: base, foldAbove: fold),
            ...bar.resolve(ChordDegree.vi, baseMidi: base, foldAbove: fold),
          ]),
      ],
    );

/// Variant v takes a distinct entry from [pool] when it can (rotated from a
/// seeded start), so A/B/C differ.
ChordBar _pickBar(List<String> pool, int v, SeededRng rng) {
  final start = rng.nextInt(pool.length);
  return parseChordBar(pool[(start + v) % pool.length]);
}

DrumRowsPattern _drumVariant(StyleRecipe r, int v, SeededRng rng) {
  final template = r.drums[(rng.nextInt(r.drums.length) + v) % r.drums.length];
  // C is the plain take: optional hits off. A and B roll them.
  final density = v == 2 ? 0.0 : r.drumDensity;
  final rows = <Drum, List<bool>>{};
  final vels = <Drum, List<double>>{};
  var anySoft = false;
  for (final MapEntry(key: drum, value: row) in template.rows.entries) {
    final hits = <bool>[];
    final vel = <double>[];
    for (final ch in row.split('')) {
      switch (ch) {
        case 'x':
          hits.add(true);
          vel.add(1.0);
        case 'g':
          hits.add(true);
          vel.add(0.45);
          anySoft = true;
        case 'o':
          final on = rng.chance(density);
          hits.add(on);
          vel.add(on ? 0.8 : 1.0);
          if (on) anySoft = true;
        default:
          hits.add(false);
          vel.add(1.0);
      }
    }
    rows[drum] = hits;
    vels[drum] = vel;
  }
  return DrumRowsPattern(rows, velocities: anySoft ? vels : null);
}

ChordBar _bassBar(StyleRecipe r, int v, SeededRng rng) {
  final bar = _pickBar(r.bassBars, v, rng);
  // Off-beat colour: an off-beat root may jump to the octave (or back) —
  // never on a strong beat nor the bar's first note, so the root lock holds.
  final onsets = chordBarOnsets(bar);
  final firstNote = bar.cells.indexWhere((c) => c.tones != null);
  return ChordBar([
    for (var i = 0; i < bar.cells.length; i++)
      () {
        final c = bar.cells[i];
        final t = c.tones;
        if (t != null &&
            i != firstNote &&
            t.length == 1 &&
            onsets[i].isOdd &&
            (t[0] == 0 || t[0] == 3) &&
            rng.chance(0.3)) {
          return (tones: [t[0] == 0 ? 3 : 0], steps: c.steps);
        }
        return c;
      }(),
  ]);
}

ChordBar _chordBar(StyleRecipe r, int v, SeededRng rng) {
  final bar = _pickBar(r.chordBars, v, rng);
  if (!rng.chance(r.invertChance)) return bar;
  // First inversion: 0 1 2 → 1 2 3 (root moved up an octave), same chord.
  return ChordBar([
    for (final c in bar.cells)
      (
        tones: c.tones == null
            ? null
            : ([for (final t in c.tones!) t == 0 ? 3 : t]..sort()),
        steps: c.steps,
      ),
  ]);
}

ChordBar _melodyBar(StyleRecipe r, int v, SeededRng rng) {
  final rhythm = r.melodyRhythms[
      (rng.nextInt(r.melodyRhythms.length) + v) % r.melodyRhythms.length];
  final cells = <({List<int>? tones, int steps})>[];
  final steps = <int>[];
  int? prev;
  var direction = rng.chance(0.5) ? 1 : -1;
  var s = 0;
  for (final ch in rhythm.split('')) {
    if (ch == '-' && cells.isNotEmpty) {
      final last = cells.removeLast();
      cells.add((tones: last.tones, steps: last.steps + 1));
    } else if (ch == 'n') {
      int idx;
      if (prev == null) {
        idx = rng.pick(const [0, 1, 2, 1]);
      } else {
        final leap = 1 + rng.nextInt(r.maxLeap);
        // Contour: keep going one way, turn at the edges or by chance.
        if (rng.chance(0.25)) direction = -direction;
        idx = prev + (rng.chance(0.2) ? 0 : direction * leap);
        if (idx < 0 || idx > 3) {
          direction = -direction;
          idx = (prev + direction * leap).clamp(0, 3);
        }
      }
      prev = idx;
      cells.add((tones: [idx], steps: 1));
      // An off-beat may lean to a pentatonic neighbour; a beat never does.
      steps.add(
        s.isOdd && rng.chance(r.neighbourChance)
            ? (rng.chance(0.5) ? 1 : -1)
            : 0,
      );
    } else {
      // A rest (or a hold with nothing to hold).
      if (cells.isNotEmpty && cells.last.tones == null) {
        final last = cells.removeLast();
        cells.add((tones: null, steps: last.steps + 1));
      } else {
        cells.add((tones: null, steps: 1));
        steps.add(0);
      }
    }
    s++;
  }
  return ChordBar(cells, scaleSteps: steps.any((x) => x != 0) ? steps : null);
}

// ---------------------------------------------------------------------------
// The catalog
// ---------------------------------------------------------------------------

/// The style catalog, gallery order. Ids are stable (they go in share tokens).
const List<StyleRecipe> kStyleRecipes = [
  // --- Pop & Rock ---
  StyleRecipe(
    id: 'pop',
    genre: StyleGenre.popRock,
    feel: StyleFeel.straight,
    tempos: [100, 120],
    kits: ['punchy', 'clean'],
    progressions: ['axis', 'doowop', 'anthem', 'ballad'],
    drums: [
      DrumTemplate({
        Drum.kick: 'x...x.o.x...x.o.',
        Drum.snare: '..x...x...x...x.',
        Drum.hat: 'xgxgxgxgxgxgxgxg',
      }),
      DrumTemplate({
        Drum.kick: 'x..ox.o.x..ox...',
        Drum.clap: '..x...x...x...x.',
        Drum.hat: 'x.x.x.x.x.x.x.x.',
        Drum.openHat: '...............o',
      }),
    ],
    bassBars: [
      '0:2 0:2 2:2 0:2',
      '0:3 0:1 2:2 2:2',
      '0:1 3:1 0:1 3:1 0:1 3:1 0:1 3:1',
      '0:4 2:2 3:2',
    ],
    chordBars: [
      '.:1 012:1 .:2 012:1 .:3',
      '012:2 012:2 012:2 012:2',
      '012:3 012:1 .:2 012:2',
    ],
    melodyRhythms: ['n-n-n-n-', 'n.nnn-n.', 'n--nn-n-', 'n-nn-.n.'],
    sparkleBars: ['.:7 2:1', '.:2 3:1 .:5', '0:1 .:3 2:1 .:3'],
  ),
  StyleRecipe(
    id: 'rock',
    genre: StyleGenre.popRock,
    feel: StyleFeel.driving,
    tempos: [120],
    kits: ['tight', 'punchy'],
    progressions: ['classic', 'anthem', 'epic', 'blues'],
    drumDensity: 0.6,
    drums: [
      DrumTemplate({
        Drum.kick: 'x...x.x.x...x.o.',
        Drum.snare: '..x...x...x...xo',
        Drum.hat: 'xxxxxxxxxxxxxxxx',
        Drum.crash: 'o...............',
      }),
      DrumTemplate({
        Drum.kick: 'x.x.x...x.x.x.o.',
        Drum.snare: '..x...x...x..ox.',
        Drum.ride: 'x.x.x.x.x.x.x.x.',
      }),
    ],
    bassBars: [
      '0:1 0:1 0:1 0:1 0:1 0:1 0:1 0:1',
      '0:1 0:1 0:1 0:1 2:1 2:1 3:1 2:1',
      '0:2 0:1 0:1 2:2 0:2',
    ],
    chordBars: [
      '012:2 012:2 012:2 012:2',
      '012:3 012:1 012:2 012:2',
      '02:1 02:1 02:1 02:1 02:1 02:1 02:1 02:1',
    ],
    melodyInstrument: Instrument.flute,
    melodyRhythms: ['n-n-n-n-', 'n--nn-n-', 'n-n-n---', 'nn.nn-n-'],
    sparkleBars: ['.:6 3:2', '0:2 .:6', '.:4 2:1 .:3'],
    gains: {'drums': 0.55, 'bass': 0.55, 'chords': 0.28},
  ),
  StyleRecipe(
    id: 'ballad',
    genre: StyleGenre.popRock,
    feel: StyleFeel.gentle,
    tempos: [75],
    kits: ['warm', 'clean'],
    progressions: ['ballad', 'emotional', 'calm', 'dreamy'],
    drumDensity: 0.35,
    drums: [
      DrumTemplate({
        Drum.kick: 'x.......x..o....',
        Drum.snare: '....x.......x...',
        Drum.hat: 'x.x.x.x.x.x.x.x.',
      }),
      DrumTemplate({
        Drum.kick: 'x.....o.x.......',
        Drum.rim: '....x.......x...',
        Drum.ride: 'x.x.x.x.x.x.x.x.',
      }),
    ],
    bassBars: ['0:8', '0:4 2:4', '0:6 2:2', '0:4 0:2 3:2'],
    chordInstrument: Instrument.flute,
    chordBars: [
      '012:8',
      '012:4 012:4',
      '0:1 1:1 2:1 3:1 2:1 1:1 0:1 1:1',
    ],
    melodyInstrument: Instrument.flute,
    neighbourChance: 0.3,
    maxLeap: 1,
    melodyRhythms: ['n---n---', 'n-n-n---', 'n---n-n-', 'n-----n-'],
    sparkleBars: ['.:4 2:4', '.:7 3:1', '0:4 .:4'],
    gains: {'drums': 0.40, 'chords': 0.32, 'melody': 0.42},
  ),
  // --- Groove ---
  StyleRecipe(
    id: 'funk',
    genre: StyleGenre.groove,
    feel: StyleFeel.driving,
    tempos: [100],
    swing: 0.1,
    kits: ['tight', 'punchy'],
    progressions: ['blues', 'cycle', 'jazz'],
    drumDensity: 0.55,
    drums: [
      DrumTemplate({
        Drum.kick: 'x..x..o.x.ox..o.',
        Drum.snare: '..x.g.x...x.g.xo',
        Drum.hat: 'xgxgxgxgxgxgxgxg',
      }),
      DrumTemplate({
        Drum.kick: 'x.o..x..x.o..x..',
        Drum.snare: '..x...xg..x...x.',
        Drum.hat: 'x.x.x.x.x.x.x.x.',
        Drum.openHat: '.......o.......o',
      }),
    ],
    bassBars: [
      '0:1 .:1 0:1 3:1 .:1 0:1 2:1 3:1',
      '0:2 .:1 0:1 3:1 0:1 2:1 .:1',
      '0:1 3:1 .:1 0:1 2:1 .:1 3:1 0:1',
    ],
    chordBars: [
      '.:1 012:1 .:1 012:1 .:3 012:1',
      '012:1 .:1 012:1 .:3 012:1 .:1',
      '.:2 12:1 .:1 .:2 12:1 .:1',
    ],
    melodyRhythms: ['n.n..nn.', '.nn.n.n.', 'n..n.nn-', 'nn.n..n.'],
    sparkleBars: ['.:3 2:1 .:4', '.:1 3:1 .:6', '.:5 2:1 .:2'],
    gains: {'chords': 0.32, 'melody': 0.36},
  ),
  StyleRecipe(
    id: 'hiphop',
    genre: StyleGenre.groove,
    feel: StyleFeel.laidBack,
    tempos: [75, 100],
    swing: 0.33,
    kits: ['boom', 'lofi'],
    scale: GrooveScale.minorPentatonic,
    progressions: ['wistful', 'epic', 'ballad'],
    drums: [
      DrumTemplate({
        Drum.kick: 'x......ox.x....o',
        Drum.snare: '..x...x...x...x.',
        Drum.hat: 'xoxoxoxoxoxoxoxo',
      }),
      DrumTemplate({
        Drum.kick: 'x..x....x.ox....',
        Drum.snare: '..x...x...x...x.',
        Drum.hat: 'xgxgxgxgxgxgxgxg',
      }),
    ],
    bassBars: ['0:3 .:1 .:2 0:1 2:1', '0:4 .:2 3:1 0:1', '0:3 0:1 .:4'],
    chordBars: ['012:8', '012:4 .:4', '.:4 012:4'],
    melodyRhythms: ['n-..n-..', '.n-.n-..', 'n-n-..n.', 'n...n.n.'],
    sparkleBars: ['.:6 2:2', '.:3 3:1 .:4', '.:8'],
    gains: {'drums': 0.56, 'bass': 0.58, 'chords': 0.26, 'melody': 0.36},
  ),
  StyleRecipe(
    id: 'house',
    genre: StyleGenre.groove,
    feel: StyleFeel.driving,
    tempos: [120],
    kits: ['deep', 'boom'],
    scale: GrooveScale.minorPentatonic,
    progressions: ['axis', 'epic', 'dreamy'],
    drums: [
      DrumTemplate({
        Drum.kick: 'x.x.x.x.x.x.x.x.',
        Drum.clap: '..x...x...x...x.',
        Drum.openHat: '.x.x.x.x.x.x.x.x',
        Drum.hat: 'o.o.o.o.o.o.o.o.',
      }),
      DrumTemplate({
        Drum.kick: 'x.x.x.x.x.x.x.x.',
        Drum.clap: '..x...x...x...x.',
        Drum.hat: 'gxgxgxgxgxgxgxgx',
        Drum.cowbell: '...o.......o....',
      }),
    ],
    bassBars: [
      '.:1 0:1 .:1 0:1 .:1 0:1 .:1 0:1',
      '0:1 3:1 0:1 3:1 0:1 3:1 0:1 3:1',
      '.:1 0:1 .:1 3:1 .:1 0:1 .:1 2:1',
    ],
    chordBars: [
      '.:1 012:1 .:1 012:1 .:1 012:1 .:1 012:1',
      '.:1 012:1 .:2 .:1 012:1 .:2',
      '012:8',
    ],
    melodyInstrument: Instrument.musicBox,
    melodyRhythms: ['n-n-n-n-', 'n.n.n.nn', 'n---n-n-', '.nn..nn.'],
    sparkleBars: ['.:1 3:1 .:6', '0:1 .:1 2:1 .:5', '.:8'],
    gains: {'drums': 0.55, 'bass': 0.52, 'chords': 0.28},
  ),
  StyleRecipe(
    id: 'lofi',
    genre: StyleGenre.groove,
    feel: StyleFeel.laidBack,
    tempos: [75],
    swing: 0.33,
    kits: ['lofi', 'tape'],
    progressions: ['dreamy', 'emotional', 'wistful', 'calm'],
    drumDensity: 0.4,
    drums: [
      DrumTemplate({
        Drum.kick: 'x.......x..o....',
        Drum.snare: '....x.......x...',
        Drum.hat: 'x.x.x.x.x.x.x.x.',
      }),
      DrumTemplate({
        Drum.kick: 'x.......x.......',
        Drum.rim: '....x.......x...',
        Drum.hat: '..x...x...x...x.',
      }),
    ],
    bassBars: ['0:4 2:4', '0:6 .:2', '0:4 3:2 2:2'],
    chordInstrument: Instrument.flute,
    chordBars: ['012:8', '12:8', '012:4 012:4'],
    melodyInstrument: Instrument.musicBox,
    melodyRhythms: ['n---n---', '..n-n---', 'n-..n-..', '..n-..n-'],
    sparkleBars: ['.:7 3:1', '2:4 .:4', '.:8'],
    gains: {'drums': 0.46, 'bass': 0.52, 'chords': 0.28, 'melody': 0.34},
  ),
  // --- World ---
  StyleRecipe(
    id: 'reggae',
    genre: StyleGenre.world,
    feel: StyleFeel.laidBack,
    tempos: [75],
    swing: 0.1,
    kits: ['warm', 'clean'],
    scale: GrooveScale.minorPentatonic,
    progressions: ['ballad', 'wistful', 'epic'],
    drums: [
      DrumTemplate({
        Drum.kick: '....x.......x...',
        Drum.rim: '....x.......x...',
        Drum.hat: 'xgxgxgxgxgxgxgxg',
      }),
      DrumTemplate({
        Drum.kick: 'x...x...x...x...',
        Drum.rim: '....x.......x...',
        Drum.hat: '.x.x.x.x.x.x.x.x',
      }),
    ],
    bassBars: ['0:3 0:1 2:2 .:2', '0:2 .:1 2:1 3:2 .:2', '0:3 2:1 0:2 .:2'],
    chordBars: ['.:2 012:1 .:3 012:1 .:1', '.:2 012:2 .:2 012:2'],
    melodyInstrument: Instrument.flute,
    melodyRhythms: ['n-n-..n.', 'n---n.n.', '.n.nn---', 'n.n.n---'],
    sparkleBars: ['.:3 2:1 .:4', '.:7 3:1', '.:8'],
    gains: {'chords': 0.30, 'bass': 0.6},
  ),
  StyleRecipe(
    id: 'bossa',
    genre: StyleGenre.world,
    feel: StyleFeel.gentle,
    tempos: [120],
    kits: ['warm', 'tight'],
    progressions: ['jazz', 'cycle', 'fifties', 'dreamy'],
    drums: [
      DrumTemplate({
        Drum.kick: 'x..xx..xx..xx..x',
        Drum.rim: 'x..x..x...x..x..',
        Drum.hat: 'xgxgxgxgxgxgxgxg',
      }),
      DrumTemplate({
        Drum.kick: 'x..ox..ox..ox..o',
        Drum.rim: '..x..x..x..x..x.',
        Drum.hat: 'x.x.x.x.x.x.x.x.',
      }),
    ],
    bassBars: ['0:3 2:1 2:3 0:1', '0:3 2:1 2:4', '0:4 2:4'],
    chordBars: [
      '012:1 .:2 012:1 .:1 012:1 .:2',
      '.:1 123:1 .:1 123:2 .:1 123:2',
      '012:3 012:3 .:2',
    ],
    melodyInstrument: Instrument.flute,
    melodyRhythms: ['n--n--n-', 'n-n.n-n.', 'n---.nn-', '.n-n-n-.'],
    sparkleBars: ['.:5 2:1 .:2', '.:2 3:1 .:5', '.:8'],
    gains: {'drums': 0.44, 'chords': 0.30},
  ),
  // --- Classic ---
  StyleRecipe(
    id: 'swing',
    genre: StyleGenre.classic,
    feel: StyleFeel.shuffle,
    tempos: [120, 100],
    swing: 0.5,
    kits: ['warm', 'clean'],
    progressions: ['jazz', 'cycle', 'fifties'],
    drums: [
      DrumTemplate({
        Drum.ride: 'x.xxx.xxx.xxx.xx',
        Drum.hat: '..x...x...x...x.',
        Drum.kick: 'g...g...g...g...',
        Drum.snare: '.....o.......o..',
      }),
      DrumTemplate({
        Drum.ride: 'x.gxx.gxx.gxx.gx',
        Drum.hat: '..x...x...x...x.',
        Drum.kick: 'g.......g.....o.',
      }),
    ],
    bassBars: ['0:2 1:2 2:2 3:2', '0:2 2:2 3:2 2:2', '0:2 1:2 2:2 1:2'],
    chordBars: ['012:3 012:1 .:4', '.:2 012:2 .:2 012:2', '012:2 .:4 012:2'],
    melodyRhythms: ['n-nnn-n.', 'n.nn.nn-', 'n--nn-..', '.nnnn-n.'],
    sparkleBars: ['.:6 3:2', '.:3 2:1 .:4', '.:8'],
    gains: {'drums': 0.44, 'bass': 0.58},
  ),
  StyleRecipe(
    id: 'march',
    genre: StyleGenre.classic,
    feel: StyleFeel.straight,
    tempos: [120],
    kits: ['tight', 'clean'],
    progressions: ['classic', 'calm'],
    drums: [
      DrumTemplate({
        Drum.kick: 'x...x...x...x...',
        Drum.snare: 'x.xxx.x.x.xxx.x.',
        Drum.crash: 'o...............',
      }),
      DrumTemplate({
        Drum.kick: 'x.x.x.x.x.x.x.x.',
        Drum.snare: 'xx.x..x.xx.x..xo',
      }),
    ],
    bassBars: ['0:2 .:2 2:2 .:2', '0:2 .:2 0:2 .:2', '0:2 2:2 0:2 2:2'],
    chordBars: ['.:2 012:2 .:2 012:2', '.:2 12:2 .:2 12:2'],
    melodyInstrument: Instrument.flute,
    neighbourChance: 0.3,
    melodyRhythms: ['n-n-n-n-', 'n-nnn-n-', 'n--nn-n-', 'n-n-n---'],
    sparkleBars: ['.:4 2:1 .:3', '0:1 .:7', '.:8'],
    gains: {'drums': 0.52, 'bass': 0.5},
  ),
  StyleRecipe(
    id: 'kinderlied',
    genre: StyleGenre.classic,
    feel: StyleFeel.gentle,
    tempos: [100],
    kits: ['clean', 'warm'],
    progressions: ['classic', 'calm', 'axis'],
    drumDensity: 0.4,
    drums: [
      DrumTemplate({
        Drum.kick: 'x...x...x...x...',
        Drum.snare: '..x...x...x...x.',
        Drum.hat: 'x.x.x.x.x.x.x.x.',
      }),
      DrumTemplate({
        Drum.kick: 'x...o...x...o...',
        Drum.clap: '..x...x...x...x.',
        Drum.hat: 'xoxoxoxoxoxoxoxo',
      }),
    ],
    bassBars: ['0:4 2:4', '0:2 2:2 0:2 2:2'],
    chordBars: ['012:2 012:2 012:2 012:2', '012:4 012:4'],
    melodyInstrument: Instrument.musicBox,
    neighbourChance: 0.25,
    maxLeap: 1,
    melodyRhythms: ['n-n-n-n-', 'n-n-n---', 'nnn-n-n-', 'n-n-nnn-'],
    sparkleBars: ['.:8', '.:6 2:2', '.:4 3:1 .:3'],
    gains: {'drums': 0.42, 'melody': 0.44},
  ),
];

/// The recipe for [id], or null when unknown (a token from a newer build).
StyleRecipe? styleRecipeById(String? id) {
  if (id == null) return null;
  for (final r in kStyleRecipes) {
    if (r.id == id) return r;
  }
  return null;
}
