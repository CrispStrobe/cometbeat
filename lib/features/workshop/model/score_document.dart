// lib/features/workshop/model/score_document.dart
//
// The editable document behind the Composition Workshop. partitura's Score is
// an immutable value tree with no in-place editing, so the editor keeps its own
// flat, mutable list of [EditorElement]s and rebuilds an immutable [Score] on
// demand (packing the flat list into bar-lined measures). All mutations go
// through commands that snapshot first, giving multi-level undo/redo.
//
// This is the foundation the Workshop grows on: later phases add ties, tuplets,
// a second voice, dynamics and more as new fields/commands here, without the
// screen having to know how a Score is assembled.

import 'package:klang_universum/shared/midi_pitch.dart';
import 'package:partitura/partitura.dart';

/// One editable event in the flat stream: a note (single pitch for now; chords
/// come later) or a rest, with a stable [id] so it can be selected and edited.
class EditorElement {
  const EditorElement.note(Pitch this.pitch, this.duration, {required this.id})
      : isRest = false;

  const EditorElement.rest(this.duration, {required this.id})
      : pitch = null,
        isRest = true;

  /// The pitch, or null for a rest.
  final Pitch? pitch;
  final NoteDuration duration;
  final String id;
  final bool isRest;

  /// This event as an immutable partitura element.
  MusicElement toElement() => isRest
      ? RestElement(duration, id: id)
      : NoteElement.note(pitch!, duration, id: id);

  EditorElement withPitch(Pitch pitch) =>
      EditorElement.note(pitch, duration, id: id);

  EditorElement withDuration(NoteDuration duration) => isRest
      ? EditorElement.rest(duration, id: id)
      : EditorElement.note(pitch!, duration, id: id);
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

/// The editable Workshop document: an ordered element stream plus the
/// document-level time/key signature, a selection, and undo/redo.
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

  String? _selectedId;
  var _nextId = 0;

  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];

  // ---- reads -------------------------------------------------------------

  List<EditorElement> get elements => List.unmodifiable(_elements);
  int get length => _elements.length;
  bool get isEmpty => _elements.isEmpty;
  String? get selectedId => _selectedId;

  EditorElement? get selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final e in _elements) {
      if (e.id == id) return e;
    }
    return null;
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  String _newId() => 'w${_nextId++}';

  // ---- history -----------------------------------------------------------

  void _snapshot() {
    _undo.add(_Snapshot(List.of(_elements), timeSignature, keySignature, clef));
    _redo.clear();
  }

  void _restore(_Snapshot s) {
    _elements
      ..clear()
      ..addAll(s.elements);
    timeSignature = s.timeSignature;
    keySignature = s.keySignature;
    clef = s.clef;
    if (!_elements.any((e) => e.id == _selectedId)) _selectedId = null;
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_Snapshot(List.of(_elements), timeSignature, keySignature, clef));
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_Snapshot(List.of(_elements), timeSignature, keySignature, clef));
    _restore(_redo.removeLast());
  }

  // ---- commands ----------------------------------------------------------

  /// The caret: new elements are inserted here — just after the selection, or
  /// at the end when nothing is selected.
  int _caretIndex() {
    final i = _indexOfSelected();
    return i < 0 ? _elements.length : i + 1;
  }

  /// Insert a note at the caret and select it. Returns the new element's id.
  String insertNote(Pitch pitch, NoteDuration duration) {
    _snapshot();
    final id = _newId();
    _elements.insert(
      _caretIndex(),
      EditorElement.note(pitch, duration, id: id),
    );
    _selectedId = id;
    return id;
  }

  /// Insert a rest at the caret and select it. Returns the new element's id.
  String insertRest(NoteDuration duration) {
    _snapshot();
    final id = _newId();
    _elements.insert(_caretIndex(), EditorElement.rest(duration, id: id));
    _selectedId = id;
    return id;
  }

  /// Re-pitch the selected element (no-op if nothing / a rest is selected).
  void repitchSelected(Pitch pitch) {
    final i = _indexOfSelected();
    if (i < 0 || _elements[i].isRest) return;
    _snapshot();
    _elements[i] = _elements[i].withPitch(pitch);
  }

  /// Nudge the selected note up/down by [semitones], respelling as needed.
  /// Clamped to a sensible instrument range.
  void transposeSelected(int semitones) {
    final i = _indexOfSelected();
    if (i < 0 || _elements[i].isRest) return;
    final midi = _elements[i].pitch!.midiNumber + semitones;
    if (midi < 21 || midi > 108) return; // A0..C8
    _snapshot();
    _elements[i] = _elements[i].withPitch(pitchFromMidi(midi));
  }

  /// Set the selected note's accidental ([alter]: -1 flat, 0 natural, 1 sharp),
  /// keeping its letter and octave.
  void setAccidentalOfSelected(int alter) {
    final i = _indexOfSelected();
    if (i < 0 || _elements[i].isRest) return;
    final p = _elements[i].pitch!;
    if (p.alter == alter) return;
    _snapshot();
    _elements[i] =
        _elements[i].withPitch(Pitch(p.step, alter: alter, octave: p.octave));
  }

  /// Change the selected element's duration (note or rest).
  void setDurationOfSelected(NoteDuration duration) {
    final i = _indexOfSelected();
    if (i < 0 || _elements[i].duration == duration) return;
    _snapshot();
    _elements[i] = _elements[i].withDuration(duration);
  }

  void deleteSelected() {
    final i = _indexOfSelected();
    if (i < 0) return;
    _snapshot();
    _elements.removeAt(i);
    // Select the element that slid into this slot (the former next), or the
    // new last one, so editing can continue fluently.
    _selectedId = _elements.isEmpty
        ? null
        : _elements[i.clamp(0, _elements.length - 1)].id;
  }

  /// Move the selection to the next / previous element (navigation only — not
  /// undoable). With nothing selected, selects the first / last.
  void selectNext() {
    if (_elements.isEmpty) return;
    final i = _indexOfSelected();
    final next = i < 0 ? 0 : (i + 1).clamp(0, _elements.length - 1);
    _selectedId = _elements[next].id;
  }

  void selectPrev() {
    if (_elements.isEmpty) return;
    final i = _indexOfSelected();
    final prev =
        i < 0 ? _elements.length - 1 : (i - 1).clamp(0, _elements.length - 1);
    _selectedId = _elements[prev].id;
  }

  void clearAll() {
    if (_elements.isEmpty) return;
    _snapshot();
    _elements.clear();
    _selectedId = null;
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

  /// Toggle selection of [id] (tapping the selected element clears it).
  void toggleSelected(String id) => _selectedId = _selectedId == id ? null : id;

  void clearSelection() => _selectedId = null;

  int _indexOfSelected() => _elements.indexWhere((e) => e.id == _selectedId);

  // ---- rendering ---------------------------------------------------------

  /// Pack the flat element stream into bar-lined [Measure]s. A note that would
  /// overflow the current bar starts a new one (no splitting/tying yet — that
  /// arrives with P2). Empty document → a single whole-rest bar so the staff
  /// stays wide and tappable.
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
    );
  }

  int get barCount => buildScore().measures.length;
}
