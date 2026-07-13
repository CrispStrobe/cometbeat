// lib/features/workshop/model/score_document.dart
//
// The editable document behind the Composition Workshop. partitura's Score is
// an immutable value tree with no in-place editing, so the editor keeps its own
// flat, mutable list of [EditorElement]s and rebuilds an immutable [Score] on
// demand (packing the flat list into bar-lined measures). All mutations go
// through commands that snapshot first, giving multi-level undo/redo.
//
// Selection is a contiguous index range (a single element is a range of one),
// which the editing commands (transpose / duration / accidental / delete /
// move / copy / cut / paste) all operate over.

import 'dart:math' as math;

import 'package:klang_universum/shared/midi_pitch.dart';
import 'package:partitura/partitura.dart';

/// One editable event in the flat stream: a note (single pitch for now; chords
/// come later) or a rest, with a stable [id] so it can be selected and edited.
class EditorElement {
  const EditorElement.note(
    Pitch this.pitch,
    this.duration, {
    required this.id,
    this.articulations = const {},
    this.tieToNext = false,
    this.dynamic,
  }) : isRest = false;

  const EditorElement.rest(this.duration, {required this.id})
      : pitch = null,
        isRest = true,
        articulations = const {},
        tieToNext = false,
        dynamic = null;

  /// The pitch, or null for a rest.
  final Pitch? pitch;
  final NoteDuration duration;
  final String id;
  final bool isRest;

  /// Note-only ornaments (rests ignore these).
  final Set<Articulation> articulations;
  final bool tieToNext;

  /// A dynamic marking anchored on this note (null = none).
  final DynamicLevel? dynamic;

  /// This event as an immutable partitura element.
  MusicElement toElement() => isRest
      ? RestElement(duration, id: id)
      : NoteElement.note(
          pitch!,
          duration,
          id: id,
          articulations: articulations,
          tieToNext: tieToNext,
        );

  EditorElement _note(
    Pitch pitch,
    NoteDuration duration, {
    Set<Articulation>? articulations,
    bool? tieToNext,
  }) =>
      EditorElement.note(
        pitch,
        duration,
        id: id,
        articulations: articulations ?? this.articulations,
        tieToNext: tieToNext ?? this.tieToNext,
        dynamic: dynamic,
      );

  EditorElement withPitch(Pitch pitch) => _note(pitch, duration);

  EditorElement withDuration(NoteDuration duration) =>
      isRest ? EditorElement.rest(duration, id: id) : _note(pitch!, duration);

  EditorElement withId(String id) => isRest
      ? EditorElement.rest(duration, id: id)
      : EditorElement.note(
          pitch!,
          duration,
          id: id,
          articulations: articulations,
          tieToNext: tieToNext,
          dynamic: dynamic,
        );

  EditorElement withArticulations(Set<Articulation> a) =>
      _note(pitch!, duration, articulations: a);

  EditorElement withTie(bool tie) => _note(pitch!, duration, tieToNext: tie);

  EditorElement withDynamic(DynamicLevel? d) => EditorElement.note(
        pitch!,
        duration,
        id: id,
        articulations: articulations,
        tieToNext: tieToNext,
        dynamic: d,
      );
}

/// An undo/redo snapshot of the document's mutable state.
class _Snapshot {
  const _Snapshot(
    this.elements,
    this.timeSignature,
    this.keySignature,
    this.clef,
  );
  final List<EditorElement> elements;
  final TimeSignature timeSignature;
  final KeySignature keySignature;
  final Clef clef;
}

/// The editable Workshop document: an ordered element stream, the document-level
/// clef/time/key, a range selection, a clipboard, and undo/redo.
class ScoreDocument {
  ScoreDocument({
    this.timeSignature = TimeSignature.fourFour,
    this.keySignature = const KeySignature(0),
    this.clef = Clef.treble,
  });

  final List<EditorElement> _elements = [];
  TimeSignature timeSignature;
  KeySignature keySignature;

  /// The staff clef — chosen by the user; no automatic mid-score flipping.
  Clef clef;

  // Selection range: [anchor..focus] inclusive; null = nothing selected.
  int? _anchor;
  int? _focus;
  var _nextId = 0;

