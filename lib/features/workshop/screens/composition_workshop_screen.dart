// lib/features/workshop/screens/composition_workshop_screen.dart
//
// "Kompositions-Werkstatt" / "Composition Workshop" — a touch-first score
// editor (see docs/WORKSHOP_PLAN.md). Layout, top→bottom: a slim action bar
// (undo/redo/play + a ⋮ menu of import/export/etc.), one compact settings row
// (clef · time · key · zoom), a multi-line score canvas that wraps cleanly and
// scrolls vertically, a status line (armed value + selection), a contextual
// selection bar, and a bottom input dock (duration/accidental strip + on-screen
// piano). Notes are placed from the piano at the caret — the staff is for
// viewing and selecting, so panning/zooming never drops a stray note. Every
// edit runs through [ScoreDocument] (editable model + multi-level undo/redo).

// Material's Stepper also exports a `Step`; partitura's pitch Step wins here.
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

/// The accidental the selected note is set to.
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

class CompositionWorkshopScreen extends StatefulWidget {
  const CompositionWorkshopScreen({super.key});

  static const maxNotes = 128;

  @override
  State<CompositionWorkshopScreen> createState() =>
      _CompositionWorkshopScreenState();
}

/// Typed window into the editor for widget tests.
@visibleForTesting
abstract interface class CompositionWorkshopTester {
  int get noteCount;
  int get barCount;
}

