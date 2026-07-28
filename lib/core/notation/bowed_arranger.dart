// lib/core/notation/bowed_arranger.dart
//
// A bowed-string LEFT-HAND arranger: assigns each note of a pitch sequence to a
// (string, hand position, finger) that a player could actually reach — the cello
// analogue of the guitar tab arranger
// (`features/games/composition/tab_arranger.dart`).
//
// Same method as the guitar side — the Sayegh (1989) "optimum path" Viterbi: each
// column gets a set of candidate hand states, and we take the min-cost path where
// the transition term penalises hand movement and the local term penalises
// awkward frames. What differs is the STATE SPACE, and that difference is the
// whole point of a separate file:
//
//   guitar : the fretboard is quantised by frets, so a candidate is just a set of
//            (string, fret) pairs and "reachable" = a span cap in frets.
//   bowed  : there are no frets. The hand is a FRAME — the fingers sit at fixed
//            semitone offsets from each other — and which pitches are reachable
//            without moving is decided by that frame, not by a span number. The
//            frame itself has modes (normal / extended / thumb), so the hidden
//            state is (mode, anchor), and the finger falls out of the frame.
//
// The three facts that make a cello model different from a violin model, all
// encoded in [frameOf]:
//
//  1. NARROW FRAME. In the neck, a cellist's four fingers span only a MINOR THIRD
//     (adjacent fingers a semitone apart), where a violinist's span a perfect
//     fourth. So diatonic passages on the cello can't use 1-2-3-4 — they come out
//     as 1-3-4 / 1-2-4 (C-D-E-F on the C string = open, 1, 3, 4). We don't encode
//     those patterns as rules: they are what the frame produces, and the
//     `kCelloFirstPosition` oracle test proves it.
//  2. EXTENSIONS. Rather than shift, a cellist widens the frame — the index finger
//     reaches back or the upper fingers reach forward, one extra semitone. Modelled
//     as two extra frame modes with a PER-NOTE cost, so an extension wins for a
//     note or two and a real shift wins once it would have to be held (which is
//     how it works in the hand). Only available low on the neck, where the
//     semitone spacing is wide enough for the reach to be a distinct technique.
//  3. THUMB POSITION. High up, the thumb comes over the neck and stops the string
//     like a movable nut — a completely different geometry (thumb + 1-2-3, no
//     4th finger, wider steps). Modelled as its own mode with a large entry cost,
//     since a player commits to it for a passage rather than one note. Unlocked
//     from 10 semitones up, NOT the octave harmonic: Becker's own edition of
//     Kummer prints his «Einsatz» at 10, and leave-one-page-out over three of his
//     scale pages agrees (see [thumbEntry] on the cello).
//
// The arranger is deliberately UNTRAINED. Published bowed-string fingering models
// (HMM: Nagata/Sako/Kitamura; BLSTM: Jen et al. 2021 + the TNUA dataset;
// semi-supervised VAE: Cheung/Kao/Su, ISMIR 2021) all agree that string choice is
// nearly solved by geometry (MRR ≈ .91) while HAND POSITION is the hard, subjective
// part (F1 ≈ .24–.31 — ten professionals disagree note by note). That hard part is
// expressive high-position choice, which is exactly what a learner does NOT need:
// cap the positions and the problem becomes near-deterministic. So this ships with
// authored weights and no model asset, and [BowedPositionModel] is the seam where
// a learned emission term can later bias WHICH reachable frame wins — never
// whether it is reachable. Note that this DP is already the decoding half of an
// HMM (states = frames, transitions = shifts): fitting real transition/emission
// tables to labelled fingerings is a parameter swap, not a rewrite.
//
// Pure Dart, Flutter-free (crisp_notation_core only) → usable from headless CLIs
// and unit-testable without a device.

import 'package:crisp_notation_core/crisp_notation_core.dart'
    show Pitch, Tuning, kFingeringThumb;

/// The finger index used for the thumb in thumb position. Fingers are `0` (open
/// string) and `1`–`4`; the thumb is written `T`.
///
/// Aliases crisp_notation's [kFingeringThumb] so an arranged finger drops straight
/// into `NoteElement.fingerings` / `extraFingerings` with no translation — the
/// notation layer draws it as the `T` glyph.
const int kThumb = kFingeringThumb;

/// The shape the left hand is holding.
enum BowedHandMode {
  /// Fingers at their natural spacing (a semitone apart on the cello).
  neck,

  /// Index finger stays, the upper fingers reach one semitone further up.
  extendedForward,

  /// Upper fingers stay, the index finger reaches one semitone back down.
  extendedBackward,

  /// Thumb stops the string as a movable nut; fingers 1-2-3 above it, no 4th.
  thumb;

  bool get isExtended =>
      this == BowedHandMode.extendedForward ||
      this == BowedHandMode.extendedBackward;
}