  final List<EditorElement> _clipboard = [];
  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];

  // ---- reads -------------------------------------------------------------

  List<EditorElement> get elements => List.unmodifiable(_elements);
  int get length => _elements.length;
  bool get isEmpty => _elements.isEmpty;

  bool get hasSelection => _anchor != null && _focus != null;
  bool get hasRange => hasSelection && _lo != _hi;
  int get _lo => math.min(_anchor!, _focus!);
  int get _hi => math.max(_anchor!, _focus!);

  /// The focus element's id (used for single-note controls + status).
  String? get selectedId => hasSelection ? _elements[_focus!].id : null;

  /// Every id in the selection range (for highlighting).
  Set<String> get selectedIds =>
      hasSelection ? {for (var i = _lo; i <= _hi; i++) _elements[i].id} : {};

  /// The focus element (or null).
  EditorElement? get selected => hasSelection ? _elements[_focus!] : null;

  List<EditorElement> get selectedElements =>
      hasSelection ? _elements.sublist(_lo, _hi + 1) : const [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get canPaste => _clipboard.isNotEmpty;

  String _newId() => 'w${_nextId++}';

  // ---- history -----------------------------------------------------------

  _Snapshot _capture() =>
      _Snapshot(List.of(_elements), timeSignature, keySignature, clef);

  void _snapshot() {
    _undo.add(_capture());
    _redo.clear();
  }

  void _restore(_Snapshot s) {
    _elements
      ..clear()
      ..addAll(s.elements);
    timeSignature = s.timeSignature;
    keySignature = s.keySignature;
    clef = s.clef;
    // Keep the selection valid against the restored length.
    if (_elements.isEmpty) {
      _anchor = _focus = null;
    } else {
      _anchor = _anchor?.clamp(0, _elements.length - 1);
      _focus = _focus?.clamp(0, _elements.length - 1);
    }
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
    _anchor = _focus = i.clamp(0, _elements.length - 1);
  }

  int _indexOf(String id) => _elements.indexWhere((e) => e.id == id);

  /// Toggle single-selection of [id] (tapping the sole selected element clears
  /// it; tapping any element while a range is active collapses to it).
  void toggleSelected(String id) {
    final i = _indexOf(id);
    if (i < 0) return;
    if (!hasRange && _focus == i) {
      clearSelection();
    } else {
      selectIndex(i);
    }
  }

  void clearSelection() => _anchor = _focus = null;

  /// Collapse to a single selection and step it forward/back.
  void selectNext() {
    if (_elements.isEmpty) return;
    selectIndex(hasSelection ? _focus! + 1 : 0);
  }

  void selectPrev() {
    if (_elements.isEmpty) return;
    selectIndex(hasSelection ? _focus! - 1 : _elements.length - 1);
  }

  /// Grow/shrink the range by moving the focus end.
  void extendRight() {
    if (!hasSelection) return;
    _focus = (_focus! + 1).clamp(0, _elements.length - 1);
  }

  void extendLeft() {
    if (!hasSelection) return;
    _focus = (_focus! - 1).clamp(0, _elements.length - 1);
  }

  // ---- insertion ---------------------------------------------------------

  /// Insert position: just after the selection, or at the end.
  int _caretIndex() => hasSelection ? _hi + 1 : _elements.length;

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
    for (var i = _lo; i <= _hi; i++) {
      final e = _elements[i];
      if (e.isRest) continue;
      final midi = e.pitch!.midiNumber + semitones;
      if (midi < 21 || midi > 108) continue;
      _elements[i] = e.withPitch(pitchFromMidi(midi));
    }
  }

  /// Set the accidental of every selected note (rests skipped). Undoable.
  void setAccidentalOfSelected(int alter) {
    if (!hasSelection) return;
    _snapshot();
    for (var i = _lo; i <= _hi; i++) {
      final e = _elements[i];
      if (e.isRest) continue;
      final p = e.pitch!;
      _elements[i] = e.withPitch(Pitch(p.step, alter: alter, octave: p.octave));
    }
  }

  /// Set the duration of every selected element. Undoable.
  void setDurationOfSelected(NoteDuration duration) {
    if (!hasSelection) return;
    _snapshot();
    for (var i = _lo; i <= _hi; i++) {
      _elements[i] = _elements[i].withDuration(duration);
    }
  }

  List<int> get _selectedNoteIndices => hasSelection
      ? [
          for (var i = _lo; i <= _hi; i++)
            if (!_elements[i].isRest) i,
        ]
      : const [];

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

  /// Re-pitch the focus element (single note; no-op on a rest). Undoable.
  void repitchSelected(Pitch pitch) {
    if (!hasSelection || _elements[_focus!].isRest) return;
    _snapshot();
    _elements[_focus!] = _elements[_focus!].withPitch(pitch);
  }

  void deleteSelected() {
    if (!hasSelection) return;
    _snapshot();
    final lo = _lo;
    _elements.removeRange(lo, _hi + 1);
    if (_elements.isEmpty) {
      clearSelection();
    } else {
      selectIndex(lo.clamp(0, _elements.length - 1));
    }
  }

  /// Move the selected block one slot left / right in the score.
  void moveSelectionLeft() {
    if (!hasSelection || _lo == 0) return;
    _snapshot();
    final e = _elements.removeAt(_lo - 1);
    _elements.insert(_hi, e);
    _anchor = _anchor! - 1;
    _focus = _focus! - 1;
  }

  void moveSelectionRight() {
    if (!hasSelection || _hi == _elements.length - 1) return;
    _snapshot();
    final e = _elements.removeAt(_hi + 1);
    _elements.insert(_lo, e);
    _anchor = _anchor! + 1;
    _focus = _focus! + 1;
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
  void paste() {
    if (_clipboard.isEmpty) return;
    _snapshot();
    final at = _caretIndex();
    final fresh = [for (final c in _clipboard) c.withId(_newId())];
    _elements.insertAll(at, fresh);
    _anchor = at;
    _focus = at + fresh.length - 1;
  }

  // ---- document settings -------------------------------------------------

  void clearAll() {
    if (_elements.isEmpty) return;
    _snapshot();
    _elements.clear();
    clearSelection();
  }

  /// Replace the whole document with the contents of [score] (undoable). Imports
  /// voice 1 only; a chord keeps its first pitch; ties/articulations are dropped
  /// (the editor is single-voice/single-note for now).
  void loadScore(Score score) {
    _snapshot();
    _elements.clear();
    clef = score.clef;
    keySignature = score.keySignature;
    timeSignature = score.timeSignature ?? TimeSignature.fourFour;
    for (final measure in score.measures) {
      for (final el in measure.elements) {
        final id = _newId();
        if (el is NoteElement) {
          _elements
              .add(EditorElement.note(el.pitches.first, el.duration, id: id));
        } else if (el is RestElement) {
          _elements.add(EditorElement.rest(el.duration, id: id));
        }
      }
    }
    clearSelection();
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

  // ---- rendering ---------------------------------------------------------

  /// Pack the flat element stream into bar-lined [Measure]s. A note that would
  /// overflow the current bar starts a new one (no splitting/tying yet). An
  /// empty document renders a single whole-rest bar so the staff stays wide.
  Score buildScore() {
    if (_elements.isEmpty) {
      return Score(
        clef: clef,
        keySignature: keySignature,
        timeSignature: timeSignature,
        measures: const [
          Measure([RestElement(NoteDuration(DurationBase.whole))]),
        ],
      );
    }

    final zero = Fraction(0, 1);
    final capacity = timeSignature.toFraction();
    final bars = <Measure>[];
    var current = <MusicElement>[];
    var filled = zero;

    for (final e in _elements) {
      final d = e.duration.toFraction();
      if (filled > zero && (filled + d) > capacity) {
        bars.add(Measure(current));
        current = [];
        filled = zero;
      }
      current.add(e.toElement());
      filled = filled + d;
    }
    if (current.isNotEmpty) bars.add(Measure(current));

    return Score(
      clef: clef,
      keySignature: keySignature,
      timeSignature: timeSignature,
      measures: bars,
      dynamics: [
        for (final e in _elements)
          if (!e.isRest && e.dynamic != null) DynamicMarking(e.id, e.dynamic!),
      ],
    );
  }

  int get barCount => buildScore().measures.length;
}
