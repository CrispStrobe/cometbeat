// lib/core/harmony/comp_arranger.dart
//
// BB-A1 — the voicing arranger. A chord symbol becomes notes a player would
// actually play, and consecutive chords are voice-led into each other rather
// than each being voiced in isolation.
//
// This is the third arranger in the codebase with the same shape: choose one
// state per event, minimise a transition cost, take the optimum path. The other
// two are `arrangeTab` (crisp_notation_core — a set of string/fret pairs) and
// `bowed_arranger.dart` (a hand FRAME). Here the state is a VOICING and the cost
// is voice leading.
//
// 🛑 **The three are NOT unified into a shared solver, deliberately.** The bowed
// arranger's weights are tuned against printed method literature — ~54% finger
// agreement over ~2,900 transcribed notes, established by a 135-point weight
// sweep — so refactoring it to share a skeleton risks real, measured numbers for
// an abstraction nobody asked for. A third self-contained DP is the cheaper
// mistake. If a fourth ever appears, extract then.
//
// ⚠️ **Flutter-free, and that is load-bearing.** The obvious source of real
// guitar shapes, `features/games/composition/chord_db.dart`, imports
// `package:flutter/services.dart` for `rootBundle`, so importing it here would
// drag Flutter into the harmony core and cost BB-D4a its command-line path.
// Grips therefore arrive through an injected [GripProvider]; the loader stays at
// the edge, the way `microphone_pitch_service.dart` is the app's only
// plugin-facing audio file.
//
// ONE DESIGN NOTE WORTH READING. The card asked for "an avoid-note table
// (natural 11 over a major triad, ♭9 where unmarked…)". Building it turned out to
// be unnecessary: once tones are PLACED as midi notes, every entry that table
// would hold reduces to *a semitone between adjacent voices*. A natural 11 over a
// major third is F against E; an unmarked ♭9 against the root is D♭ against C.
// So there is one rule — [_clashCost] — instead of a table that would need a new
// row per chord type, and it generalises to clashes nobody enumerated.

import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show Pitch, VoiceLeadingRule, checkVoiceLeading;

/// A way of arranging a chord's tones into a playable shape.
enum VoicingShape {
  /// All tones inside an octave, stacked in order. The default keyboard shape.
  close,

  /// Close position with the second voice from the top dropped an octave — the
  /// standard guitar/piano spread that opens the sound without widening the hand.
  drop2,

  /// Close position with the THIRD voice from the top dropped an octave.
  drop3,

  /// Root and seventh, plus the third when a third voice is allowed. Sparse,
  /// stays out of a soloist's way.
  shell,

  /// 3-5-7-9 with no root — the bass has the root, so the comp does not need it.
  rootlessA,

  /// The same tones voiced from the seventh up.
  rootlessB,

  /// The third and the seventh only: the two notes that carry the quality.
  guideTones,

  /// A shape supplied by a [GripProvider] — a real fingering, not a computed one.
  grip,
}

/// Supplies ready-made voicings as ascending absolute MIDI notes — real guitar
/// or ukulele grips, typically. Injected rather than imported so this file stays
/// Flutter-free; see the header.
typedef GripProvider = List<List<int>> Function(ChordSpec chord);

/// The register and density a role plays in.
class VoicingConstraints {
  const VoicingConstraints({
    required this.lowMidi,
    required this.highMidi,
    this.maxVoices = 4,
    this.maxSpan = 14,
    this.includeRoot = true,
    this.shapes = const {
      VoicingShape.close,
      VoicingShape.drop2,
      VoicingShape.drop3,
      VoicingShape.shell,
    },
  });

  /// The lowest and highest MIDI note the role may sound.
  final int lowMidi;
  final int highMidi;

  /// How many notes at most. Fewer than the chord has tones means tones get
  /// dropped, in the priority [_selectTones] documents.
  final int maxVoices;

  /// The widest interval from bottom to top, in semitones. 14 is a comfortable
  /// keyboard hand; a pad can be wider, a guitar grip is what it is.
  final int maxSpan;

  /// Whether the voicing includes the root. False for the rootless shapes, where
  /// the bass is expected to supply it.
  final bool includeRoot;

  final Set<VoicingShape> shapes;

