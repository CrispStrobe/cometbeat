// lib/features/workshop/screens/composition_workshop_screen.dart
//
// "Kompositions-Werkstatt" / "Composition Workshop" — the score editor that
// grows toward professional score-writing depth (see docs/WORKSHOP_PLAN.md).
// It is intentionally simple by default: pick a note value (and, when wanted, a
// dot or an accidental) and tap an empty spot on the staff to write there.
// Tap a note to select it; the value / dot / accidental controls then edit the
// selected note, the ◀ ▶ arrows walk the selection, and ▲ ▼ nudge its pitch.
// Everything runs through [ScoreDocument] — an editable model with multi-level
// undo/redo — so new notation features slot in without the screen assembling a
// Score by hand.

// Material's Stepper also exports a `Step`; partitura's pitch Step wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/features/games/songs/user_songs_service.dart';
import 'package:klang_universum/features/workshop/model/score_document.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/widgets/music_glyph.dart';
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

/// The accidental the next placed note gets (or the selected note is set to).
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

/// Key-signature choices offered in the picker (circle-of-fifths position).
const _keyChoices = [-4, -3, -2, -1, 0, 1, 2, 3, 4];

String _keyLabel(int fifths) =>
    fifths == 0 ? '♮' : (fifths > 0 ? '$fifths♯' : '${-fifths}♭');

class CompositionWorkshopScreen extends StatefulWidget {
  const CompositionWorkshopScreen({super.key});

  static const maxNotes = 64;

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

  @override
  int get noteCount => _doc.length;

  @override
  int get barCount => _doc.barCount;

  NoteDuration get _pendingDuration =>
      NoteDuration(_pendingBase, dots: _dotted ? 1 : 0);

  /// Mirror the toolbar controls onto whatever is currently selected, so they
  /// read as "this note's value / accidental" while a note is selected.
  void _syncControlsToSelection() {
    final e = _doc.selected;
    if (e == null) return;
    _pendingBase = e.duration.base;
    _dotted = e.duration.dots > 0;
    _accidental =
        e.isRest ? _Accidental.natural : _accidentalOf(e.pitch!.alter);
  }

  void _onStaffTap(StaffTarget target) {
    if (_doc.length >= CompositionWorkshopScreen.maxNotes) return;
    final pitch =
        target.pitchFor(_doc.clef, preferredAlter: _alterOf(_accidental));
    context.read<AudioService>().playMidiNote(pitch.midiNumber, ms: 400);
    setState(() => _doc.insertNote(pitch, _pendingDuration));
  }

  void _onElementTap(String id) => setState(() {
        _doc.toggleSelected(id);
        _syncControlsToSelection();
      });

  void _pickValue(DurationBase base) => setState(() {
        _pendingBase = base;
        if (_doc.selected != null) {
          _doc.setDurationOfSelected(NoteDuration(base, dots: _dotted ? 1 : 0));
        }
      });

  void _toggleDot(bool value) => setState(() {
        _dotted = value;
        if (_doc.selected != null) {
          _doc.setDurationOfSelected(
            NoteDuration(_pendingBase, dots: value ? 1 : 0),
          );
        }
      });