/// The geometry of one bowed instrument: its strings, and how its left hand is
/// shaped. Everything the arranger knows about the instrument lives here, so a
/// new member of the family is data, not code.
class BowedInstrument {
  const BowedInstrument({
    required this.name,
    required this.tuning,
    required this.firstPositionOffset,
    required this.neckFingers,
    required this.fingerStep,
    required this.maxNeckPosition,
    required this.allowsExtensions,
    required this.extensionMaxPosition,
    required this.thumbEntry,
    required this.thumbFrame,
  });

  /// Display name.
  final String name;

  /// Open strings, HIGHEST first — so string index 0 is the string notated `I`
  /// (cello: A-D-G-C). Same convention as the guitar tab arranger's tab lines.
  final Tuning tuning;

  /// Semitones from the open string to the first finger in FIRST position
  /// (cello/violin: 2 — first finger sits a whole step above the open string).
  /// Position `n` therefore anchors at `firstPositionOffset + n - 1`, which makes
  /// position 0 the "half position" a semitone above the open string.
  final int firstPositionOffset;

  /// Which fingers the neck frame uses, low to high. Cello/violin `[1,2,3,4]`;
  /// double bass uses Simandl's `[1,2,4]` (no third finger).
  final List<int> neckFingers;

  /// Semitones between adjacent fingers of [neckFingers] in the neck. 1 on the
  /// cello and bass — this is the "narrow frame" that makes cello fingering
  /// unlike violin fingering.
  final int fingerStep;

  /// Highest neck position (frames above it need the thumb).
  final int maxNeckPosition;

  /// Whether the instrument's technique includes extensions at all.
  final bool allowsExtensions;

  /// Highest position at which an extension is a distinct technique. Higher up
  /// the string the spacing shrinks until the reach is unremarkable, and players
  /// stop notating it.
  final int extensionMaxPosition;

  /// Lowest anchor (semitones above the open string) at which thumb position is
  /// available. The octave harmonic (12) is where players are usually *taught* to
  /// enter it, but printed practice puts it lower — see the cello's value below.
  /// Null when the instrument has no thumb position (violin, viola).
  final int? thumbEntry;

  /// Thumb-position frame as semitone offsets from the thumb, paired positionally
  /// with `[kThumb, 1, 2, 3]`. `[0, 2, 4, 5]` is the common diatonic tetrachord
  /// (whole-whole-half); pedagogies differ, and this is the one knob to change.
  final List<int> thumbFrame;

  bool get hasThumbPosition => thumbEntry != null;

  /// Semitone offset of the frame anchor for neck position [n].
  int anchorOfPosition(int n) => firstPositionOffset + n - 1;

  /// The neck position number an [anchor] corresponds to (0 = half position).
  int positionOfAnchor(int anchor) => anchor - firstPositionOffset + 1;

  /// Standard cello: A3-D3-G2-C2, four fingers a semitone apart, thumb position
  /// from the octave harmonic up.
  static final BowedInstrument cello = BowedInstrument(
    name: 'Cello',
    tuning: Tuning(
      [
        Pitch.parse('a3'),
        Pitch.parse('d3'),
        Pitch.parse('g2'),
        Pitch.parse('c2'),
      ],
      name: 'Cello',
    ),
    firstPositionOffset: 2,
    neckFingers: const [1, 2, 3, 4],
    fingerStep: 1,
    maxNeckPosition: 7,
    allowsExtensions: true,
    extensionMaxPosition: 4,
    // 10, not the octave harmonic at 12. Evidence, three independent lines:
    //  1. Hugo Becker's own edition of Kummer Op.60 prints his C-dur «Einsatz» with
    //     the thumb at exactly 10 semitones — C4 on the D string and G4 on the A
    //     string, a pure fifth, thumb glyph on both noteheads (his p.32).
    //  2. Leave-one-page-out over three independently-read scale pages (p14/15/16,
    //     20 systems, 1056 notes): 12 -> 10 improves agreement on EVERY page, by
    //     4.1 / 6.8 / 6.4 points.
    //  3. Below 10 the gains stop generalising — p15 is flat at 55.4% for 10, 9 and
    //     8 — so the higher-scoring 8 is overfitting one page. 10 is the value that
    //     survives the held-out check AND matches the printed placement.
    thumbEntry: 10,
    thumbFrame: const [0, 2, 4, 5],
  );

  /// Double bass in Simandl fingering (1-2-4, no third finger), sounding pitch.
  /// Included because it exercises the same frame model with a different finger
  /// set — extensions off (the bass equivalent is a different technique).
  static final BowedInstrument doubleBass = BowedInstrument(
    name: 'Double bass',
    tuning: Tuning(
      [
        Pitch.parse('g2'),
        Pitch.parse('d2'),
        Pitch.parse('a1'),
        Pitch.parse('e1'),
      ],
      name: 'Double bass',
    ),
    firstPositionOffset: 1,
    neckFingers: const [1, 2, 4],
    fingerStep: 1,
    maxNeckPosition: 7,
    allowsExtensions: false,
    extensionMaxPosition: 0,
    thumbEntry: 12,
    thumbFrame: const [0, 2, 4, 5],
  );