  /// Both hands' worth of comping range, four voices.
  ///
  /// ⚠️ `maxSpan` is 19, not the one-hand default of 14: a drop-2 of a four-note
  /// close voicing spans 15 semitones and a drop-3 spans 18, so 14 would have
  /// silently rejected every drop voicing and left only close position — the
  /// shapes would have existed and never been reachable.
  static const piano =
      VoicingConstraints(lowMidi: 48, highMidi: 84, maxSpan: 19);

  /// The rootless register a pianist comps in behind a soloist, where the bass
  /// owns the root.
  static const pianoRootless = VoicingConstraints(
    lowMidi: 55,
    highMidi: 84,
    includeRoot: false,
    shapes: {VoicingShape.rootlessA, VoicingShape.rootlessB},
  );

  /// Guitar: real grips first, computed shapes as the fallback for qualities the
  /// grip database cannot express.
  static const guitar = VoicingConstraints(
    lowMidi: 40,
    highMidi: 76,
    maxVoices: 6,
    maxSpan: 24,
    shapes: {VoicingShape.grip, VoicingShape.drop2, VoicingShape.close},
  );

  /// A sustained background: few notes, wide, high.
  static const pad = VoicingConstraints(
    lowMidi: 60,
    highMidi: 88,
    maxVoices: 3,
    maxSpan: 19,
    shapes: {VoicingShape.close, VoicingShape.guideTones},
  );

  VoicingConstraints copyWith({
    int? lowMidi,
    int? highMidi,
    int? maxVoices,
    int? maxSpan,
    bool? includeRoot,
    Set<VoicingShape>? shapes,
  }) =>
      VoicingConstraints(
        lowMidi: lowMidi ?? this.lowMidi,
        highMidi: highMidi ?? this.highMidi,
        maxVoices: maxVoices ?? this.maxVoices,
        maxSpan: maxSpan ?? this.maxSpan,
        includeRoot: includeRoot ?? this.includeRoot,
        shapes: shapes ?? this.shapes,
      );
}

/// One playable shape for one chord.
class Voicing {
  Voicing(this.chord, this.shape, List<int> midis)
      : midis = List.unmodifiable(midis) {
    assert(midis.isNotEmpty, 'a voicing needs at least one note');
    assert(_isAscending(midis), 'midis must be ascending and unique');
  }

  final ChordSpec chord;
  final VoicingShape shape;

  /// Ascending, unique, absolute MIDI notes.
  final List<int> midis;

  int get bottom => midis.first;
  int get top => midis.last;
  int get span => top - bottom;
  int get voices => midis.length;

  /// The voicing as pitches ordered TOP FIRST, which is the order
  /// `checkVoiceLeading` expects (voice 0 is the top voice).
  List<Pitch> get pitchesTopDown =>
      [for (final m in midis.reversed) Pitch.fromMidi(m)];

  /// Semitones between neighbouring voices, bottom to top.
  List<int> get gaps =>
      [for (var i = 1; i < midis.length; i++) midis[i] - midis[i - 1]];

  @override
  String toString() => 'Voicing(${chord.text} ${shape.name} $midis)';

  static bool _isAscending(List<int> xs) {
    for (var i = 1; i < xs.length; i++) {
      if (xs[i] <= xs[i - 1]) return false;
    }
    return true;
  }
}

// ── candidate generation (A1a) ─────────────────────────────────────────────

