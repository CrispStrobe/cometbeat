// lib/features/workshop/model/multi_part_document.dart
//
// The multi-instrument container behind the Composition Workshop (G6). It is a
// thin shell over N single-part [ScoreDocument]s — one per instrument staff —
// that assembles them into an immutable crisp_notation [MultiPartScore] for the
// full-score canvas ([MultiPartView]). Each part keeps its own element stream,
// clef and undo/redo; the toolbar always edits [activePart], so the whole
// single-part editing pipeline is reused unchanged.
//
// Two things the assembly guarantees that a bare list of parts does not:
//
//  1. **Aligned bar grid.** Parts with different amounts of music would
//     otherwise produce systems with mismatched measure counts. [buildMultiPart]
//     pads every part up to the longest part's measure count with whole-rest
//     bars, so the system is always valid and the barlines line up.
//  2. **Globally-unique element ids.** Each [ScoreDocument] numbers its elements
//     from `w0`, so ids collide across parts and a tap would be ambiguous.
//     [buildMultiPart] namespaces every id with a per-part prefix (`p0:`, `p1:`,
//     …); [partIndexOf]/[rawIdOf]/[selectByGlobalId] decode it back so a tap on
//     the full score selects the right element in the right part.
//
// Per the G6 handover this deliberately does NOT rewrite [ScoreDocument]; it
// composes it. Undo/redo stays per part for v1.

import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/foundation.dart';

/// Selects a practical single-staff clef for an imported part when its source
/// clef is the generic treble default. A part is bass-led when most sounding
/// pitches sit at or below middle C and its median is in the bass register;
/// isolated low notes in a treble melody do not flip the staff.
Clef suggestedClefForScore(Score score) {
  if (score.clef != Clef.treble) return score.clef;
  final pitches = [
    for (final measure in score.measures)
      for (final voice in [
        measure.elements,
        measure.voice2,
        measure.voice3,
        measure.voice4,
      ])
        for (final element in voice)
          if (element case NoteElement(:final pitches)) ...pitches,
  ];
  if (pitches.isEmpty) return score.clef;
  final sorted = pitches.map((p) => p.diatonicIndex).toList()..sort();
  final median = sorted[sorted.length ~/ 2];
  final low = sorted.where((index) => index <= 28).length;
  return low * 100 >= sorted.length * 60 && median <= 28
      ? Clef.bass
      : Clef.treble;
}

/// A whole piece as an ordered list of instrument [parts], plus the layout
/// grouping (brackets/braces and barline connections) drawn down the left edge.
///
/// A fresh document starts with a single treble part, so it can back the
/// single-part editor with no behavioural change until a second part is added.
class MultiPartDocument extends ChangeNotifier {
  /// Creates a document seeded with [parts] (at least one). [names] and
  /// [transpositions] default to `Part 1…N` and concert pitch. When omitted
  /// entirely, a single empty treble part is created.
  MultiPartDocument({
    List<ScoreDocument>? parts,
    List<String>? names,
    List<Transposition?>? transpositions,
    List<StaffBracket> brackets = const [],
    List<BarlineGroup> barlineGroups = const [],
  })  : _parts = (parts == null || parts.isEmpty)
            ? [ScoreDocument()]
            : List.of(parts),
        brackets = List.of(brackets),
        barlineGroups = List.of(barlineGroups) {
    final n = _parts.length;
    _names = List.generate(
      n,
      (i) => names != null && i < names.length ? names[i] : 'Part ${i + 1}',
    );
    _transpositions = List.generate(
      n,
      (i) => transpositions != null && i < transpositions.length
          ? transpositions[i]
          : null,
    );
  }