  /// Violin tuning. ⚠ The violin hand does NOT use this file's rigid frame: its
  /// four fingers span a perfect fourth and each finger chooses a half or whole
  /// step from its neighbour (the "patterns" of violin pedagogy), so a violin
  /// arranger needs a flexible-frame model, not `fingerStep`. Kept here because
  /// the tuning itself is useful (string choice, range checks); do not hand it to
  /// [arrangeBowed] and expect idiomatic violin fingerings.
  static final Tuning violinTuning = Tuning(
    [
      Pitch.parse('e5'),
      Pitch.parse('a4'),
      Pitch.parse('d4'),
      Pitch.parse('g3'),
    ],
    name: 'Violin',
  );

  /// Viola tuning. Same caveat as [violinTuning].
  static final Tuning violaTuning = Tuning(
    [
      Pitch.parse('a4'),
      Pitch.parse('d4'),
      Pitch.parse('g3'),
      Pitch.parse('c3'),
    ],
    name: 'Viola',
  );
}

/// How much technique the player has. This is the knob that makes the arranger
/// pedagogically useful: capping positions (and switching extensions/thumb off)
/// turns the literature's hard, subjective problem into a near-deterministic one,
/// because it removes exactly the expressive high-position freedom that
/// professionals disagree about.
class BowedSkill {
  const BowedSkill({
    required this.maxPosition,
    required this.allowExtensions,
    required this.allowThumb,
    required this.preferOpenStrings,
  });

  /// Highest neck position number the player knows (1 = first position only).
  final int maxPosition;

  final bool allowExtensions;
  final bool allowThumb;

  /// Beginners are HELPED by open strings (nothing to stop, easy intonation);
  /// advanced players avoid them mid-phrase because the timbre breaks the line.
  /// This flips the sign of [BowedArrangeCost.openString].
  final bool preferOpenStrings;

  /// First position only, no extensions — what the cello games teach.
  static const BowedSkill firstPosition = BowedSkill(
    maxPosition: 1,
    allowExtensions: false,
    allowThumb: false,
    preferOpenStrings: true,
  );

  /// Neck positions 1–4 with extensions: a few years in.
  static const BowedSkill neckPositions = BowedSkill(
    maxPosition: 4,
    allowExtensions: true,
    allowThumb: false,
    preferOpenStrings: true,
  );

  /// Everything the instrument can do.
  static const BowedSkill advanced = BowedSkill(
    maxPosition: 99,
    allowExtensions: true,
    allowThumb: true,
    preferOpenStrings: false,
  );

  BowedSkill copyWith({
    int? maxPosition,
    bool? allowExtensions,
    bool? allowThumb,
    bool? preferOpenStrings,
  }) =>
      BowedSkill(
        maxPosition: maxPosition ?? this.maxPosition,
        allowExtensions: allowExtensions ?? this.allowExtensions,
        allowThumb: allowThumb ?? this.allowThumb,
        preferOpenStrings: preferOpenStrings ?? this.preferOpenStrings,
      );
}

/// The weights of the arranger's cost function. Defaults are authored so that
/// hand movement dominates (stay in position), an extension buys you one or two
/// notes before a shift becomes cheaper, and thumb position is a last resort.
class BowedArrangeCost {
  const BowedArrangeCost({
    this.shift = 1.0,
    this.shiftBase = 0.5,
    this.slurShiftScale = 2.0,
    this.stringCross = 0.3,
    this.height = 0.05,
    this.openString = 0.4,
    this.sameFinger = 0.5,
    this.extension = 0.8,
    this.thumb = 3.0,
    this.beyondSkill = 4.0,
  });

  /// Per semitone of frame-anchor movement between adjacent columns.
  final double shift;

  /// Flat cost of moving the hand AT ALL, independent of distance.
  ///
  /// [shift] alone is linear in semitones, which makes a one-semitone creep the
  /// cheapest move available — cheaper than holding an extension — and printed
  /// practice says the opposite: Romberg forbids it in words ("muss die Stellung
  /// der Hand nicht verrückt, sondern der kleine Finger … gestreckt werden"), and
  /// Becker marks the same figures as extensions. Re-placing the hand costs
  /// something regardless of how far it travels: the intonation has to be found
  /// again.
  ///
  /// 0.5 was chosen on three legs measured together, which is what every earlier
  /// attempt at this defect lacked — see `docs/PLAN.md`. At 0.5 the p.18 frame
  /// agreement goes 48/72 -> 65/72 (0 -> 17 extensions correctly chosen), the CC0
  /// repertoire RISES 50.3% -> 53.9%, and leave-one-page-out over the three Becker
  /// scale plates improves all three with none regressing. 0.75 regresses p15 and
  /// 0.25 leaves the frame defect unfixed, so the window is narrow and 0.5 sits in
  /// it on evidence rather than on a best score.
  final double shiftBase;

