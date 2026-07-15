// lib/features/workshop/screens/composition_workshop_screen.dart
//
// "Kompositions-Werkstatt" / "Composition Workshop" — a touch- and desktop-first
// score editor (see docs/WORKSHOP_PLAN.md). Chrome is kept to two slim rows so
// the score gets the space:
//   • a slim action bar (undo/redo/play + a ⋮ menu of save/export/…),
//   • Row A — compact clef/time/key/zoom dropdowns + a status readout,
//   • the multi-line score canvas (wraps + scrolls),
//   • Row B — the value/accidental/rest strip + contextual selection actions
//     (move · pitch · copy/cut/paste · delete over a note or a range),
//   • the on-screen piano (places notes at the caret).
// Every edit runs through [ScoreDocument] (editable model + multi-level undo).

import 'dart:convert';

import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's pitch Step wins here.
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:klang_universum/core/note_naming.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/features/games/songs/user_songs_service.dart';
import 'package:klang_universum/features/workshop/model/multi_part_document.dart';
import 'package:klang_universum/features/workshop/model/score_document.dart';
import 'package:klang_universum/features/workshop/widgets/multi_part_canvas.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/midi_pitch.dart';
import 'package:klang_universum/shared/score_theme.dart';
import 'package:klang_universum/shared/widgets/music_glyph.dart';
import 'package:klang_universum/shared/widgets/piano_keyboard.dart';
import 'package:provider/provider.dart';

/// A choosable note value: glyph + base duration.
typedef _Value = ({String glyph, DurationBase base});

const _values = <_Value>[
  (glyph: Smufl.wholeNote, base: DurationBase.whole),
  (glyph: Smufl.halfNote, base: DurationBase.half),
  (glyph: Smufl.quarterNote, base: DurationBase.quarter),
  (glyph: Smufl.eighthNote, base: DurationBase.eighth),
  (glyph: Smufl.sixteenthNote, base: DurationBase.sixteenth),
];

/// The accidental the selected note is set to (or the next placed note gets).
enum _Accidental { natural, sharp, flat }

int _alterOf(_Accidental a) => switch (a) {
      _Accidental.natural => 0,
      _Accidental.sharp => 1,
      _Accidental.flat => -1,
    };

_Accidental _accidentalOf(int alter) => alter > 0
    ? _Accidental.sharp
    : alter < 0
        ? _Accidental.flat
        : _Accidental.natural;

const _accidentalGlyph = {
  _Accidental.natural: '♮',
  _Accidental.sharp: '♯',
  _Accidental.flat: '♭',
};

const _keyChoices = [-4, -3, -2, -1, 0, 1, 2, 3, 4];

// Anacrusis lengths offered in the top bar (null = the piece starts on beat 1).
const _pickupChoices = <NoteDuration?>[
  null,
  NoteDuration(DurationBase.eighth),
  NoteDuration(DurationBase.quarter),
  NoteDuration(DurationBase.quarter, dots: 1),
  NoteDuration(DurationBase.half),
];

String _keyLabel(int fifths) =>
    fifths == 0 ? '♮' : (fifths > 0 ? '$fifths♯' : '${-fifths}♭');

/// How the staff is shown: a single treble or bass staff, or both clefs at once
/// (a grand staff that auto-splits the line by pitch).
enum _StaffMode { treble, bass, grand }

const _staffModeGlyph = {
  _StaffMode.treble: '𝄞',
  _StaffMode.bass: '𝄢',
  _StaffMode.grand: '𝄞𝄢',
};

const _articulationOptions = <Articulation>[
  Articulation.staccato,
  Articulation.tenuto,
  Articulation.accent,
  Articulation.marcato,
  Articulation.fermata,
];

String _articulationLabel(AppLocalizations l, Articulation a) => switch (a) {
      Articulation.staccato => l.workshopStaccato,
      Articulation.tenuto => l.workshopTenuto,
      Articulation.accent => l.workshopAccent,
      Articulation.marcato => l.workshopMarcato,
      Articulation.fermata => l.workshopFermata,
      _ => a.name,
    };

const _dynamicOptions = <DynamicLevel>[
  DynamicLevel.pp,
  DynamicLevel.p,
  DynamicLevel.mp,
  DynamicLevel.mf,
  DynamicLevel.f,
  DynamicLevel.ff,
];

// The sweepable piano: C1..~A6, a fixed key width so it scrolls horizontally.
const _pianoWhiteKeys = 42;
const _pianoKeyWidth = 46.0;
const _pianoStartMidi = 24; // C1

// Computer-keyboard note entry (letters) and duration selection (digits).
final _letterSteps = <LogicalKeyboardKey, Step>{
  LogicalKeyboardKey.keyA: Step.a,
  LogicalKeyboardKey.keyB: Step.b,
  LogicalKeyboardKey.keyC: Step.c,
  LogicalKeyboardKey.keyD: Step.d,
  LogicalKeyboardKey.keyE: Step.e,
  LogicalKeyboardKey.keyF: Step.f,
  LogicalKeyboardKey.keyG: Step.g,
};
final _digitBases = <LogicalKeyboardKey, DurationBase>{
  LogicalKeyboardKey.digit1: DurationBase.whole,
  LogicalKeyboardKey.digit2: DurationBase.half,
  LogicalKeyboardKey.digit3: DurationBase.quarter,
  LogicalKeyboardKey.digit4: DurationBase.eighth,
  LogicalKeyboardKey.digit5: DurationBase.sixteenth,
};

// ---- File I/O (unified, multi-format) ------------------------------------

/// Every score file type the Workshop can open (one picker, auto-detected by
/// extension). All parsers are pure Dart (web-safe).
const _kImportExtensions = [
  'musicxml', 'xml', 'mxl', // MusicXML (+ compressed)
  'mid', 'midi', // MIDI
  'abc', // ABC
  'mei', // MEI
  'krn', // Humdrum **kern
  'mscx', 'mscz', // MuseScore (+ compressed)
  'gp', 'gpx', // Guitar Pro
];

const _kImportGroups = <XTypeGroup>[
  XTypeGroup(label: 'Music scores', extensions: _kImportExtensions),
];

/// Parses an opened file into a [Score] by its extension. Pure (given the raw
/// [bytes]) so it is unit-testable without a file picker. Throws a
/// [FormatException] on an unknown extension and rethrows any parser error.
@visibleForTesting
Score importScore(String fileName, Uint8List bytes) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  String text() => utf8.decode(bytes);
  return switch (ext) {
    'musicxml' || 'xml' => scoreFromMusicXml(text()),
    'mxl' => scoreFromMusicXml(readMusicXmlFromMxl(bytes)),
    'mid' || 'midi' => scoreFromMidi(bytes),
    'abc' => scoreFromAbc(text()),
    'mei' => scoreFromMei(text()),
    'krn' => scoreFromKern(text()),
    'mscx' => scoreFromMscx(text()),
    'mscz' => scoreFromMscx(readMscxFromMscz(bytes)),
    'gp' => scoreFromGpif(readGpifFromGp(bytes)),
    'gpx' => scoreFromGpif(readGpifFromGpx(bytes)),
    _ => throw FormatException('Unsupported file type: .$ext'),
  };
}

/// Parses an opened file into a [MultiPartScore] (all instrument parts) by its
/// extension — the multi-part sibling of [importScore]. Formats with a
/// multi-part reader (MusicXML/`.mxl`/ABC/MEI/`**kern`) keep every part; the
/// rest fall back to a single-part document wrapping [importScore]. Pure (given
/// the raw [bytes]) so it is unit-testable without a file picker.
@visibleForTesting
MultiPartScore importMultiPart(String fileName, Uint8List bytes) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  String text() => utf8.decode(bytes);
  return switch (ext) {
    'musicxml' || 'xml' => multiPartScoreFromMusicXml(text()),
    'mxl' => multiPartScoreFromMusicXml(readMusicXmlFromMxl(bytes)),
    'abc' => multiPartScoreFromAbc(text()),
    'mei' => multiPartScoreFromMei(text()),
    'krn' => multiPartScoreFromKern(text()),
    // MIDI / MuseScore / Guitar Pro have no multi-part reader here yet.
    _ => MultiPartScore([importScore(fileName, bytes)]),
  };
}