  /// Rebuilds an editable document from an immutable [score] — one
  /// [ScoreDocument] per part, seeded via [ScoreDocument.loadScore]. Used by the
  /// multi-part import flow ([multiPartScoreFromMusicXml] etc.).
  factory MultiPartDocument.fromMultiPartScore(
    MultiPartScore score, {
    List<String>? names,
    List<Transposition?>? transpositions,
    bool autoClef = false,
  }) {
    final parts = <ScoreDocument>[];
    for (final part in score.parts) {
      final doc = ScoreDocument()
        ..loadScore(
          part,
          clefOverride: autoClef ? suggestedClefForScore(part) : null,
        );
      parts.add(doc);
    }
    return MultiPartDocument(
      parts: parts,
      names: names,
      transpositions:
          transpositions ?? [for (final p in score.parts) _transpositionOf(p)],
      brackets: score.brackets,
      barlineGroups: score.barlineGroups,
    );
  }

  /// Replace the whole document in place with the parts of [score] (one
  /// [ScoreDocument] per part), resetting the active part to the first and
  /// notifying. Used by the multi-part "open file" flow for a score that has
  /// more than one part; a single-part file loads into the active part instead.
  void loadMultiPart(MultiPartScore score, {List<String>? names}) {
    _parts
      ..clear()
      ..addAll([for (final p in score.parts) ScoreDocument()..loadScore(p)]);
    _names = List.generate(
      _parts.length,
      (i) => names != null && i < names.length ? names[i] : 'Part ${i + 1}',
    );
    _transpositions = [for (final p in score.parts) _transpositionOf(p)];
    brackets = List.of(score.brackets);
    barlineGroups = List.of(score.barlineGroups);
    _active = 0;
    notifyListeners();
  }

  final List<ScoreDocument> _parts;
  late List<String> _names;
  late List<Transposition?> _transpositions;

  /// Bracket/brace groups drawn at the left edge (0-based staff indices).
  List<StaffBracket> brackets;

  /// Contiguous part-index runs whose barlines connect (empty = all connected).
  List<BarlineGroup> barlineGroups;

  int _active = 0;

  // ---- reads -------------------------------------------------------------

  /// The parts, top to bottom (read-only view).
  List<ScoreDocument> get parts => List.unmodifiable(_parts);

  /// The number of instrument parts (always ≥ 1).
  int get partCount => _parts.length;

  /// The index of the part the toolbar currently edits.
  int get active => _active;

  /// The part the toolbar edits.
  ScoreDocument get activePart => _parts[_active];

  /// The display name of part [i].
  String nameOf(int i) => _names[i];

  /// The transposition of part [i] (null = concert pitch).
  Transposition? transpositionOf(int i) => _transpositions[i];

  /// The clef of part [i] (lives on the underlying [ScoreDocument]).
  Clef clefOf(int i) => _parts[i].clef;

  /// The per-part display names (read-only view).
  List<String> get names => List.unmodifiable(_names);

  /// The active part's selected element ids, namespaced to match the ids in
  /// [buildMultiPart] — so they can drive `highlightedIds` on the full-score
  /// canvas ([MultiPartView]/`InteractiveMultiPartView`).
  Set<String> get selectedGlobalIds =>
      {for (final id in activePart.selectedIds) '${prefixFor(active)}$id'};

  // ---- assembly ----------------------------------------------------------

  /// The per-part id prefix used to keep element ids unique across parts.
  static String prefixFor(int part) => 'p$part:';

  /// The part index encoded in a global element id (`p2:w7` → 2), or -1 if the
  /// id carries no part prefix.
  static int partIndexOf(String globalId) {
    if (!globalId.startsWith('p')) return -1;
    final colon = globalId.indexOf(':');
    if (colon < 2) return -1;
    return int.tryParse(globalId.substring(1, colon)) ?? -1;
  }

  /// The underlying [ScoreDocument] id from a global id (`p2:w7` → `w7`). An id
  /// without a prefix is returned unchanged.
  static String rawIdOf(String globalId) {
    final colon = globalId.indexOf(':');
    return colon < 0 ? globalId : globalId.substring(colon + 1);
  }