  /// [shift] is multiplied by this when the previous note is slurred into this
  /// one — shifting inside a bow stroke risks an audible glissando, so players
  /// shift at bow changes and rests where they can.
  final double slurShiftScale;

  /// Per string crossed between adjacent columns.
  final double stringCross;

  /// Per position of distance from the HOME frame (first position): a small pull
  /// back to where the hand rests, so all else equal the familiar frame wins.
  /// Measured from first position rather than from the nut because half position
  /// is not the cello's default — it is the special frame you take to reach a
  /// semitone above the open string, and a pure "toward the nut" pull would pick
  /// it for every note that happens to fit.
  final double height;

  /// Cost of an open string when a stopped alternative exists. Negated when
  /// [BowedSkill.preferOpenStrings] is set.
  final double openString;

  /// Reusing the same finger for a different pitch on the same string — a forced
  /// slide, and a real source of intonation trouble.
  final double sameFinger;

  /// Per note held in an extended frame.
  final double extension;

  /// Per note held in thumb position.
  final double thumb;

  /// Per position (or per technique) that a note reaches BEYOND the player's
  /// [BowedSkill]. A cost rather than a hard limit on purpose: a learner whose
  /// piece has two notes above their range plays those two notes higher and stays
  /// where they belong for the rest — they don't relearn the whole passage. Large
  /// enough to outbid any ordinary shift, so the cap only yields where it must.
  final double beyondSkill;

  /// Weights for a player who keeps the hand still: shifting is expensive and
  /// there is a pull back to the home frame. What a learner is taught, and what
  /// the `kCelloFirstPosition` oracle pins.
  static const BowedArrangeCost learner = BowedArrangeCost();

  /// Weights for a player who moves freely: shifting costs half as much and there
  /// is no pull back to first position. Measured on the CC0 gold set of printed
  /// cello fingerings (`test/bowed_arranger_accept_test.dart`), where a free hand
  /// agrees with the editors 50.3% against 43.5% for [learner] — professional
  /// editions shift readily to keep a phrase on one string. Deliberately NOT the
  /// global default: the same weights make a beginner's fingering worse, because a
  /// beginner really does keep the hand in one place.
  static const BowedArrangeCost professional =
      BowedArrangeCost(shift: 0.5, height: 0.0);

  /// The weights that match [skill]: the pedagogical profiles get [learner],
  /// anyone with thumb position gets [professional].
  static BowedArrangeCost forSkill(BowedSkill skill) =>
      skill.allowThumb ? professional : learner;
}

/// One note's assignment.
class BowedFingering {
  const BowedFingering({
    required this.string,
    required this.finger,
    required this.semitones,
    required this.mode,
    required this.anchor,
    required this.position,
  });

  /// String index, 0 = highest string (notated `I`).
  final int string;

  /// `0` = open string, `1`–`4` = fingers, [kThumb] = thumb.
  final int finger;

  /// Semitones above the open string (0 = open).
  final int semitones;

  /// The frame the hand is in.
  final BowedHandMode mode;

  /// Frame anchor, in semitones above the open string.
  final int anchor;

  /// Neck position number (0 = half position). Also filled in thumb mode, where
  /// it is the position the thumb's stop corresponds to.
  final int position;

  bool get isOpen => finger == 0;

  /// String number as players notate it: `I` (highest) … `IV`.
  String get roman => const ['I', 'II', 'III', 'IV', 'V', 'VI'][string];

  /// Finger as players notate it: `0`, `1`–`4`, `T`.
  String get fingerLabel => finger == kThumb ? 'T' : '$finger';

  @override
  String toString() => '$roman/$fingerLabel@$position'
      '${mode == BowedHandMode.neck ? '' : ' ${mode.name}'}';
}

/// The result of an arrange: one entry per input column (empty for a rest).
class BowedArrangement {
  const BowedArrangement({
    required this.columns,
    required this.skill,
    required this.relaxed,
    required this.cost,
  });

  final List<List<BowedFingering>> columns;

  /// The skill profile actually used — see [relaxed].
  final BowedSkill skill;

  /// True when at least one note reaches beyond the requested [BowedSkill]. The
  /// caps are soft costs, so the rest of the passage still fingers at the
  /// player's level — callers that care can surface "bar 12 needs fourth
  /// position", and nobody ever gets a partial result.
  final bool relaxed;

  /// Total path cost (for benchmarks and A/B sweeps).
  final double cost;
}