class _CompositionWorkshopScreenState extends State<CompositionWorkshopScreen>
    implements CompositionWorkshopTester {
  final ScoreDocument _doc = ScoreDocument();

  DurationBase _pendingBase = DurationBase.quarter;
  bool _dotted = false;
  _Accidental _accidental = _Accidental.natural;
  double _zoom = 16; // staff space (px)

  @override
  int get noteCount => _doc.length;

  @override
  int get barCount => _doc.barCount;

  NoteDuration get _pendingDuration =>
      NoteDuration(_pendingBase, dots: _dotted ? 1 : 0);

  AudioService get _audio => context.read<AudioService>();

  void _syncControlsToSelection() {
    final e = _doc.selected;
    if (e == null) return;
    _pendingBase = e.duration.base;
    _dotted = e.duration.dots > 0;
    _accidental =
        e.isRest ? _Accidental.natural : _accidentalOf(e.pitch!.alter);
  }

  // ---- entry -------------------------------------------------------------

  void _onPianoKey(int midi) {
    if (_doc.length >= CompositionWorkshopScreen.maxNotes) return;
    _audio.playMidiNote(midi, ms: 400);
    setState(() => _doc.insertNote(pitchFromMidi(midi), _pendingDuration));
  }

  void _onElementTap(String id) => setState(() {
        _doc.toggleSelected(id);
        _syncControlsToSelection();
      });

  // ---- controls ----------------------------------------------------------

  void _pickValue(DurationBase base) => setState(() {
        _pendingBase = base;
        if (_doc.selected != null) {
          _doc.setDurationOfSelected(NoteDuration(base, dots: _dotted ? 1 : 0));
        }
      });

  void _toggleDot() => setState(() {
        _dotted = !_dotted;
        if (_doc.selected != null) {
          _doc.setDurationOfSelected(
            NoteDuration(_pendingBase, dots: _dotted ? 1 : 0),
          );
        }
      });

  void _pickAccidental(_Accidental a) => setState(() {
        _accidental = a;
        if (_doc.selected != null) _doc.setAccidentalOfSelected(_alterOf(a));
      });

  void _addRest() {
    if (_doc.length >= CompositionWorkshopScreen.maxNotes) return;
    setState(() => _doc.insertRest(_pendingDuration));
  }

  void _selectPrev() => setState(() {
        _doc.selectPrev();
        _syncControlsToSelection();
      });

  void _selectNext() => setState(() {
        _doc.selectNext();
        _syncControlsToSelection();
      });

  void _transpose(int semitones) {
    final before = _doc.selected?.pitch?.midiNumber;
    setState(() {
      _doc.transposeSelected(semitones);
      _syncControlsToSelection();
    });
    final now = _doc.selected?.pitch?.midiNumber;
    if (now != null && now != before) _audio.playMidiNote(now, ms: 300);
  }

  void _zoomBy(double delta) =>
      setState(() => _zoom = (_zoom + delta).clamp(10.0, 30.0));

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

  // ---- menu actions ------------------------------------------------------

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
    final selectedId = _doc.selectedId;
    final hasSelection = selectedId != null;
    const theme = PartituraTheme.kids;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        titleSpacing: 8,
        title: const SizedBox.shrink(),
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
              PopupMenuItem(
                value: 'save',
                enabled: !_doc.isEmpty,
                child: _menuRow(Icons.bookmark_add_outlined, l10n.myMelodySave),
              ),
              PopupMenuItem(
                value: 'xml',
                enabled: !_doc.isEmpty,
                child: _menuRow(Icons.code, l10n.workshopExportXml),
              ),
              PopupMenuItem(
                value: 'abc',
                enabled: !_doc.isEmpty,
                child: _menuRow(Icons.abc, l10n.workshopExportAbc),
              ),
              PopupMenuItem(
                value: 'clear',
                enabled: !_doc.isEmpty,
                child:
                    _menuRow(Icons.delete_sweep_outlined, l10n.myMelodyClear),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _SettingsRow(
            clef: _doc.clef,
            timeSignature: _doc.timeSignature,
            fifths: _doc.keySignature.fifths,
            onClef: (c) => setState(() => _doc.setClef(c)),
            onTime: (t) => setState(() => _doc.setTimeSignature(t)),
            onKey: (f) => setState(() => _doc.setKeySignature(KeySignature(f))),
            onZoomIn: () => _zoomBy(3),
            onZoomOut: () => _zoomBy(-3),
          ),
          const Divider(height: 1),
          // Multi-line, vertically scrolling score canvas.
          Expanded(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: MultiSystemView(
                  score: _doc.buildScore(),
                  theme: theme,
                  staffSpace: _zoom,
                  elementColors: {if (hasSelection) selectedId: Colors.amber},
                  onElementTap: _onElementTap,
                ),
              ),
            ),
          ),
          if (hasSelection)
            _SelectionBar(
              canTranspose: _doc.selected?.isRest == false,
              onPrev: _selectPrev,
              onNext: _selectNext,
              onUp: () => _transpose(1),
              onDown: () => _transpose(-1),
              onDelete: () => setState(_doc.deleteSelected),
            ),
          _StatusLine(
            glyph: _values.firstWhere((v) => v.base == _pendingBase).glyph,
            dotted: _dotted,
            text: _selectionText(context, l10n),
          ),
          _InputDock(
            pendingBase: _pendingBase,
            dotted: _dotted,
            accidental: _accidental,
            onPickValue: _pickValue,
            onToggleDot: _toggleDot,
            onPickAccidental: _pickAccidental,
            onRest: _addRest,
            onPianoKey: _onPianoKey,
          ),
        ],
      ),
    );
  }

  Widget _menuRow(IconData icon, String label) => Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
        ],
      );

  String _selectionText(BuildContext context, AppLocalizations l10n) {
    final e = _doc.selected;
    if (e == null) return l10n.workshopReady;
    if (e.isRest) return l10n.workshopRest;
    final p = e.pitch!;
    final acc = p.alter > 0 ? '♯' : (p.alter < 0 ? '♭' : '');
    return '${noteNameFor(context, p.step)}$acc${p.octave}';
  }
}