/// Every shape × octave placement that fits [c], for one chord.
///
/// Returns candidates rather than a single answer because choosing between them
/// needs the NEXT chord, which only [arrangeComp] knows. Deterministic: the same
/// inputs always produce the same list in the same order, so the path search
/// below can break ties by index and stay reproducible without a seed.
List<Voicing> voicingCandidates(
  ChordSpec chord,
  VoicingConstraints c, {
  GripProvider? grips,
}) {
  final out = <Voicing>[];

  for (final shape in c.shapes) {
    if (shape == VoicingShape.grip) {
      for (final grip in grips?.call(chord) ?? const <List<int>>[]) {
        final sorted = (grip.toSet().toList())..sort();
        if (sorted.isEmpty) continue;
        if (sorted.first < c.lowMidi || sorted.last > c.highMidi) continue;
        out.add(Voicing(chord, shape, sorted));
      }
      continue;
    }

    final base = _shapeOffsets(shape, chord, c);
    if (base == null || base.isEmpty) continue;

    // Place the shape at every octave of the ROOT that fits the window. A shape
    // that fits in three octaves yields three candidates and the path picks the
    // register.
    //
    // 🔴 The alignment is the whole point: offsets are semitones above the root,
    // so the anchor must be a midi note whose pitch class IS the root. Stepping
    // by 12 from the window's bottom instead (the first version of this) voices
    // every chord at whatever pitch the window happens to start on — a D minor
    // seventh came out as C-E♭-G-B♭, i.e. a different chord. It survived the
    // twelve-key gate because that gate only measured top-voice MOTION and
    // parallels, both of which look perfect on a consistently-wrong answer. The
    // test now also asserts that a voicing spells its chord.
    final rootPc = _rootPcOf(chord);
    for (final offsets in _inversions(base)) {
      for (var rootMidi = _alignUpTo(c.lowMidi - 24, rootPc);
          rootMidi <= c.highMidi + 12;
          rootMidi += 12) {
        final midis = (offsets.map((o) => rootMidi + o).toSet().toList())
          ..sort();
        if (midis.first < c.lowMidi || midis.last > c.highMidi) continue;
        if (midis.last - midis.first > c.maxSpan) continue;
        out.add(Voicing(chord, shape, midis));
      }
    }
  }

  // A chord whose window admits nothing (an extreme register, or a grip set that
  // does not fit) must still produce something playable — a silent comp is a bug
  // the user hears, and no caller should have to handle an empty list.
  if (out.isEmpty) out.add(_lastResort(chord, c));
  return out;
}

/// Every inversion of a shape: the lowest tone moves up an octave, repeatedly.
///
/// 🔴 **This is not a refinement, it is a requirement, and the card's acceptance
/// gate is what proved it.** Without inversions a shape can only be placed at
/// octaves of the root, so the notes available on TOP are quantised 12 semitones
/// apart. Measured on the ii-V-I in C: Dm7 could put only 60, 72 or 84 on top and
/// G7 only 65 or 77, making the smallest possible top-voice move 5 semitones —
/// the gate asks for ≤2, and no cost tuning could ever have reached it. Rotating
/// the shape is how a real comper controls the top line, and it is what lets a
/// guide-tone line exist at all.
List<List<int>> _inversions(List<int> offsets) {
  final out = <List<int>>[];
  final cur = [...offsets]..sort();
  for (var i = 0; i < offsets.length; i++) {
    out.add([...cur]);
    final lowest = cur.removeAt(0);
    cur.add(lowest + 12);
    cur.sort();
  }
  return out;
}

/// Semitone offsets above the root for [shape], or null when the shape does not
/// apply to this chord (a rootless voicing of a power chord, say).
List<int>? _shapeOffsets(
  VoicingShape shape,
  ChordSpec chord,
  VoicingConstraints c,
) {
  final guide = chord.guideTones;
  final all = chord.intervals;

  switch (shape) {
    case VoicingShape.guideTones:
      return guide.isEmpty ? null : guide;

    case VoicingShape.shell:
      final seventh = _seventhOf(all);
      if (seventh == null) return null;
      final third = _thirdOf(all);
      return c.maxVoices >= 3 && third != null
          ? [0, third, seventh]
          : [0, seventh];

    case VoicingShape.rootlessA:
    case VoicingShape.rootlessB:
      final third = _thirdOf(all);
      final seventh = _seventhOf(all);
      if (third == null || seventh == null) return null;
      final fifth = _fifthOf(all);
      final ninth = _ninthOf(all);
      // Same priority discipline as [_selectTones], and it has to be a LOOP
      // rather than one removal: dropping only the fifth still leaves three notes
      // for a two-voice role. Guide tones first, then colour, then filler.
      final priority = <int>[
        third,
        seventh,
        if (ninth != null) ninth,
        if (fifth != null) fifth,
      ];
      final tones = <int>[];
      for (final t in priority) {
        if (tones.length >= c.maxVoices) break;
        tones.add(t);
      }
      if (tones.isEmpty) return null;
      // Rootless B is the same tones voiced from the seventh up: everything
      // below the seventh moves up an octave, which is what puts the 7th at the
      // bottom without inventing new notes.
      if (shape == VoicingShape.rootlessB) {
        return [for (final t in tones) t < seventh ? t + 12 : t]..sort();
      }
      return tones..sort();

    case VoicingShape.close:
      return _closePosition(chord, c);

    case VoicingShape.drop2:
    case VoicingShape.drop3:
      final close = _closePosition(chord, c);
      if (close == null || close.length < 4) return null;
      // Count from the TOP: drop2 lowers the 2nd voice down, drop3 the 3rd.
      final indexFromTop = shape == VoicingShape.drop2 ? 1 : 2;
      final i = close.length - 1 - indexFromTop;
      final dropped = [...close];
      dropped[i] = dropped[i] - 12;
      final set = dropped.toSet().toList()..sort();
      return set.length == close.length ? set : null;

    case VoicingShape.grip:
      return null; // handled by the caller
  }
}

