// lib/features/workshop/model/score_document.dart
//
// The editable document behind the Composition Workshop. crisp_notation's Score is
// an immutable value tree with no in-place editing, so the editor keeps its own
// flat, mutable list of [EditorElement]s and rebuilds an immutable [Score] on
// demand (packing the flat list into bar-lined measures). All mutations go
// through commands that snapshot first, giving multi-level undo/redo.
//
// Selection is a SET of element ids (so a marquee over two clusters selects
// exactly those, discontiguously) plus a focus id; the editing commands
// (transpose / duration / accidental / delete / copy / cut / paste) operate
// over the whole set, while contiguous-only commands (block move, extend)
// derive an index range from it.

import 'package:crisp_notation/crisp_notation.dart';
import 'package:klang_universum/shared/midi_pitch.dart';

/// One editable event in the flat stream: a note, a chord (several simultaneous
/// pitches), or a rest, with a stable [id] so it can be selected and edited.
class EditorElement {
  /// A single note.
  EditorElement.note(
    Pitch pitch,
    this.duration, {
    required this.id,
    this.articulations = const {},
    this.tieToNext = false,
    this.dynamic,
    this.ornament,
    this.graceNotes = const [],
    this.graceStyle = GraceStyle.acciaccatura,
  }) : pitches = [pitch];

  /// A chord: two or more simultaneous pitches (kept low → high).
  const EditorElement.chord(
    this.pitches,
    this.duration, {
    required this.id,
    this.articulations = const {},
    this.tieToNext = false,
    this.dynamic,
    this.ornament,
    this.graceNotes = const [],
    this.graceStyle = GraceStyle.acciaccatura,
  });

  const EditorElement.rest(this.duration, {required this.id})
      : pitches = const [],
        articulations = const {},
        tieToNext = false,
        dynamic = null,
        ornament = null,
        graceNotes = const [],
        graceStyle = GraceStyle.acciaccatura;

  /// The simultaneous pitches, low → high; empty for a rest.
  final List<Pitch> pitches;
  final NoteDuration duration;
  final String id;

  /// Note-only ornaments (rests ignore these).
  final Set<Articulation> articulations;
  final bool tieToNext;

  /// A dynamic marking anchored on this element (null = none).
  final DynamicLevel? dynamic;

  /// A single ornament above the note — trill / mordent / turn (null = none;
  /// rests carry none).
  final Ornament? ornament;

  /// Grace notes played just before this note, drawn as small notes to its left
  /// (empty = none; rests carry none). A list of pitches — a run of graces is a
  /// mini-sequence, not a single value — with [graceStyle] choosing the look.
  final List<Pitch> graceNotes;

  /// Whether [graceNotes] read as acciaccatura (slashed, crushed) or
  /// appoggiatura (leaning). Irrelevant when [graceNotes] is empty.
  final GraceStyle graceStyle;

  bool get isRest => pitches.isEmpty;

  /// The lowest pitch (for single-note logic), or null for a rest.
  Pitch? get pitch => pitches.isEmpty ? null : pitches.first;

  bool get isChord => pitches.length > 1;

  /// This event as an immutable crisp_notation element.
  MusicElement toElement() => isRest
      ? RestElement(duration, id: id)
      : NoteElement(
          pitches: pitches,
          duration: duration,
          id: id,
          articulations: articulations,
          tieToNext: tieToNext,
          ornament: ornament,
          graceNotes: graceNotes,
          graceStyle: graceStyle,
        );

  EditorElement _copyWith({
    List<Pitch>? pitches,
    NoteDuration? duration,
    Set<Articulation>? articulations,
    bool? tieToNext,
    DynamicLevel? dyn,
    bool clearDynamic = false,
    Ornament? orn,
    bool clearOrnament = false,
    List<Pitch>? graceNotes,
    GraceStyle? graceStyle,
  }) =>
      EditorElement.chord(
        pitches ?? this.pitches,
        duration ?? this.duration,
        id: id,
        articulations: articulations ?? this.articulations,
        tieToNext: tieToNext ?? this.tieToNext,
        dynamic: clearDynamic ? null : (dyn ?? dynamic),
        ornament: clearOrnament ? null : (orn ?? ornament),
        graceNotes: graceNotes ?? this.graceNotes,
        graceStyle: graceStyle ?? this.graceStyle,
      );

  EditorElement withOrnament(Ornament? o) =>
      _copyWith(orn: o, clearOrnament: o == null);

  /// Attach [notes] as grace notes (empty clears them), with [style]
  /// (default acciaccatura). A no-op semantic on rests is enforced by the
  /// caller ([setGraceNotesOfSelected] skips rests).
  EditorElement withGraceNotes(
    List<Pitch> notes, {
    GraceStyle style = GraceStyle.acciaccatura,
  }) =>
      _copyWith(graceNotes: List.of(notes), graceStyle: style);

  /// Replace with a single pitch (collapses a chord).
  EditorElement withPitch(Pitch pitch) => _copyWith(pitches: [pitch]);

  EditorElement withPitches(List<Pitch> pitches) => _copyWith(pitches: pitches);

  EditorElement withDuration(NoteDuration duration) =>
      _copyWith(duration: duration);

  EditorElement withId(String newId) => EditorElement.chord(
        pitches,
        duration,
        id: newId,
        articulations: articulations,
        tieToNext: tieToNext,
        dynamic: dynamic,
        ornament: ornament,
        graceNotes: graceNotes,
        graceStyle: graceStyle,
      );

  EditorElement withArticulations(Set<Articulation> a) =>
      _copyWith(articulations: a);

  EditorElement withTie(bool tie) => _copyWith(tieToNext: tie);

  EditorElement withDynamic(DynamicLevel? d) =>
      _copyWith(dyn: d, clearDynamic: d == null);

  /// Add [p] to the chord (kept low → high, deduped by pitch).
  EditorElement addPitch(Pitch p) {
    if (pitches.any((e) => e.midiNumber == p.midiNumber)) return this;
    final next = [...pitches, p]
      ..sort((a, b) => a.midiNumber.compareTo(b.midiNumber));
    return _copyWith(pitches: next);
  }

  /// Move so the lowest note lands on [target] — a single note re-pitches
  /// exactly; a chord transposes as a block.
  EditorElement moveTo(Pitch target) {
    if (pitches.length <= 1) return withPitch(target);
    final delta = target.midiNumber - pitches.first.midiNumber;
    return _copyWith(
      pitches: [for (final p in pitches) pitchFromMidi(p.midiNumber + delta)],
    );
  }
}

/// An undo/redo snapshot of the document's mutable state.
class _Snapshot {
  const _Snapshot(
    this.elements,
    this.timeSignature,
    this.keySignature,
    this.clef,
    this.slurs,
    this.hairpins,
    this.lyrics,
    this.pickup,
    this.clefChanges,
    this.keyChanges,
    this.timeChanges,
    this.repeatStarts,
    this.repeatEnds,
    this.voltas,
    this.navigation,
    this.tuplets,
    this.tempo,
    this.tempoChanges,
  );
  final List<EditorElement> elements;
  final TimeSignature timeSignature;
  final KeySignature keySignature;
  final Clef clef;

  /// The document-start tempo and mid-score tempo changes (id → mark).
  final Tempo? tempo;
  final Map<String, Tempo> tempoChanges;

  /// Mid-score clef / key / time changes (element id → value), captured for undo.
  final Map<String, Clef> clefChanges;
  final Map<String, KeySignature> keyChanges;
  final Map<String, TimeSignature> timeChanges;

  /// Repeat-barline anchors (element ids), captured for undo.
  final Set<String> repeatStarts;
  final Set<String> repeatEnds;

  /// Volta numbers and navigation marks (element id → value), captured for undo.
  final Map<String, int> voltas;
  final Map<String, NavigationMark> navigation;

  /// Tuplet groups, captured for undo.
  final List<Tuplet> tuplets;