/// One compact row: clef · time · key · zoom.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.clef,
    required this.timeSignature,
    required this.fifths,
    required this.onClef,
    required this.onTime,
    required this.onKey,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final Clef clef;
  final TimeSignature timeSignature;
  final int fifths;
  final ValueChanged<Clef> onClef;
  final ValueChanged<TimeSignature> onTime;
  final ValueChanged<int> onKey;
  final VoidCallback onZoomIn, onZoomOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _label(context, l10n.workshopClef),
          SegmentedButton<Clef>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: Clef.treble, label: Text('𝄞')),
              ButtonSegment(value: Clef.bass, label: Text('𝄢')),
            ],
            selected: {clef == Clef.bass ? Clef.bass : Clef.treble},
            onSelectionChanged: (s) => onClef(s.first),
          ),
          const SizedBox(width: 16),
          _label(context, l10n.workshopTimeSignature),
          SegmentedButton<TimeSignature>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: TimeSignature.twoFour, label: Text('2/4')),
              ButtonSegment(value: TimeSignature.threeFour, label: Text('3/4')),
              ButtonSegment(value: TimeSignature.fourFour, label: Text('4/4')),
            ],
            selected: {timeSignature},
            onSelectionChanged: (s) => onTime(s.first),
          ),
          const SizedBox(width: 16),
          _label(context, l10n.workshopKey),
          DropdownButton<int>(
            value: fifths,
            items: [
              for (final f in _keyChoices)
                DropdownMenuItem(value: f, child: Text(_keyLabel(f))),
            ],
            onChanged: (f) => onKey(f ?? 0),
          ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: onZoomOut,
            icon: const Icon(Icons.zoom_out),
            tooltip: l10n.workshopZoomOut,
          ),
          IconButton(
            onPressed: onZoomIn,
            icon: const Icon(Icons.zoom_in),
            tooltip: l10n.workshopZoomIn,
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Text(text, style: Theme.of(context).textTheme.labelMedium),
      );
}

/// Armed value glyph + a line of text (selection / prompt).
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.glyph,
    required this.dotted,
    required this.text,
  });

  final String glyph;
  final bool dotted;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          MusicGlyph(glyph, size: 20),
          if (dotted)
            const Text(' .', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Contextual controls for the current selection.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.canTranspose,
    required this.onPrev,
    required this.onNext,
    required this.onUp,
    required this.onDown,
    required this.onDelete,
  });

  final bool canTranspose;
  final VoidCallback onPrev, onNext, onUp, onDown, onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
            tooltip: l10n.workshopSelectPrev,
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: l10n.workshopSelectNext,
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: canTranspose ? onUp : null,
            icon: const Icon(Icons.arrow_upward),
            tooltip: l10n.workshopUp,
          ),
          IconButton(
            onPressed: canTranspose ? onDown : null,
            icon: const Icon(Icons.arrow_downward),
            tooltip: l10n.workshopDown,
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.workshopDelete,
          ),
        ],
      ),
    );
  }
}

/// The bottom input dock: a duration/accidental glyph strip above the piano.
class _InputDock extends StatelessWidget {
  const _InputDock({
    required this.pendingBase,
    required this.dotted,
    required this.accidental,
    required this.onPickValue,
    required this.onToggleDot,
    required this.onPickAccidental,
    required this.onRest,
    required this.onPianoKey,
  });

  final DurationBase pendingBase;
  final bool dotted;
  final _Accidental accidental;
  final ValueChanged<DurationBase> onPickValue;
  final VoidCallback onToggleDot;
  final ValueChanged<_Accidental> onPickAccidental;
  final VoidCallback onRest;
  final ValueChanged<int> onPianoKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  for (final v in _values)
                    _GlyphButton(
                      selected: pendingBase == v.base,
                      onTap: () => onPickValue(v.base),
                      child: MusicGlyph(v.glyph, size: 24),
                    ),
                  _GlyphButton(
                    selected: dotted,
                    onTap: onToggleDot,
                    tooltip: l10n.workshopDot,
                    child: const Text(
                      '.',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const _DockDivider(),
                  for (final a in _Accidental.values)
                    _GlyphButton(
                      selected: accidental == a,
                      onTap: () => onPickAccidental(a),
                      child: Text(
                        _accidentalGlyph[a]!,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  const _DockDivider(),
                  _GlyphButton(
                    selected: false,
                    onTap: onRest,
                    tooltip: l10n.workshopRest,
                    child: const Icon(Icons.music_off_outlined),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 132,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: PianoKeyboard(
                  startMidi: 48, // C3
                  whiteKeyCount: 15,
                  showLabels: true,
                  onKeyTap: onPianoKey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A square, selectable glyph button used across the input dock.
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
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(width: 48, height: 44, child: Center(child: child)),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _DockDivider extends StatelessWidget {
  const _DockDivider();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(height: 32, child: VerticalDivider(width: 1)),
      );
}