/// The selected tones packed inside one octave above the root, ascending.
List<int>? _closePosition(ChordSpec chord, VoicingConstraints c) {
  final tones = _selectTones(chord, c);
  if (tones.isEmpty) return null;
  // Reducing into one octave is what "close position" MEANS — a ninth becomes a
  // second. That is the sound, not a loss: a close-voiced C9 really is C-D-E-G-B♭.
  final reduced = <int>{for (final t in tones) t % 12};
  final out = reduced.toList()..sort();
  return out;
}

/// Which tones to keep when the chord has more than [VoicingConstraints.maxVoices].
///
/// The priority is what a player does, in order:
///   1. **keep the guide tones** — the third (or its sus substitute) and the
///      seventh carry the chord's identity and are never dropped;
///   2. drop the **fifth** first, unless it is altered, in which case it is
///      colour rather than filler;
///   3. drop the **root** next when the bass has it ([includeRoot] false);
///   4. keep the **highest extension** — it is what the symbol is NAMED for. A
///      C13 voiced 1-3-♭7-9 has dropped the 13th, i.e. the whole point of the
///      chord; 1-3-♭7-13 is what a player reaches for.
List<int> _selectTones(ChordSpec chord, VoicingConstraints c) {
  final all = chord.intervals;
  final guide = chord.guideTones;

  final fifthAltered = chord.alterations.contains(ChordAlteration.flatFive) ||
      chord.alterations.contains(ChordAlteration.sharpFive);

  // Everything else, most-wanted first.
  final mandatory = <int>{...guide, if (c.includeRoot) 0};
  final rest = <int>[
    for (final t in all)
      if (!mandatory.contains(t) && t != 0) t,
  ]..sort();
  final fifth = _fifthOf(all);

  // Colour before filler. Extensions come HIGHEST-FIRST because the top of the
  // stack is what the symbol names — on a C13 the 13th is the chord's identity
  // and the 9th is padding, so a four-voice reading is 1-3-♭7-13. An altered
  // fifth is colour too and ranks with them; a plain fifth is the first thing a
  // player drops.
  final extensions = rest.where((t) => t >= 13).toList()
    ..sort((a, b) => b.compareTo(a));
  final lower = rest.where((t) => t < 13 && t != fifth).toList()..sort();
  final ordered = <int>[
    if (fifth != null && fifthAltered) fifth,
    ...extensions,
    ...lower,
    if (fifth != null && !fifthAltered) fifth,
  ];

  // ONE priority list, so `maxVoices` is honoured even when it is smaller than
  // the mandatory set. Guide tones first (they are the chord's identity), then
  // the root, then colour, then filler. A two-voice reading of C13 is therefore
  // 3-♭7 — the guide tones — and not 1-3-♭7 truncated at three notes, which is
  // what a version that seeded the set with the mandatory tones produced.
  final priority = <int>[
    ...guide,
    if (c.includeRoot) 0,
    ...ordered,
  ];
  final out = <int>{};
  for (final t in priority) {
    if (out.length >= c.maxVoices) break;
    out.add(t);
  }
  final list = out.toList()..sort();
  return list;
}

int? _thirdOf(List<int> intervals) {
  for (final t in const [3, 4, 2, 5]) {
    if (intervals.contains(t)) return t;
  }
  return null;
}

int? _fifthOf(List<int> intervals) {
  for (final t in const [7, 6, 8]) {
    if (intervals.contains(t)) return t;
  }
  return null;
}

int? _seventhOf(List<int> intervals) {
  for (final t in const [10, 11, 9]) {
    if (intervals.contains(t)) return t;
  }
  return null;
}

int? _ninthOf(List<int> intervals) {
  for (final t in const [14, 13, 15]) {
    if (intervals.contains(t)) return t;
  }
  return null;
}