  void _pickAccidental(_Accidental a) => setState(() {
        _accidental = a;
        if (_doc.selected != null) _doc.setAccidentalOfSelected(_alterOf(a));
      });

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
    if (now != null && now != before) {
      context.read<AudioService>().playMidiNote(now, ms: 300);
    }
  }

  void _addRest() {
    if (_doc.length >= CompositionWorkshopScreen.maxNotes) return;
    setState(() => _doc.insertRest(_pendingDuration));
  }

  void _play() {
    if (_doc.isEmpty) return;
    context.read<AudioService>().playSequence([
      for (final e in _doc.elements)
        if (!e.isRest)
          (
            e.pitch!.midiNumber,
            (e.duration.toFraction().toDouble() * 4 * 480).round(),
          ),
    ]);
  }

  // Export the score as ABC notation — a compact text form that pastes into ABC
  // tools and back into the Song Book importer.
  Future<void> _exportAbc() async {
    if (_doc.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final abc = scoreToAbc(_doc.buildScore());
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.workshopExportAbc),
        content: SingleChildScrollView(child: SelectableText(abc)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).closeButtonLabel),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: abc));
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selectedId = _doc.selectedId;
    final hasSelection = selectedId != null;
    final theme = PartituraTheme.kids.copyWith(
      elementColors: {if (hasSelection) selectedId: Colors.amber},
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.workshopComposeTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.abc),
            tooltip: l10n.workshopExportAbc,
            onPressed: _doc.isEmpty ? null : _exportAbc,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Time + key signature.
              Row(
                children: [
                  Text(
                    l10n.workshopTimeSignature,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(width: 8),
                  _TimeSignaturePicker(
                    value: _doc.timeSignature,
                    onChanged: (t) => setState(() => _doc.setTimeSignature(t)),
                  ),
                  const Spacer(),
                  Text(
                    l10n.workshopKey,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _doc.keySignature.fifths,
                    items: [
                      for (final f in _keyChoices)
                        DropdownMenuItem(value: f, child: Text(_keyLabel(f))),
                    ],
                    onChanged: (f) => setState(
                      () => _doc.setKeySignature(KeySignature(f ?? 0)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Note value.
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final v in _values)
                    ChoiceChip(
                      avatar: MusicGlyph(v.glyph, size: 22),
                      label: Text(_beatsLabel(l10n, v.base)),
                      selected: _pendingBase == v.base,
                      onSelected: (_) => _pickValue(v.base),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // Dot + accidental modifiers.
              Wrap(
                spacing: 12,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    avatar: const Text('.', style: TextStyle(fontSize: 20)),
                    label: Text(l10n.workshopDot),
                    selected: _dotted,
                    onSelected: _toggleDot,
                  ),
                  SegmentedButton<_Accidental>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: _Accidental.natural,
                        label: Text('♮'),
                      ),
                      ButtonSegment(value: _Accidental.sharp, label: Text('♯')),
                      ButtonSegment(value: _Accidental.flat, label: Text('♭')),
                    ],
                    selected: {_accidental},
                    onSelectionChanged: (s) => _pickAccidental(s.first),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  child: Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: InteractiveStaff(
                        score: _doc.buildScore(),
                        theme: theme,
                        staffSpace: 14,
                        onStaffTap: _onStaffTap,
                        onElementTap: _onElementTap,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasSelection ? l10n.workshopEditHint : l10n.workshopHint,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              // Cursor: walk the selection and nudge pitch.
              _CursorBar(
                enabled: !_doc.isEmpty,
                canTranspose: hasSelection && _doc.selected?.isRest == false,
                onPrev: _selectPrev,
                onNext: _selectNext,
                onUp: () => _transpose(1),
                onDown: () => _transpose(-1),
                canDelete: hasSelection,
                onDelete: () => setState(_doc.deleteSelected),
              ),
              const SizedBox(height: 6),
              _Toolbar(
                canPlay: !_doc.isEmpty,
                canSave: !_doc.isEmpty,
                canUndo: _doc.canUndo,
                canRedo: _doc.canRedo,
                canClear: !_doc.isEmpty,
                onPlay: _play,
                onSave: _save,
                onRest: _addRest,
                onUndo: () => setState(_doc.undo),
                onRedo: () => setState(_doc.redo),
                onClear: () => setState(_doc.clearAll),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _beatsLabel(AppLocalizations l10n, DurationBase base) {
    // Quarter-note beats this value lasts (in a /4 metre).
    final beats = NoteDuration(base).toFraction().toDouble() * 4;
    if (beats == 0.25) return l10n.quarterBeat;
    if (beats == 0.5) return l10n.halfBeat;
    return l10n.beatsCount(beats.toInt());
  }
}

/// The 2/4 · 3/4 · 4/4 chooser.
class _TimeSignaturePicker extends StatelessWidget {
  const _TimeSignaturePicker({required this.value, required this.onChanged});

  final TimeSignature value;
  final ValueChanged<TimeSignature> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TimeSignature>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: TimeSignature.twoFour, label: Text('2/4')),
        ButtonSegment(value: TimeSignature.threeFour, label: Text('3/4')),
        ButtonSegment(value: TimeSignature.fourFour, label: Text('4/4')),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// Selection cursor: previous/next, pitch up/down, delete.
class _CursorBar extends StatelessWidget {
  const _CursorBar({
    required this.enabled,
    required this.canTranspose,
    required this.onPrev,
    required this.onNext,
    required this.onUp,
    required this.onDown,
    required this.canDelete,
    required this.onDelete,
  });

  final bool enabled, canTranspose, canDelete;
  final VoidCallback onPrev, onNext, onUp, onDown, onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton.filledTonal(
          onPressed: enabled ? onPrev : null,
          icon: const Icon(Icons.chevron_left),
          tooltip: l10n.workshopSelectPrev,
        ),
        IconButton.filledTonal(
          onPressed: enabled ? onNext : null,
          icon: const Icon(Icons.chevron_right),
          tooltip: l10n.workshopSelectNext,
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: canTranspose ? onUp : null,
          icon: const Icon(Icons.arrow_upward),
          tooltip: l10n.workshopUp,
        ),
        IconButton.filledTonal(
          onPressed: canTranspose ? onDown : null,
          icon: const Icon(Icons.arrow_downward),
          tooltip: l10n.workshopDown,
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: canDelete ? onDelete : null,
          icon: const Icon(Icons.delete_outline),
          tooltip: l10n.workshopDelete,
        ),
      ],
    );
  }
}

/// The action row under the staff.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.canPlay,
    required this.canSave,
    required this.canUndo,
    required this.canRedo,
    required this.canClear,
    required this.onPlay,
    required this.onSave,
    required this.onRest,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
  });

  final bool canPlay, canSave, canUndo, canRedo, canClear;
  final VoidCallback onPlay, onSave, onRest, onUndo, onRedo, onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        FilledButton.icon(
          onPressed: canPlay ? onPlay : null,
          icon: const Icon(Icons.play_arrow),
          label: Text(l10n.myMelodyPlay),
        ),
        FilledButton.tonalIcon(
          onPressed: canSave ? onSave : null,
          icon: const Icon(Icons.bookmark_add_outlined),
          label: Text(l10n.myMelodySave),
        ),
        FilledButton.tonalIcon(
          onPressed: onRest,
          icon: const Icon(Icons.music_off_outlined),
          label: Text(l10n.workshopRest),
        ),
        IconButton.filledTonal(
          onPressed: canUndo ? onUndo : null,
          icon: const Icon(Icons.undo),
          tooltip: l10n.myMelodyUndo,
        ),
        IconButton.filledTonal(
          onPressed: canRedo ? onRedo : null,
          icon: const Icon(Icons.redo),
          tooltip: l10n.workshopRedo,
        ),
        TextButton.icon(
          onPressed: canClear ? onClear : null,
          icon: const Icon(Icons.delete_sweep_outlined),
          label: Text(l10n.myMelodyClear),
        ),
      ],
    );
  }
}