  /// Phrase slurs / hairpins (start→end note ids) and per-note lyric syllables
  /// (id → verse → syllable) — spans/attachments that live alongside the
  /// element stream, keyed by id.
  final List<Slur> slurs;
  final List<Hairpin> hairpins;
  final Map<String, Map<int, String>> lyrics;

  /// The anacrusis length (null = the piece starts on beat 1).
  final NoteDuration? pickup;
}

/// The editable Workshop document: an ordered element stream, the document-level
/// clef/time/key, a range selection, a clipboard, and undo/redo.
class ScoreDocument {
  ScoreDocument({
    this.timeSignature = TimeSignature.fourFour,
    this.keySignature = const KeySignature(0),
    this.clef = Clef.treble,
    this.tempo,
  });

  final List<EditorElement> _elements = [];
  TimeSignature timeSignature;
  KeySignature keySignature;

  /// The staff clef — chosen by the user; no automatic mid-score flipping.
  Clef clef;

  /// The initial (document-start) tempo, or null if unspecified. A document-
  /// level default like [clef] / [keySignature]; mid-score tempo changes live in
  /// [_tempoChanges]. Feeds crisp_notation's `Score.tempo` → `TempoMap`, so it
  /// is the anchor real variable-tempo playback reads.
  Tempo? tempo;

  /// How an over-long note is handled when it doesn't fit the current bar.
  /// [RhythmPolicy.spill] (the default, kid-sandbox behaviour) short-fills the
  /// bar and starts the note fresh in the next; [RhythmPolicy.split] (Studio)
  /// notates it correctly as tied notes across the barline. A view/authoring
  /// mode, not content — set it directly; it just invalidates the render cache.
  RhythmPolicy _rhythmPolicy = RhythmPolicy.spill;
  RhythmPolicy get rhythmPolicy => _rhythmPolicy;
  set rhythmPolicy(RhythmPolicy value) {
    if (value == _rhythmPolicy) return;
    _rhythmPolicy = value;
    _invalidate();
  }

  // Selection: a SET of element ids (so it can be discontiguous — a marquee
  // over two clusters selects exactly those, not the span between), plus the
  // focus id (the "active" element for single-note controls and the insertion
  // caret). Contiguous-only operations (block move, extend) derive indices from
  // the set on demand; stale ids (from a deleted element) are filtered out by
  // the index helpers, so the set never needs eager pruning.
  final Set<String> _selectedIds = {};
  String? _focusId;
  var _nextId = 0;