/// When nothing fits the window, sound the chord's guide tones (or its root) at
/// the bottom of the register. Never silence.
Voicing _lastResort(ChordSpec chord, VoicingConstraints c) {
  final tones = chord.guideTones.isEmpty ? [0] : chord.guideTones;
  final rootPc = _rootPcOf(chord);
  final midis = <int>{};
  for (final t in tones) {
    var m = _alignUpTo(c.lowMidi, (rootPc + t) % 12);
    if (m > c.highMidi) m = c.highMidi;
    midis.add(m);
  }
  final list = midis.toList()..sort();
  return Voicing(chord, VoicingShape.guideTones, list);
}

// ── the optimum path (A1b) ─────────────────────────────────────────────────

/// How much each part-writing fault costs. Tunable, and named so a test can say
/// which rule it is asserting on rather than a magic number.
class CompCosts {
  const CompCosts({
    this.motionPerSemitone = 1.0,
    this.parallels = 24.0,
    this.hidden = 8.0,
    this.crossingOrOverlap = 10.0,
    this.spacing = 4.0,
    this.semitoneClash = 30.0,
    this.minorNinthClash = 8.0,
    this.registerDriftPerSemitone = 0.35,
    this.spanPerSemitone = 0.25,
    this.commonToneBonus = 1.5,
    this.shapeChange = 2.0,
    this.gripPreference = 4.0,
    this.colourDropped = 6.0,
  });

  final double motionPerSemitone;
  final double parallels;
  final double hidden;
  final double crossingOrOverlap;
  final double spacing;

  /// A semitone between adjacent voices. Heavy: inside a voicing this is a
  /// mistake, not a colour — and it is the single rule that replaces the whole
  /// avoid-note table (see the file header).
  final double semitoneClash;

  /// A minor ninth between adjacent voices — harsh, but waived for root→♭9 on an
  /// altered dominant, where it is exactly the intended sound.
  final double minorNinthClash;

  final double registerDriftPerSemitone;
  final double spanPerSemitone;

  /// Subtracted per tone held between consecutive voicings. Rewarding common
  /// tones is what makes a comp sound connected rather than merely close.
  final double commonToneBonus;

  /// A small charge for switching shape, so a passage settles into one idiom
  /// instead of flickering between drop2 and close on every chord.
  final double shapeChange;

  /// Subtracted for a [VoicingShape.grip]. A real fingering beats a computed
  /// stack on a fretted instrument — that is the whole reason the grip database
  /// is worth loading — and without this the computed shape wins on span alone.
  final double gripPreference;

  /// Charged per CHARACTERISTIC tone the voicing leaves out: an extension, or an
  /// altered fifth. The notes the symbol is NAMED for.
  ///
  /// Without it the arranger reads `C13` and plays a three-note shell, which is a
  /// perfectly good voicing of `C7` and discards the one note the chord is called
  /// after. Guide tones are already protected by [_selectTones]; this protects the
  /// colour above them.
  final double colourDropped;

  static const standard = CompCosts();
}

/// Voice-leads [chords] into a single sequence of voicings, one per chord.
///
/// Deterministic — no randomness anywhere, and ties resolve to the earliest
/// candidate — so a shared chart voices identically on two devices. That is
/// ladder rule 3, met by construction rather than by threading a seed.
List<Voicing> arrangeComp(
  List<ChordSpec> chords, {
  VoicingConstraints constraints = VoicingConstraints.piano,
  CompCosts costs = CompCosts.standard,
  GripProvider? grips,
}) {
  if (chords.isEmpty) return const [];

  final lattice = [
    for (final chord in chords)
      voicingCandidates(chord, constraints, grips: grips),
  ];

  // Viterbi. `best[i]` is the cheapest total cost of reaching candidate i of the
  // current chord; `from[i]` is the candidate it came from.
  var best = [
    for (final v in lattice.first) _emissionCost(v, constraints, costs),
  ];
  final backPointers = <List<int>>[];

  for (var step = 1; step < lattice.length; step++) {
    final here = lattice[step];
    final prev = lattice[step - 1];
    final nextBest = List<double>.filled(here.length, double.infinity);
    final from = List<int>.filled(here.length, 0);

    for (var j = 0; j < here.length; j++) {
      final emission = _emissionCost(here[j], constraints, costs);
      for (var i = 0; i < prev.length; i++) {
        final total =
            best[i] + emission + _transitionCost(prev[i], here[j], costs);
        // Strictly-less keeps the EARLIEST candidate on a tie, which is what
        // makes the result reproducible.
        if (total < nextBest[j]) {
          nextBest[j] = total;
          from[j] = i;
        }
      }
    }
    best = nextBest;
    backPointers.add(from);
  }

  var bestIndex = 0;
  for (var i = 1; i < best.length; i++) {
    if (best[i] < best[bestIndex]) bestIndex = i;
  }

  final path = <Voicing>[lattice.last[bestIndex]];
  for (var step = lattice.length - 1; step > 0; step--) {
    bestIndex = backPointers[step - 1][bestIndex];
    path.add(lattice[step - 1][bestIndex]);
  }
  return path.reversed.toList();
}