  /// Assembles the parts into an immutable [MultiPartScore] for the full-score
  /// canvas: every part padded to the longest part's measure count, every
  /// element id namespaced per part, and each transposing part tagged so the
  /// concert-pitch toggle ([MultiPartScore.atConcertPitch]) can un-transpose it.
  MultiPartScore buildMultiPart() {
    final built = [for (final p in _parts) p.buildScore()];
    if (_cache != null && _cacheMatches(built)) return _cache!;
    final maxMeasures = built.fold<int>(
      1,
      (m, s) => s.measures.length > m ? s.measures.length : m,
    );
    final assembled = [
      for (var i = 0; i < built.length; i++)
        _reindex(built[i], prefixFor(i), maxMeasures, _transpositions[i]),
    ];
    _cache = MultiPartScore(
      assembled,
      brackets: brackets,
      barlineGroups: barlineGroups,
    );
    _cacheParts = built;
    _cacheBrackets = brackets;
    _cacheBarlineGroups = barlineGroups;
    _cacheTranspositions = List.of(_transpositions);
    return _cache!;
  }

  // Memoized assembly, mirroring [ScoreDocument]'s own `_scoreCache`.
  // [buildMultiPart] is called from `build()`, so without this every hover or
  // selection rebuild re-allocated every Measure and element (via [_reindex])
  // and handed the render object a new-but-equal document — defeating its
  // `document ==` fast path and forcing a full re-layout of every part.
  //
  // The key is derived entirely from state rather than from `_invalidate()`
  // calls, so a mutator can't forget to clear it: each part's `buildScore()` is
  // itself memoized (an unchanged part returns an *identical* Score), and every
  // brackets/barlineGroups mutator reassigns its list rather than mutating in
  // place, so identity is sound for those too. Transpositions do mutate in
  // place, hence the copy.
  MultiPartScore? _cache;
  List<Score> _cacheParts = const [];
  List<StaffBracket> _cacheBrackets = const [];
  List<BarlineGroup> _cacheBarlineGroups = const [];
  List<Transposition?> _cacheTranspositions = const [];

  bool _cacheMatches(List<Score> built) {
    if (!identical(brackets, _cacheBrackets) ||
        !identical(barlineGroups, _cacheBarlineGroups) ||
        built.length != _cacheParts.length ||
        _transpositions.length != _cacheTranspositions.length) {
      return false;
    }
    for (var i = 0; i < built.length; i++) {
      if (!identical(built[i], _cacheParts[i])) return false;
    }
    for (var i = 0; i < _transpositions.length; i++) {
      if (_transpositions[i] != _cacheTranspositions[i]) return false;
    }
    return true;
  }

  /// One padding bar: a full-measure whole rest with no id (never selectable).
  static const Measure _padBar =
      Measure([RestElement(NoteDuration(DurationBase.whole))]);

  /// Returns [s] with every element id prefixed, padded to [targetMeasures]
  /// bars, and tagged with [transposition]. Only the note/rest/span/lyric/
  /// dynamic ids that [ScoreDocument.buildScore] emits are remapped.
  static Score _reindex(
    Score s,
    String prefix,
    int targetMeasures,
    Transposition? transposition,
  ) {
    final measures = <Measure>[
      for (final m in s.measures)
        m.copyWith(
          elements: [for (final e in m.elements) _reid(e, prefix)],
          // copyWith defaults voice2 to the ORIGINAL, so without this the
          // voice-2 element ids stay unprefixed while their markings (dynamics/
          // lyrics/slurs, prefixed below) get rewritten — detaching them — and
          // the raw ids collide across parts.
          voice2: [for (final e in m.voice2) _reid(e, prefix)],
        ),
    ];
    while (measures.length < targetMeasures) {
      measures.add(_padBar);
    }
    return Score(
      clef: s.clef,
      keySignature: s.keySignature,
      timeSignature: s.timeSignature,
      measures: measures,
      dynamics: [
        for (final d in s.dynamics)
          DynamicMarking('$prefix${d.elementId}', d.level),
      ],
      slurs: [
        for (final sl in s.slurs)
          Slur('$prefix${sl.startId}', '$prefix${sl.endId}'),
      ],
      hairpins: [
        for (final h in s.hairpins)
          Hairpin('$prefix${h.startId}', '$prefix${h.endId}', h.type),
      ],
      lyrics: [
        for (final ly in s.lyrics)
          Lyric('$prefix${ly.elementId}', ly.text, verse: ly.verse),
      ],
      transposition: transposition,
    );
  }