/// Scores candidate frames per column so a data-driven model can supply the
/// LOCAL term while the Viterbi stays the arbiter — the bowed twin of
/// `TabPositionModel`. Shift cost and frame reachability remain ours, so a model
/// can bias which playable frame wins but can never produce an unreachable one.
/// A null return (whole or per-column) defers to the authored cost.
abstract interface class BowedPositionModel {
  /// `higher = more idiomatic`, keyed by (mode, anchor) per column.
  List<Map<(BowedHandMode mode, int anchor), double>?>? score(
    List<List<int>> columns,
    BowedInstrument instrument,
  );
}

/// Process-wide model consulted when no explicit `model` is passed, mirroring
/// `TabArranger.shared`. Null (the default) = the authored cost function, which
/// is also the guaranteed fallback.
class BowedArranger {
  BowedArranger._();

  static BowedPositionModel? shared;
}

/// Finger → semitone offset above the open string for the frame [mode] anchored
/// at [anchor]. This is the entire hand model; everything else is bookkeeping.
Map<int, int> frameOf(
  BowedInstrument inst,
  BowedHandMode mode,
  int anchor,
) {
  switch (mode) {
    case BowedHandMode.neck:
      // Rule 1: adjacent fingers one [fingerStep] apart — the narrow frame.
      return {
        for (var i = 0; i < inst.neckFingers.length; i++)
          inst.neckFingers[i]: anchor + i * inst.fingerStep,
      };
    case BowedHandMode.extendedForward:
      // Rule 2a: 1 stays put, everything above reaches one semitone further.
      return {
        for (var i = 0; i < inst.neckFingers.length; i++)
          inst.neckFingers[i]: anchor + i * inst.fingerStep + (i == 0 ? 0 : 1),
      };
    case BowedHandMode.extendedBackward:
      // Rule 2b: the 2-3-4 group stays, 1 reaches a semitone back.
      return {
        for (var i = 0; i < inst.neckFingers.length; i++)
          inst.neckFingers[i]: anchor + i * inst.fingerStep + (i == 0 ? -1 : 0),
      };
    case BowedHandMode.thumb:
      // Rule 3: a different geometry — thumb as a movable nut, fingers 1-2-3
      // above it at [thumbFrame] steps, no 4th finger.
      const fingers = [kThumb, 1, 2, 3];
      return {
        for (var i = 0; i < inst.thumbFrame.length && i < fingers.length; i++)
          fingers[i]: anchor + inst.thumbFrame[i],
      };
  }
}

/// A hand state: which frame, anchored where.
class _Hand {
  const _Hand(this.mode, this.anchor);
  final BowedHandMode mode;
  final int anchor;

  @override
  bool operator ==(Object other) =>
      other is _Hand && other.mode == mode && other.anchor == anchor;

  @override
  int get hashCode => Object.hash(mode, anchor);
}

/// One playable way to sound a column: a hand state plus the per-pitch stops.
class _Candidate {
  _Candidate(this.hand, this.stops, this.local);

  /// Null when the column needs no finger at all (all-open / rest): the hand is
  /// then free, and we inherit the previous anchor so an open string costs no
  /// movement — the same "position-free" treatment open strings get on guitar.
  final _Hand? hand;
  final List<BowedFingering> stops;
  final double local;
}

/// Whether the INSTRUMENT can hold this frame at all. Hard: no cost can buy a
/// cellist a fifth finger or a thumb below the octave.
bool _modeAllowed(
  BowedInstrument inst,
  BowedHandMode mode,
  int anchor,
) {
  final position = inst.positionOfAnchor(anchor);
  if (mode == BowedHandMode.thumb) {
    if (!inst.hasThumbPosition) return false;
    return anchor >= inst.thumbEntry!;
  }
  if (position < 0 || position > inst.maxNeckPosition) return false;
  if (mode.isExtended) {
    if (!inst.allowsExtensions) return false;
    if (position < 1 || position > inst.extensionMaxPosition) return false;
  }
  return true;
}

/// What this frame costs a player of the given [skill] — 0 when it is within
/// their technique. Soft, so a passage that briefly leaves their range costs them
/// those notes instead of the whole piece.
double _skillCost(
  BowedInstrument inst,
  BowedSkill skill,
  BowedHandMode mode,
  int anchor,
  BowedArrangeCost cost,
) {
  var out = 0.0;
  final position = inst.positionOfAnchor(anchor);
  if (position > skill.maxPosition) {
    out += cost.beyondSkill * (position - skill.maxPosition);
  }
  if (mode.isExtended && !skill.allowExtensions) out += cost.beyondSkill;
  if (mode == BowedHandMode.thumb && !skill.allowThumb) {
    out += cost.beyondSkill * 2;
  }
  return out;
}

