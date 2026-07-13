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

// Material's Stepper also exports a `Step`; partitura's pitch Step wins here.
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/features/games/songs/user_songs_service.dart';
import 'package:klang_universum/features/workshop/model/score_document.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/midi_pitch.dart';
import 'package:klang_universum/shared/widgets/music_glyph.dart';
import 'package:klang_universum/shared/widgets/piano_keyboard.dart';
import 'package:partitura/partitura.dart';
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

class CompositionWorkshopScreen extends StatefulWidget {
  const CompositionWorkshopScreen({super.key});

  static const maxNotes = 256;

  @override
  State<CompositionWorkshopScreen> createState() =>
      _CompositionWorkshopScreenState();
}

/// Typed window into the editor for widget tests.
@visibleForTesting
abstract interface class CompositionWorkshopTester {
  int get noteCount;
  int get barCount;
  bool get hasSelection;
  int get selectedCount;
}

class _CompositionWorkshopScreenState extends State<CompositionWorkshopScreen>
    implements CompositionWorkshopTester {
  final ScoreDocument _doc = ScoreDocument();

  DurationBase _pendingBase = DurationBase.quarter;
  bool _dotted = false;
  _Accidental _accidental = _Accidental.natural;
  double _zoom = 16;
  _StaffMode _mode = _StaffMode.treble;
  bool _chordMode = false; // placed pitches stack onto the selected note
  StaffTarget? _hover; // where a click/tap would land (desktop hover preview)

  // Start the sweepable piano scrolled to around C3 (24 = C1, 7 white/octave).
  final _pianoScroll =
      ScrollController(initialScrollOffset: 14 * _pianoKeyWidth);

  @override
  void dispose() {
    _pianoScroll.dispose();
    super.dispose();
  }

  bool get _grand => _mode == _StaffMode.grand;

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

  NoteDuration get _pendingDuration =>
      NoteDuration(_pendingBase, dots: _dotted ? 1 : 0);

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

  /// Click a staff line: if a note is selected, move it there (re-pitch);
  /// otherwise place a new note at that pitch.
  void _onStaffTap(StaffTarget target) {
    final pitch = target.pitchFor(
      _clefForTarget(target),
      preferredAlter: _alterOf(_accidental),
    );
    final selected = _doc.selected;
    if (selected != null && !selected.isRest) {
      setState(() => _doc.repitchSelected(pitch));
      _audio.playMidiNote(pitch.midiNumber, ms: 300);
    } else {
      _placePitch(pitch);
    }
  }

  void _onElementTap(String id) => setState(() {
        _doc.toggleSelected(id);
        _syncControlsToSelection();
      });

  /// Drag a note on the staff to re-pitch it (vertical drag → new pitch).
  void _onElementDragEnd(String id, StaffTarget target) {
    Pitch? moved;
    setState(() {
      moved = _doc.moveById(id, target, clef: _clefForTarget(target));
      _hover = null;
    });
    if (moved != null) _audio.playMidiNote(moved!.midiNumber, ms: 300);
  }

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
      setState(() => _zoom = (_zoom + d).clamp(10.0, 32.0));

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

  Future<void> _openFile({
    required List<String> extensions,
    required String label,
    required Future<Score> Function(XFile file) parse,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await openFile(
        acceptedTypeGroups: [XTypeGroup(label: label, extensions: extensions)],
      );
      if (file == null) return;
      final score = await parse(file);
      if (!mounted) return;
      setState(() => _doc.loadScore(score));
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
    const theme = PartituraTheme.kids;
    final selectedIds = _doc.selectedIds;

    return Focus(
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
            armedGlyph: _values.firstWhere((v) => v.base == _pendingBase).glyph,
            dotted: _dotted,
            status: _statusText(context, l10n),
            onMode: _setMode,
            onTime: (t) => setState(() => _doc.setTimeSignature(t)),
            onKey: (f) => setState(() => _doc.setKeySignature(KeySignature(f))),
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
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                switch (v) {
                  case 'openxml':
                    _openFile(
                      extensions: const ['musicxml', 'xml'],
                      label: 'MusicXML',
                      parse: (f) async =>
                          scoreFromMusicXml(await f.readAsString()),
                    );
                  case 'openmidi':
                    _openFile(
                      extensions: const ['mid', 'midi'],
                      label: 'MIDI',
                      parse: (f) async => scoreFromMidi(await f.readAsBytes()),
                    );
                  case 'save':
                    _save();
                  case 'xml':
                    _exportText(
                      l10n.workshopExportXml,
                      scoreToMusicXml(_doc.buildScore()),
                    );
                  case 'abc':
                    _exportText(
                      l10n.workshopExportAbc,
                      scoreToAbc(_doc.buildScore()),
                    );
                  case 'clear':
                    setState(_doc.clearAll);
                }
              },
              itemBuilder: (ctx) => [
                _menuItem(
                  'openxml',
                  Icons.file_open_outlined,
                  l10n.importMusicXmlFile,
                  true,
                ),
                _menuItem(
                  'openmidi',
                  Icons.file_open_outlined,
                  l10n.importMidiFile,
                  true,
                ),
                const PopupMenuDivider(),
                _menuItem(
                  'save',
                  Icons.bookmark_add_outlined,
                  l10n.myMelodySave,
                  !_doc.isEmpty,
                ),
                _menuItem(
                  'xml',
                  Icons.code,
                  l10n.workshopExportXml,
                  !_doc.isEmpty,
                ),
                _menuItem(
                  'abc',
                  Icons.abc,
                  l10n.workshopExportAbc,
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
            // Row A — compact settings + status.
            // Score canvas — multi-line, vertical scroll.
            Expanded(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _grand
                      ? InteractiveGrandStaffView(
                          grandStaff: _doc.buildGrandStaff(),
                          theme: theme,
                          staffSpace: _zoom,
                          elementColors: {
                            for (final id in selectedIds) id: Colors.amber,
                          },
                          onElementTap: _onElementTap,
                          onStaffTap: _onStaffTap,
                          onHover: (t) => setState(() => _hover = t),
                          ghostTarget: _hover,
                          ghostDuration: _pendingDuration,
                          onElementDragUpdate: (id, t) =>
                              setState(() => _hover = t),
                          onElementDragEnd: _onElementDragEnd,
                        )
                      : MultiSystemView(
                          score: _doc.buildScore(),
                          theme: theme,
                          staffSpace: _zoom,
                          elementColors: {
                            for (final id in selectedIds) id: Colors.amber,
                          },
                          onElementTap: _onElementTap,
                          onStaffTap: _onStaffTap,
                          onHover: (t) => setState(() => _hover = t),
                          ghostTarget: _hover,
                          ghostDuration: _pendingDuration,
                          onElementDragUpdate: (id, t) =>
                              setState(() => _hover = t),
                          onElementDragEnd: _onElementDragEnd,
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
              palette: _paletteButton(l10n),
              onDelete: () => _run(_doc.deleteSelected),
            ),
            // Piano — places notes at the caret.
            Material(
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
                    child: SizedBox(
                      width: _pianoWhiteKeys * _pianoKeyWidth,
                      child: PianoKeyboard(
                        startMidi: _pianoStartMidi,
                        whiteKeyCount: _pianoWhiteKeys,
                        showLabels: true,
                        showOctaveNumbers: true,
                        onKeyTap: _onPianoKey,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
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
    required this.armedGlyph,
    required this.dotted,
    required this.status,
    required this.onMode,
    required this.onTime,
    required this.onKey,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final _StaffMode mode;
  final TimeSignature timeSignature;
  final int fifths;
  final String armedGlyph;
  final bool dotted;
  final String status;
  final ValueChanged<_StaffMode> onMode;
  final ValueChanged<TimeSignature> onTime;
  final ValueChanged<int> onKey;
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
    required this.palette,
    required this.onDelete,
  });

  final DurationBase pendingBase;
  final bool dotted;
  final _Accidental accidental;
  final bool hasSelection, canTranspose, canPaste;
  final ValueChanged<DurationBase> onPickValue;
  final VoidCallback onToggleDot, onRest, onChord;
  final bool chordMode;
  final ValueChanged<_Accidental> onPickAccidental;
  final VoidCallback onSelectPrev, onSelectNext, onExtendLeft, onExtendRight;
  final VoidCallback onUp, onDown, onMoveLeft, onMoveRight;
  final VoidCallback onCopy, onCut, onPaste, onDelete;
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
                if (palette != null) palette!,
                _act(Icons.delete_outline, l10n.workshopDelete, onDelete),
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