  /// Clones a note/rest element with its id prefixed (id-less padding rests and
  /// any other element type pass through unchanged).
  static MusicElement _reid(MusicElement e, String prefix) {
    final id = e.id;
    if (id == null) return e;
    if (e is NoteElement) {
      // A straight clone with a prefixed id — preserve EVERY field, or
      // ornaments/grace notes/fingerings/arpeggio/tremolo are silently dropped
      // from every note on the full-score render and export.
      return NoteElement(
        pitches: e.pitches,
        duration: e.duration,
        id: '$prefix$id',
        showAccidental: e.showAccidental,
        tieToNext: e.tieToNext,
        articulations: e.articulations,
        graceNotes: e.graceNotes,
        graceStyle: e.graceStyle,
        ornament: e.ornament,
        fingerings: e.fingerings,
        arpeggio: e.arpeggio,
        tremolo: e.tremolo,
        notehead: e.notehead,
      );
    }
    if (e is RestElement) return RestElement(e.duration, id: '$prefix$id');
    return e;
  }

  /// Reads the transposition tag off an imported part's [Score] (null = concert).
  static Transposition? _transpositionOf(Score s) => s.transposition;

  // ---- active + structural edits (all notify) ----------------------------

  /// Switch the part the toolbar edits. No-op if out of range or unchanged.
  void setActive(int i) {
    if (i < 0 || i >= _parts.length || i == _active) return;
    _active = i;
    notifyListeners();
  }

  /// Clears every instrument part, not only the currently selected row.
  void clearAll() {
    for (final part in _parts) {
      part.clearAll();
    }
    notifyListeners();
  }

  /// Append a new instrument part and make it active. Returns its index.
  int addPart({
    String? name,
    Clef clef = Clef.treble,
    Transposition? transposition,
  }) {
    final doc = ScoreDocument(clef: clef);
    _parts.add(doc);
    _names.add(name ?? 'Part ${_parts.length}');
    _transpositions.add(transposition);
    _active = _parts.length - 1;
    notifyListeners();
    return _active;
  }

  /// Remove part [i] (a document always keeps at least one part). Brackets and
  /// barline groups are re-indexed to survive the removal; the active part is
  /// clamped to stay in range.
  void removePart(int i) {
    if (i < 0 || i >= _parts.length || _parts.length == 1) return;
    _parts.removeAt(i);
    _names.removeAt(i);
    _transpositions.removeAt(i);
    brackets = _adjustBrackets(brackets, i);
    barlineGroups = _adjustBarlineGroups(barlineGroups, i);
    if (_active >= _parts.length) _active = _parts.length - 1;
    notifyListeners();
  }

  /// Reorder: move the part at [from] to sit at index [to]. The active part
  /// follows its content. Index-based grouping cannot survive an arbitrary
  /// reorder, so brackets and barline groups are cleared (documented v1
  /// behaviour — regroup after reordering).
  void movePart(int from, int to) {
    if (from < 0 || from >= _parts.length) return;
    final dest = to.clamp(0, _parts.length - 1);
    if (from == dest) return;
    final activeDoc = _parts[_active];
    _parts.insert(dest, _parts.removeAt(from));
    _names.insert(dest, _names.removeAt(from));
    _transpositions.insert(dest, _transpositions.removeAt(from));
    _active = _parts.indexOf(activeDoc);
    if (brackets.isNotEmpty || barlineGroups.isNotEmpty) {
      brackets = const [];
      barlineGroups = const [];
    }
    notifyListeners();
  }

  /// Rename part [i].
  void setPartName(int i, String name) {
    if (i < 0 || i >= _parts.length || _names[i] == name) return;
    _names[i] = name;
    notifyListeners();
  }

  /// Set (or clear, with null) the transposing-instrument tag of part [i].
  void setTransposition(int i, Transposition? t) {
    if (i < 0 || i >= _parts.length || _transpositions[i] == t) return;
    _transpositions[i] = t;
    notifyListeners();
  }