/// True when [f] reaches past what [skill] covers — drives
/// [BowedArrangement.relaxed].
///
/// ⚠ PUBLIC because the playability check needs exactly this question, and the
/// skill limits are SOFT COSTS: the arranger will happily hand a first-position
/// student a fingering in 7th position, paying `beyondSkill` for it, rather than
/// refuse the note. So "is it playable at this level?" cannot be answered by
/// asking whether a fingering EXISTS — it always does — only by asking whether
/// the one chosen stayed inside the level. Two copies of that predicate would
/// drift, so there is one.
bool beyondSkill(BowedInstrument inst, BowedSkill skill, BowedFingering f) =>
    f.position > skill.maxPosition ||
    (f.mode.isExtended && !skill.allowExtensions) ||
    (f.mode == BowedHandMode.thumb && !skill.allowThumb);

/// Every stop that sounds [midi] on [inst]: (string, semitones above open).
List<(int, int)> _stopsFor(int midi, BowedInstrument inst) {
  final out = <(int, int)>[];
  for (var s = 0; s < inst.tuning.strings.length; s++) {
    final semis = midi - inst.tuning.strings[s].midiNumber;
    if (semis >= 0) out.add((s, semis));
  }
  return out;
}

/// All hand states under which [midi] is playable, ignoring skill caps.
Set<_Hand> _handsFor(int midi, BowedInstrument inst) {
  final out = <_Hand>{};
  for (final (_, semis) in _stopsFor(midi, inst)) {
    if (semis == 0) continue; // open: frame-free
    for (final mode in BowedHandMode.values) {
      // Invert the frame: for each finger that could take this stop, the anchor
      // it implies. Cheaper and exact compared with sweeping every anchor.
      final probe = frameOf(inst, mode, 0);
      for (final delta in probe.values) {
        out.add(_Hand(mode, semis - delta));
      }
    }
  }
  return out;
}

/// Assign every pitch of one column to a stop within [hand] (or an open string).
/// Returns null when the column cannot be played in that hand state. Each string
/// and each finger may be used once; open strings are always available.
///
/// Exhaustive, not greedy: a column has at most a handful of pitches and each has
/// at most one stop per string, so the search is tiny — and greedy gets double
/// stops wrong (the low note has to end up on the lower string, which only shows
/// up as a constraint once the high note has been placed).
List<BowedFingering>? _assign(
  List<int> pitches,
  BowedInstrument inst,
  _Hand? hand,
  BowedSkill skill,
  BowedArrangeCost cost,
) {
  final frame =
      hand == null ? const <int, int>{} : frameOf(inst, hand.mode, hand.anchor);
  final byOffset = <int, int>{for (final e in frame.entries) e.value: e.key};
  // Lowest pitch first, so the recursion places the note with the fewest options
  // (the low one, on the low strings) before the flexible ones.
  final sorted = [...pitches]..sort();
  final openTerm = skill.preferOpenStrings ? -cost.openString : cost.openString;

  List<BowedFingering>? best;
  var bestScore = double.infinity;

  void walk(
    int index,
    Set<int> usedStrings,
    Set<int> usedFingers,
    List<BowedFingering> acc,
    double score,
  ) {
    if (score >= bestScore) return; // nothing below can beat the incumbent
    if (index == sorted.length) {
      bestScore = score;
      best = [...acc];
      return;
    }
    for (final (string, semis) in _stopsFor(sorted[index], inst)) {
      if (usedStrings.contains(string)) continue;
      final int finger;
      if (semis == 0) {
        finger = 0;
      } else {
        final f = byOffset[semis];
        if (f == null) continue;
        if (usedFingers.contains(f)) {
          // One finger CAN take two notes: laid flat across adjacent strings at
          // the same stop, which is how a cellist plays a fifth. Any other reuse
          // is one finger in two places at once.
          final barred = acc.any(
            (s) =>
                s.finger == f &&
                s.semitones == semis &&
                (s.string - string).abs() == 1,
          );
          if (!barred) continue;
        }
        finger = f;
      }
      acc.add(
        BowedFingering(
          string: string,
          finger: finger,
          semitones: semis,
          mode: hand?.mode ?? BowedHandMode.neck,
          anchor: hand?.anchor ?? inst.firstPositionOffset,
          position:
              inst.positionOfAnchor(hand?.anchor ?? inst.firstPositionOffset),
        ),
      );
      usedStrings.add(string);
      if (finger != 0) usedFingers.add(finger);
      // Prefer the shortest stop (lowest on the string, so the highest string
      // that works) and let the skill profile decide about open strings.
      walk(
        index + 1,
        usedStrings,
        usedFingers,
        acc,
        score + semis + (finger == 0 ? openTerm : 0),
      );
      acc.removeLast();
      usedStrings.remove(string);
      if (finger != 0) usedFingers.remove(finger);
    }
  }

  walk(0, <int>{}, <int>{}, <BowedFingering>[], 0);
  if (best == null) return null;
  // Report in input order, not sorted order, so callers can zip with their notes.
  final byPitch = <int, List<BowedFingering>>{};
  for (var i = 0; i < sorted.length; i++) {
    byPitch.putIfAbsent(sorted[i], () => []).add(best![i]);
  }
  return [for (final midi in pitches) byPitch[midi]!.removeLast()];
}