  final List<EditorElement> _clipboard = [];
  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];

  // Phrase slurs / hairpins (start→end note ids) and per-note verse-1 lyric
  // syllables. All attach to element ids, so structural edits prune danglers.
  final List<Slur> _slurs = [];
  final List<Hairpin> _hairpins = [];

  // Per-note lyric syllables: element id → verse number (1-based) → syllable.
  final Map<String, Map<int, String>> _lyrics = {};

  // Mid-score clef / key changes, anchored to an element id: the change takes
  // effect at the start of the bar that element lands in. Anchoring to the id
  // (not a bar index) is the whole point — bars are reflowed on every edit, so a
  // bar index would drift, but the id moves with its note. This is the
  // element-id-anchor mechanism the measure-spine work needs; it does NOT
  // require bars to be a first-class store (see docs/WORKSHOP_PARITY.md,
  // Cause 1). Neither affects bar capacity, so they're a pure post-reflow stamp;
  // time changes (which do affect capacity) will need a reflow tweak too.
  final Map<String, Clef> _clefChanges = {};
  final Map<String, KeySignature> _keyChanges = {};

  // Mid-score tempo (metronome) changes, same element-id anchor as clef/key: the
  // change takes effect at the start of the bar its anchor note reflows into.
  // A pure post-reflow stamp — tempo does not affect bar capacity — with the
  // running value seeded from the document-level [tempo].
  final Map<String, Tempo> _tempoChanges = {};

  // Mid-score time-signature changes, same element-id anchor — but unlike
  // clef/key these change bar *capacity*, so they're applied inside [reflow]
  // (which re-bars from the anchor), not as a post-reflow stamp.
  final Map<String, TimeSignature> _timeChanges = {};

  // Repeat barlines, anchored to an element id (same rationale): the bar
  // containing the element starts / ends a repeat. Booleans per bar, so a set
  // of anchored ids rather than a value map.
  final Set<String> _repeatStarts = {};
  final Set<String> _repeatEnds = {};

  // Volta (ending) numbers and navigation marks (D.C./D.S./coda/segno/fine),
  // both bar-anchored to an element id and both pure post-reflow stamps.
  final Map<String, int> _voltas = {};
  final Map<String, NavigationMark> _navigation = {};

  // Tuplets: groups of consecutive elements played [actual] in the time of
  // [normal] (a triplet is 3:2). Not a single-id anchor and not a pure stamp:
  // members keep their written duration but *sound* scaled, so [reflow] must
  // pack them at their scaled duration (else the bar mis-fills), and buildScore
  // emits a [TupletSpan] over their index range within the bar they land in.
  final List<Tuplet> _tuplets = [];

  /// The anacrusis: when set, the first bar holds only this much music before
  /// the downbeat (the piece "starts before beat 1"). Null = no pickup.
  NoteDuration? pickup;

  // Memoized renders — invalidated only when the music changes, so hover/select
  // rebuilds don't force crisp_notation to re-lay-out every frame.
  Score? _scoreCache;
  GrandStaff? _grandCache;

  void _invalidate() {
    _scoreCache = null;
    _grandCache = null;
  }

  // ---- reads -------------------------------------------------------------

  List<EditorElement> get elements => List.unmodifiable(_elements);
  int get length => _elements.length;
  bool get isEmpty => _elements.isEmpty;

  /// The document indices of the currently-selected elements, ascending, with
  /// any stale ids (from deleted elements) dropped. The single source of truth
  /// the range/note helpers below are derived from.
  List<int> get _selectedIndices {
    if (_selectedIds.isEmpty) return const [];
    final r = <int>[];
    for (var i = 0; i < _elements.length; i++) {
      if (_selectedIds.contains(_elements[i].id)) r.add(i);
    }
    return r;
  }

  bool get hasSelection => _selectedIndices.isNotEmpty;
  bool get hasRange => _selectedIndices.length > 1;

  /// Lowest / highest selected index (the range the selection spans). For
  /// contiguous-only operations; guard with [hasSelection] first.
  int get _lo => _selectedIndices.first;
  int get _hi => _selectedIndices.last;

  /// Whether the selection is a single unbroken run (no gaps).
  bool get _isContiguous {
    final idx = _selectedIndices;
    return idx.isNotEmpty && idx.last - idx.first == idx.length - 1;
  }

  /// The focus element's id (used for single-note controls + status), or the
  /// last selected id if the focus was deleted.
  String? get selectedId {
    if (_focusId != null && _indexOf(_focusId!) >= 0) return _focusId;
    final idx = _selectedIndices;
    return idx.isEmpty ? null : _elements[idx.last].id;
  }

  /// Every selected id (for highlighting) — exactly the set, no widening.
  Set<String> get selectedIds =>
      {for (final i in _selectedIndices) _elements[i].id};

  /// The focus element (or null).
  EditorElement? get selected {
    final id = selectedId;
    if (id == null) return null;
    final i = _indexOf(id);
    return i < 0 ? null : _elements[i];
  }

  List<EditorElement> get selectedElements =>
      [for (final i in _selectedIndices) _elements[i]];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get canPaste => _clipboard.isNotEmpty;

  /// The phrase slurs currently on the score.
  List<Slur> get slurs => List.unmodifiable(_slurs);

  /// The lyric syllable under element [id] for [verse] (null = none).
  String? lyricOf(String id, {int verse = 1}) => _lyrics[id]?[verse];

  /// The highest verse number carrying any lyric (0 = none). Lets the UI offer
  /// the next empty verse.
  int get maxVerse {
    var max = 0;
    for (final byVerse in _lyrics.values) {
      for (final v in byVerse.keys) {
        if (v > max) max = v;
      }
    }
    return max;
  }

  /// A slur/hairpin needs at least two selected notes to span.
  bool get canSlur => _selectedNoteIndices.length >= 2;
  bool get canHairpin => canSlur;

  /// Whether the selected range's endpoints already carry a slur (so the UI can
  /// show the toggle as active).
  bool get isSlurred {
    final notes = _selectedNoteIndices;
    if (notes.length < 2) return false;
    return _slurs.contains(
      Slur(_elements[notes.first].id, _elements[notes.last].id),
    );
  }

  /// The crescendo/diminuendo wedges currently on the score.
  List<Hairpin> get hairpins => List.unmodifiable(_hairpins);

  /// The hairpin type on the selected range's endpoints (null = none).
  HairpinType? get hairpinType {
    final notes = _selectedNoteIndices;
    if (notes.length < 2) return null;
    final start = _elements[notes.first].id, end = _elements[notes.last].id;
    for (final h in _hairpins) {
      if (h.startId == start && h.endId == end) return h.type;
    }
    return null;
  }

  String _newId() => 'w${_nextId++}';

  // ---- history -----------------------------------------------------------

  _Snapshot _capture() => _Snapshot(
        List.of(_elements),
        timeSignature,
        keySignature,
        clef,
        List.of(_slurs),
        List.of(_hairpins),
        {for (final e in _lyrics.entries) e.key: Map.of(e.value)},
        pickup,
        Map.of(_clefChanges),
        Map.of(_keyChanges),
        Map.of(_timeChanges),
        Set.of(_repeatStarts),
        Set.of(_repeatEnds),
        Map.of(_voltas),
        Map.of(_navigation),
        [for (final t in _tuplets) t.copy()],
        tempo,
        Map.of(_tempoChanges),
      );

  void _snapshot() {
    _undo.add(_capture());
    _redo.clear();
    _invalidate();
  }

  void _restore(_Snapshot s) {
    _elements
      ..clear()
      ..addAll(s.elements);
    timeSignature = s.timeSignature;
    keySignature = s.keySignature;
    clef = s.clef;
    _slurs
      ..clear()
      ..addAll(s.slurs);
    _hairpins
      ..clear()
      ..addAll(s.hairpins);
    _lyrics.clear();
    for (final e in s.lyrics.entries) {
      _lyrics[e.key] = Map.of(e.value);
    }
    pickup = s.pickup;
    _clefChanges
      ..clear()
      ..addAll(s.clefChanges);
    _keyChanges
      ..clear()
      ..addAll(s.keyChanges);
    _timeChanges
      ..clear()
      ..addAll(s.timeChanges);
    _repeatStarts
      ..clear()
      ..addAll(s.repeatStarts);
    _repeatEnds
      ..clear()
      ..addAll(s.repeatEnds);
    _voltas
      ..clear()
      ..addAll(s.voltas);
    _navigation
      ..clear()
      ..addAll(s.navigation);
    _tuplets
      ..clear()
      ..addAll(s.tuplets);
    tempo = s.tempo;
    _tempoChanges
      ..clear()
      ..addAll(s.tempoChanges);
    _invalidate();
    // Drop selected ids that the restored document no longer contains.
    _selectedIds.removeWhere((id) => _indexOf(id) < 0);
    if (_focusId != null && _indexOf(_focusId!) < 0) _focusId = null;
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_capture());
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_capture());
    _restore(_redo.removeLast());
  }

  // ---- selection (navigation only — not undoable) ------------------------

  void selectIndex(int i) {
    if (_elements.isEmpty) return;
    _selectSingle(i.clamp(0, _elements.length - 1));
  }

  int _indexOf(String id) => _elements.indexWhere((e) => e.id == id);

  /// Replace the selection with a single element at index [i] (its focus).
  void _selectSingle(int i) {
    final id = _elements[i].id;
    _selectedIds
      ..clear()
      ..add(id);
    _focusId = id;
  }

  /// Tapping an element: collapse to a single selection of [id]; tapping the
  /// sole selected element clears it. (Discontiguous multi-select comes from the
  /// marquee — [selectByIds] — not from plain taps.)
  void toggleSelected(String id) {
    final i = _indexOf(id);
    if (i < 0) return;
    if (!hasRange && _focusId == id) {
      clearSelection();
    } else {
      _selectSingle(i);
    }
  }

  /// Add [id] to the selection (or remove it if already selected) — the
  /// discontiguous multi-select primitive (e.g. a modifier-tap). No-op for an
  /// unknown id.
  void toggleInSelection(String id) {
    if (_indexOf(id) < 0) return;
    if (!_selectedIds.add(id)) {
      _selectedIds.remove(id);
      if (_focusId == id) _focusId = selectedId;
    } else {
      _focusId = id;
    }
  }

  void clearSelection() {
    _selectedIds.clear();
    _focusId = null;
  }

  /// Select **exactly** the ids in [ids] that exist (a marquee result) — a
  /// discontiguous set, no longer widened to the span between them. Clears the
  /// selection if none are found. Selection only — not undoable.
  void selectByIds(Iterable<String> ids) {
    final present = [
      for (final id in ids)
        if (_indexOf(id) >= 0) id,
    ];
    if (present.isEmpty) {
      clearSelection();
      return;
    }
    _selectedIds
      ..clear()
      ..addAll(present);
    _focusId = present.last;
  }

  /// Collapse to a single selection and step it forward/back.
  void selectNext() {
    if (_elements.isEmpty) return;
    final focus = _focusId == null ? -1 : _indexOf(_focusId!);
    selectIndex(hasSelection ? focus + 1 : 0);
  }

  void selectPrev() {
    if (_elements.isEmpty) return;
    final focus = _focusId == null ? _elements.length : _indexOf(_focusId!);
    selectIndex(hasSelection ? focus - 1 : _elements.length - 1);
  }

  /// Grow the selected run outward by one element (the contiguous-extend the
  /// toolbar arrows drive). No shrink — the set model has no single focus end.
  void extendRight() {
    if (!hasSelection || _hi + 1 >= _elements.length) return;
    final id = _elements[_hi + 1].id;
    _selectedIds.add(id);
    _focusId = id;
  }

  void extendLeft() {
    if (!hasSelection || _lo == 0) return;
    final id = _elements[_lo - 1].id;
    _selectedIds.add(id);
    _focusId = id;
  }

  // ---- insertion ---------------------------------------------------------

  /// Insert position: just after the selection, or at the end.
  int _caretIndex() => hasSelection ? _hi + 1 : _elements.length;

  /// The id the insertion caret sits *before* (the element that would follow a
  /// newly placed note), or null when the caret is at the very end of the
  /// stream. Drives the visible editor caret.
  String? get caretBeforeId {
    final at = _caretIndex();
    return at < _elements.length ? _elements[at].id : null;
  }

  /// Insert a note at the caret and select it. Returns the new element's id.
  String insertNote(Pitch pitch, NoteDuration duration) {
    _snapshot();
    final id = _newId();
    final at = _caretIndex();
    _elements.insert(at, EditorElement.note(pitch, duration, id: id));
    selectIndex(at);
    return id;
  }

  /// Insert a rest at the caret and select it. Returns the new element's id.
  String insertRest(NoteDuration duration) {
    _snapshot();
    final id = _newId();
    final at = _caretIndex();
    _elements.insert(at, EditorElement.rest(duration, id: id));
    selectIndex(at);
    return id;
  }

  // ---- edits over the selection range ------------------------------------

  /// Nudge every selected note up/down by [semitones] (rests skipped, notes
  /// clamped to A0..C8 individually). Undoable.
  void transposeSelected(int semitones) {
    if (!hasSelection) return;
    _snapshot();
    for (final i in _selectedIndices) {
      final e = _elements[i];
      if (e.isRest) continue;
      _elements[i] = e.withPitches([
        for (final p in e.pitches)
          (p.midiNumber + semitones >= 21 && p.midiNumber + semitones <= 108)
              ? pitchFromMidi(p.midiNumber + semitones)
              : p,
      ]);
    }
  }

  /// The document index of the focus element, or null (deleted / no selection).
  int? get _focusIndex {
    final id = selectedId;
    if (id == null) return null;
    final i = _indexOf(id);
    return i < 0 ? null : i;
  }

  /// Add [pitch] to the focus element, turning a note into a chord. Undoable.
  void addPitchToSelected(Pitch pitch) {
    final f = _focusIndex;
    if (f == null || _elements[f].isRest) return;
    _snapshot();
    _elements[f] = _elements[f].addPitch(pitch);
  }

  /// Set the accidental of every selected note (rests skipped). Undoable.
  void setAccidentalOfSelected(int alter) {
    if (!hasSelection) return;
    _snapshot();
    for (final i in _selectedIndices) {
      final e = _elements[i];
      if (e.isRest) continue;
      _elements[i] = e.withPitches([
        for (final p in e.pitches)
          Pitch(p.step, alter: alter, octave: p.octave),
      ]);
    }
  }

  /// Set the duration of every selected element. Undoable.
  void setDurationOfSelected(NoteDuration duration) {
    if (!hasSelection) return;
    _snapshot();
    for (final i in _selectedIndices) {
      _elements[i] = _elements[i].withDuration(duration);
    }
  }

  List<int> get _selectedNoteIndices => [
        for (final i in _selectedIndices)
          if (!_elements[i].isRest) i,
      ];

  /// Toggle an articulation across the selected notes: if every selected note
  /// already has it, remove it from all; otherwise add it to all. Undoable.
  void toggleArticulationOfSelected(Articulation a) {
    final notes = _selectedNoteIndices;
    if (notes.isEmpty) return;
    final allHave = notes.every((i) => _elements[i].articulations.contains(a));
    _snapshot();
    for (final i in notes) {
      final set = {..._elements[i].articulations};
      allHave ? set.remove(a) : set.add(a);
      _elements[i] = _elements[i].withArticulations(set);
    }
  }

  /// Set (or clear, with null) the dynamic marking on the first selected note.
  void setDynamicOfSelected(DynamicLevel? level) {
    final notes = _selectedNoteIndices;
    if (notes.isEmpty) return;
    _snapshot();
    _elements[notes.first] = _elements[notes.first].withDynamic(level);
  }

  /// Set (or clear, with null) the ornament on every selected note. Undoable.
  void setOrnamentOfSelected(Ornament? ornament) {
    final notes = _selectedNoteIndices;
    if (notes.isEmpty) return;
    _snapshot();
    for (final i in notes) {
      _elements[i] = _elements[i].withOrnament(ornament);
    }
  }

  /// Attach [notes] as grace notes (an empty list clears them) with [style] on
  /// every selected note. Grace notes have zero bar duration, so this never
  /// changes packing. Rests are skipped. Undoable.
  void setGraceNotesOfSelected(
    List<Pitch> notes, {
    GraceStyle style = GraceStyle.acciaccatura,
  }) {
    final indices = _selectedNoteIndices;
    if (indices.isEmpty) return;
    _snapshot();
    for (final i in indices) {
      _elements[i] = _elements[i].withGraceNotes(notes, style: style);
    }
  }

  /// Tie every selected note to the next (or untie, if all are already tied).
  void toggleTieOfSelected() {
    final notes = _selectedNoteIndices;
    if (notes.isEmpty) return;
    final allTied = notes.every((i) => _elements[i].tieToNext);
    _snapshot();
    for (final i in notes) {
      _elements[i] = _elements[i].withTie(!allTied);
    }
  }

  /// Toggle a phrase slur over the selected range: draws an arc from the first
  /// selected note to the last (needs ≥2 notes). If that exact slur already
  /// exists, it is removed. Undoable.
  void slurSelected() {
    final notes = _selectedNoteIndices;
    if (notes.length < 2) return;
    final slur = Slur(_elements[notes.first].id, _elements[notes.last].id);
    _snapshot();
    if (!_slurs.remove(slur)) _slurs.add(slur);
  }

  /// Toggle a crescendo/diminuendo wedge over the selected range (needs ≥2
  /// notes). Applying the same type again removes it; a different type replaces
  /// it. Undoable.
  void hairpinSelected(HairpinType type) {
    final notes = _selectedNoteIndices;
    if (notes.length < 2) return;
    final start = _elements[notes.first].id, end = _elements[notes.last].id;
    _snapshot();
    final existing =
        _hairpins.where((h) => h.startId == start && h.endId == end).toList();
    final wasSameType = existing.any((h) => h.type == type);
    _hairpins.removeWhere((h) => h.startId == start && h.endId == end);
    if (!wasSameType) _hairpins.add(Hairpin(start, end, type));
  }

  /// Set (or clear, with empty/null) the lyric syllable under note [id] for
  /// [verse]. No-op on a rest or when unchanged (so it doesn't clutter undo).
  /// Undoable.
  void setLyricFor(String id, String? text, {int verse = 1}) {
    final i = _indexOf(id);
    if (i < 0 || _elements[i].isRest) return;
    final t = (text ?? '').trim();
    if ((_lyrics[id]?[verse] ?? '') == t) return;
    _snapshot();
    if (t.isEmpty) {
      _lyrics[id]?.remove(verse);
      if (_lyrics[id]?.isEmpty ?? false) _lyrics.remove(id);
    } else {
      (_lyrics[id] ??= {})[verse] = t;
    }
  }

  /// Drop any slur/lyric that references an id no longer in the stream (called
  /// after structural edits so spans never dangle).
  void _pruneOrnaments() {
    final ids = {for (final e in _elements) e.id};
    _slurs.removeWhere(
      (s) => !ids.contains(s.startId) || !ids.contains(s.endId),
    );
    _hairpins.removeWhere(
      (h) => !ids.contains(h.startId) || !ids.contains(h.endId),
    );
    _lyrics.removeWhere((id, _) => !ids.contains(id));
  }

  /// Set the anacrusis length (null clears it). The first bar then holds only
  /// this much music before the downbeat. Undoable.
  void setPickup(NoteDuration? value) {
    if (value == pickup) return;
    _snapshot();
    pickup = value;
  }

  /// Move the focus element so its lowest note lands on [pitch] (a chord moves
  /// as a block). No-op on a rest. Undoable.
  void repitchSelected(Pitch pitch) {
    final f = _focusIndex;
    if (f == null || _elements[f].isRest) return;
    _snapshot();
    _elements[f] = _elements[f].moveTo(pitch);
  }

  /// Re-pitch the note [id] to the staff position of a dragged [target]
  /// (keeps its accidental). Used by drag-to-move. Returns the new pitch, or
  /// null if nothing changed. Undoable.
  /// The measure (bar) index the element [id] currently lays out in, or -1.
  int measureIndexOf(String id) {
    final measures = buildScore().measures;
    for (var m = 0; m < measures.length; m++) {
      for (final el in measures[m].elements) {
        if (el.id == id) return m;
      }
    }
    return -1;
  }

  /// Horizontal drag-reorder: move element [id] so it lands at the start of bar
  /// [measureIndex] (clamped). Element order is preserved elsewhere, so this is
  /// a coarse (bar-level) reorder — dragging a note into another bar. Returns
  /// true if it moved. Undoable.
  bool moveByIdToMeasure(String id, int measureIndex) {
    final from = _indexOf(id);
    if (from < 0) return false;
    final measures = buildScore().measures;
    var target = 0;
    for (var m = 0; m < measureIndex && m < measures.length; m++) {
      target += measures[m].elements.length;
    }
    target = target.clamp(0, _elements.length);
    // No-op if it would land in the same slot.
    if (target == from || target == from + 1) return false;
    _snapshot();
    final el = _elements.removeAt(from);
    final insertAt =
        (target > from ? target - 1 : target).clamp(0, _elements.length);
    _elements.insert(insertAt, el);
    selectIndex(insertAt.clamp(0, _elements.length - 1));
    return true;
  }

  /// Fine drag-reorder: move element [id] to [index] in the flat stream (the
  /// index is in the post-removal list — i.e. "how many elements end up before
  /// it"). No-op if it wouldn't move. Undoable.
  bool moveByIdToIndex(String id, int index) {
    final from = _indexOf(id);
    if (from < 0) return false;
    final target = index.clamp(0, _elements.length - 1);
    if (target == from) return false;
    _snapshot();
    final el = _elements.removeAt(from);
    final insertAt = index.clamp(0, _elements.length);
    _elements.insert(insertAt, el);
    selectIndex(insertAt.clamp(0, _elements.length - 1));
    return true;
  }

  Pitch? moveById(String id, StaffTarget target, {Clef? clef}) {
    final i = _indexOf(id);
    if (i < 0 || _elements[i].isRest) return null;
    final current = _elements[i].pitch!;
    final moved =
        target.pitchFor(clef ?? this.clef, preferredAlter: current.alter);
    if (moved.midiNumber == current.midiNumber) return null;
    _snapshot();
    _elements[i] = _elements[i].moveTo(moved);
    return moved;
  }

  void deleteSelected() {
    if (!hasSelection) return;
    _snapshot();
    final lo = _lo;
    // Delete every selected element (the set may be discontiguous), not a range.
    final doomed = Set.of(selectedIds);
    _elements.removeWhere((e) => doomed.contains(e.id));
    _pruneOrnaments();
    clearSelection();
    if (_elements.isNotEmpty) {
      selectIndex(lo.clamp(0, _elements.length - 1));
    }
  }

  /// Move the selected block one slot left / right in the score. Only a
  /// contiguous selection can move as a block; a discontiguous one is a no-op.
  void moveSelectionLeft() {
    if (!hasSelection || !_isContiguous || _lo == 0) return;
    _snapshot();
    final e = _elements.removeAt(_lo - 1);
    _elements.insert(_hi, e);
  }

  void moveSelectionRight() {
    if (!hasSelection || !_isContiguous || _hi == _elements.length - 1) return;
    _snapshot();
    final e = _elements.removeAt(_hi + 1);
    _elements.insert(_lo, e);
  }

  // ---- clipboard ---------------------------------------------------------

  void copySelection() {
    if (!hasSelection) return;
    _clipboard
      ..clear()
      ..addAll(selectedElements);
  }

  void cutSelection() {
    if (!hasSelection) return;
    copySelection();
    deleteSelected();
  }

  /// Paste the clipboard after the selection (or at the end) and select it.
  /// Lyrics ride along with each copied element (onto its fresh id).
  void paste() {
    if (_clipboard.isEmpty) return;
    _snapshot();
    final at = _caretIndex();
    final fresh = <EditorElement>[];
    for (final c in _clipboard) {
      final e = c.withId(_newId());
      fresh.add(e);
      final syllables = _lyrics[c.id];
      if (syllables != null) _lyrics[e.id] = Map.of(syllables);
    }
    _elements.insertAll(at, fresh);
    // Select the pasted run (its ids), focus the last.
    _selectedIds
      ..clear()
      ..addAll(fresh.map((e) => e.id));
    _focusId = fresh.last.id;
  }

  // ---- document settings -------------------------------------------------

  void clearAll() {
    if (_elements.isEmpty) return;
    _snapshot();
    _elements.clear();
    _slurs.clear();
    _hairpins.clear();
    _lyrics.clear();
    _clefChanges.clear();
    _keyChanges.clear();
    _tempoChanges.clear();
    _timeChanges.clear();
    _repeatStarts.clear();
    _repeatEnds.clear();
    _voltas.clear();
    _navigation.clear();
    _tuplets.clear();
    clearSelection();
  }

  /// Replace the whole document with the contents of [score] (undoable).
  ///
  /// This is the exact inverse of [buildScore] for everything an
  /// [EditorElement] can hold — chords, articulations, ties, dynamics, slurs,
  /// hairpins, lyrics and the pickup all survive, so **save → reopen is
  /// lossless**. (It used to keep only `pitches.first` and drop ties,
  /// articulations, dynamics and the pickup, which silently destroyed the
  /// user's work on reopen.)
  ///
  /// Bar-anchored attributes are recovered too: mid-score clef/key/time changes
  /// and repeat barlines re-anchor onto their bar's first element.
  ///
  /// Per-note attributes are recovered too: ornaments and grace notes ride the
  /// element as it is rebuilt.
  ///
  /// Still dropped, because the flat element stream cannot represent them:
  /// voices 2–4. Those are unblocked by the measure-spine work, not here —
  /// see docs/WORKSHOP_PARITY.md.
  void loadScore(Score score) {
    _snapshot();
    _elements.clear();
    _slurs.clear();
    _hairpins.clear();
    _lyrics.clear();
    _clefChanges.clear();
    _keyChanges.clear();
    _tempoChanges.clear();
    _timeChanges.clear();
    _repeatStarts.clear();
    _repeatEnds.clear();
    _voltas.clear();
    _navigation.clear();
    _tuplets.clear();
    clef = score.clef;
    keySignature = score.keySignature;
    timeSignature = score.timeSignature ?? TimeSignature.fourFour;
    tempo = score.tempo;
    pickup = _pickupOf(score);
    // Dynamics live in a side list keyed by element id, so they have to be
    // re-anchored onto the elements as we rebuild them.
    final dynamics = {for (final d in score.dynamics) d.elementId: d.level};
    // Old element id → the fresh id we assign, so imported slurs/lyrics re-anchor.
    final remap = <String, String>{};
    for (final measure in score.measures) {
      String? firstIdInBar;
      final barNewIds = <String>[]; // new id per element, in reading order
      for (final el in measure.elements) {
        final id = _newId();
        firstIdInBar ??= id;
        barNewIds.add(id);
        if (el.id != null) remap[el.id!] = id;
        if (el is NoteElement) {
          _elements.add(
            EditorElement.chord(
              List.of(el.pitches),
              el.duration,
              id: id,
              articulations: Set.of(el.articulations),
              tieToNext: el.tieToNext,
              dynamic: el.id == null ? null : dynamics[el.id!],
              ornament: el.ornament,
              graceNotes: List.of(el.graceNotes),
              graceStyle: el.graceStyle,
            ),
          );
        } else if (el is RestElement) {
          _elements.add(EditorElement.rest(el.duration, id: id));
        }
      }
      // Recover bar-start clef / key changes by anchoring them to the bar's
      // first element, so save → reopen keeps them (the inverse of
      // [_withMidScoreChanges]). Mid-bar clef changes (inlineClefs) aren't
      // modelled by the editor yet.
      if (firstIdInBar != null) {
        final cc = measure.clefChange;
        if (cc != null) _clefChanges[firstIdInBar] = cc;
        final kc = measure.keyChange;
        if (kc != null) _keyChanges[firstIdInBar] = kc;
        final tmpo = measure.tempoChange;
        if (tmpo != null) _tempoChanges[firstIdInBar] = tmpo;
        final tc = measure.timeChange;
        if (tc != null) _timeChanges[firstIdInBar] = tc;
        if (measure.startRepeat) _repeatStarts.add(firstIdInBar);
        if (measure.endRepeat) _repeatEnds.add(firstIdInBar);
        final vol = measure.volta;
        if (vol != null) _voltas[firstIdInBar] = vol;
        final nav = measure.navigation;
        if (nav != null) _navigation[firstIdInBar] = nav;
      }
      // Recover voice-1 tuplets: a span's [startIndex..endIndex] map onto the
      // new ids we just assigned in reading order.
      for (final span in measure.tuplets) {
        if (span.voice != 0) continue; // editor is single-voice
        if (span.endIndex >= barNewIds.length) continue;
        _tuplets.add(
          Tuplet(
            barNewIds.sublist(span.startIndex, span.endIndex + 1),
            actual: span.actual,
            normal: span.normal,
          ),
        );
      }
    }
    for (final s in score.slurs) {
      final start = remap[s.startId], end = remap[s.endId];
      if (start != null && end != null) _slurs.add(Slur(start, end));
    }
    for (final h in score.hairpins) {
      final start = remap[h.startId], end = remap[h.endId];
      if (start != null && end != null) {
        _hairpins.add(Hairpin(start, end, h.type));
      }
    }
    for (final ly in score.lyrics) {
      final id = remap[ly.elementId];
      if (id != null && ly.text.isNotEmpty) {
        (_lyrics[id] ??= {})[ly.verse] = ly.text;
      }
    }
    clearSelection();
  }

  /// The anacrusis of [score], recovered from its flagged opening bar.
  ///
  /// [buildScore] writes the pickup as `Measure(pickup: true)` and lets the bar
  /// hold whatever music fits, so reading it back means re-measuring that bar's
  /// contents. Returns null unless the total lands exactly on a duration the
  /// editor can represent — an unrepresentable anacrusis re-packs as a normal
  /// bar rather than silently rounding the music to the wrong length.
  static NoteDuration? _pickupOf(Score score) {
    if (score.measures.isEmpty || !score.measures.first.pickup) return null;
    var total = Fraction(0, 1);
    for (final el in score.measures.first.elements) {
      total = total + el.duration.toFraction();
    }
    for (final base in DurationBase.values) {
      for (var dots = 0; dots <= 2; dots++) {
        final candidate = NoteDuration(base, dots: dots);
        if (candidate.toFraction() == total) return candidate;
      }
    }
    return null;
  }

  void setTimeSignature(TimeSignature value) {
    if (value == timeSignature) return;
    _snapshot();
    timeSignature = value;
  }

  void setKeySignature(KeySignature value) {
    if (value == keySignature) return;
    _snapshot();
    keySignature = value;
  }

  void setClef(Clef value) {
    if (value == clef) return;
    _snapshot();
    clef = value;
  }

  /// The mid-score clef / key / time changes as (element id → value), read-only.
  Map<String, Clef> get clefChanges => Map.unmodifiable(_clefChanges);
  Map<String, KeySignature> get keyChanges => Map.unmodifiable(_keyChanges);
  Map<String, TimeSignature> get timeChanges => Map.unmodifiable(_timeChanges);

  /// The mid-score tempo changes as (element id → mark), read-only.
  Map<String, Tempo> get tempoChanges => Map.unmodifiable(_tempoChanges);

  /// The mid-score tempo mark anchored at element [id], or null.
  Tempo? tempoChangeAt(String id) => _tempoChanges[id];

  /// Set (or clear, with null) the document's **initial tempo** (metronome mark
  /// at the start of the piece). Undoable; a no-op for an unchanged value.
  void setInitialTempo(Tempo? value) {
    if (value == tempo) return;
    _snapshot();
    tempo = value;
  }

  /// Set (or clear, with null) a **mid-score tempo change** that takes effect at
  /// the start of the bar containing element [id]. Undoable; element-anchored
  /// like [setClefChangeAt], so it rides re-barring. Does not affect bar
  /// capacity, so it is a pure post-reflow stamp.
  void setTempoChangeAt(String id, Tempo? mark) {
    if (_indexOf(id) < 0) return;
    if (_tempoChanges[id] == mark) return;
    _snapshot();
    if (mark == null) {
      _tempoChanges.remove(id);
    } else {
      _tempoChanges[id] = mark;
    }
  }

  /// Set (or clear, with null) a **mid-score clef change** that takes effect at
  /// the start of the bar containing element [id]. Undoable; a no-op for an
  /// unknown id or an unchanged value.
  ///
  /// The change is anchored to the element, not to a bar number, so it rides
  /// along as the music is re-barred by [reflow] — insert a note earlier and the
  /// clef change stays with its note rather than jumping to the wrong bar.
  void setClefChangeAt(String id, Clef? clef) {
    if (_indexOf(id) < 0) return;
    if (_clefChanges[id] == clef) return;
    _snapshot();
    if (clef == null) {
      _clefChanges.remove(id);
    } else {
      _clefChanges[id] = clef;
    }
  }

  /// Set (or clear, with null) a **mid-score key change** at the start of the bar
  /// containing element [id]. Undoable; element-anchored exactly like
  /// [setClefChangeAt], so it rides re-barring. (Does not affect bar capacity.)
  void setKeyChangeAt(String id, KeySignature? key) {
    if (_indexOf(id) < 0) return;
    if (_keyChanges[id] == key) return;
    _snapshot();
    if (key == null) {
      _keyChanges.remove(id);
    } else {
      _keyChanges[id] = key;
    }
  }

  /// Set (or clear, with null) a **mid-score time-signature change** at the bar
  /// containing element [id]. Undoable; element-anchored like the others, but
  /// this one re-bars from the anchor onward (the new meter changes bar
  /// capacity), so it is applied inside [reflow].
  void setTimeChangeAt(String id, TimeSignature? time) {
    if (_indexOf(id) < 0) return;
    if (_timeChanges[id] == time) return;
    _snapshot();
    if (time == null) {
      _timeChanges.remove(id);
    } else {
      _timeChanges[id] = time;
    }
  }

  /// Whether the bar containing element [id] starts / ends a repeat.
  bool repeatStartsAt(String id) => _repeatStarts.contains(id);
  bool repeatEndsAt(String id) => _repeatEnds.contains(id);

  /// Toggle a repeat barline at the bar containing element [id]. Undoable;
  /// element-anchored like the mid-score changes, so it rides re-barring. A
  /// start repeat draws `‖:` at that bar's left; an end repeat draws `:‖` at its
  /// right — both are booleans on the [crisp_notation] `Measure`, and playback
  /// expands them (`playbackTimeline`).
  void toggleRepeatStartAt(String id) => _toggleRepeat(_repeatStarts, id);
  void toggleRepeatEndAt(String id) => _toggleRepeat(_repeatEnds, id);

  void _toggleRepeat(Set<String> set, String id) {
    if (_indexOf(id) < 0) return;
    _snapshot();
    if (!set.add(id)) set.remove(id);
  }

  /// The volta (ending) number / navigation mark at the bar of element [id].
  int? voltaAt(String id) => _voltas[id];
  NavigationMark? navigationAt(String id) => _navigation[id];

  /// Set (or clear, with null) the **volta ending number** (1, 2, …) on the bar
  /// containing element [id]. Undoable; element-anchored, drawn as an ending
  /// bracket over the bar. Numbers < 1 clear it.
  void setVoltaAt(String id, int? volta) {
    if (_indexOf(id) < 0) return;
    final v = (volta != null && volta >= 1) ? volta : null;
    if (_voltas[id] == v) return;
    _snapshot();
    if (v == null) {
      _voltas.remove(id);
    } else {
      _voltas[id] = v;
    }
  }

  /// Set (or clear, with null) a **navigation mark** (D.C./D.S./coda/segno/fine)
  /// on the bar containing element [id]. Undoable; element-anchored, drawn above
  /// the staff, and expanded by `playbackTimeline`.
  void setNavigationAt(String id, NavigationMark? mark) {
    if (_indexOf(id) < 0) return;
    if (_navigation[id] == mark) return;
    _snapshot();
    if (mark == null) {
      _navigation.remove(id);
    } else {
      _navigation[id] = mark;
    }
  }

  /// The tuplet group containing element [id], or null.
  Tuplet? tupletOf(String id) {
    for (final t in _tuplets) {
      if (t.memberIds.contains(id)) return t;
    }
    return null;
  }

  /// Group the elements at [ids] into an [actual]:[normal] tuplet (default a
  /// 3:2 triplet). No-op unless there are ≥2 ids that are **consecutive** in the
  /// stream and none already belong to a tuplet. Undoable.
  void addTuplet(Iterable<String> ids, {int actual = 3, int normal = 2}) {
    final idList = ids.toList();
    if (idList.length < 2 || actual < 2 || normal < 1) return;
    final indices = [for (final id in idList) _indexOf(id)];
    if (indices.any((i) => i < 0)) return;
    indices.sort();
    // Consecutive in the stream?
    if (indices.last - indices.first != indices.length - 1) return;
    final ordered = [for (final i in indices) _elements[i].id];
    if (ordered.any((id) => tupletOf(id) != null)) return; // already tupleted
    _snapshot();
    _tuplets.add(Tuplet(ordered, actual: actual, normal: normal));
  }

  /// Remove the tuplet group containing element [id] (undoable; no-op if none).
  void removeTupletAt(String id) {
    final t = tupletOf(id);
    if (t == null) return;
    _snapshot();
    _tuplets.remove(t);
  }

  // ---- rendering ---------------------------------------------------------

  /// Pack the flat element stream into bar-lined [Measure]s. A note that would
  /// overflow the current bar starts a new one (no splitting/tying yet). An
  /// empty document renders a single whole-rest bar so the staff stays wide.
  Score buildScore() {
    return _scoreCache ??= Score(
      clef: clef,
      keySignature: keySignature,
      timeSignature: timeSignature,
      tempo: tempo,
      measures: _withTuplets(
        _withMidScoreChanges(
          reflow(
            [for (final e in _elements) e.toElement()],
            timeSignature: timeSignature,
            pickup: pickup,
            timeChanges: _timeChanges,
            durationScale: _tupletScale(),
            split: _rhythmPolicy == RhythmPolicy.split,
          ),
        ),
      ),
      dynamics: [
        for (final e in _elements)
          if (!e.isRest && e.dynamic != null) DynamicMarking(e.id, e.dynamic!),
      ],
      slurs: List.of(_slurs),
      hairpins: List.of(_hairpins),
      lyrics: [
        for (final e in _elements)
          if (_lyrics[e.id] != null)
            for (final v in _lyrics[e.id]!.entries)
              Lyric(e.id, v.value, verse: v.key),
      ],
    );
  }

  /// The score rendered across two clefs: each note goes on the treble staff
  /// (from middle C up) or the bass staff (below), with a matching rest on the
  /// other staff so both share the same bar grid. This displays one melody with
  /// both clefs (no jarring whole-score flip) — it is not two independent voices.
  GrandStaff buildGrandStaff() {
    final cached = _grandCache;
    if (cached != null) return cached;
    final upper = <MusicElement>[];
    final lower = <MusicElement>[];
    for (final e in _elements) {
      if (e.isRest) {
        upper.add(RestElement(e.duration, id: e.id));
        lower.add(RestElement(e.duration));
      } else if (e.pitch!.midiNumber >= 60) {
        upper.add(e.toElement());
        lower.add(RestElement(e.duration));
      } else {
        lower.add(e.toElement());
        upper.add(RestElement(e.duration));
      }
    }
    return _grandCache = GrandStaff(
      upper: Score(
        clef: Clef.treble,
        keySignature: keySignature,
        timeSignature: timeSignature,
        measures: reflow(upper, timeSignature: timeSignature, pickup: pickup),
      ),
      lower: Score(
        clef: Clef.bass,
        keySignature: keySignature,
        timeSignature: timeSignature,
        measures: reflow(lower, timeSignature: timeSignature, pickup: pickup),
      ),
    );
  }

  /// Stamps mid-score clef / key changes onto the reflowed [bars].
  ///
  /// A change anchored to an element takes effect at the start of the bar that
  /// element landed in; [crisp_notation]'s engine then carries that clef/key
  /// forward until the next change, so only the changing bars are marked.
  /// Redundant anchors (same value as the running one) are skipped so nothing
  /// draws twice, and a bar with several anchors of a kind takes the last one in
  /// reading order.
  ///
  /// Repeat barlines are stamped here too (booleans, so `copyWith` only ever
  /// sets them true — an unanchored bar is left untouched at false).
  ///
  /// The all-empty fast path returns [bars] untouched, so a document with no
  /// mid-score changes renders byte-for-byte as before — every existing golden
  /// holds.
  List<Measure> _withMidScoreChanges(List<Measure> bars) {
    if (_clefChanges.isEmpty &&
        _keyChanges.isEmpty &&
        _tempoChanges.isEmpty &&
        _repeatStarts.isEmpty &&
        _repeatEnds.isEmpty &&
        _voltas.isEmpty &&
        _navigation.isEmpty) {
      return bars;
    }
    var runningClef = clef;
    var runningKey = keySignature;
    var runningTempo = tempo;
    final out = <Measure>[];
    for (final m in bars) {
      var next = m;
      final clefHere = _anchoredIn(m, _clefChanges);
      if (clefHere != null && clefHere != runningClef) {
        next = next.copyWith(clefChange: clefHere);
        runningClef = clefHere;
      }
      final keyHere = _anchoredIn(m, _keyChanges);
      if (keyHere != null && keyHere != runningKey) {
        next = next.copyWith(keyChange: keyHere);
        runningKey = keyHere;
      }
      final tempoHere = _anchoredIn(m, _tempoChanges);
      if (tempoHere != null && tempoHere != runningTempo) {
        next = next.copyWith(tempoChange: tempoHere);
        runningTempo = tempoHere;
      }
      if (_anchoredInSet(m, _repeatStarts)) {
        next = next.copyWith(startRepeat: true);
      }
      if (_anchoredInSet(m, _repeatEnds)) {
        next = next.copyWith(endRepeat: true);
      }
      final voltaHere = _anchoredIn(m, _voltas);
      if (voltaHere != null) next = next.copyWith(volta: voltaHere);
      final navHere = _anchoredIn(m, _navigation);
      if (navHere != null) next = next.copyWith(navigation: navHere);
      out.add(next);
    }
    return out;
  }

  /// Whether any element of [m] carries an anchor in [ids].
  bool _anchoredInSet(Measure m, Set<String> ids) =>
      m.elements.any((e) => e.id != null && ids.contains(e.id));

  /// element id → sounding-duration scale, for [reflow] (built from [_tuplets]).
  Map<String, Fraction> _tupletScale() => {
        for (final t in _tuplets)
          for (final id in t.memberIds) id: t.scale,
      };

  /// Emits a [TupletSpan] per group over the index range its members occupy in
  /// the bar they landed in. A group is skipped (no bracket) when re-barring has
  /// split its members across bars or made them non-contiguous — the group data
  /// survives, so it reappears if a later edit makes it valid again.
  ///
  /// Empty-list fast path keeps repeat-free / tuplet-free scores byte-identical.
  List<Measure> _withTuplets(List<Measure> bars) {
    if (_tuplets.isEmpty) return bars;
    // element id → (bar index, index within that bar).
    final pos = <String, (int, int)>{};
    for (var b = 0; b < bars.length; b++) {
      final els = bars[b].elements;
      for (var i = 0; i < els.length; i++) {
        final id = els[i].id;
        if (id != null) pos[id] = (b, i);
      }
    }
    final perBar = <int, List<TupletSpan>>{};
    for (final t in _tuplets) {
      final locs = [
        for (final id in t.memberIds)
          if (pos[id] case final p?) p,
      ];
      if (locs.length != t.memberIds.length) continue; // a member vanished
      final bar = locs.first.$1;
      if (locs.any((l) => l.$1 != bar)) continue; // crosses a barline
      final idxs = [for (final l in locs) l.$2]..sort();
      if (idxs.last - idxs.first != idxs.length - 1) continue; // not contiguous
      (perBar[bar] ??= []).add(
        TupletSpan(idxs.first, idxs.last, actual: t.actual, normal: t.normal),
      );
    }
    if (perBar.isEmpty) return bars;
    return [
      for (var b = 0; b < bars.length; b++)
        if (perBar[b] case final spans?)
          bars[b].copyWith(tuplets: [...bars[b].tuplets, ...spans])
        else
          bars[b],
    ];
  }

  /// The value anchored to an element within [m] (last anchor in reading order
  /// wins), or null if none of [m]'s elements carry an anchor in [changes].
  V? _anchoredIn<V>(Measure m, Map<String, V> changes) {
    V? found;
    for (final el in m.elements) {
      final id = el.id;
      if (id != null && changes.containsKey(id)) found = changes[id];
    }
    return found;
  }

  int get barCount => buildScore().measures.length;
}