/// What a voicing costs on its own: register, span and internal clashes.
double _emissionCost(Voicing v, VoicingConstraints c, CompCosts k) {
  final centre = (c.lowMidi + c.highMidi) / 2;
  final voicingCentre = (v.bottom + v.top) / 2;
  return (voicingCentre - centre).abs() * k.registerDriftPerSemitone +
      v.span * k.spanPerSemitone +
      _clashCost(v, k) +
      _colourCost(v, k) +
      (v.shape == VoicingShape.grip ? -k.gripPreference : 0.0);
}

/// What the voicing gives up of the chord's NAMED colour — see
/// [CompCosts.colourDropped].
double _colourCost(Voicing v, CompCosts k) {
  final rootPc = _rootPcOf(v.chord);
  final sounding = v.midis.map((m) => m % 12).toSet();
  var missing = 0;
  for (final t in v.chord.intervals) {
    // Extensions, and a fifth that has been altered — a plain fifth is filler.
    if (t < 13 && t != 6 && t != 8) continue;
    if (!sounding.contains((rootPc + t) % 12)) missing++;
  }
  return missing * k.colourDropped;
}

/// The one rule that replaces an avoid-note table. See the file header.
double _clashCost(Voicing v, CompCosts k) {
  var cost = 0.0;
  final rootPc = _rootPcOf(v.chord);
  final flatNinePc = (rootPc + 1) % 12;
  final isAlteredDominant =
      v.chord.alterations.contains(ChordAlteration.altered) ||
          v.chord.alterations.contains(ChordAlteration.flatNine);

  for (var i = 1; i < v.midis.length; i++) {
    final gap = v.midis[i] - v.midis[i - 1];
    if (gap == 1) cost += k.semitoneClash;
    if (gap == 13) {
      // Root → ♭9 on an altered dominant IS the chord's sound; anywhere else a
      // minor ninth between neighbours is just harsh.
      final lowerIsRoot = v.midis[i - 1] % 12 == rootPc;
      final upperIsFlatNine = v.midis[i] % 12 == flatNinePc;
      final intended = isAlteredDominant && lowerIsRoot && upperIsFlatNine;
      if (!intended) cost += k.minorNinthClash;
    }
  }
  return cost;
}

/// What moving from [a] to [b] costs.
double _transitionCost(Voicing a, Voicing b, CompCosts k) {
  // Motion, matched from the TOP down over however many voices both have. Top
  // first because the top voice is the one a listener follows as a line.
  final n = a.midis.length < b.midis.length ? a.midis.length : b.midis.length;
  var motion = 0.0;
  for (var i = 0; i < n; i++) {
    final from = a.midis[a.midis.length - 1 - i];
    final to = b.midis[b.midis.length - 1 - i];
    motion += (to - from).abs() * k.motionPerSemitone;
  }

  final held = a.midis.toSet().intersection(b.midis.toSet()).length;
  var cost = motion - held * k.commonToneBonus;
  if (a.shape != b.shape) cost += k.shapeChange;

  for (final issue in checkVoiceLeading([a.pitchesTopDown, b.pitchesTopDown])) {
    cost += switch (issue.rule) {
      VoiceLeadingRule.parallelFifths ||
      VoiceLeadingRule.parallelOctaves =>
        k.parallels,
      VoiceLeadingRule.hiddenFifths ||
      VoiceLeadingRule.hiddenOctaves =>
        k.hidden,
      VoiceLeadingRule.voiceCrossing ||
      VoiceLeadingRule.voiceOverlap =>
        k.crossingOrOverlap,
      VoiceLeadingRule.spacing => k.spacing,
    };
  }
  return cost;
}

/// The lowest midi note at or above [floor] whose pitch class is [pc].
int _alignUpTo(int floor, int pc) => floor + ((pc - floor % 12) + 12) % 12;