/// Assigns a (string, position, finger) to every note of [columns] — a list of
/// simultaneous MIDI pitches per column, empty for a rest.
///
/// [slurToNext] (optional, one flag per column) marks a column slurred into the
/// next, which makes a shift across that join more expensive.
///
/// Never returns a partial arrangement: [skill] is a set of soft costs, so a note
/// beyond the player's technique is fingered anyway (at a large penalty, so only
/// where forced) and [BowedArrangement.relaxed] is set.
BowedArrangement arrangeBowed(
  List<List<int>> columns, {
  required BowedSkill skill,
  BowedInstrument? instrument,
  BowedArrangeCost? cost,
  List<bool>? slurToNext,
  BowedPositionModel? model,
}) {
  final inst = instrument ?? BowedInstrument.cello;
  // Weights follow the skill unless the caller pins them (benchmarks, sweeps).
  final weights = cost ?? BowedArrangeCost.forSkill(skill);
  final result = _arrange(
    columns,
    inst,
    skill,
    weights,
    slurToNext,
    model ?? BowedArranger.shared,
  );
  if (result != null) {
    return BowedArrangement(
      columns: result.$1,
      skill: skill,
      relaxed: result.$1.any((c) => c.any((f) => beyondSkill(inst, skill, f))),
      cost: result.$2,
    );
  }
  // Out of range for the instrument as a SEQUENCE — e.g. a part that dips below
  // the lowest string, or a chord no single frame can hold. Fall back to fingering
  // each column on its own, so the caller still gets every note we can reach and
  // only the genuinely impossible ones come back empty.
  return BowedArrangement(
    columns: [for (final column in columns) _bestEffort(column, inst, weights)],
    skill: BowedSkill.advanced,
    relaxed: true,
    cost: double.infinity,
  );
}

/// The best fingering for one column considered alone, over every frame the
/// instrument has. Used only by the last-resort path in [arrangeBowed].
List<BowedFingering> _bestEffort(
  List<int> column,
  BowedInstrument inst,
  BowedArrangeCost cost,
) {
  if (column.isEmpty) return const [];
  final open = _assign(column, inst, null, BowedSkill.advanced, cost);
  if (open != null) return open;
  final hands = <_Hand>{};
  for (final midi in column) {
    hands.addAll(_handsFor(midi, inst));
  }
  List<BowedFingering>? best;
  var bestHome = 1 << 30;
  for (final hand in hands) {
    if (!_modeAllowed(inst, hand.mode, hand.anchor)) continue;
    final stops = _assign(column, inst, hand, BowedSkill.advanced, cost);
    if (stops == null) continue;
    final home = _homeDistance(inst, hand.anchor);
    if (home < bestHome) {
      bestHome = home;
      best = stops;
    }
  }
  return best ?? const [];
}

/// How far [anchor] sits from the home (first) position, in positions.
int _homeDistance(BowedInstrument inst, int anchor) =>
    (inst.positionOfAnchor(anchor) - 1).abs();