/// Parses pasted **bekern** ("basic extended kern") tokens — the flat text the
/// OMR model emits (`<s>`/`<t>`/`<b>` markers) — into a [MultiPartScore], one
/// part per spine. Pure (no picker), so it is unit-testable. Reuses
/// crisp_notation's pure-Dart `bekernToStaffSystem`; throws on malformed input.
@visibleForTesting
MultiPartScore importBekern(String text) =>
    MultiPartScore.fromStaffSystem(bekernToStaffSystem(text.trim()));

/// One export target: display [label], file [ext], and MIME type. [binary]
/// formats are raw bytes; the rest are UTF-8 text (and so can fall back to the
/// copyable dialog where the platform has no save picker).
typedef ExportFormat = ({String label, String ext, String mime, bool binary});

/// Everything the Workshop can write out (one "Export…" menu → this list).
const kExportFormats = <ExportFormat>[
  (label: 'MusicXML', ext: 'musicxml', mime: 'application/xml', binary: false),
  (
    label: 'MusicXML (compressed)',
    ext: 'mxl',
    mime: 'application/vnd.recordare.musicxml',
    binary: true,
  ),
  (label: 'MIDI', ext: 'mid', mime: 'audio/midi', binary: true),
  (label: 'ABC', ext: 'abc', mime: 'text/plain', binary: false),
  (label: 'MEI', ext: 'mei', mime: 'application/xml', binary: false),
  (label: 'Humdrum **kern', ext: 'krn', mime: 'text/plain', binary: false),
  (label: 'MuseScore', ext: 'mscx', mime: 'application/xml', binary: false),
  (label: 'LilyPond', ext: 'ly', mime: 'text/plain', binary: false),
  (label: 'Braille music', ext: 'brf', mime: 'text/plain', binary: false),
  (label: 'SVG (vector)', ext: 'svg', mime: 'image/svg+xml', binary: false),
  (label: 'PNG (image)', ext: 'png', mime: 'image/png', binary: true),
];

class CompositionWorkshopScreen extends StatefulWidget {
  const CompositionWorkshopScreen({super.key});

  static const maxNotes = 256;

  @override
  State<CompositionWorkshopScreen> createState() =>
      _CompositionWorkshopScreenState();
}

/// Reading-order drop slot for a horizontal reorder drag: among [regions]
/// (excluding [draggedId]), the count sitting before pointer x [dropX] in
/// measure [targetMeasure] is the insertion [index]; [beforeId] is the id the
/// drop caret should sit before (null past the last element). Ordering is by
/// measure then notehead x, so it holds across bars and wrapped lines. Pure (no
/// render state) so it's unit-testable; [_dropSlotFor] feeds it the live C7
/// element regions, and both the drop-caret preview and the drop itself use it.
@visibleForTesting
({int index, String? beforeId}) computeDropSlot(
  Iterable<({String id, Rect bounds, int measureIndex})> regions,
  String draggedId,
  double dropX,
  int targetMeasure,
) {
  final ordered = regions.where((r) => r.id != draggedId).toList()
    ..sort(
      (a, b) => a.measureIndex != b.measureIndex
          ? a.measureIndex.compareTo(b.measureIndex)
          : a.bounds.center.dx.compareTo(b.bounds.center.dx),
    );
  final index = ordered
      .where(
        (r) =>
            r.measureIndex < targetMeasure ||
            (r.measureIndex == targetMeasure && r.bounds.center.dx < dropX),
      )
      .length;
  return (
    index: index,
    beforeId: index < ordered.length ? ordered[index].id : null,
  );
}

/// Typed window into the editor for widget tests.
@visibleForTesting
abstract interface class CompositionWorkshopTester {
  int get noteCount;
  int get barCount;
  bool get hasSelection;
  int get selectedCount;
  int get slurCount;
  int get hairpinCount;

  /// G6: number of instrument parts, and which one the toolbar edits.
  int get partCount;
  int get activePartIndex;
}