  /// Set the clef of part [i] (delegates to the part's own undoable setClef).
  void setClefOfPart(int i, Clef clef) {
    if (i < 0 || i >= _parts.length || _parts[i].clef == clef) return;
    _parts[i].setClef(clef);
    notifyListeners();
  }

  // ---- grouping ----------------------------------------------------------

  /// Add (or replace an equal) bracket/brace over staves [first]..[last].
  void addBracket(
    int first,
    int last, {
    StaffBracketKind kind = StaffBracketKind.bracket,
  }) {
    if (first < 0 || last >= _parts.length || last <= first) return;
    final b = StaffBracket(first, last, kind: kind);
    if (brackets.contains(b)) return;
    brackets = [...brackets, b];
    notifyListeners();
  }

  /// Remove any bracket exactly spanning [first]..[last].
  void removeBracket(int first, int last) {
    final next =
        brackets.where((b) => b.first != first || b.last != last).toList();
    if (next.length == brackets.length) return;
    brackets = next;
    notifyListeners();
  }

  /// Drop all grouping.
  void clearBrackets() {
    if (brackets.isEmpty) return;
    brackets = const [];
    notifyListeners();
  }

  /// Replace the barline-connection groups (empty = connect through all parts).
  void setBarlineGroups(List<BarlineGroup> groups) {
    barlineGroups = List.of(groups);
    notifyListeners();
  }

  /// The part indices *after* which the systemic barline breaks (a gap between
  /// part i and i+1). Derived from [barlineGroups]; empty when barlines connect
  /// through every part.
  Set<int> get barlineBreaks {
    if (barlineGroups.isEmpty) return {};
    return {
      for (final g in barlineGroups)
        if (g.last < partCount - 1) g.last,
    };
  }

  /// Whether the barline breaks between part [i] and the part below it.
  bool hasBarlineBreakAfter(int i) => barlineBreaks.contains(i);

  /// Toggle the barline break between part [i] and part i+1 (used to separate
  /// instrument groups). No-op on the last part; recomputes [barlineGroups] as
  /// the contiguous runs between the break points.
  void toggleBarlineBreakAfter(int i) {
    if (i < 0 || i + 1 >= partCount) return;
    final breaks = barlineBreaks;
    breaks.contains(i) ? breaks.remove(i) : breaks.add(i);
    if (breaks.isEmpty) {
      barlineGroups = const [];
    } else {
      final sorted = breaks.toList()..sort();
      final groups = <BarlineGroup>[];
      var start = 0;
      for (final b in sorted) {
        groups.add(BarlineGroup(start, b));
        start = b + 1;
      }
      groups.add(BarlineGroup(start, partCount - 1));
      barlineGroups = groups;
    }
    notifyListeners();
  }

  // ---- selection across parts --------------------------------------------

  /// Handle a tap on a full-score element id: switch to the owning part and
  /// select the element there. Returns the owning part index, or -1 if the id
  /// carries no valid part prefix.
  int selectByGlobalId(String globalId) {
    final part = partIndexOf(globalId);
    if (part < 0 || part >= _parts.length) return -1;
    setActive(part);
    _parts[part].selectByIds([rawIdOf(globalId)]);
    notifyListeners();
    return part;
  }

  // ---- bracket / group re-indexing (private) -----------------------------

  static List<StaffBracket> _adjustBrackets(
    List<StaffBracket> src,
    int removed,
  ) {
    final out = <StaffBracket>[];
    for (final b in src) {
      final first = b.first > removed ? b.first - 1 : b.first;
      final last = b.last >= removed ? b.last - 1 : b.last;
      if (last > first) out.add(StaffBracket(first, last, kind: b.kind));
    }
    return out;
  }

  static List<BarlineGroup> _adjustBarlineGroups(
    List<BarlineGroup> src,
    int removed,
  ) {
    final out = <BarlineGroup>[];
    for (final g in src) {
      final first = g.first > removed ? g.first - 1 : g.first;
      final last = g.last >= removed ? g.last - 1 : g.last;
      if (last >= first) out.add(BarlineGroup(first, last));
    }
    return out;
  }
}