(List<List<BowedFingering>>, double)? _arrange(
  List<List<int>> columns,
  BowedInstrument inst,
  BowedSkill skill,
  BowedArrangeCost cost,
  List<bool>? slurToNext,
  BowedPositionModel? model,
) {
  if (columns.isEmpty) return (const [], 0);
  final emissions = model?.score(columns, inst);

  // 1. Candidates per column.
  final candidates = <List<_Candidate>>[];
  for (var c = 0; c < columns.length; c++) {
    final column = columns[c];
    final out = <_Candidate>[];
    if (column.isEmpty) {
      out.add(_Candidate(null, const [], 0));
    } else {
      // The frame-free candidate first (all notes on open strings).
      final open = _assign(column, inst, null, skill, cost);
      if (open != null && open.every((f) => f.isOpen)) {
        out.add(
          _Candidate(
            null,
            open,
            _localOf(open, null, inst, skill, cost, emissions, c),
          ),
        );
      }
      final hands = <_Hand>{};
      for (final midi in column) {
        hands.addAll(_handsFor(midi, inst));
      }
      for (final hand in hands) {
        if (!_modeAllowed(inst, hand.mode, hand.anchor)) continue;
        final stops = _assign(column, inst, hand, skill, cost);
        if (stops == null) continue;
        // An all-open assignment under a frame is the frame-free candidate in
        // disguise; drop it so the hand isn't pinned by a note it never stopped.
        if (stops.every((f) => f.isOpen)) continue;
        out.add(
          _Candidate(
            hand,
            stops,
            _localOf(stops, hand, inst, skill, cost, emissions, c),
          ),
        );
      }
    }
    if (out.isEmpty) return null;
    candidates.add(out);
  }

  // 2. Viterbi.
  var prev = <int, double>{
    for (var i = 0; i < candidates[0].length; i++) i: candidates[0][i].local,
  };
  final back = <Map<int, int>>[];
  // The anchor a frame-free column inherits, tracked per path so an open-string
  // note between two stopped notes costs no movement.
  var prevAnchor = <int, _Hand?>{
    for (var i = 0; i < candidates[0].length; i++) i: candidates[0][i].hand,
  };
  for (var c = 1; c < columns.length; c++) {
    final next = <int, double>{};
    final choice = <int, int>{};
    final anchor = <int, _Hand?>{};
    for (var j = 0; j < candidates[c].length; j++) {
      final cand = candidates[c][j];
      var best = double.infinity;
      var bestFrom = -1;
      for (final entry in prev.entries) {
        final from = prevAnchor[entry.key];
        final t = entry.value +
            _transition(
              from,
              cand.hand,
              candidates[c - 1][entry.key].stops,
              cand.stops,
              cost,
              slurred: slurToNext != null &&
                  c - 1 < slurToNext.length &&
                  slurToNext[c - 1],
            );
        if (t < best) {
          best = t;
          bestFrom = entry.key;
        }
      }
      if (bestFrom < 0) continue;
      next[j] = best + cand.local;
      choice[j] = bestFrom;
      anchor[j] = cand.hand ?? prevAnchor[bestFrom];
    }
    if (next.isEmpty) return null;
    prev = next;
    prevAnchor = anchor;
    back.add(choice);
  }

  // 3. Backtrack.
  var bestEnd = -1;
  var bestCost = double.infinity;
  for (final e in prev.entries) {
    if (e.value < bestCost) {
      bestCost = e.value;
      bestEnd = e.key;
    }
  }
  if (bestEnd < 0) return null;
  final chosen = List<int>.filled(columns.length, 0);
  chosen[columns.length - 1] = bestEnd;
  for (var c = columns.length - 1; c > 0; c--) {
    chosen[c - 1] = back[c - 1][chosen[c]]!;
  }
  return (
    [for (var c = 0; c < columns.length; c++) candidates[c][chosen[c]].stops],
    bestCost,
  );
}

double _localOf(
  List<BowedFingering> stops,
  _Hand? hand,
  BowedInstrument inst,
  BowedSkill skill,
  BowedArrangeCost cost,
  List<Map<(BowedHandMode, int), double>?>? emissions,
  int column,
) {
  var out = 0.0;
  if (hand != null) {
    out += cost.height * _homeDistance(inst, hand.anchor);
    if (hand.mode.isExtended) out += cost.extension;
    if (hand.mode == BowedHandMode.thumb) out += cost.thumb;
    // The player's own limits. Kept OUT of the model branch below: what a learner
    // can reach is a property of the player, not of what is idiomatic, so a
    // learned emission must not be able to talk them into eighth position.
    out += _skillCost(inst, skill, hand.mode, hand.anchor, cost);
  }
  for (final stop in stops) {
    if (stop.isOpen) {
      out += skill.preferOpenStrings ? -cost.openString : cost.openString;
    }
  }
  // A model, when present, REPLACES the authored frame preference (height /
  // extension / thumb) with its learned emission but keeps the open-string term;
  // reachability and movement stay with the DP either way.
  final e = emissions == null || column >= emissions.length
      ? null
      : emissions[column];
  if (e != null && hand != null) {
    final score = e[(hand.mode, hand.anchor)];
    if (score != null) {
      out -= score;
      out -= cost.height * _homeDistance(inst, hand.anchor);
      if (hand.mode.isExtended) out -= cost.extension;
      if (hand.mode == BowedHandMode.thumb) out -= cost.thumb;
    }
  }
  return out;
}

double _transition(
  _Hand? from,
  _Hand? to,
  List<BowedFingering> fromStops,
  List<BowedFingering> toStops,
  BowedArrangeCost cost, {
  required bool slurred,
}) {
  var out = 0.0;
  if (from != null && to != null) {
    final shift = (to.anchor - from.anchor).abs().toDouble();
    if (shift > 0) out += cost.shiftBase;
    out += shift * cost.shift * (slurred ? cost.slurShiftScale : 1.0);
  }
  if (fromStops.isNotEmpty && toStops.isNotEmpty) {
    out += cost.stringCross *
        (toStops.first.string - fromStops.first.string).abs();
    // Same finger, same string, different pitch = a forced slide.
    for (final a in fromStops) {
      for (final b in toStops) {
        if (a.finger != 0 &&
            a.finger == b.finger &&
            a.string == b.string &&
            a.semitones != b.semitones) {
          out += cost.sameFinger;
        }
      }
    }
  }
  return out;
}