class _CompositionWorkshopScreenState extends State<CompositionWorkshopScreen>
    implements CompositionWorkshopTester {
  // G6: the whole piece is a MultiPartDocument (≥1 instrument part). The toolbar
  // and every editing command target the *active* part through the [_doc]
  // getter, so the single-part editing pipeline is reused unchanged; only the
  // canvas/parts-strip below know there can be more than one part.
  final MultiPartDocument _mpd = MultiPartDocument();

  /// The part the toolbar edits — every existing command reads/writes this.
  ScoreDocument get _doc => _mpd.activePart;

  DurationBase _pendingBase = DurationBase.quarter;
  bool _dotted = false;
  _Accidental _accidental = _Accidental.natural;
  double _zoom = 13;
  _StaffMode _mode = _StaffMode.treble;
  bool _chordMode = false; // placed pitches stack onto the selected note
  bool _barNumbers = false; // label each wrapped system with its bar number
  bool _noteNames = false; // draw each note's name below the staff
  StaffTarget? _hover; // where a click/tap would land (desktop hover preview)
  String? _dragId; // the note being dragged (the view re-paints it live, C10b)
  String? _dropCaretId; // live drop slot during a horizontal reorder drag
  // Opacity of the view-painted drag preview: the real glyph, slightly lifted.
  static const double _kDragPreviewOpacity = 0.85;
  int _verse = 1; // which lyric verse the inline field edits
  bool _marquee = false; // rubber-band select mode (drag selects, not places)

  // C7: the view feeds its element hit-regions here so a marquee rect → ids.
  final ElementRegionController _regions = ElementRegionController();

  // The canvas-local pointer position (from a passive Listener), and where a
  // drag began — used to reorder a note by the horizontal drop position.
  Offset? _pointerLocal;
  Offset? _dragStartLocal;

  // Start the sweepable piano scrolled to around C3 (24 = C1, 7 white/octave).
  final _pianoScroll =
      ScrollController(initialScrollOffset: 14 * _pianoKeyWidth);

  // The 42-key keyboard never changes (constant config + a stable `onKeyTap`
  // tear-off), so build it once and reuse the instance — Flutter then skips
  // rebuilding all 42 keys on every editor setState (edits / selection / hover).
  late final Widget _pianoKeyboard = SizedBox(
    width: _pianoWhiteKeys * _pianoKeyWidth,
    child: PianoKeyboard(
      startMidi: _pianoStartMidi,
      whiteKeyCount: _pianoWhiteKeys,
      showLabels: true,
      showOctaveNumbers: true,
      onKeyTap: _onPianoKey,
    ),
  );

  @override
  void dispose() {
    _pianoScroll.dispose();
    _mpd.dispose();
    super.dispose();
  }

  bool get _grand => _mode == _StaffMode.grand;

  /// The engraving note-name spelling for the note-names overlay, mapped from
  /// the app's note-naming setting (auto follows the locale — German = H).
  NoteNameStyle get _noteNameStyle {
    switch (context.read<SettingsService>().noteNaming) {
      case NoteNaming.english:
        return NoteNameStyle.letter;
      case NoteNaming.germanH:
        return NoteNameStyle.german;
      case NoteNaming.solfege:
        return NoteNameStyle.solfege;
      case NoteNaming.auto:
        return Localizations.localeOf(context).languageCode == 'de'
            ? NoteNameStyle.german
            : NoteNameStyle.letter;
    }
  }

  /// The clef to interpret a staff position under: in grand mode it depends on
  /// which staff was hit (0 = treble, 1 = bass); otherwise the document clef.
  Clef _clefForTarget(StaffTarget t) =>
      _grand ? (t.staffIndex == 0 ? Clef.treble : Clef.bass) : _doc.clef;

  void _setMode(_StaffMode m) => setState(() {
        _mode = m;
        if (m == _StaffMode.treble) _doc.setClef(Clef.treble);
        if (m == _StaffMode.bass) _doc.setClef(Clef.bass);
      });

  @override
  int get noteCount => _doc.length;

  @override
  int get barCount => _doc.barCount;

  @override
  bool get hasSelection => _doc.hasSelection;

  @override
  int get selectedCount => _doc.selectedIds.length;

  @override
  int get slurCount => _doc.slurs.length;

  @override
  int get hairpinCount => _doc.hairpins.length;

  @override
  int get partCount => _mpd.partCount;

  @override
  int get activePartIndex => _mpd.active;

  NoteDuration get _pendingDuration =>
      NoteDuration(_pendingBase, dots: _dotted ? 1 : 0);

  /// The ghost notehead's duration: the dragged note's own value while a drag is
  /// live, else the pending value (for the hover/placement preview).
  NoteDuration get _ghostDuration {
    final id = _dragId;
    if (id != null) {
      for (final e in _doc.elements) {
        if (e.id == id) return e.duration;
      }
    }
    return _pendingDuration;
  }

  AudioService get _audio => context.read<AudioService>();

  bool get _selectionHasNote => _doc.selectedElements.any((e) => !e.isRest);

  void _syncControlsToSelection() {
    final e = _doc.selected;
    if (e == null) return;
    _pendingBase = e.duration.base;
    _dotted = e.duration.dots > 0;
    _accidental =
        e.isRest ? _Accidental.natural : _accidentalOf(e.pitch!.alter);
  }

  // ---- entry -------------------------------------------------------------

  /// Place a pitch: in chord mode it stacks onto the selected note; otherwise it
  /// inserts a new note at the caret. Shared by the piano, staff-tap and keys.
  void _placePitch(Pitch pitch) {
    _audio.playMidiNote(pitch.midiNumber, ms: 400);
    final selected = _doc.selected;
    if (_chordMode && selected != null && !selected.isRest) {
      setState(() => _doc.addPitchToSelected(pitch));
    } else if (_doc.length < CompositionWorkshopScreen.maxNotes) {
      setState(() => _doc.insertNote(pitch, _pendingDuration));
    }
  }

  void _onPianoKey(int midi) => _placePitch(pitchFromMidi(midi));

  /// Click blank staff: place a new note at that pitch (advancing the caret),
  /// exactly like a piano key. In chord mode it stacks the clicked pitch onto
  /// the selected note instead. Re-pitching an existing note is done by dragging
  /// it (or selecting it and using ↑/↓) — not by a blank-staff click.
  void _onStaffTap(StaffTarget target) {
    final pitch = target.pitchFor(
      _clefForTarget(target),
      preferredAlter: _alterOf(_accidental),
    );
    _placePitch(pitch);
  }

  void _onElementTap(String id) => setState(() {
        _doc.toggleSelected(id);
        _syncControlsToSelection();
      });

  /// Full-score canvas tap (multi-part mode): select the element across parts
  /// and switch the toolbar to its owning part.
  void _onGlobalElementTap(String globalId) => setState(() {
        _mpd.selectByGlobalId(globalId);
        _syncControlsToSelection();
      });

  // ---- G6: in-place editing on the full-score canvas (C12) ----------------

  /// The part the hover ghost is over (null = off-staff), paired with [_hover].
  int? _hoverPart;

  /// Tap on empty staff in part [partIndex]: make it active and place a note at
  /// the tapped staff position (in chord mode, stack onto the selection).
  void _onMpStaffTap(int partIndex, StaffTarget target) {
    setState(() {
      _mpd.setActive(partIndex);
      _syncControlsToSelection();
    });
    final pitch = target.pitchFor(
      _mpd.clefOf(partIndex),
      preferredAlter: _alterOf(_accidental),
    );
    _placePitch(pitch); // targets _doc == the now-active part
  }

  /// Hover over part [partIndex] (−1/null off-staff): drive the placement ghost.
  /// Guarded on the quantized target so a mouse sweep doesn't rebuild per pixel.
  void _onMpHover(int partIndex, StaffTarget? target) {
    final part = partIndex < 0 ? null : partIndex;
    if (part == _hoverPart && target == _hover) return;
    setState(() {
      _hoverPart = part;
      _hover = target;
    });
  }

  void _onMpDragStart(String globalId) => setState(() => _dragId = globalId);

  /// While dragging, the source note is suppressed (see [_mpSuppressed]) and the
  /// placement ghost follows the pointer — a live drag preview built from the
  /// existing suppress + ghost APIs (no dedicated `dragPreviewOpacity` needed).
  void _onMpDragUpdate(String globalId, int partIndex, StaffTarget target) =>
      setState(() {
        _hoverPart = partIndex;
        _hover = target;
      });

  /// Drop a dragged element: switch to its part and re-pitch it to the drop
  /// staff position (vertical move).
  void _onMpDragEnd(String globalId, int partIndex, StaffTarget target) {
    setState(() {
      _mpd.setActive(partIndex);
      _mpd.parts[partIndex].moveById(
        MultiPartDocument.rawIdOf(globalId),
        target,
        clef: _mpd.clefOf(partIndex),
      );
      _dragId = null;
      _hover = null;
      _hoverPart = null;
      _syncControlsToSelection();
    });
  }

  /// The dragged note, hidden from the full-score layout so the ghost can stand
  /// in for it (live drag preview). Empty when no drag is in flight.
  Set<String> get _mpSuppressed => _dragId == null ? const {} : {_dragId!};

  /// The insertion caret for the full-score canvas: the active part's caret
  /// element, namespaced to match the ids [MultiPartDocument.buildMultiPart]
  /// emits.
  EditorCaret? get _mpCaret {
    if (_dragId != null) return null; // the moving ghost already shows intent
    final id = _doc.caretBeforeId;
    return id == null
        ? null
        : EditorCaret(
            beforeElementId: '${MultiPartDocument.prefixFor(_mpd.active)}$id',
          );
  }

  /// Marquee over the full score: select within the part that has the most
  /// enclosed notes (making it active), since selection is per part.
  void _applyMpMarquee(Rect rect) => setState(() {
        final ids = _regions.elementIdsIn(rect);
        final byPart = <int, List<String>>{};
        for (final id in ids) {
          final p = MultiPartDocument.partIndexOf(id);
          if (p >= 0) (byPart[p] ??= []).add(MultiPartDocument.rawIdOf(id));
        }
        if (byPart.isEmpty) {
          _doc.clearSelection();
          return;
        }
        final best = byPart.entries
            .reduce((a, b) => b.value.length > a.value.length ? b : a);
        _mpd.setActive(best.key);
        _doc.selectByIds(best.value); // _doc == the now-active part
        _syncControlsToSelection();
      });

  // ---- G6: instrument parts ----------------------------------------------

  void _addInstrument() => setState(_mpd.addPart);

  void _selectPart(int i) => setState(() {
        _mpd.setActive(i);
        _syncControlsToSelection();
      });

  void _removeInstrument(int i) => setState(() => _mpd.removePart(i));

  void _setPartClef(int i, Clef clef) =>
      setState(() => _mpd.setClefOfPart(i, clef));

  void _setPartTransposition(int i, Transposition? t) =>
      setState(() => _mpd.setTransposition(i, t));

  /// Toggle a piano-style brace over this part and the one below it (used to
  /// group e.g. a piano's two staves). No-op on the last part.
  void _toggleBraceBelow(int i) => setState(() {
        if (i + 1 >= _mpd.partCount) return;
        final has = _mpd.brackets.any(
          (b) => b.first == i && b.last == i + 1,
        );
        if (has) {
          _mpd.removeBracket(i, i + 1);
        } else {
          _mpd.addBracket(i, i + 1, kind: StaffBracketKind.brace);
        }
      });

  static String _clefGlyph(Clef clef) => switch (clef) {
        Clef.bass => '𝄢',
        Clef.alto || Clef.tenor => '𝄡',
        _ => '𝄞',
      };

  // The transposing-instrument presets offered per part (label + tag).
  static const _transpositionOptions = <(String, Transposition?)>[
    ('C', null),
    ('B♭', Transposition.bFlat),
    ('E♭', Transposition.eFlat),
    ('F', Transposition.f),
    ('A', Transposition.a),
  ];

  /// The instrument-parts strip: a chip per part (tap selects; ⋮ opens clef /
  /// transposition / brace / remove) plus an "add instrument" button.
  Widget _partsStrip(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('workshop-add-instrument'),
              icon: const Icon(Icons.add),
              tooltip: l10n.workshopAddInstrument,
              onPressed: _addInstrument,
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                itemCount: _mpd.partCount,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => _partChip(l10n, i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _partChip(AppLocalizations l10n, int i) {
    final scheme = Theme.of(context).colorScheme;
    final active = i == _mpd.active;
    return Container(
      decoration: BoxDecoration(
        color:
            active ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: active
            ? Border.all(color: scheme.primary, width: 1.5)
            : Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: ValueKey('workshop-part-$i'),
            onTap: () => _selectPart(i),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Glyph + name in one Text so it never collides with the
                  // staff-mode clef dropdown's lone-glyph finders.
                  Text('${_clefGlyph(_mpd.clefOf(i))}  ${_mpd.nameOf(i)}'),
                  if (_mpd.transpositionOf(i) != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        _transpositionLabel(_mpd.transpositionOf(i)),
                        style: TextStyle(color: scheme.primary, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _partMenu(l10n, i),
        ],
      ),
    );
  }

  String _transpositionLabel(Transposition? t) {
    for (final (label, value) in _transpositionOptions) {
      if (value == t) return label;
    }
    return '';
  }

  Widget _partMenu(AppLocalizations l10n, int i) =>
      PopupMenuButton<void Function()>(
        icon: const Icon(Icons.tune, size: 18),
        tooltip: _mpd.nameOf(i),
        onSelected: (action) => action(),
        itemBuilder: (context) => [
          PopupMenuItem(
            enabled: false,
            child: Text(
              l10n.workshopPartClef,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          for (final clef in const [Clef.treble, Clef.bass])
            CheckedPopupMenuItem<void Function()>(
              value: () => _setPartClef(i, clef),
              checked: _mpd.clefOf(i) == clef,
              child: Text('${_clefGlyph(clef)}  ${clef.name}'),
            ),
          const PopupMenuDivider(),
          PopupMenuItem(
            enabled: false,
            child: Text(
              l10n.workshopPartTransposition,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          for (final (label, value) in _transpositionOptions)
            CheckedPopupMenuItem<void Function()>(
              value: () => _setPartTransposition(i, value),
              checked: _mpd.transpositionOf(i) == value,
              child: Text(value == null ? l10n.workshopConcertPitch : label),
            ),
          const PopupMenuDivider(),
          if (i + 1 < _mpd.partCount)
            CheckedPopupMenuItem<void Function()>(
              value: () => _toggleBraceBelow(i),
              checked:
                  _mpd.brackets.any((b) => b.first == i && b.last == i + 1),
              child: Text(l10n.workshopBraceBelow),
            ),
          if (_mpd.partCount > 1)
            PopupMenuItem<void Function()>(
              value: () => _removeInstrument(i),
              child: Row(
                children: [
                  const Icon(Icons.delete_outline, size: 18),
                  const SizedBox(width: 8),
                  Text(l10n.workshopRemoveInstrument),
                ],
              ),
            ),
        ],
      );

  /// Marquee result: select every note the rubber-band rect enclosed (C7).
  void _applyMarquee(Rect rect) => setState(() {
        _doc.selectByIds(_regions.elementIdsIn(rect));
        _syncControlsToSelection();
      });

  /// Desktop hover preview. Fires on every pointer move, but the ghost snaps to
  /// the nearest line/space, so only rebuild when the *quantized* target
  /// actually changes — otherwise a mouse sweep would rebuild the whole editor
  /// on every pixel. `StaffTarget` compares by value, so this is exact.
  void _onHover(StaffTarget? target) {
    if (target != _hover) setState(() => _hover = target);
  }

  /// Drag a note on the staff. A **horizontal** drag reorders it to the drop
  /// position (fine, using the C7 element regions to read order across bars and
  /// lines); a **vertical** drag re-pitches it. While the drag is live the
  /// view suppresses the original and re-paints the real glyph following the
  /// pointer (crisp_notation C10b `dragPreviewOpacity`), so the app clears its own
  /// hover ghost and keeps no stand-in of its own.
  void _onElementDragStart(String id) => setState(() {
        _dragId = id;
        _dragStartLocal = _pointerLocal;
        _hover = null; // the view paints the moving note; no app ghost
        _dropCaretId = null;
      });

  /// As a horizontal reorder drag moves, mark the live drop slot with the
  /// insertion caret (a vertical re-pitch shows none — the moving glyph already
  /// shows the new pitch). Repaint only; the model isn't touched until drop.
  void _onElementDragUpdate(String id, StaffTarget target) {
    final drop = _pointerLocal;
    final start = _dragStartLocal;
    if (drop == null || start == null) return;
    final dx = drop.dx - start.dx;
    final dy = drop.dy - start.dy;
    final horizontal = dx.abs() > 20 && dx.abs() > dy.abs();
    final beforeId = (!_grand && horizontal)
        ? _dropSlotFor(id, drop, target).beforeId
        : null;
    if (beforeId != _dropCaretId) setState(() => _dropCaretId = beforeId);
  }

  void _onElementDragEnd(String id, StaffTarget target) {
    final drop = _pointerLocal;
    final start = _dragStartLocal;
    final dx = (drop != null && start != null) ? drop.dx - start.dx : 0.0;
    final dy = (drop != null && start != null) ? drop.dy - start.dy : 0.0;
    final horizontal = drop != null && dx.abs() > 20 && dx.abs() > dy.abs();

    if (!_grand && horizontal) {
      setState(() {
        _doc.moveByIdToIndex(id, _dropSlotFor(id, drop, target).index);
        _hover = null;
        _dragId = null;
        _dragStartLocal = null;
        _dropCaretId = null;
      });
      return;
    }

    Pitch? moved;
    setState(() {
      moved = _doc.moveById(id, target, clef: _clefForTarget(target));
      _hover = null;
      _dragId = null;
      _dragStartLocal = null;
      _dropCaretId = null;
    });
    if (moved != null) _audio.playMidiNote(moved!.midiNumber, ms: 300);
  }

  /// The reading-order drop slot for dragging [id] to pointer [drop] / [target],
  /// over the live element regions. Delegates to the pure [computeDropSlot].
  ({int index, String? beforeId}) _dropSlotFor(
    String id,
    Offset drop,
    StaffTarget target,
  ) =>
      computeDropSlot(
        _regions.elementRegions,
        id,
        drop.dx,
        target.measureIndex,
      );

  // ---- value / accidental controls ---------------------------------------

  void _pickValue(DurationBase base) => setState(() {
        _pendingBase = base;
        if (_doc.hasSelection) {
          _doc.setDurationOfSelected(NoteDuration(base, dots: _dotted ? 1 : 0));
        }
      });

  void _toggleDot() => setState(() {
        _dotted = !_dotted;
        if (_doc.hasSelection) {
          _doc.setDurationOfSelected(
            NoteDuration(_pendingBase, dots: _dotted ? 1 : 0),
          );
        }
      });

  void _pickAccidental(_Accidental a) => setState(() {
        _accidental = a;
        if (_doc.hasSelection) _doc.setAccidentalOfSelected(_alterOf(a));
      });

  void _addRest() {
    if (_doc.length >= CompositionWorkshopScreen.maxNotes) return;
    setState(() => _doc.insertRest(_pendingDuration));
  }

  /// Computer-keyboard entry: A–G place notes, 1–5 pick a value, arrows move the
  /// caret / pitch, R a rest, `.` a dot, Del/⌫ deletes, Ctrl/⌘ Z·Y·C·X·V for
  /// undo/redo/copy/cut/paste.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final kb = HardwareKeyboard.instance;

    if (kb.isControlPressed || kb.isMetaPressed) {
      if (key == LogicalKeyboardKey.keyZ) {
        setState(kb.isShiftPressed ? _doc.redo : _doc.undo);
      } else if (key == LogicalKeyboardKey.keyY) {
        setState(_doc.redo);
      } else if (key == LogicalKeyboardKey.keyC) {
        _run(_doc.copySelection);
      } else if (key == LogicalKeyboardKey.keyX) {
        _run(_doc.cutSelection);
      } else if (key == LogicalKeyboardKey.keyV) {
        _run(_doc.paste);
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    final step = _letterSteps[key];
    if (step != null) {
      final octave = _doc.selected?.pitch?.octave ?? 4;
      _placePitch(Pitch(step, alter: _alterOf(_accidental), octave: octave));
      return KeyEventResult.handled;
    }
    final base = _digitBases[key];
    if (base != null) {
      _pickValue(base);
      return KeyEventResult.handled;
    }
    switch (key) {
      case LogicalKeyboardKey.arrowLeft:
        _run(_doc.selectPrev);
      case LogicalKeyboardKey.arrowRight:
        _run(_doc.selectNext);
      case LogicalKeyboardKey.arrowUp:
        _transpose(1);
      case LogicalKeyboardKey.arrowDown:
        _transpose(-1);
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        _run(_doc.deleteSelected);
      case LogicalKeyboardKey.keyR:
        _addRest();
      case LogicalKeyboardKey.keyS:
        _run(_doc.slurSelected);
      case LogicalKeyboardKey.period:
        _toggleDot();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---- selection / range actions -----------------------------------------

  void _run(void Function() action) => setState(() {
        action();
        _syncControlsToSelection();
      });

  void _transpose(int semitones) {
    final before = _doc.selected?.pitch?.midiNumber;
    _run(() => _doc.transposeSelected(semitones));
    final now = _doc.selected?.pitch?.midiNumber;
    if (now != null && now != before) _audio.playMidiNote(now, ms: 300);
  }

  // ---- transport / menu --------------------------------------------------

  void _zoomBy(double d) =>
      setState(() => _zoom = (_zoom + d).clamp(8.0, 28.0));

  void _play() {
    if (_doc.isEmpty) return;
    _audio.playSequence([
      for (final e in _doc.elements)
        if (!e.isRest)
          (
            e.pitch!.midiNumber,
            (e.duration.toFraction().toDouble() * 4 * 480).round(),
          ),
    ]);
  }

  Future<void> _exportText(String title, String text) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).closeButtonLabel),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.of(ctx).pop();
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.workshopCopied)),
              );
            },
            icon: const Icon(Icons.copy),
            label: Text(l10n.workshopCopy),
          ),
        ],
      ),
    );
  }

  /// Open any supported score file — one picker for every format; the type is
  /// detected from the extension by [importScore].
  Future<void> _open() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await openFile(acceptedTypeGroups: _kImportGroups);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final score = importMultiPart(file.name, bytes);
      if (!mounted) return;
      setState(() {
        // A true multi-part file replaces the whole document; a single-part
        // file loads into the active part (keeping any other instruments).
        if (score.parts.length > 1) {
          _mpd.loadMultiPart(score);
        } else {
          _doc.loadScore(score.parts.first);
        }
      });
      messenger.showSnackBar(SnackBar(content: Text(l10n.importDone)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.importFailed(e.toString()))),
      );
    }
  }

  /// Paste **bekern** tokens (the OMR model's text output) and load them as a
  /// playable score — a no-file, web-safe "text → notation" path. Multi-spine
  /// bekern seeds one instrument part per spine (reusing the G6 multi-part
  /// document); a single spine loads into the active part.
  Future<void> _pasteTokens() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    var value = '';
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.workshopPasteTokens),
        content: TextField(
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          onChanged: (v) => value = v,
          decoration: InputDecoration(
            hintText: l10n.workshopPasteTokensHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(value),
            child: Text(l10n.workshopPasteTokensLoad),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    try {
      final score = importBekern(text);
      setState(() {
        if (score.parts.length > 1) {
          _mpd.loadMultiPart(score);
        } else {
          _doc.loadScore(score.parts.first);
        }
      });
      messenger.showSnackBar(SnackBar(content: Text(l10n.importDone)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.importFailed(e.toString()))),
      );
    }
  }

  /// The note-property dropdown (articulations · tie · dynamics), anchored at
  /// its own button. Returns null unless a single editable note is selected.
  Widget? _paletteButton(AppLocalizations l10n) {
    final note = _doc.selected;
    if (note == null || note.isRest) return null;
    return PopupMenuButton<(String, Object?)>(
      icon: const Icon(Icons.expand_less),
      tooltip: l10n.workshopArticulations,
      onSelected: (a) => setState(() {
        switch (a.$1) {
          case 'art':
            _doc.toggleArticulationOfSelected(a.$2! as Articulation);
          case 'tie':
            _doc.toggleTieOfSelected();
          case 'dyn':
            _doc.setDynamicOfSelected(a.$2 as DynamicLevel?);
        }
      }),
      itemBuilder: (ctx) {
        final n = _doc.selected;
        return [
          for (final art in _articulationOptions)
            CheckedPopupMenuItem<(String, Object?)>(
              value: ('art', art),
              checked: n?.articulations.contains(art) ?? false,
              child: Text(_articulationLabel(l10n, art)),
            ),
          CheckedPopupMenuItem<(String, Object?)>(
            value: const ('tie', null),
            checked: n?.tieToNext ?? false,
            child: Text(l10n.workshopTie),
          ),
          const PopupMenuDivider(),
          CheckedPopupMenuItem<(String, Object?)>(
            value: const ('dyn', null),
            checked: n?.dynamic == null,
            child:
                Text('${l10n.workshopDynamics}: ${l10n.workshopDynamicNone}'),
          ),
          for (final d in _dynamicOptions)
            CheckedPopupMenuItem<(String, Object?)>(
              value: ('dyn', d),
              checked: n?.dynamic == d,
              child: Text('${l10n.workshopDynamics}: ${d.name}'),
            ),
        ];
      },
    );
  }

  /// The unified export flow: pick a format, generate it, and save it via the
  /// system dialog. Where the platform has no save picker (web / mobile), text
  /// formats fall back to the copyable dialog. Replaces the per-format menu.
  Future<void> _showExportSheet() async {
    final l10n = AppLocalizations.of(context)!;
    final fmt = await showDialog<ExportFormat>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.workshopExportChoose),
        children: [
          for (final f in kExportFormats)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(f),
              child: Text('${f.label}  ·  .${f.ext}'),
            ),
        ],
      ),
    );
    if (fmt != null) await _export(fmt);
  }

  /// Renders [fmt] from the current score — bytes for binary formats, UTF-8 text
  /// otherwise. SVG/PNG are grand-staff aware; the rest export the single-staff
  /// score (as MusicXML / save-to-Song-Book always have).
  /// The score as MusicXML: **all** instrument parts when there is more than one
  /// (crisp_notation C11 `multiPartToMusicXml`), else the single active part.
  String _musicXmlExport() => _mpd.partCount > 1
      ? multiPartToMusicXml(_mpd.buildMultiPart(), partNames: _mpd.names)
      : scoreToMusicXml(_doc.buildScore());

  Future<(Uint8List?, String?)> _generateExport(ExportFormat fmt) async {
    final score = _doc.buildScore();
    switch (fmt.ext) {
      case 'musicxml':
        return (null, _musicXmlExport());
      case 'mxl':
        return (writeMusicXmlToMxl(_musicXmlExport()), null);
      case 'mid':
        return (scoreToMidi(score), null);
      case 'abc':
        return (null, scoreToAbc(score));
      case 'mei':
        return (null, scoreToMei(score));
      case 'krn':
        return (null, scoreToKern(score));
      case 'mscx':
        return (null, scoreToMscx(score));
      case 'ly':
        return (null, scoreToLilyPond(score));
      case 'brf':
        return (null, scoreToBraille(score));
      case 'svg':
        return (
          null,
          _grand
              ? await exportGrandStaffToSvg(
                  _doc.buildGrandStaff(),
                  theme: kidsScoreTheme,
                  staffSpace: _zoom,
                )
              : await exportScoreToSvg(
                  score,
                  theme: kidsScoreTheme,
                  staffSpace: _zoom,
                ),
        );
      case 'png':
        return (
          _grand
              ? await exportGrandStaffToPng(
                  _doc.buildGrandStaff(),
                  theme: kidsScoreTheme,
                  staffSpace: _zoom,
                )
              : await exportScoreToPng(
                  score,
                  theme: kidsScoreTheme,
                  staffSpace: _zoom,
                ),
          null,
        );
      default:
        return (null, null);
    }
  }

  Future<void> _export(ExportFormat fmt) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final (bytes, text) = await _generateExport(fmt);
      if (!mounted) return;
      final data = bytes ?? Uint8List.fromList(utf8.encode(text!));
      try {
        final location = await getSaveLocation(
          suggestedName: 'score.${fmt.ext}',
          acceptedTypeGroups: [
            XTypeGroup(label: fmt.label, extensions: [fmt.ext]),
          ],
        );
        if (location == null) return; // cancelled
        await XFile.fromData(data, mimeType: fmt.mime, name: 'score.${fmt.ext}')
            .saveTo(location.path);
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.workshopSavedTo(location.path))),
        );
      } catch (_) {
        // No save dialog on this platform (web / mobile): a text format can
        // still be copied out; a binary one needs a desktop save.
        if (text != null && mounted) {
          await _exportText(fmt.label, text);
        } else {
          rethrow;
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.importFailed(e.toString()))),
        );
      }
    }
  }

  /// A slur toggle — shown only when ≥2 notes are selected. Active (filled) when
  /// the range's endpoints already carry a slur.
  Widget? _slurButton(AppLocalizations l10n) {
    if (!_doc.canSlur) return null;
    final active = _doc.isSlurred;
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      iconSize: 22,
      visualDensity: VisualDensity.compact,
      isSelected: active,
      tooltip: l10n.workshopSlur,
      onPressed: () => _run(_doc.slurSelected),
      icon: Text(
        '⌒',
        style: TextStyle(
          fontSize: 24,
          height: 1.0,
          fontWeight: FontWeight.bold,
          color: active ? scheme.primary : null,
        ),
      ),
    );
  }

  /// Crescendo / diminuendo toggles — shown when ≥2 notes are selected. Each is
  /// highlighted when that wedge already spans the range.
  Widget? _hairpinButtons(AppLocalizations l10n) {
    if (!_doc.canHairpin) return null;
    final active = _doc.hairpinType;
    final scheme = Theme.of(context).colorScheme;
    Widget button(HairpinType type, String glyph, String tooltip) => IconButton(
          iconSize: 22,
          visualDensity: VisualDensity.compact,
          isSelected: active == type,
          tooltip: tooltip,
          onPressed: () => _run(() => _doc.hairpinSelected(type)),
          icon: Text(
            glyph,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: active == type ? scheme.primary : null,
            ),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(HairpinType.crescendo, '<', l10n.workshopCrescendo),
        button(HairpinType.diminuendo, '>', l10n.workshopDiminuendo),
      ],
    );
  }

  /// An inline lyric field — shown when a single note is selected. A small verse
  /// selector precedes it. The field is keyed by (note id, verse) so it resets
  /// to that note+verse's syllable as either changes.
  Widget? _lyricField(AppLocalizations l10n) {
    final e = _doc.selected;
    if (e == null || e.isRest || _doc.selectedIds.length != 1) return null;
    // Offer every existing verse plus the next empty one (cap at a sane max).
    final verses = [
      for (var v = 1; v <= (_doc.maxVerse + 1).clamp(1, 8); v++) v,
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: l10n.workshopLyricVerse,
          child: DropdownButton<int>(
            value: _verse.clamp(1, verses.last),
            isDense: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final v in verses)
                DropdownMenuItem(value: v, child: Text('$v')),
            ],
            onChanged: (v) => setState(() => _verse = v ?? 1),
          ),
        ),
        const SizedBox(width: 4),
        _LyricField(
          key: ValueKey('lyric-${e.id}-v$_verse'),
          initial: _doc.lyricOf(e.id, verse: _verse) ?? '',
          hint: l10n.workshopLyricHint,
          onCommit: (t) =>
              setState(() => _doc.setLyricFor(e.id, t, verse: _verse)),
        ),
      ],
    );
  }

  /// A read-only cheat-sheet of the computer-keyboard shortcuts.
  Future<void> _showShortcuts(AppLocalizations l10n) async {
    final rows = <(String, String)>[
      ('A – G', l10n.workshopShortcutPlaceNote),
      ('1 – 5', l10n.workshopShortcutNoteValue),
      ('R', l10n.workshopRest),
      ('.', l10n.workshopDot),
      ('S', l10n.workshopSlur),
      ('← →', l10n.workshopShortcutSelect),
      ('↑ ↓', l10n.workshopShortcutTranspose),
      ('⌫  Del', l10n.workshopDelete),
      ('⌘/Ctrl  Z', l10n.workshopShortcutUndoRedo),
      ('⌘/Ctrl  C · X · V', l10n.workshopShortcutCopyPaste),
    ];
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.workshopShortcuts),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (keys, label) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 140,
                        child: Text(
                          keys,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(child: Text(label)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).closeButtonLabel),
          ),
        ],
      ),
    );
  }

  /// Ask what to do with unsaved work when leaving. Returns 'save', 'discard',
  /// or null (keep editing / cancelled).
  Future<String?> _confirmExit(AppLocalizations l10n) => showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.workshopExitTitle),
          content: Text(l10n.workshopExitMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.workshopKeepEditing),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('discard'),
              child: Text(l10n.workshopDiscard),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('save'),
              child: Text(l10n.myMelodySave),
            ),
          ],
        ),
      );

  Future<void> _handleExit() async {
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context)!;
    final action = await _confirmExit(l10n);
    if (action == null) return; // keep editing
    if (action == 'save') await _save();
    if (mounted) navigator.pop();
  }

  Future<void> _save() async {
    if (_doc.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final songs = context.read<UserSongsService>();

    final controller = TextEditingController(text: l10n.myMelodyDefaultName);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.myMelodySaveTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l10n.myMelodySave),
          ),
        ],
      ),
    );
    if (title == null) return;
    final name = title.trim().isEmpty ? l10n.myMelodyDefaultName : title.trim();
    songs.addSong(
      ImportedSong(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: name,
        musicXml: scoreToMusicXml(_doc.buildScore()),
      ),
    );
    messenger.showSnackBar(SnackBar(content: Text(l10n.myMelodySaved)));
  }

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = kidsScoreTheme;
    final selectedIds = _doc.selectedIds;
    final elementColors = <String, Color>{
      for (final id in selectedIds) id: Colors.amber,
    };
    // Live drag is owned by crisp_notation (C10b `dragPreviewOpacity`): while a note
    // is dragged the view suppresses it and re-paints the *real* glyph
    // (notehead/stem/accidental/flag/ledgers) following the pointer, snapped to
    // pitch — so the app keeps no suppress/ghost bookkeeping for moves.
    // A visible insertion caret: during a horizontal reorder drag it marks the
    // live drop slot; otherwise it sits before the element the next note precedes.
    final EditorCaret? caret;
    if (_dragId != null) {
      caret = _dropCaretId != null
          ? EditorCaret(beforeElementId: _dropCaretId)
          : null;
    } else {
      final caretId = _doc.caretBeforeId;
      caret = caretId != null ? EditorCaret(beforeElementId: caretId) : null;
    }

    return PopScope(
      // When there's content, intercept the back gesture to ask keep/discard/save.
      canPop: _doc.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleExit();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: 48,
            titleSpacing: 4,
            // The score settings live inline in the top bar (one row).
            title: _TopBar(
              mode: _mode,
              timeSignature: _doc.timeSignature,
              fifths: _doc.keySignature.fifths,
              pickup: _doc.pickup,
              armedGlyph:
                  _values.firstWhere((v) => v.base == _pendingBase).glyph,
              dotted: _dotted,
              status: _statusText(context, l10n),
              onMode: _setMode,
              onTime: (t) => setState(() => _doc.setTimeSignature(t)),
              onKey: (f) =>
                  setState(() => _doc.setKeySignature(KeySignature(f))),
              onPickup: (p) => setState(() => _doc.setPickup(p)),
              onZoomIn: () => _zoomBy(3),
              onZoomOut: () => _zoomBy(-3),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: l10n.myMelodyUndo,
                onPressed: _doc.canUndo ? () => setState(_doc.undo) : null,
              ),
              IconButton(
                icon: const Icon(Icons.redo),
                tooltip: l10n.workshopRedo,
                onPressed: _doc.canRedo ? () => setState(_doc.redo) : null,
              ),
              IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: l10n.myMelodyPlay,
                onPressed: _doc.isEmpty ? null : _play,
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: l10n.workshopShortcuts,
                onPressed: () => _showShortcuts(l10n),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  switch (v) {
                    case 'open':
                      _open();
                    case 'paste':
                      _pasteTokens();
                    case 'barnums':
                      setState(() => _barNumbers = !_barNumbers);
                    case 'notenames':
                      setState(() => _noteNames = !_noteNames);
                    case 'save':
                      _save();
                    case 'export':
                      _showExportSheet();
                    case 'clear':
                      setState(_doc.clearAll);
                  }
                },
                itemBuilder: (ctx) => [
                  _menuItem(
                    'open',
                    Icons.file_open_outlined,
                    l10n.workshopOpen,
                    true,
                  ),
                  _menuItem(
                    'paste',
                    Icons.content_paste_go_outlined,
                    l10n.workshopPasteTokens,
                    true,
                  ),
                  CheckedPopupMenuItem<String>(
                    value: 'barnums',
                    checked: _barNumbers,
                    child: Text(l10n.workshopBarNumbers),
                  ),
                  CheckedPopupMenuItem<String>(
                    value: 'notenames',
                    checked: _noteNames,
                    child: Text(l10n.workshopNoteNames),
                  ),
                  const PopupMenuDivider(),
                  _menuItem(
                    'save',
                    Icons.bookmark_add_outlined,
                    l10n.myMelodySave,
                    !_doc.isEmpty,
                  ),
                  _menuItem(
                    'export',
                    Icons.ios_share,
                    l10n.workshopExport,
                    !_doc.isEmpty,
                  ),
                  _menuItem(
                    'clear',
                    Icons.delete_sweep_outlined,
                    l10n.myMelodyClear,
                    !_doc.isEmpty,
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              // G6: instrument parts strip (add · select · clef/transposition/
              // brace/remove). One part = the classic single-instrument editor.
              _partsStrip(l10n),
              // Row A — compact settings + status.
              // Score canvas — multi-line, vertical scroll.
              Expanded(
                // Isolate the canvas's repaints (live drag / ghost / caret) from
                // the dock + piano so a drag never repaints the whole screen.
                child: RepaintBoundary(
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    // G6: with more than one instrument part, show the full-score
                    // canvas (tap selects across parts; the bottom dock edits the
                    // active part). One part keeps the single-part interactive
                    // pipeline (ghost/drag/staff-tap placement).
                    child: _mpd.partCount > 1
                        ? Stack(
                            children: [
                              MultiPartCanvas(
                                document: _mpd,
                                staffSpace: _zoom,
                                onElementTap: _onGlobalElementTap,
                                onStaffTap: _onMpStaffTap,
                                onHover: _onMpHover,
                                ghostPart: _hoverPart,
                                ghostTarget: _hover,
                                ghostDuration: _ghostDuration,
                                highlightedIds: _mpd.selectedGlobalIds,
                                suppressElementIds: _mpSuppressed,
                                onElementDragStart: _onMpDragStart,
                                onElementDragUpdate: _onMpDragUpdate,
                                onElementDragEnd: _onMpDragEnd,
                                controller: _regions,
                                caret: _mpCaret,
                                showMeasureNumbers: _barNumbers,
                              ),
                              if (_marquee)
                                Positioned.fill(
                                  child: _MarqueeOverlay(
                                    onSelect: _applyMpMarquee,
                                  ),
                                ),
                            ],
                          )
                        // Bind the engraving width to the visible viewport so
                        // systems break within the screen (never off the edge).
                        : LayoutBuilder(
                            builder: (context, constraints) =>
                                SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: SizedBox(
                                width: (constraints.maxWidth - 32)
                                    .clamp(0.0, 4000.0),
                                // Passively track the canvas-local pointer so a drag's
                                // drop position can reorder a note (fine, C7 regions).
                                child: Listener(
                                  onPointerDown: (e) =>
                                      _pointerLocal = e.localPosition,
                                  onPointerMove: (e) =>
                                      _pointerLocal = e.localPosition,
                                  child: Stack(
                                    children: [
                                      _grand
                                          ? InteractiveGrandStaffView(
                                              grandStaff:
                                                  _doc.buildGrandStaff(),
                                              theme: theme,
                                              staffSpace: _zoom,
                                              showMeasureNumbers: _barNumbers,
                                              controller: _regions,
                                              elementColors: elementColors,
                                              dragPreviewOpacity:
                                                  _kDragPreviewOpacity,
                                              onElementTap: _onElementTap,
                                              onStaffTap: _onStaffTap,
                                              onHover: _onHover,
                                              ghostTarget: _hover,
                                              ghostDuration: _ghostDuration,
                                              caret: caret,
                                              onElementDragStart:
                                                  _onElementDragStart,
                                              onElementDragUpdate:
                                                  _onElementDragUpdate,
                                              onElementDragEnd:
                                                  _onElementDragEnd,
                                            )
                                          : MultiSystemView(
                                              score: _doc.buildScore(),
                                              theme: theme,
                                              staffSpace: _zoom,
                                              showMeasureNumbers: _barNumbers,
                                              showNoteNames: _noteNames,
                                              noteNameStyle: _noteNameStyle,
                                              controller: _regions,
                                              elementColors: elementColors,
                                              dragPreviewOpacity:
                                                  _kDragPreviewOpacity,
                                              onElementTap: _onElementTap,
                                              onStaffTap: _onStaffTap,
                                              onHover: _onHover,
                                              ghostTarget: _hover,
                                              ghostDuration: _ghostDuration,
                                              caret: caret,
                                              onElementDragStart:
                                                  _onElementDragStart,
                                              onElementDragUpdate:
                                                  _onElementDragUpdate,
                                              onElementDragEnd:
                                                  _onElementDragEnd,
                                            ),
                                      if (_marquee)
                                        Positioned.fill(
                                          child: _MarqueeOverlay(
                                            onSelect: _applyMarquee,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              // Row B — value/accidental strip + contextual selection actions.
              _InputBar(
                pendingBase: _pendingBase,
                dotted: _dotted,
                accidental: _accidental,
                hasSelection: _doc.hasSelection,
                canTranspose: _selectionHasNote,
                canPaste: _doc.canPaste,
                onPickValue: _pickValue,
                onToggleDot: _toggleDot,
                onPickAccidental: _pickAccidental,
                onRest: _addRest,
                chordMode: _chordMode,
                onChord: () => setState(() => _chordMode = !_chordMode),
                marquee: _marquee,
                onMarquee: () => setState(() => _marquee = !_marquee),
                onSelectPrev: () => _run(_doc.selectPrev),
                onSelectNext: () => _run(_doc.selectNext),
                onExtendLeft: () => _run(_doc.extendLeft),
                onExtendRight: () => _run(_doc.extendRight),
                onUp: () => _transpose(1),
                onDown: () => _transpose(-1),
                onMoveLeft: () => _run(_doc.moveSelectionLeft),
                onMoveRight: () => _run(_doc.moveSelectionRight),
                onCopy: () => _run(_doc.copySelection),
                onCut: () => _run(_doc.cutSelection),
                onPaste: () => _run(_doc.paste),
                slur: _slurButton(l10n),
                hairpin: _hairpinButtons(l10n),
                lyric: _lyricField(l10n),
                palette: _paletteButton(l10n),
                onDelete: () => _run(_doc.deleteSelected),
              ),
              // Piano — places notes at the caret. In its own repaint boundary
              // so canvas repaints (and its own horizontal scroll) stay local.
              RepaintBoundary(
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  elevation: 3,
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      height: 140,
                      child: SingleChildScrollView(
                        controller: _pianoScroll,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(8),
                        child: _pianoKeyboard,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    bool enabled,
  ) =>
      PopupMenuItem(
        value: value,
        enabled: enabled,
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Flexible(child: Text(label)),
          ],
        ),
      );

  String _statusText(BuildContext context, AppLocalizations l10n) {
    if (!_doc.hasSelection) return l10n.workshopReady;
    final ids = _doc.selectedIds;
    if (ids.length > 1) return l10n.workshopSelectedCount(ids.length);
    final e = _doc.selected!;
    if (e.isRest) return l10n.workshopRest;
    final p = e.pitch!;
    final acc = p.alter > 0 ? '♯' : (p.alter < 0 ? '♭' : '');
    return '${noteNameFor(context, p.step)}$acc${p.octave}';
  }
}

/// Row A — compact clef/time/key/zoom dropdowns + a status readout.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.mode,
    required this.timeSignature,
    required this.fifths,
    required this.pickup,
    required this.armedGlyph,
    required this.dotted,
    required this.status,
    required this.onMode,
    required this.onTime,
    required this.onKey,
    required this.onPickup,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final _StaffMode mode;
  final TimeSignature timeSignature;
  final int fifths;
  final NoteDuration? pickup;
  final String armedGlyph;
  final bool dotted;
  final String status;
  final ValueChanged<_StaffMode> onMode;
  final ValueChanged<TimeSignature> onTime;
  final ValueChanged<int> onKey;
  final ValueChanged<NoteDuration?> onPickup;
  final VoidCallback onZoomIn, onZoomOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _dropdown<_StaffMode>(
              value: mode,
              items: {
                for (final m in _StaffMode.values) m: _staffModeGlyph[m]!,
              },
              onChanged: onMode,
              tooltip: l10n.workshopClef,
            ),
            _dropdown<TimeSignature>(
              value: timeSignature,
              items: {
                TimeSignature.twoFour: '2/4',
                TimeSignature.threeFour: '3/4',
                TimeSignature.fourFour: '4/4',
              },
              onChanged: onTime,
              tooltip: l10n.workshopTimeSignature,
            ),
            _dropdown<int>(
              value: fifths,
              items: {for (final f in _keyChoices) f: _keyLabel(f)},
              onChanged: onKey,
              tooltip: l10n.workshopKey,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Tooltip(
                message: l10n.workshopPickup,
                child: DropdownButton<NoteDuration?>(
                  value: pickup,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final p in _pickupChoices)
                      DropdownMenuItem(
                        value: p,
                        child: _pickupLabel(p, l10n),
                      ),
                  ],
                  onChanged: onPickup,
                ),
              ),
            ),
            IconButton(
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              onPressed: onZoomOut,
              icon: const Icon(Icons.zoom_out),
              tooltip: l10n.workshopZoomOut,
            ),
            IconButton(
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              onPressed: onZoomIn,
              icon: const Icon(Icons.zoom_in),
              tooltip: l10n.workshopZoomIn,
            ),
            const SizedBox(width: 8),
            const VerticalDivider(width: 1),
            const SizedBox(width: 8),
            MusicGlyph(armedGlyph, size: 18),
            if (dotted)
              const Text(' .', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text(status, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
    required String tooltip,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Tooltip(
          message: tooltip,
          child: DropdownButton<T>(
            value: value,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final e in items.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );

  /// The pickup dropdown's label: a dash for "none", else the note-value glyph
  /// (with a dot for dotted values).
  Widget _pickupLabel(NoteDuration? p, AppLocalizations l10n) {
    if (p == null) return const Text('—', style: TextStyle(fontSize: 16));
    final glyph = switch (p.base) {
      DurationBase.eighth => Smufl.eighthNote,
      DurationBase.half => Smufl.halfNote,
      _ => Smufl.quarterNote,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MusicGlyph(glyph, size: 16),
        if (p.dots > 0)
          const Text('.', style: TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

/// Row B — the value/accidental/rest strip, plus contextual selection actions.
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.pendingBase,
    required this.dotted,
    required this.accidental,
    required this.hasSelection,
    required this.canTranspose,
    required this.canPaste,
    required this.onPickValue,
    required this.onToggleDot,
    required this.onPickAccidental,
    required this.onRest,
    required this.chordMode,
    required this.onChord,
    required this.marquee,
    required this.onMarquee,
    required this.onSelectPrev,
    required this.onSelectNext,
    required this.onExtendLeft,
    required this.onExtendRight,
    required this.onUp,
    required this.onDown,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.onCopy,
    required this.onCut,
    required this.onPaste,
    required this.slur,
    required this.hairpin,
    required this.lyric,
    required this.palette,
    required this.onDelete,
  });

  final DurationBase pendingBase;
  final bool dotted;
  final _Accidental accidental;
  final bool hasSelection, canTranspose, canPaste;
  final ValueChanged<DurationBase> onPickValue;
  final VoidCallback onToggleDot, onRest, onChord, onMarquee;
  final bool chordMode;
  final bool marquee;
  final ValueChanged<_Accidental> onPickAccidental;
  final VoidCallback onSelectPrev, onSelectNext, onExtendLeft, onExtendRight;
  final VoidCallback onUp, onDown, onMoveLeft, onMoveRight;
  final VoidCallback onCopy, onCut, onPaste, onDelete;
  final Widget? slur;
  final Widget? hairpin;
  final Widget? lyric;
  final Widget? palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: SizedBox(
        height: 52,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              for (final v in _values)
                _GlyphButton(
                  selected: pendingBase == v.base,
                  onTap: () => onPickValue(v.base),
                  child: MusicGlyph(v.glyph, size: 22),
                ),
              _GlyphButton(
                selected: dotted,
                onTap: onToggleDot,
                tooltip: l10n.workshopDot,
                child: const Text(
                  '.',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const _Sep(),
              for (final a in _Accidental.values)
                _GlyphButton(
                  selected: accidental == a,
                  onTap: () => onPickAccidental(a),
                  child: Text(
                    _accidentalGlyph[a]!,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              const _Sep(),
              _act(Icons.music_off_outlined, l10n.workshopRest, onRest),
              _GlyphButton(
                selected: chordMode,
                onTap: onChord,
                tooltip: l10n.workshopChord,
                child: const Icon(Icons.layers, size: 22),
              ),
              _GlyphButton(
                selected: marquee,
                onTap: onMarquee,
                tooltip: l10n.workshopMarquee,
                child: const Icon(Icons.highlight_alt, size: 22),
              ),
              if (hasSelection) ...[
                const _Sep(),
                _act(Icons.chevron_left, l10n.workshopSelectPrev, onSelectPrev),
                _act(
                  Icons.chevron_right,
                  l10n.workshopSelectNext,
                  onSelectNext,
                ),
                _act(
                  Icons.keyboard_double_arrow_left,
                  l10n.workshopExtendLeft,
                  onExtendLeft,
                ),
                _act(
                  Icons.keyboard_double_arrow_right,
                  l10n.workshopExtendRight,
                  onExtendRight,
                ),
                _act(
                  Icons.arrow_upward,
                  l10n.workshopUp,
                  canTranspose ? onUp : null,
                ),
                _act(
                  Icons.arrow_downward,
                  l10n.workshopDown,
                  canTranspose ? onDown : null,
                ),
                _act(Icons.west, l10n.workshopMoveLeft, onMoveLeft),
                _act(Icons.east, l10n.workshopMoveRight, onMoveRight),
                _act(Icons.copy, l10n.workshopCopy, onCopy),
                _act(Icons.content_cut, l10n.workshopCut, onCut),
                _act(
                  Icons.content_paste,
                  l10n.workshopPaste,
                  canPaste ? onPaste : null,
                ),
                if (slur != null) slur!,
                if (hairpin != null) hairpin!,
                if (palette != null) palette!,
                _act(Icons.delete_outline, l10n.workshopDelete, onDelete),
                if (lyric != null) ...[const _Sep(), lyric!],
              ] else if (canPaste)
                _act(Icons.content_paste, l10n.workshopPaste, onPaste),
            ],
          ),
        ),
      ),
    );
  }

  Widget _act(IconData icon, String tooltip, VoidCallback? onTap) => IconButton(
        iconSize: 22,
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
        icon: Icon(icon),
        tooltip: tooltip,
      );
}

/// A square, selectable glyph button for the value/accidental strip.
class _GlyphButton extends StatelessWidget {
  const _GlyphButton({
    required this.selected,
    required this.onTap,
    required this.child,
    this.tooltip,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: SizedBox(width: 44, height: 40, child: Center(child: child)),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _Sep extends StatelessWidget {
  const _Sep();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 5),
        child: SizedBox(height: 28, child: VerticalDivider(width: 1)),
      );
}

/// A rubber-band selection overlay. Drag to sweep a rectangle; on release it
/// reports the rect (in the canvas's local pixels, aligned with the view's
/// element regions) so the screen can select the enclosed notes.
class _MarqueeOverlay extends StatefulWidget {
  const _MarqueeOverlay({required this.onSelect});

  final void Function(Rect rect) onSelect;

  @override
  State<_MarqueeOverlay> createState() => _MarqueeOverlayState();
}

class _MarqueeOverlayState extends State<_MarqueeOverlay> {
  Offset? _start;
  Offset? _current;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => setState(() {
        _start = d.localPosition;
        _current = d.localPosition;
      }),
      onPanUpdate: (d) => setState(() => _current = d.localPosition),
      onPanEnd: (_) {
        final s = _start, c = _current;
        if (s != null && c != null) widget.onSelect(Rect.fromPoints(s, c));
        setState(() {
          _start = null;
          _current = null;
        });
      },
      child: CustomPaint(
        size: Size.infinite,
        painter: _MarqueePainter(_start, _current, color),
      ),
    );
  }
}

class _MarqueePainter extends CustomPainter {
  _MarqueePainter(this.start, this.current, this.color);

  final Offset? start;
  final Offset? current;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = start, c = current;
    if (s == null || c == null) return;
    final rect = Rect.fromPoints(s, c);
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_MarqueePainter old) =>
      old.start != start || old.current != current;
}

/// An inline lyric editor for the selected note. Keyed by note id so a fresh one
/// (and controller) is built per note; commits on Enter or when focus leaves.
class _LyricField extends StatefulWidget {
  const _LyricField({
    super.key,
    required this.initial,
    required this.hint,
    required this.onCommit,
  });

  final String initial;
  final String hint;
  final ValueChanged<String> onCommit;

  @override
  State<_LyricField> createState() => _LyricFieldState();
}

class _LyricFieldState extends State<_LyricField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    if (_controller.text.trim() != widget.initial.trim()) {
      widget.onCommit(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Focus(
        onFocusChange: (hasFocus) {
          if (!hasFocus) _commit();
        },
        child: TextField(
          controller: _controller,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _commit(),
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            prefixIcon: const Icon(Icons.lyrics_outlined, size: 18),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 30, minHeight: 30),
            hintText: widget.hint,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
    );
  }
}