int _rootPcOf(ChordSpec chord) =>
    (chord.root.step.semitonesFromC + chord.root.alter) % 12;

// ── narrowing onto the guitar grip database ────────────────────────────────

/// The quality labels the bundled chords-db grips are keyed by — the keys of
/// `kQualityToChordDbSuffix` in `features/games/composition/chord_db.dart`.
///
/// Duplicated here rather than imported because that file is Flutter-bound (see
/// the header). `comp_arranger_test.dart` asserts this list against the real map,
/// so the two cannot drift apart silently.
const List<String> kGripQualityLabels = [
  'maj',
  'm',
  '5',
  '7',
  'maj7',
  'm7',
  'm7♭5',
  'dim',
  'dim7',
  'aug',
  'sus2',
  'sus4',
  '6',
  'm6',
  'add9',
  '9',
  'm9',
];

/// The nearest grip-database quality for [chord], plus what had to be given up
/// to get there.
///
/// The grip database speaks a 17-label vocabulary and `ChordSpec` is
/// compositional, so this narrowing is LOSSY by construction — `C7♯11` can only
/// be fingered as a `7`. It reports the loss rather than hiding it, the same way
/// BB-D3 reports what MusicXML's `<kind>` cannot carry: a caller can then decide
/// to use a computed shape instead of a grip that quietly drops the colour.
({String label, List<String> dropped}) gripQualityFor(ChordSpec chord) {
  final dropped = <String>[];

  for (final a in chord.alterations) {
    dropped.add(
      switch (a) {
        ChordAlteration.flatFive => '♭5',
        ChordAlteration.sharpFive => '♯5',
        ChordAlteration.flatNine => '♭9',
        ChordAlteration.sharpNine => '♯9',
        ChordAlteration.sharpEleven => '♯11',
        ChordAlteration.flatThirteen => '♭13',
        ChordAlteration.altered => 'alt',
      },
    );
  }
  for (final d in (chord.added.toList()..sort())) {
    dropped.add('add$d');
  }
  for (final d in (chord.omitted.toList()..sort())) {
    dropped.add('no$d');
  }

  String label;
  switch (chord.triad) {
    case ChordTriad.fifthOnly:
      label = '5';
    case ChordTriad.sus2:
      label = 'sus2';
    case ChordTriad.sus4:
      label = 'sus4';
    case ChordTriad.augmented:
      label = 'aug';
    case ChordTriad.diminished:
      label = chord.seventh == ChordSeventh.diminished ? 'dim7' : 'dim';
    case ChordTriad.minor:
      // A half-diminished is a minor triad with a flat five in this model, so it
      // is recognised HERE rather than under `diminished` — and when it matches,
      // the ♭5 is carried by the label and is no longer a loss.
      if (chord.alterations.contains(ChordAlteration.flatFive) &&
          chord.seventh == ChordSeventh.minor) {
        label = 'm7♭5';
        dropped.remove('♭5');
      } else {
        label = switch (chord.seventh) {
          ChordSeventh.sixth => 'm6',
          ChordSeventh.minor => chord.extension >= 9 ? 'm9' : 'm7',
          ChordSeventh.major => 'm7',
          ChordSeventh.diminished => 'm7',
          ChordSeventh.none => 'm',
        };
        if (chord.seventh == ChordSeventh.major) dropped.add('major 7th');
      }
    case ChordTriad.major:
      label = switch (chord.seventh) {
        ChordSeventh.major => 'maj7',
        ChordSeventh.minor => chord.extension >= 9 ? '9' : '7',
        ChordSeventh.sixth => '6',
        ChordSeventh.diminished => '7',
        ChordSeventh.none => chord.added.contains(9) ? 'add9' : 'maj',
      };
      if (label == 'add9') dropped.remove('add9');
  }

  // A stack the label cannot reach: `m9` and `9` carry a ninth, nothing carries
  // an eleventh or a thirteenth.
  if (chord.extension >= 11) dropped.add('${chord.extension}th');
  if (chord.triad == ChordTriad.augmented &&
      chord.seventh != ChordSeventh.none) {
    dropped.add('seventh');
  }
  if (chord.triad == ChordTriad.sus2 || chord.triad == ChordTriad.sus4) {
    if (chord.seventh != ChordSeventh.none) dropped.add('seventh');
  }

  assert(kGripQualityLabels.contains(label), 'unknown grip label $label');
  return (label: label, dropped: List.unmodifiable(dropped));
}