/// Packs a flat element stream into bar-lined [Measure]s for the prevailing
/// [timeSignature] and optional [pickup] (anacrusis). A note that would overflow
/// the current bar starts a new one (no splitting/tying yet); an empty list
/// yields a single whole-rest bar so the staff stays wide and tappable.
///
/// Pure and document-free by design: this is the seam the measure-spine work
/// builds on (docs/WORKSHOP_PARITY.md, Cause 1 — bars become first-class and a
/// `RhythmPolicy.spill` document reflows through exactly this). Its output is
/// pinned byte-for-byte by `test/score_document_packing_golden_test.dart`, so
/// the representation change stays externally invisible. Today its only callers
/// are [ScoreDocument.buildScore] and [ScoreDocument.buildGrandStaff].
/// How [reflow] handles a note that overruns its bar.
enum RhythmPolicy {
  /// Short-fill the bar and start the note fresh in the next (kid sandbox).
  spill,

  /// Split the note into tied notes across the barline (Studio).
  split,
}

/// The note values [reflow]'s split mode can write, largest first (dotted before
/// plain of the same base, since dotted is larger). Whole … sixteenth, 0–1 dots
/// — the range the editor supports.
final List<(NoteDuration, Fraction)> _notatableValues = () {
  final v = <(NoteDuration, Fraction)>[
    for (final base in DurationBase.values)
      if (base.index <= DurationBase.sixteenth.index)
        for (final dots in [1, 0])
          (
            NoteDuration(base, dots: dots),
            NoteDuration(base, dots: dots).toFraction()
          ),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return v;
}();

/// Decomposes [total] (a fraction of a whole note) into the fewest supported
/// note values, largest first — e.g. 5/8 → [half, eighth], 5/16 → [quarter,
/// sixteenth]. These are the tied pieces a split note becomes. Returns `[]` for
/// a non-positive [total]; any residue it can't express (below a sixteenth) is
/// dropped, which the bar-aligned caller never hits.
List<NoteDuration> notate(Fraction total) {
  final zero = Fraction(0, 1);
  final out = <NoteDuration>[];
  var rem = total;
  var guard = 0;
  while (rem.compareTo(zero) > 0 && guard++ < 64) {
    var placed = false;
    for (final (nd, frac) in _notatableValues) {
      if (frac.compareTo(rem) <= 0) {
        out.add(nd);
        rem = rem - frac;
        placed = true;
        break;
      }
    }
    if (!placed) break; // residue smaller than a sixteenth
  }
  return out;
}

/// A tuplet group: the [memberIds] (consecutive notes/rests) are played [actual]
/// in the time of [normal] of their written value — a triplet is 3:2, a
/// quintuplet 5:4. Immutable; the document owns the list.
class Tuplet {
  Tuplet(List<String> memberIds, {required this.actual, required this.normal})
      : memberIds = List.unmodifiable(memberIds);

  final List<String> memberIds;
  final int actual;
  final int normal;

  /// The factor a member's written duration is scaled by when it sounds and
  /// when [reflow] packs it into a bar (normal/actual — 2/3 for a triplet).
  Fraction get scale => Fraction(normal, actual);

  Tuplet copy() => Tuplet(memberIds, actual: actual, normal: normal);
}

List<Measure> reflow(
  List<MusicElement> elements, {
  required TimeSignature timeSignature,
  NoteDuration? pickup,
  Map<String, TimeSignature> timeChanges = const {},
  Map<String, Fraction> durationScale = const {},
  bool split = false,
}) {
  if (elements.isEmpty) {
    return const [
      Measure([RestElement(NoteDuration(DurationBase.whole))]),
    ];
  }
  final zero = Fraction(0, 1);
  final pickupCap = pickup?.toFraction();
  final bars = <Measure>[];
  var current = <MusicElement>[];
  var filled = zero;
  var isFirst = true;
  // Unlike clef/key, a time change alters bar *capacity*, so it can't be a
  // post-reflow stamp — it lives here. `meter`/`full` track the running meter,
  // and `barTimeChange` is stamped on the bar currently being accumulated (a
  // meter change starts a fresh bar and marks it). With no timeChanges this all
  // stays inert, so the output is byte-identical to the single-meter packer.
  var meter = timeSignature;
  var full = meter.toFraction();
  TimeSignature? barTimeChange;
  // The opening bar holds only the anacrusis (when set); every later bar is
  // a full measure. The short opening bar is flagged as a pickup.
  Fraction capacity() => (isFirst && pickupCap != null) ? pickupCap : full;
  void flush() {
    bars.add(
      Measure(
        current,
        pickup: isFirst && pickupCap != null,
        timeChange: barTimeChange,
      ),
    );
    current = [];
    filled = zero;
    isFirst = false;
    barTimeChange = null;
  }

  for (final el in elements) {
    // A meter change must fall on a barline: close the current bar, switch
    // capacity, and mark the new bar. Anchored to the element id (like clef/key)
    // so it rides re-barring.
    final change = timeChanges[el.id];
    if (change != null && change != meter) {
      if (current.isNotEmpty) flush();
      meter = change;
      full = meter.toFraction();
      barTimeChange = change;
    }
    // A tuplet member fills the bar at its scaled (sounding) duration, not its
    // written one — 3 written eighths of a triplet occupy 2 eighths of the bar.
    final scale = durationScale[el.id];
    final d = scale == null
        ? el.duration.toFraction()
        : el.duration.toFraction() * scale;

    // SPILL (default): a note that would overflow starts a new bar, short-
    // filling this one. Byte-identical to the single-meter packer.
    if (!split) {
      if (filled > zero && (filled + d) > capacity()) flush();
      current.add(el);
      filled = filled + d;
      continue;
    }

    // SPLIT: if it fits whole in the current bar, place it as-is (keeping its
    // id / articulations / tie). Otherwise notate it as tied pieces that fill
    // each bar exactly and carry across the barline.
    if ((filled + d).compareTo(capacity()) <= 0) {
      current.add(el);
      filled = filled + d;
      continue;
    }
    final origTie = el is NoteElement && el.tieToNext;
    var remaining = d;
    var pieceIndex = 0;
    while (remaining.compareTo(zero) > 0) {
      var room = capacity() - filled;
      if (room.compareTo(zero) <= 0) {
        flush();
        room = capacity();
      }
      final take = remaining.compareTo(room) <= 0 ? remaining : room;
      for (final nd in notate(take)) {
        remaining = remaining - nd.toFraction();
        final isVeryLast = remaining.compareTo(zero) <= 0;
        current.add(
          _splitPiece(el, nd, pieceIndex, tie: !isVeryLast || origTie),
        );
        pieceIndex++;
        filled = filled + nd.toFraction();
      }
      if (remaining.compareTo(zero) > 0) flush();
    }
  }
  if (current.isNotEmpty) flush();
  return bars;
}

/// One tied piece of a split note/rest: piece 0 keeps [src]'s id + articulations
/// (a slur/staccato belongs on the first of a tie); continuations get a derived
/// id (`<id>s2`, `<id>s3`) and no articulations. [tie] carries the sustain to
/// the next piece.
MusicElement _splitPiece(
  MusicElement src,
  NoteDuration nd,
  int index, {
  required bool tie,
}) {
  final baseId = src.id;
  final id =
      index == 0 ? baseId : (baseId == null ? null : '${baseId}s${index + 1}');
  if (src is NoteElement) {
    return NoteElement(
      pitches: src.pitches,
      duration: nd,
      id: id,
      articulations: index == 0 ? src.articulations : const {},
      tieToNext: tie,
    );
  }
  return RestElement(nd, id: id);
}
