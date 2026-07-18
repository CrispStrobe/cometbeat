// lib/features/games/composition/advanced_tracker_screen.dart
//
// The Tracker's ADVANCED mode — a classic ProTracker / Scream Tracker 3 /
// Impulse Tracker / FastTracker 2 style pattern editor, in contrast to the
// Beginner mode (tracker_screen.dart, a scale-locked kid grid capped at one
// bar). It drops every kid limit:
//
//   * endless pattern length  (the "Length" control — no more 2-3 Takte),
//   * endless tracks          ("Add track" / per-track remove),
//   * chromatic entry          (full-range notes, no pentatonic snapping),
//   * a rows x channels grid   with hex row numbers and a moving playhead,
//   * DUAL note entry          — a computer-keyboard piano map (FT2 layout,
//                                edit-step + octave) on desktop/web AND an
//                                on-screen piano at the cursor on touch,
//   * per-track instruments    (tap a track header) and per-cell dynamics +
//     effect (long-press a cell).
//
// It drives the general [TrackerSong] document over the shared [TrackerEngine]
// (same offline mixStems -> one looping WAV -> GaplessLoopPlayer path the
// Beginner grid and Loop Mixer use; the Stopwatch owns the musical phase so an
// edit re-swaps the loop without the beat restarting; a Ticker created in
// initState — never a lazy `late final`, see CLAUDE.md — drives the playhead).
//
// Shipped over slices, all on this one document: S1 grid + endless length/
// tracks + Play/Stop; S2 the edit cursor + keyboard/on-screen-piano entry +
// per-track instruments + per-cell volume/effect; S3 multi-pattern songs + the
// order list; S4 the full inline transport (Play/Pause/Stop/Back/Forward + loop
// + position); S5a mute/solo; S5b module import (.mod/.s3m/.xm/.it) + Save to
// Song Book; S5c the keyboard/layout modernization — a 2nd note-entry mode
// (note names: "F" then "2"), a sweepable multi-octave piano (the Workshop's
// PianoKeyboard), a keyboard legend (ⓘ), tempo + up-to-256/custom length, and an
// optional onboarding tutorial (i18n). S5d the classic BLOCK ops — mark a
// rectangle (Shift+arrows / tap-mark / select-track / select-pattern) then copy/
// cut/paste/paste-mix/transpose/clear, via a Block menu AND keyboard shortcuts.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/sample_edit.dart';
import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart';
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:comet_beat/core/audio/voice_clip_recorder.dart';
import 'package:comet_beat/core/notation/multi_part_export.dart'
    show multiPartToMidi, multiTrackMidiToMultiPart;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/gapless_loop_player.dart';
import 'package:comet_beat/features/games/composition/tracker_notation.dart';
import 'package:comet_beat/features/games/composition/tracker_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart'
    show CompositionWorkshopScreen;
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/tutorial/tutorial.dart';
import 'package:comet_beat/shared/tutorial/tutorial_sheet.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show MultiPartScore, Score, multiPartScoreFromMusicXml, multiPartToMusicXml;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Note names for chromatic display, classic-tracker style ("C-4", "C#4").
const _kNoteNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

/// A MIDI number as a tracker note label, e.g. 60 -> "C-4", 61 -> "C#4".
String trackerNoteName(int midi) {
  final name = _kNoteNames[midi % 12];
  final octave = midi ~/ 12 - 1;
  return name.length == 1 ? '$name-$octave' : '$name$octave';
}

/// Selectable pattern lengths (rows). Covers the classic ceilings — MOD/S3M 64,
/// IT up to 200, XM up to 256 — plus a "Custom…" entry (the engine has no cap).
const _kLengthOptions = [16, 32, 48, 64, 96, 128, 192, 200, 256];

/// Common tempos (BPM) offered in the toolbar.
const _kTempoOptions = [80, 100, 110, 120, 128, 140, 150, 160, 175, 200];

/// Note letter -> semitone within an octave (for the "note-name" entry mode:
/// type a letter then an octave digit, e.g. F then 2 -> F2).
const _kLetterSemitone = <String, int>{
  'c': 0,
  'd': 2,
  'e': 4,
  'f': 5,
  'g': 7,
  'a': 9,
  'b': 11,
};

/// How the computer keyboard enters notes.
enum _NoteEntry {
  /// The classic FastTracker-2 piano map (Z=C … / Q=C an octave up).
  pianoKeys,

  /// Note name + octave: a letter (C..B), optional #, then a digit (F #? 2).
  noteNames,
}

/// The sub-column the in-grid cursor edits (FT2's note / volume / effect
/// columns). Typing digits into [volume]/[effect] edits that column directly.
enum _CellField { note, volume, effect }

/// FastTracker-2 style computer-keyboard piano map: the typed character ->
/// semitone offset from the current base octave. Two rows span ~two octaves
/// (the lower ZXCV… row + the upper QWERTY… row).
const _kKeyToSemitone = <String, int>{
  // Lower octave.
  'z': 0, 's': 1, 'x': 2, 'd': 3, 'c': 4, 'v': 5,
  'g': 6, 'b': 7, 'h': 8, 'n': 9, 'j': 10, 'm': 11, ',': 12,
  // Upper octave.
  'q': 12, '2': 13, 'w': 14, '3': 15, 'e': 16, 'r': 17,
  '5': 18, 't': 19, '6': 20, 'y': 21, '7': 22, 'u': 23, 'i': 24,
};

class AdvancedTrackerScreen extends StatefulWidget {
  const AdvancedTrackerScreen({super.key});

  @override
  State<AdvancedTrackerScreen> createState() => _AdvancedTrackerScreenState();
}

/// Test handle onto the running screen (the state class is private) — mirrors
/// [TrackerTester] on the Beginner screen.
@visibleForTesting
abstract interface class AdvancedTrackerTester {
  int get channelCount;
  int get rows;
  int get noteCount;
  bool get isPlaying;
  bool get isSongPlaying;
  bool get isPaused;
  int get cursorChannel;
  int get cursorRow;
  int get octave;
  int get patternCount;
  int get currentPattern;
  int get orderLength;

  /// Place [midi] at [channel]/[row] (chromatic, no snapping).
  void setNote(int channel, int row, int midi);
  void clearNote(int channel, int row);
  void setRows(int rows);
  void addTrack();
  void removeTrack(int channel);
  void togglePlay();

  /// Move the edit cursor and type a piano key ('z'..'m', 'q'..'i') at it.
  void moveCursor(int channel, int row);
  void typeKey(String character);
  void setChannelInstrument(int channel, String instrumentId);

  /// Arrangement: patterns + order list + song playback.
  void addPattern({bool clone});
  void selectPattern(int index);
  void addToOrder(int patternIndex);
  void playSong();

  /// Transport.
  void stop();
  void back();
  void forward();

  /// Mute / solo.
  bool isMuted(int channel);
  bool isSoloed(int channel);
  void toggleMute(int channel);
  void toggleSolo(int channel);

  /// Import a module (.mod/.s3m/.xm/.it) from raw [bytes]; save to the Song Book.
  void importModuleBytes(Uint8List bytes);
  bool debugSaveToSongBook(UserSongsService songs);

  /// Export the whole song as MIDI / MusicXML bytes (null when nothing pitched).
  Uint8List? debugExportMidi();
  String? debugExportMusicXml();

  /// Assign a recorded/edited [raw] clip (with voice [fx]) to [channel] — the
  /// device-free path onto the sample editor (the mic is device-only).
  void injectRecording(int channel, Float64List raw, VoiceEffect fx);

  /// Undo / redo of pattern cell edits.
  bool get canUndo;
  bool get canRedo;
  void undo();
  void redo();

  /// FT2 feel: live record (jam at the playhead) + block interpolate.
  bool get isRecording;
  void toggleRecord();
  void interpolateBlock();

  /// Block editing (copy/cut/paste/paste-mix/transpose over a marked rectangle).
  bool get hasSelection;
  void selectTrack();
  void selectWholePattern();
  void copyBlock();
  void cutBlock();
  void pasteBlock({bool mix});
  void clearBlock();
  void transposeBlock(int semitones);
  void unmark();
}

class _AdvancedTrackerScreenState extends State<AdvancedTrackerScreen>
    with SingleTickerProviderStateMixin
    implements AdvancedTrackerTester {
  // Non-final so a module import can swap in a whole new document.
  TrackerSong _song = TrackerSong();
  final _loop = GaplessLoopPlayer();
  final _recorder = VoiceClipRecorder();
  final _focus = FocusNode();

  /// The musical clock — playback phase derives from it, never the player, so an
  /// edit re-enters the loop in phase.
  final _clock = Stopwatch();
  late final Ticker _ticker;

  /// The sounding row (0-based), or -1 when stopped. Drives the playhead without
  /// a full rebuild.
  final _row = ValueNotifier<int>(-1);

  /// Which order-list position is sounding in song mode (else -1).
  final _playingOrder = ValueNotifier<int>(-1);

  /// Per-channel VU levels (0..1), updated each frame while playing.
  final _levels = ValueNotifier<List<double>>(const []);

  /// True while playing the whole arrangement (the order list) rather than
  /// looping the current pattern.
  bool _songMode = false;

  /// Paused (playhead + audio frozen in place, resumable).
  bool _paused = false;

  /// Whether playback loops at the end (else it stops on the first wrap).
  bool _loopOn = true;

  /// Added to the stopwatch so a seek can jump the transport position without a
  /// settable Stopwatch. Reset on stop/play-from-top.
  int _baseMs = 0;

  int get _elapsedMs => _clock.elapsedMilliseconds + _baseMs;

  /// The edit cursor — keyboard and on-screen piano enter notes here.
  int _cursorChannel = 0;
  int _cursorRow = 0;

  /// Block selection anchor (the other corner is the cursor). Null = no block.
  int? _anchorChannel;
  int? _anchorRow;

  /// Touch "mark" mode: while on, tapping a cell EXTENDS the selection rather
  /// than moving the cursor freely.
  bool _marking = false;

  /// The copied block (row-major), for paste / paste-mix.
  List<List<TrackerCell>>? _clipboard;

  bool get _hasSelection => _anchorChannel != null && _anchorRow != null;

  /// Keyboard/piano entry state.
  int _octave = 4;
  int _editStep = 1;
  _NoteEntry _entryMode = _NoteEntry.pianoKeys;

  /// FT2-style live record: while ON and playing, notes land at the SOUNDING row
  /// (the playhead) instead of the edit cursor — jam straight into the pattern.
  bool _recording = false;

  /// Which sub-column the cursor edits in-grid (FT2 note/vol/fx columns). Typing
  /// hex into vol/fx edits that column directly; Tab / ←→ move between fields.
  _CellField _field = _CellField.note;

  /// The number of rows between highlighted "beat" lines in the grid (FT2's
  /// row-highlight spacing; default = the beat, i.e. stepsPerBeat).
  int? _highlightEvery;

  /// Pending state for note-name entry ("F" then "2"): the note's semitone and
  /// whether a sharp was typed, awaiting the octave digit. Null = nothing armed.
  int? _pendingSemi;
  bool _pendingSharp = false;

  /// Show the computer-key hints near the on-screen piano.
  bool _showKeyHints = false;

  /// Undo/redo of pattern CELL edits — each entry is a deep snapshot of the
  /// current pattern's cells. Structural changes (add/remove track, set length,
  /// switch pattern, import) clear the history (a snapshot restores cells only
  /// at a fixed channel/row shape).
  final _undoStack = <List<List<TrackerCell>>>[];
  final _redoStack = <List<List<TrackerCell>>>[];
  static const _maxUndo = 80;

  final _vScroll = ScrollController();
  // The on-screen piano sweeps C1..~C7; start scrolled to around C3.
  static const _pianoStartMidi = 24; // C1
  static const _pianoWhiteKeys = 42; // C1..~A6
  static const _pianoKeyWidth = 40.0;
  final _pianoScroll =
      ScrollController(initialScrollOffset: 14 * _pianoKeyWidth);
  int _lastFollowedRow = -1;

  static const _rowNumWidth = 44.0;
  static const _cellWidth = 74.0;
  static const _rowHeight = 30.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (_paused) return; // freeze the playhead where it is
      if (!_clock.isRunning) {
        if (_row.value != -1) _row.value = -1;
        if (_playingOrder.value != -1) _playingOrder.value = -1;
        if (_levels.value.isNotEmpty) _levels.value = const [];
        return;
      }
      final t = _song.timing;
      int posInPattern;
      if (_songMode && _song.songTotalMs > 0) {
        final elapsed = _elapsedMs;
        // Loop off: stop at the end instead of wrapping.
        if (!_loopOn && elapsed >= _song.songTotalMs) {
          _stop();
          return;
        }
        final pos = elapsed % _song.songTotalMs;
        _playingOrder.value = pos ~/ t.totalMs;
        posInPattern = pos % t.totalMs;
        final step = posInPattern ~/ t.stepMs;
        if (step != _row.value) _row.value = step;
      } else {
        if (_playingOrder.value != -1) _playingOrder.value = -1;
        posInPattern = _elapsedMs % t.totalMs;
        final step = posInPattern ~/ t.stepMs;
        if (step != _row.value) {
          _row.value = step;
          _followPlayhead(step);
        }
      }
      _updateLevels(posInPattern);
    })
      ..start();
    // Optional onboarding — shows once on first entry (and via the "?" button).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        maybeShowTutorial(context, 'tracker_advanced', advancedTrackerPrimer);
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _row.dispose();
    _playingOrder.dispose();
    _levels.dispose();
    _vScroll.dispose();
    _pianoScroll.dispose();
    _focus.dispose();
    _loop.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // --- AdvancedTrackerTester ---
  @override
  int get channelCount => _song.channelCount;
  @override
  int get rows => _song.rows;
  @override
  // Reads the engine's LIVE cells (the working copy of the current pattern) —
  // the pattern snapshot only catches up on syncCurrent().
  int get noteCount => _song.engine.channels
      .fold(0, (n, c) => n + c.cells.where((cell) => !cell.isEmpty).length);
  @override
  bool get isPlaying => _clock.isRunning;
  @override
  int get cursorChannel => _cursorChannel;
  @override
  int get cursorRow => _cursorRow;
  @override
  int get octave => _octave;
  @override
  void setNote(int channel, int row, int midi) =>
      _setCell(channel, row, TrackerCell(midi: midi));
  @override
  void clearNote(int channel, int row) =>
      _setCell(channel, row, TrackerCell.empty);
  @override
  void setRows(int rows) {
    _clearUndo();
    setState(() {
      _song.setRows(rows);
      if (_cursorRow >= rows) _cursorRow = rows - 1;
    });
    _syncPlayback();
  }

  @override
  void addTrack() {
    _clearUndo();
    setState(_song.addChannel);
    _syncPlayback();
  }

  @override
  void removeTrack(int channel) {
    _clearUndo();
    setState(() {
      _song.removeChannel(channel);
      if (_cursorChannel >= _song.channelCount) {
        _cursorChannel = _song.channelCount - 1;
      }
    });
    _syncPlayback();
  }

  @override
  void togglePlay() => _togglePlay();
  @override
  void moveCursor(int channel, int row) {
    setState(() {
      _cursorChannel = channel.clamp(0, _song.channelCount - 1);
      _cursorRow = row.clamp(0, _song.rows - 1);
    });
    _ensureCursorVisible();
  }

  @override
  void typeKey(String character) => _typeKey(character);
  @override
  void setChannelInstrument(int channel, String instrumentId) {
    final opt = kTrackerInstruments.firstWhere(
      (o) => o.id == instrumentId,
      orElse: () => kTrackerInstruments.first,
    );
    setState(() => _song.setChannelInstrument(channel, opt.build()));
    _syncPlayback();
  }

  @override
  bool get isSongPlaying => _clock.isRunning && _songMode;
  @override
  bool get isPaused => _paused;
  @override
  void stop() => _stop();
  @override
  void back() => _step(-1);
  @override
  void forward() => _step(1);
  @override
  int get patternCount => _song.patterns.length;
  @override
  int get currentPattern => _song.currentIndex;
  @override
  int get orderLength => _song.order.length;
  @override
  void addPattern({bool clone = false}) {
    _clearUndo();
    setState(() {
      final i = _song.addPattern(cloneCurrent: clone);
      _song.selectPattern(i);
      _cursorRow = 0;
    });
    _syncPlayback();
  }

  @override
  void selectPattern(int index) {
    _clearUndo();
    setState(() {
      _song.selectPattern(index);
      if (_cursorRow >= _song.rows) _cursorRow = _song.rows - 1;
    });
    _syncPlayback();
  }

  @override
  void addToOrder(int patternIndex) {
    setState(() => _song.addToOrder(patternIndex));
    _syncPlayback();
  }

  @override
  void playSong() => _playSong();

  void _addEmptyPattern() => addPattern();
  void _clonePattern() => addPattern(clone: true);

  // --- Editing ---

  void _setCell(int channel, int row, TrackerCell cell) {
    _pushUndo();
    setState(() => _song.engine.setCell(channel, row, cell));
    _syncPlayback();
  }

  void _clearAll() {
    _pushUndo();
    setState(_song.engine.clearAll);
    _syncPlayback();
  }

  Future<void> _confirmClearAll() async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.trackerClear),
        content: Text(l10n.trackerClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.trackerCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.trackerClear),
          ),
        ],
      ),
    );
    if (ok ?? false) _clearAll();
  }

  // --- Undo / redo (pattern cell edits) ----------------------------------

  bool get _canUndo => _undoStack.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty;

  /// Snapshot the current pattern's cells before a cell edit.
  void _pushUndo() {
    _undoStack.add(_song.engine.exportCells());
    if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  /// Drop the history — after a structural change a snapshot can't be restored.
  void _clearUndo() {
    _undoStack.clear();
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_song.engine.exportCells());
    final snap = _undoStack.removeLast();
    setState(() => _song.engine.importCells(snap));
    _syncPlayback();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_song.engine.exportCells());
    final snap = _redoStack.removeLast();
    setState(() => _song.engine.importCells(snap));
    _syncPlayback();
  }

  /// Scrolls the grid so the edit cursor's row stays on-screen (with a margin)
  /// — called on every cursor move so typing/arrowing never loses the cursor.
  void _ensureCursorVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_vScroll.hasClients) return;
      final pos = _vScroll.position;
      final rowTop = _cursorRow * _rowHeight;
      final rowBottom = rowTop + _rowHeight;
      final viewTop = _vScroll.offset;
      final viewBottom = viewTop + pos.viewportDimension;
      const margin = _rowHeight * 2;
      double? target;
      if (rowTop < viewTop + margin) {
        target = rowTop - margin;
      } else if (rowBottom > viewBottom - margin) {
        target = rowBottom - pos.viewportDimension + margin;
      }
      if (target != null) {
        _vScroll.jumpTo(target.clamp(0.0, pos.maxScrollExtent));
      }
    });
  }

  /// Enters [midi] at the cursor and advances by the edit-step (wrapping). In
  /// live-record mode (playing) it lands at the SOUNDING row instead, preserving
  /// any existing volume/effect on that cell, and doesn't move the edit cursor —
  /// jam straight into the pattern.
  void _enterNoteAtCursor(int midi) {
    _pushUndo();
    if (_recording && _clock.isRunning && _row.value >= 0) {
      final row = _row.value;
      final cur = _song.engine.cellAt(_cursorChannel, row);
      _song.engine.setCell(
        _cursorChannel,
        row,
        TrackerCell(
          midi: midi,
          volume: cur.volume,
          effect: cur.effect,
          fxCmd: cur.fxCmd,
          fxParam: cur.fxParam,
        ),
      );
      setState(() {});
      _syncPlayback();
      return;
    }
    _song.engine.setCell(_cursorChannel, _cursorRow, TrackerCell(midi: midi));
    setState(() => _cursorRow = (_cursorRow + _editStep) % _song.rows);
    _ensureCursorVisible();
    _syncPlayback();
  }

  void _clearAtCursorAndAdvance() {
    _pushUndo();
    _song.engine.clearCell(_cursorChannel, _cursorRow);
    setState(() => _cursorRow = (_cursorRow + _editStep) % _song.rows);
    _ensureCursorVisible();
    _syncPlayback();
  }

  // --- Block / selection editing (classic tracker block ops) -------------

  /// Move the cursor and drop any selection (a plain move / click).
  void _moveCursorClearing(int channel, int row) {
    setState(() {
      _cursorChannel = channel.clamp(0, _song.channelCount - 1);
      _cursorRow = row.clamp(0, _song.rows - 1);
      _anchorChannel = null;
      _anchorRow = null;
    });
    _ensureCursorVisible();
  }

  /// Extend the selection to (channel,row): arm the anchor at the current cursor
  /// if none, then move the cursor to the new corner.
  void _extendTo(int channel, int row) {
    setState(() {
      _anchorChannel ??= _cursorChannel;
      _anchorRow ??= _cursorRow;
      _cursorChannel = channel.clamp(0, _song.channelCount - 1);
      _cursorRow = row.clamp(0, _song.rows - 1);
    });
    _ensureCursorVisible();
  }

  void _unmark() => setState(() {
        _anchorChannel = null;
        _anchorRow = null;
        _marking = false;
      });

  /// The selection rectangle, or the single cursor cell when nothing is marked.
  ({int cLo, int cHi, int rLo, int rHi}) get _selRect {
    final ac = _anchorChannel ?? _cursorChannel;
    final ar = _anchorRow ?? _cursorRow;
    return (
      cLo: ac < _cursorChannel ? ac : _cursorChannel,
      cHi: ac > _cursorChannel ? ac : _cursorChannel,
      rLo: ar < _cursorRow ? ar : _cursorRow,
      rHi: ar > _cursorRow ? ar : _cursorRow,
    );
  }

  bool _inSelection(int channel, int row) {
    if (!_hasSelection) return false;
    final s = _selRect;
    return channel >= s.cLo && channel <= s.cHi && row >= s.rLo && row <= s.rHi;
  }

  void _selectTrack() {
    setState(() {
      _anchorChannel = _cursorChannel;
      _anchorRow = 0;
      _cursorRow = _song.rows - 1;
    });
    _ensureCursorVisible();
  }

  void _selectPattern() {
    setState(() {
      _anchorChannel = 0;
      _anchorRow = 0;
      _cursorChannel = _song.channelCount - 1;
      _cursorRow = _song.rows - 1;
    });
    _ensureCursorVisible();
  }

  void _copyBlock() {
    final s = _selRect;
    _clipboard = _song.copyBlock(s.cLo, s.rLo, s.cHi, s.rHi);
  }

  void _cutBlock() {
    final s = _selRect;
    _copyBlock();
    _pushUndo();
    setState(() => _song.clearBlock(s.cLo, s.rLo, s.cHi, s.rHi));
    _syncPlayback();
  }

  void _pasteBlock({bool mix = false}) {
    if (_clipboard == null) return;
    _pushUndo();
    setState(
      () => _song.pasteBlock(_clipboard!, _cursorChannel, _cursorRow, mix: mix),
    );
    _syncPlayback();
  }

  void _clearBlock() {
    final s = _selRect;
    _pushUndo();
    setState(() => _song.clearBlock(s.cLo, s.rLo, s.cHi, s.rHi));
    _syncPlayback();
  }

  void _transposeBlock(int semitones) {
    final s = _selRect;
    _pushUndo();
    setState(() => _song.transposeBlock(s.cLo, s.rLo, s.cHi, s.rHi, semitones));
    _syncPlayback();
  }

  /// FT2 "interpolate": linearly ramps each selected channel's note volumes from
  /// the top selected row to the bottom (a fade/swell over the block).
  void _interpolateBlock() {
    if (!_hasSelection) return;
    final s = _selRect;
    if (s.rHi <= s.rLo) return;
    _pushUndo();
    setState(() {
      for (var c = s.cLo; c <= s.cHi; c++) {
        final v0 = _song.engine.cellAt(c, s.rLo).volume ?? 1.0;
        final v1 = _song.engine.cellAt(c, s.rHi).volume ?? 1.0;
        for (var r = s.rLo; r <= s.rHi; r++) {
          if (_song.engine.cellAt(c, r).midi == null) continue;
          final t = (r - s.rLo) / (s.rHi - s.rLo);
          final v = (v0 + (v1 - v0) * t).clamp(0.0, 1.0);
          _song.engine.setCellVolume(c, r, v >= 0.999 ? null : v);
        }
      }
    });
    _syncPlayback();
  }

  // --- Keyboard ---

  /// Field-cursor editing: Tab cycles note→volume→effect; a hex digit in the
  /// volume field sets the cursor note's volume (16 levels, FT2's volume column).
  /// Returns non-null when the key was part of field editing.
  KeyEventResult? _handleFieldKey(KeyEvent event, LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.tab) {
      const vals = _CellField.values;
      final next = HardwareKeyboard.instance.isShiftPressed
          ? (_field.index - 1 + vals.length) % vals.length
          : (_field.index + 1) % vals.length;
      setState(() => _field = vals[next]);
      return KeyEventResult.handled;
    }
    if (_field == _CellField.volume) {
      final hex = _hexOf(event.character);
      if (hex != null) {
        final cell = _song.engine.cellAt(_cursorChannel, _cursorRow);
        if (cell.midi != null) {
          _pushUndo();
          final v = hex / 15.0;
          setState(
            () => _song.engine.setCellVolume(
              _cursorChannel,
              _cursorRow,
              v >= 0.999 ? null : v,
            ),
          );
          _syncPlayback();
        }
        return KeyEventResult.handled;
      }
      // Swallow other printable keys so they don't become notes in this field.
      if (event.character != null && event.character!.trim().isNotEmpty) {
        return KeyEventResult.handled;
      }
    }
    if (_field == _CellField.effect) {
      // Any printable key opens the effect-column editor for the cursor cell.
      if (event.character != null && event.character!.trim().isNotEmpty) {
        _cellMenu(_cursorChannel, _cursorRow);
        return KeyEventResult.handled;
      }
    }
    return null;
  }

  int? _hexOf(String? ch) {
    if (ch == null || ch.isEmpty) return null;
    final c = ch.toLowerCase().codeUnitAt(0);
    if (c >= 0x30 && c <= 0x39) return c - 0x30; // 0-9
    if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10; // a-f
    return null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final hw = HardwareKeyboard.instance;
    final ctrl = hw.isControlPressed || hw.isMetaPressed;
    final shift = hw.isShiftPressed;
    final alt = hw.isAltPressed;

    // Block ops (Ctrl/⌘ + …). Checked before note entry so Ctrl+C isn't a note.
    if (ctrl) {
      if (key == LogicalKeyboardKey.keyC) {
        _copyBlock();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyX) {
        _cutBlock();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV) {
        _pasteBlock();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyM) {
        _pasteBlock(mix: true);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyA) {
        // First Ctrl+A = the track column; a second widens to the whole pattern.
        if (_hasSelection &&
            _selRect.rLo == 0 &&
            _selRect.rHi == _song.rows - 1 &&
            _selRect.cLo == _cursorChannel &&
            _selRect.cHi == _cursorChannel) {
          _selectPattern();
        } else {
          _selectTrack();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyI) {
        _interpolateBlock();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyZ) {
        _undo();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        _redo();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.escape) {
      _unmark();
      return KeyEventResult.handled;
    }

    // In-grid field cursor (Tab cycles note/vol/fx; hex edits the volume field).
    final fieldResult = _handleFieldKey(event, key);
    if (fieldResult != null) return fieldResult;

    // Alt+Arrows / Alt+PageUp/Down: transpose the block (semitone / octave).
    if (alt) {
      if (key == LogicalKeyboardKey.arrowUp) {
        _transposeBlock(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _transposeBlock(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.pageUp) {
        _transposeBlock(12);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.pageDown) {
        _transposeBlock(-12);
        return KeyEventResult.handled;
      }
    }

    // Navigation. Shift+arrow extends the block; a plain arrow drops it.
    void go(int channel, int row) =>
        shift ? _extendTo(channel, row) : _moveCursorClearing(channel, row);
    if (key == LogicalKeyboardKey.arrowDown) {
      go(_cursorChannel, (_cursorRow + 1) % _song.rows);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      go(_cursorChannel, (_cursorRow - 1 + _song.rows) % _song.rows);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      go((_cursorChannel + 1) % _song.channelCount, _cursorRow);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      go(
        (_cursorChannel - 1 + _song.channelCount) % _song.channelCount,
        _cursorRow,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (_hasSelection) {
        _clearBlock();
      } else {
        _clearAtCursorAndAdvance();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      setState(() => _octave = (_octave + 1).clamp(0, 8));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      setState(() => _octave = (_octave - 1).clamp(0, 8));
      return KeyEventResult.handled;
    }

    // Note-name mode: a letter (C..B), optional #, then an octave digit.
    if (_entryMode == _NoteEntry.noteNames) {
      final r = _handleNoteNameKey(event);
      if (r != null) return r;
    }

    // Otherwise the classic FT2 piano-map character.
    final ch = event.character?.toLowerCase();
    if (_entryMode == _NoteEntry.pianoKeys && ch != null && _typeKey(ch)) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Types a piano-map character at the cursor; returns true if it mapped.
  bool _typeKey(String character) {
    final semi = _kKeyToSemitone[character.toLowerCase()];
    if (semi == null) return false;
    final midi = ((_octave + 1) * 12 + semi).clamp(0, 127);
    _enterNoteAtCursor(midi);
    return true;
  }

  /// Note-name entry: "F" arms F, "#" makes it sharp, an octave digit commits it
  /// (F #? 2 -> F#2 / F2). Returns null if the key isn't part of this mode.
  KeyEventResult? _handleNoteNameKey(KeyEvent event) {
    final ch = event.character?.toLowerCase();
    if (ch == null) return null;
    if (_kLetterSemitone.containsKey(ch)) {
      setState(() {
        _pendingSemi = _kLetterSemitone[ch];
        _pendingSharp = false;
      });
      return KeyEventResult.handled;
    }
    if (ch == '#' || ch == '+') {
      if (_pendingSemi != null) setState(() => _pendingSharp = true);
      return KeyEventResult.handled;
    }
    if (ch.length == 1 &&
        ch.codeUnitAt(0) >= 0x30 &&
        ch.codeUnitAt(0) <= 0x39) {
      if (_pendingSemi != null) {
        final octave = int.parse(ch);
        final midi =
            ((octave + 1) * 12 + _pendingSemi! + (_pendingSharp ? 1 : 0))
                .clamp(0, 127);
        _enterNoteAtCursor(midi);
        setState(() {
          _pendingSemi = null;
          _pendingSharp = false;
        });
      }
      return KeyEventResult.handled;
    }
    return null;
  }

  /// The armed note-name entry as a label ("F#…"), or empty when nothing armed.
  String get _pendingLabel => _pendingSemi == null
      ? ''
      : '${_kNoteNames[(_pendingSemi! + (_pendingSharp ? 1 : 0)) % 12]}…';

  // --- Transport (Play / Pause / Stop / Back / Forward — real-tracker set) ---

  /// The FAB / space-bar action: play from stopped, pause when playing, resume
  /// when paused.
  void _togglePlay() {
    if (_paused) {
      _resume();
    } else if (_clock.isRunning) {
      _pause();
    } else {
      _playPattern();
    }
  }

  void _pause() {
    _clock.stop();
    _loop.pause();
    setState(() => _paused = true);
  }

  void _resume() {
    _clock.start();
    _loop.resume();
    setState(() => _paused = false);
  }

  void _stop() {
    _clock
      ..stop()
      ..reset();
    _loop.stop();
    _baseMs = 0;
    _paused = false;
    _row.value = -1;
    _playingOrder.value = -1;
    setState(() => _songMode = false);
  }

  /// Loop the current pattern.
  void _playPattern() {
    _songMode = false;
    _paused = false;
    _baseMs = 0;
    _clock
      ..reset()
      ..start();
    _syncPlayback();
    setState(() {});
  }

  /// Play the whole arrangement (the order list) back to back.
  void _playSong() {
    _song.syncCurrent();
    _songMode = true;
    _paused = false;
    _baseMs = 0;
    _clock
      ..reset()
      ..start();
    _syncPlayback();
    setState(() {});
  }

  /// Back / Forward. While a song plays, seek to the prev/next order position;
  /// otherwise move the edit selection to the prev/next pattern (wrapping).
  void _step(int delta) {
    if (_songMode && _clock.isRunning) {
      _seekOrder(delta);
    } else {
      final n = _song.patterns.length;
      selectPattern((_song.currentIndex + delta + n) % n);
    }
  }

  void _seekOrder(int delta) {
    if (_song.order.isEmpty) return;
    final from = _playingOrder.value < 0 ? 0 : _playingOrder.value;
    final target = (from + delta).clamp(0, _song.order.length - 1);
    _baseMs = _song.patternStartMs(target);
    _paused = false;
    _clock
      ..reset()
      ..start();
    _syncPlayback();
    setState(() {});
  }

  /// Swaps/stops the looping mix to match the current pattern (or the whole
  /// song in song mode), keeping the musical phase so an edit never resets the
  /// beat.
  void _syncPlayback() {
    if (!_clock.isRunning) return;
    final anyNote = _song.engine.channels.any((c) => c.hasAnyNote) ||
        _song.patterns.any((p) => p.hasAnyNote);
    if (!anyNote) {
      _loop.stop();
      return;
    }
    if (!context.read<AudioService>().soundOn) return; // master mute
    final wav =
        _songMode ? _song.renderSongWav() : _song.renderCurrentPatternWav();
    final total = _songMode ? _song.songTotalMs : _song.timing.totalMs;
    final position = Duration(
      milliseconds: total > 0 ? _elapsedMs % total : 0,
    );
    _loop.playLoop(wav, position: position);
  }

  /// Reads each channel's RMS at the current in-pattern position for the VU
  /// meters (a ~1/30 s window). Cheap — the stems are already cached.
  void _updateLevels(int posInPatternMs) {
    final startSample = (posInPatternMs * 44100) ~/ 1000;
    const window = 1470; // ~33 ms at 44.1 kHz
    final out = List<double>.filled(_song.channelCount, 0);
    for (var c = 0; c < _song.channelCount; c++) {
      // sqrt-scaled so quiet notes still show; clamp to the meter range.
      final rms = _song.engine.channelRms(c, startSample, window);
      out[c] = (rms * 3.0).clamp(0.0, 1.0);
    }
    _levels.value = out;
  }

  void _followPlayhead(int step) {
    if (!_vScroll.hasClients || step == _lastFollowedRow) return;
    _lastFollowedRow = step;
    final target = (step * _rowHeight) - 120;
    final max = _vScroll.position.maxScrollExtent;
    _vScroll.jumpTo(target.clamp(0.0, max));
  }

  // --- Mixer / instrument panel (per-track instrument + gain + mute/solo) ---

  void _showMixer(AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l10n.trackerMixer,
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: Text(l10n.trackerAddTrack),
                      onPressed: () {
                        addTrack();
                        setSheet(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _song.channelCount,
                    itemBuilder: (ctx, c) => _mixerRow(ctx, l10n, c, setSheet),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mixerRow(
    BuildContext ctx,
    AppLocalizations l10n,
    int c,
    void Function(void Function()) setSheet,
  ) {
    final ch = _song.channels[c];
    final scheme = Theme.of(ctx).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text('${c + 1}')),
          // Instrument (tap to change).
          SizedBox(
            width: 96,
            child: OutlinedButton(
              onPressed: () async {
                await _pickInstrument(c);
                setSheet(() {});
              },
              child: Text(
                _instrumentLabel(ch.instrument.id),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Gain slider.
          Expanded(
            child: Slider(
              value: ch.gain.clamp(0.0, 1.2),
              max: 1.2,
              onChanged: (v) {
                _song.setChannelGain(c, v);
                _syncPlayback();
                setSheet(() {});
              },
            ),
          ),
          _headerToggle('M', _song.isMuted(c), scheme.error, () {
            toggleMute(c);
            setSheet(() {});
          }),
          _headerToggle('S', _song.isSoloed(c), scheme.tertiary, () {
            toggleSolo(c);
            setSheet(() {});
          }),
          IconButton(
            icon: const Icon(Icons.mic, size: 20),
            tooltip: l10n.trackerRecordSample,
            onPressed: () async {
              await _recordSampleSheet(c);
              setSheet(() {});
            },
          ),
          if (_song.channelCount > 1)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () {
                removeTrack(c);
                setSheet(() {});
              },
            ),
        ],
      ),
    );
  }

  // --- Sample / voice editor (record → effect/trim/normalize → assign) ------

  /// Builds a [SampleInstrument] from raw PCM with the chosen non-destructive
  /// edits (each returns a new buffer), then the voice effect.
  SampleInstrument _sampleFrom(
    Float64List raw, {
    VoiceEffect fx = VoiceEffect.normal,
    double stretch = 1.0,
    bool trim = false,
    bool normalize = false,
    bool reverse = false,
  }) {
    var pcm = raw;
    if (stretch != 1.0 && pcm.isNotEmpty) pcm = timeStretch(pcm, stretch);
    if (trim && pcm.isNotEmpty) pcm = trimSilence(pcm);
    if (normalize && pcm.isNotEmpty) pcm = normalizePcm(pcm);
    if (reverse && pcm.isNotEmpty) pcm = reversePcm(pcm);
    return SampleInstrument.recorded('rec', pcm, fx);
  }

  void _assignSample(int channel, SampleInstrument inst) {
    setState(() => _song.setChannelInstrument(channel, inst));
    _syncPlayback();
  }

  @override
  void injectRecording(int channel, Float64List raw, VoiceEffect fx) =>
      _assignSample(channel, _sampleFrom(raw, fx: fx));

  @override
  bool get canUndo => _canUndo;
  @override
  bool get canRedo => _canRedo;
  @override
  void undo() => _undo();
  @override
  void redo() => _redo();
  @override
  bool get isRecording => _recording;
  @override
  void toggleRecord() => setState(() => _recording = !_recording);
  @override
  void interpolateBlock() => _interpolateBlock();

  static const _voiceIcons = <VoiceEffect, IconData>{
    VoiceEffect.normal: Icons.person,
    VoiceEffect.chipmunk: Icons.pets,
    VoiceEffect.monster: Icons.sentiment_very_dissatisfied,
    VoiceEffect.deep: Icons.waves,
    VoiceEffect.robot: Icons.smart_toy,
    VoiceEffect.alien: Icons.blur_on,
    VoiceEffect.cyborg: Icons.memory,
    VoiceEffect.radio: Icons.radio,
    VoiceEffect.demon: Icons.local_fire_department,
  };

  Future<void> _recordSampleSheet(int channel) async {
    final l10n = AppLocalizations.of(context)!;
    Float64List? clip;
    var recording = false;
    var fx = VoiceEffect.normal;
    var stretch = 1.0;
    var trim = false, normalize = false, reverse = false;
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l10n.trackerRecordSample} → ${_song.channels[channel].id}',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: Icon(recording ? Icons.mic : Icons.fiber_manual_record),
                  label: Text(
                    recording ? l10n.trackerRecording : l10n.trackerRecord,
                  ),
                  onPressed: recording
                      ? null
                      : () async {
                          setSheet(() {
                            recording = true;
                            error = null;
                          });
                          try {
                            clip = await _recorder.record();
                          } catch (_) {
                            error = l10n.trackerRecordFailed;
                          } finally {
                            if (ctx.mounted) setSheet(() => recording = false);
                          }
                        },
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  ),
                if (clip != null && clip!.isNotEmpty) ...[
                  const Divider(height: 20),
                  Text(l10n.trackerVoiceNormal),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final v in VoiceEffect.values)
                        ChoiceChip(
                          avatar: Icon(_voiceIcons[v], size: 18),
                          label: Text(_voiceLabel(l10n, v)),
                          selected: fx == v,
                          onSelected: (_) => setSheet(() => fx = v),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final (label, s) in [
                        (l10n.trackerSpeedSlow, 1.5),
                        (l10n.trackerSpeedNormal, 1.0),
                        (l10n.trackerSpeedFast, 0.6),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: stretch == s,
                          onSelected: (_) => setSheet(() => stretch = s),
                        ),
                      FilterChip(
                        label: Text(l10n.trackerSampleTrim),
                        selected: trim,
                        onSelected: (v) => setSheet(() => trim = v),
                      ),
                      FilterChip(
                        label: Text(l10n.trackerSampleNormalize),
                        selected: normalize,
                        onSelected: (v) => setSheet(() => normalize = v),
                      ),
                      FilterChip(
                        label: Text(l10n.trackerSampleReverse),
                        selected: reverse,
                        onSelected: (v) => setSheet(() => reverse = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () {
                        _assignSample(
                          channel,
                          _sampleFrom(
                            clip!,
                            fx: fx,
                            stretch: stretch,
                            trim: trim,
                            normalize: normalize,
                            reverse: reverse,
                          ),
                        );
                        Navigator.of(ctx).pop();
                      },
                      child: Text(l10n.trackerAssignSample),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _voiceLabel(AppLocalizations l10n, VoiceEffect v) => switch (v) {
        VoiceEffect.normal => l10n.trackerVoiceNormal,
        VoiceEffect.chipmunk => l10n.trackerVoiceChipmunk,
        VoiceEffect.monster => l10n.trackerVoiceMonster,
        VoiceEffect.deep => l10n.trackerVoiceDeep,
        VoiceEffect.robot => l10n.trackerVoiceRobot,
        VoiceEffect.alien => l10n.trackerVoiceAlien,
        VoiceEffect.cyborg => l10n.trackerVoiceCyborg,
        VoiceEffect.radio => l10n.trackerVoiceRadio,
        VoiceEffect.demon => l10n.trackerVoiceDemon,
      };

  // --- Per-track instrument picker ---

  Future<void> _pickInstrument(int channel) async {
    final l10n = AppLocalizations.of(context)!;
    final currentId = _song.channels[channel].instrument.id;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l10n.trackerChangeInstrument} — ${_song.channels[channel].id}',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final opt in kTrackerInstruments)
                    ChoiceChip(
                      label: Text(_instrumentLabel(opt.id)),
                      selected: opt.id == currentId,
                      onSelected: (_) {
                        setChannelInstrument(channel, opt.id);
                        Navigator.of(ctx).pop();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _instrumentLabel(String id) => switch (id) {
        'piano' => 'Piano',
        'cello' => 'Cello',
        'flute' => 'Flute',
        'musicBox' => 'Music box',
        _ => id, // sfxr presets keep their short id (zap/blip/laser/…)
      };

  // --- Per-cell volume + effect menu (long-press) ---

  Future<void> _cellMenu(int channel, int row) async {
    final l10n = AppLocalizations.of(context)!;
    final cell = _song.engine.cellAt(channel, row);
    if (cell.isEmpty) {
      // Empty cell: let a long-press open the note picker (touch shortcut).
      moveCursor(channel, row);
      _focus.requestFocus();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${trackerNoteName(cell.midi!)} · '
                '${_song.channels[channel].id}',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(l10n.trackerSoftNote),
              Row(
                children: [
                  for (final (label, vol) in const [
                    ('ff', 1.0),
                    ('mf', 0.66),
                    ('p', 0.4),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: (cell.volume ?? 1.0) == vol,
                        onSelected: (_) {
                          setState(
                            () => _song.engine.setCellVolume(
                              channel,
                              row,
                              vol == 1.0 ? null : vol,
                            ),
                          );
                          _syncPlayback();
                          Navigator.of(ctx).pop();
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(l10n.trackerEffect),
              Wrap(
                spacing: 8,
                children: [
                  for (final fx in TrackerEffect.values)
                    ChoiceChip(
                      label: Text(_effectLabel(l10n, fx)),
                      selected: cell.effect == fx,
                      onSelected: (_) {
                        setState(
                          () => _song.engine.setCellEffect(channel, row, fx),
                        );
                        _syncPlayback();
                        Navigator.of(ctx).pop();
                      },
                    ),
                ],
              ),
              const Divider(height: 20),
              // Classic MOD effect COLUMN (Cxx set-volume, Axy volume-slide);
              // more commands land as the replayer grows. Applies live.
              _CommandEditor(
                l10n: l10n,
                initialCmd: cell.fxCmd,
                initialParam: cell.fxParam,
                onChanged: (cmd, param) =>
                    _setCellCommand(channel, row, cmd, param),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.backspace_outlined),
                  label: Text(l10n.trackerClear),
                  onPressed: () {
                    clearNote(channel, row);
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setCellCommand(int channel, int row, int cmd, int param) {
    _pushUndo();
    final cur = _song.engine.cellAt(channel, row);
    setState(
      () => _song.engine.setCell(
        channel,
        row,
        TrackerCell(
          midi: cur.midi,
          volume: cur.volume,
          effect: cur.effect,
          fxCmd: cmd,
          fxParam: param,
        ),
      ),
    );
    _syncPlayback();
  }

  String _effectLabel(AppLocalizations l10n, TrackerEffect fx) => switch (fx) {
        TrackerEffect.none => l10n.trackerEffectNone,
        TrackerEffect.arpeggio => l10n.trackerEffectArp,
        TrackerEffect.vibrato => l10n.trackerEffectVibrato,
        TrackerEffect.slideUp => l10n.trackerEffectSlideUp,
        TrackerEffect.slideDown => l10n.trackerEffectSlideDown,
      };

  void _toBeginner() => Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TrackerScreen()),
      );

  // --- Import / export (reuses the existing module + notation bridges) ---

  void _replaceSong(TrackerSong song) {
    _stop();
    _clearUndo();
    setState(() {
      _song = song;
      _cursorChannel = 0;
      _cursorRow = 0;
    });
  }

  @override
  void importModuleBytes(Uint8List bytes) =>
      _replaceSong(songFromModuleBytes(bytes));

  Future<void> _importModule() async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context)!.trackerModFailed;
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Module',
            extensions: ['mod', 'xm', 's3m', 'it'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      importModuleBytes(await file.readAsBytes());
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  /// The WHOLE SONG's pitched channels as one multi-part score: each channel's
  /// cells are concatenated across the order list (not just the current pattern
  /// — that was the "place some notes first" bug when notes lived on another
  /// pattern). Drums/empty channels are skipped. Null = nothing pitched.
  ({List<TrackerChannel> channels, TrackerTiming timing})? _songAsChannels() {
    _song.syncCurrent();
    final chCount = _song.channelCount;
    final rows = _song.rows;
    final totalRows = rows * _song.order.length;
    if (totalRows == 0) return null;
    final combined = <List<TrackerCell>>[
      for (var c = 0; c < chCount; c++) <TrackerCell>[],
    ];
    for (final o in _song.order) {
      final pat = _song.patterns[o];
      for (var c = 0; c < chCount; c++) {
        combined[c].addAll(pat.cells[c]);
      }
    }
    final channels = [
      for (var c = 0; c < chCount; c++)
        TrackerChannel(
          id: _song.channels[c].id,
          instrument: _song.channels[c].instrument,
          rows: totalRows,
          cells: combined[c],
        ),
    ];
    return (channels: channels, timing: _song.timing.copyWith(rows: totalRows));
  }

  /// Writes the whole song's pitched channels to the Song Book as multi-part
  /// MusicXML. Returns false when nothing pitched is placed anywhere.
  bool _writeToSongBook(UserSongsService songs, String title) {
    final src = _songAsChannels();
    if (src == null) return false;
    final parts = trackerToScoreParts(src.channels, src.timing);
    if (parts.isEmpty) return false;
    final names = [
      for (final c in src.channels)
        if (c.hasAnyNote && c.instrument is! PercussionInstrument)
          c.instrument.id,
    ];
    songs.addSong(
      ImportedSong(
        id: 'tracker-adv-${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        musicXml: multiPartToMusicXml(MultiPartScore(parts), partNames: names),
      ),
    );
    return true;
  }

  @override
  bool debugSaveToSongBook(UserSongsService songs) => _writeToSongBook(
        songs,
        AppLocalizations.of(context)!.trackerAdvancedTitle,
      );

  @override
  Uint8List? debugExportMidi() {
    final mp = _songMultiPart();
    return mp == null ? null : multiPartToMidi(mp.score);
  }

  @override
  String? debugExportMusicXml() {
    final mp = _songMultiPart();
    return mp == null
        ? null
        : multiPartToMusicXml(mp.score, partNames: mp.names);
  }

  Future<void> _saveToSongBook() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final saved = _writeToSongBook(
      context.read<UserSongsService>(),
      l10n.trackerAdvancedTitle,
    );
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(saved ? l10n.trackerSavedSong : l10n.trackerSaveEmpty),
      ),
    );
  }

  /// The whole song as a multi-part score (+ part names), or null when nothing
  /// pitched is placed. Shared by Save / Export / Open-in-Workshop.
  ({MultiPartScore score, List<String> names})? _songMultiPart() {
    final src = _songAsChannels();
    if (src == null) return null;
    final parts = trackerToScoreParts(src.channels, src.timing);
    if (parts.isEmpty) return null;
    final names = [
      for (final c in src.channels)
        if (c.hasAnyNote && c.instrument is! PercussionInstrument)
          c.instrument.id,
    ];
    return (score: MultiPartScore(parts), names: names);
  }

  Future<void> _saveBytes(
    Uint8List bytes,
    String suggestedName,
    String label,
    List<String> extensions,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: [
          XTypeGroup(label: label, extensions: extensions),
        ],
      );
      if (location == null || !mounted) return;
      await XFile.fromData(bytes, name: suggestedName).saveTo(location.path);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.workshopSavedTo(location.path))),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.trackerModFailed)));
    }
  }

  Future<void> _exportMidi() async {
    final mp = _songMultiPart();
    final l10n = AppLocalizations.of(context)!;
    if (mp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.trackerSaveEmpty)),
      );
      return;
    }
    await _saveBytes(
      multiPartToMidi(mp.score),
      'tracker.mid',
      'MIDI',
      ['mid', 'midi'],
    );
  }

  Future<void> _exportMusicXml() async {
    final mp = _songMultiPart();
    final l10n = AppLocalizations.of(context)!;
    if (mp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.trackerSaveEmpty)),
      );
      return;
    }
    final xml = multiPartToMusicXml(mp.score, partNames: mp.names);
    await _saveBytes(
      Uint8List.fromList(xml.codeUnits),
      'tracker.musicxml',
      'MusicXML',
      ['musicxml', 'xml'],
    );
  }

  /// Open the current song in the Composition (Score) Workshop for staff editing.
  void _openInWorkshop() {
    final mp = _songMultiPart();
    final l10n = AppLocalizations.of(context)!;
    if (mp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.trackerSaveEmpty)),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CompositionWorkshopScreen(
          initialScore: mp.score,
          initialNames: mp.names,
        ),
      ),
    );
  }

  /// Import a score file (MusicXML / MIDI / …) as a new tracker song — one track
  /// per part, chromatic (no pentatonic snap). The reverse of Export/Open.
  Future<void> _importScore() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Score',
            extensions: ['musicxml', 'xml', 'mid', 'midi'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      final name = file.name.toLowerCase();
      final mp = (name.endsWith('.mid') || name.endsWith('.midi'))
          ? multiTrackMidiToMultiPart(bytes)
          : multiPartScoreFromMusicXml(utf8.decode(bytes));
      _replaceSong(_songFromMultiPart(mp));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.trackerModFailed)));
    }
  }

  TrackerSong _songFromMultiPart(MultiPartScore mp) {
    const timing = TrackerTiming(rows: 64);
    final channels = <TrackerChannel>[];
    final cells = <List<TrackerCell>>[];
    for (var p = 0; p < mp.parts.length; p++) {
      final Score part = mp.parts[p];
      final col = scoreToChannels(
        part,
        timing,
        channelCount: 1,
        snapToScale: false,
      ).first;
      channels.add(
        TrackerChannel(
          id: 'part${p + 1}',
          instrument: kTrackerInstruments.first.build(),
          rows: timing.rows,
          cells: col,
        ),
      );
      cells.add(col);
    }
    if (channels.isEmpty) return TrackerSong();
    return TrackerSong.fromParts(
      channels: channels,
      timing: timing,
      patterns: [TrackerPattern(name: '00', cells: cells)],
      order: [0],
    );
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: GameAppBar(
        title: l10n.trackerAdvancedTitle,
        tutorial: advancedTrackerPrimer,
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: l10n.myMelodyUndo,
            onPressed: _canUndo ? _undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: l10n.workshopRedo,
            onPressed: _canRedo ? _redo : null,
          ),
          IconButton(
            icon: const Icon(Icons.child_care),
            tooltip: l10n.trackerModeToBeginner,
            onPressed: _toBeginner,
          ),
          // (Play song lives in the transport row next to Play/Stop.)
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: l10n.trackerMixer,
            onPressed: () => _showMixer(l10n),
          ),
          _blockMenu(l10n),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: l10n.trackerClear,
            onPressed: _confirmClearAll,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'import':
                  _importModule();
                case 'importScore':
                  _importScore();
                case 'saveSong':
                  _saveToSongBook();
                case 'exportMidi':
                  _exportMidi();
                case 'exportXml':
                  _exportMusicXml();
                case 'workshop':
                  _openInWorkshop();
              }
            },
            itemBuilder: (ctx) => [
              _menuRow('import', Icons.library_music, l10n.trackerImportMod),
              _menuRow(
                'importScore',
                Icons.file_open_outlined,
                l10n.trackerImportScore,
              ),
              const PopupMenuDivider(),
              _menuRow(
                'saveSong',
                Icons.bookmark_add_outlined,
                l10n.trackerSaveSong,
              ),
              _menuRow('exportMidi', Icons.piano, l10n.trackerExportMidi),
              _menuRow('exportXml', Icons.description, l10n.trackerExportXml),
              const PopupMenuDivider(),
              _menuRow('workshop', Icons.edit_note, l10n.trackerOpenWorkshop),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: GestureDetector(
            // Tap anywhere on the grid area keeps keyboard focus for entry.
            onTap: _focus.requestFocus,
            behavior: HitTestBehavior.deferToChild,
            child: Column(
              children: [
                _toolbar(l10n),
                _arrangementBar(l10n),
                const Divider(height: 1),
                Expanded(child: _grid(context)),
                const Divider(height: 1),
                _transportBar(l10n),
                _pianoBar(l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The classic block-editing menu (touch-friendly; the same ops have keyboard
  /// shortcuts on desktop — see the ⓘ legend). Mark begin/drag-select, select
  /// track/pattern, copy/cut/paste/paste-mix, transpose, clear, unmark.
  PopupMenuItem<String> _menuRow(String value, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Text(label),
          ],
        ),
      );

  Widget _blockMenu(AppLocalizations l10n) => PopupMenuButton<String>(
        icon: Icon(
          _marking || _hasSelection ? Icons.select_all : Icons.highlight_alt,
        ),
        tooltip: l10n.trackerBlock,
        onSelected: (v) {
          switch (v) {
            case 'mark':
              setState(() {
                _marking = !_marking;
                if (_marking) {
                  _anchorChannel = _cursorChannel;
                  _anchorRow = _cursorRow;
                } else {
                  _unmark();
                }
              });
            case 'track':
              _selectTrack();
            case 'pattern':
              _selectPattern();
            case 'copy':
              _copyBlock();
            case 'cut':
              _cutBlock();
            case 'paste':
              _pasteBlock();
            case 'pasteMix':
              _pasteBlock(mix: true);
            case 'up':
              _transposeBlock(1);
            case 'down':
              _transposeBlock(-1);
            case 'octUp':
              _transposeBlock(12);
            case 'octDown':
              _transposeBlock(-12);
            case 'interp':
              _interpolateBlock();
            case 'clear':
              _clearBlock();
            case 'unmark':
              _unmark();
          }
        },
        itemBuilder: (ctx) => [
          CheckedPopupMenuItem(
            value: 'mark',
            checked: _marking,
            child: Text(l10n.trackerBlockMark),
          ),
          PopupMenuItem(value: 'track', child: Text(l10n.trackerBlockTrack)),
          PopupMenuItem(
            value: 'pattern',
            child: Text(l10n.trackerBlockPattern),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'copy', child: Text(l10n.trackerBlockCopy)),
          PopupMenuItem(value: 'cut', child: Text(l10n.trackerBlockCut)),
          PopupMenuItem(
            enabled: _clipboard != null,
            value: 'paste',
            child: Text(l10n.trackerBlockPaste),
          ),
          PopupMenuItem(
            enabled: _clipboard != null,
            value: 'pasteMix',
            child: Text(l10n.trackerBlockPasteMix),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'up', child: Text(l10n.trackerBlockTransUp)),
          PopupMenuItem(value: 'down', child: Text(l10n.trackerBlockTransDown)),
          PopupMenuItem(value: 'octUp', child: Text(l10n.trackerBlockOctUp)),
          PopupMenuItem(
            value: 'octDown',
            child: Text(l10n.trackerBlockOctDown),
          ),
          PopupMenuItem(value: 'interp', child: Text(l10n.trackerInterpolate)),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'clear', child: Text(l10n.trackerBlockClear)),
          if (_hasSelection)
            PopupMenuItem(
              value: 'unmark',
              child: Text(l10n.trackerBlockUnmark),
            ),
        ],
      );

  /// The classic transport row: Play/Pause · Back · Stop · Forward · Play-song ·
  /// Loop + a position readout — all inline (no floating button over the grid).
  Widget _transportBar(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final playing = _clock.isRunning && !_paused;
    return Container(
      color: scheme.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true, // keep the readout end visible; buttons scroll off left
        child: Row(
          children: [
            IconButton.filledTonal(
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              tooltip: playing ? l10n.trackerPause : l10n.trackerPlay,
              onPressed: _togglePlay,
            ),
            IconButton(
              icon: const Icon(Icons.fiber_manual_record),
              color: _recording ? scheme.error : null,
              tooltip: l10n.trackerRecordLive,
              onPressed: () => setState(() => _recording = !_recording),
            ),
            IconButton(
              icon: const Icon(Icons.skip_previous),
              tooltip: l10n.trackerBack,
              onPressed: _song.patterns.length > 1 || _songMode
                  ? () => _step(-1)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.stop),
              tooltip: l10n.trackerStop,
              onPressed: _clock.isRunning || _paused ? _stop : null,
            ),
            IconButton(
              icon: const Icon(Icons.skip_next),
              tooltip: l10n.trackerForward,
              onPressed: _song.patterns.length > 1 || _songMode
                  ? () => _step(1)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.playlist_play),
              tooltip: l10n.trackerPlaySong,
              onPressed: _playSong,
            ),
            IconButton(
              icon: Icon(_loopOn ? Icons.repeat_on : Icons.repeat),
              tooltip: l10n.trackerLoop,
              color: _loopOn ? scheme.primary : null,
              onPressed: () => setState(() => _loopOn = !_loopOn),
            ),
            const SizedBox(width: 16),
            AnimatedBuilder(
              animation: Listenable.merge([_row, _playingOrder]),
              builder: (context, _) {
                final row = _row.value;
                final rowStr = row < 0 ? '··' : row.toString().padLeft(2, '0');
                final total = _song.rows.toString().padLeft(2, '0');
                final pos = _songMode && _playingOrder.value >= 0
                    ? '${(_playingOrder.value + 1).toString().padLeft(2, '0')}'
                        '/${_song.order.length.toString().padLeft(2, '0')} · '
                    : '';
                return Text(
                  '$pos$rowStr/$total',
                  style: TextStyle(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  /// The pattern selector + order list (the song arrangement).
  Widget _arrangementBar(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // Patterns: which one is being edited (+ add / clone).
          Text('${l10n.trackerPattern}: '),
          Expanded(
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _song.patterns.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: ChoiceChip(
                        label: Text(_song.patterns[i].name),
                        selected: i == _song.currentIndex,
                        onSelected: (_) => selectPattern(i),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 20),
                    tooltip: l10n.trackerPatternNew,
                    onPressed: _addEmptyPattern,
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: l10n.trackerPatternClone,
                    onPressed: _clonePattern,
                  ),
                  if (_song.patterns.length > 1)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: l10n.trackerRemoveTrack,
                      onPressed: () => setState(
                        () => _song.removePattern(_song.currentIndex),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Order list: the play sequence; the sounding entry lights up.
          Text('${l10n.trackerSong}: '),
          Expanded(
            child: SizedBox(
              height: 36,
              child: ValueListenableBuilder<int>(
                valueListenable: _playingOrder,
                builder: (context, playing, _) => ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < _song.order.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: InputChip(
                          label: Text(_song.patterns[_song.order[i]].name),
                          selected: i == playing,
                          onPressed: () => selectPattern(_song.order[i]),
                          onDeleted: () =>
                              setState(() => _song.removeFromOrder(i)),
                        ),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: Text(_song.current.name),
                      onPressed: () => addToOrder(_song.currentIndex),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar(AppLocalizations l10n) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            // Endless length — the direct fix for "stops after 2-3 Takte".
            // (MOD/S3M 64 · IT ≤200 · XM ≤256 · Custom = any.)
            Text('${l10n.trackerLength}: '),
            DropdownButton<int>(
              value: _kLengthOptions.contains(_song.rows) ? _song.rows : -1,
              items: [
                for (final n in _kLengthOptions)
                  DropdownMenuItem(value: n, child: Text('$n')),
                DropdownMenuItem(
                  value: -1,
                  child: Text(
                    _kLengthOptions.contains(_song.rows)
                        ? l10n.trackerCustomLength
                        : '${_song.rows} ✎',
                  ),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                if (v == -1) {
                  _promptCustomLength(l10n);
                } else {
                  setRows(v);
                }
              },
            ),
            const SizedBox(width: 16),
            // Tempo (BPM).
            Text('${l10n.trackerTempo}: '),
            DropdownButton<int>(
              value: _kTempoOptions.contains(_song.timing.tempoBpm)
                  ? _song.timing.tempoBpm
                  : null,
              hint: Text('${_song.timing.tempoBpm}'),
              items: [
                for (final b in _kTempoOptions)
                  DropdownMenuItem(value: b, child: Text('$b')),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() => _song.setTempo(v));
                  _syncPlayback();
                }
              },
            ),
            const SizedBox(width: 16),
            // Endless tracks.
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.trackerAddTrack),
              onPressed: addTrack,
            ),
            const SizedBox(width: 16),
            // Edit-step: rows the cursor auto-advances after each note entry.
            Tooltip(
              message: l10n.trackerEditStepHelp,
              child: Row(
                children: [
                  const Icon(Icons.south, size: 16),
                  const SizedBox(width: 2),
                  Text('${l10n.trackerEditStep}: '),
                  DropdownButton<int>(
                    value: _editStep,
                    items: [
                      for (final n in const [0, 1, 2, 4])
                        DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: (v) => setState(() => _editStep = v ?? 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptCustomLength(AppLocalizations l10n) async {
    final controller = TextEditingController(text: '${_song.rows}');
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.trackerCustomLength),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.trackerCustomLengthPrompt),
          onSubmitted: (t) => Navigator.of(ctx).pop(int.tryParse(t)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.trackerCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(controller.text)),
            child: Text(l10n.trackerOk),
          ),
        ],
      ),
    );
    if (value != null && value > 0) setRows(value.clamp(1, 1024));
  }

  Widget _grid(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stepsPerBeat = _song.timing.stepsPerBeat;
    final gridWidth = _rowNumWidth + _song.channelCount * _cellWidth;

    return Scrollbar(
      controller: _vScroll,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: gridWidth,
          child: Column(
            children: [
              _headerRow(scheme),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: _row,
                  builder: (context, activeRow, _) => ListView.builder(
                    controller: _vScroll,
                    itemExtent: _rowHeight,
                    itemCount: _song.rows,
                    itemBuilder: (context, row) =>
                        _rowWidget(row, activeRow, stepsPerBeat, scheme),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _headerHeight = 56.0;

  Widget _headerRow(ColorScheme scheme) {
    return Container(
      height: _headerHeight,
      color: scheme.surfaceContainerHigh,
      child: Row(
        children: [
          const SizedBox(width: _rowNumWidth),
          for (var c = 0; c < _song.channelCount; c++)
            _channelHeader(c, scheme),
        ],
      ),
    );
  }

  Widget _channelHeader(int c, ColorScheme scheme) {
    final muted = _song.isMuted(c);
    final soloed = _song.isSoloed(c);
    return SizedBox(
      width: _cellWidth,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Instrument name — tap to change the track's instrument.
          InkWell(
            onTap: () => _pickInstrument(c),
            child: Text(
              _song.channels[c].instrument.id,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: muted ? scheme.onSurfaceVariant : scheme.onSurface,
                decoration: muted ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _headerToggle('M', muted, scheme.error, () => toggleMute(c)),
              _headerToggle('S', soloed, scheme.tertiary, () => toggleSolo(c)),
              if (_song.channelCount > 1)
                InkWell(
                  onTap: () => removeTrack(c),
                  child: Icon(
                    Icons.close,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          // VU meter — lights up with the channel's live level during playback.
          _ChannelMeter(levels: _levels, channel: c, muted: muted),
        ],
      ),
    );
  }

  Widget _headerToggle(
    String label,
    bool on,
    Color onColor,
    VoidCallback onTap,
  ) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: on ? onColor : Colors.grey.withValues(alpha: 0.55),
            ),
          ),
        ),
      );

  @override
  bool isMuted(int channel) => _song.isMuted(channel);
  @override
  bool isSoloed(int channel) => _song.isSoloed(channel);

  @override
  void toggleMute(int channel) {
    setState(() => _song.toggleMute(channel));
    _syncPlayback();
  }

  @override
  void toggleSolo(int channel) {
    setState(() => _song.toggleSolo(channel));
    _syncPlayback();
  }

  // Block-editing tester hooks (delegate to the private implementations).
  @override
  bool get hasSelection => _hasSelection;
  @override
  void selectTrack() => _selectTrack();
  @override
  void selectWholePattern() => _selectPattern();
  @override
  void copyBlock() => _copyBlock();
  @override
  void cutBlock() => _cutBlock();
  @override
  void pasteBlock({bool mix = false}) => _pasteBlock(mix: mix);
  @override
  void clearBlock() => _clearBlock();
  @override
  void transposeBlock(int semitones) => _transposeBlock(semitones);
  @override
  void unmark() => _unmark();

  Widget _rowWidget(
    int row,
    int activeRow,
    int stepsPerBeat,
    ColorScheme scheme,
  ) {
    final isActive = row == activeRow;
    final hl = _highlightEvery ?? stepsPerBeat;
    final isBeat = row % hl == 0;
    final isMeasure = row % (hl * 4) == 0;
    final rowBg = isActive
        ? scheme.primaryContainer
        : isMeasure
            ? scheme.surfaceContainerHigh
            : (isBeat ? scheme.surfaceContainerHighest : null);
    return Container(
      height: _rowHeight,
      color: rowBg,
      child: Row(
        children: [
          SizedBox(
            width: _rowNumWidth,
            child: Text(
              row.toString().padLeft(2, '0'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFeatures: const [FontFeature.tabularFigures()],
                fontSize: 12,
                color: isBeat ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: isBeat ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          for (var c = 0; c < _song.channelCount; c++) _cell(c, row, scheme),
        ],
      ),
    );
  }

  Widget _cell(int channel, int row, ColorScheme scheme) {
    final cell = _song.engine.cellAt(channel, row);
    final hasNote = cell.midi != null;
    final isCursor = channel == _cursorChannel && row == _cursorRow;
    final selected = _inSelection(channel, row);
    // note + volume + effect sub-columns (classic tracker cell).
    final note = hasNote ? trackerNoteName(cell.midi!) : '···';
    final vol = hasNote && cell.volume != null && cell.volume != 1.0
        ? (cell.volume! * 99).round().toString().padLeft(2, '0')
        : '··';
    // Effect column: the classic hex command (e.g. C20/A04) when present, else
    // the legacy arp/vibrato/slide letter, else a dot.
    final fx = cell.hasCommand
        ? _commandHex(cell)
        : (hasNote && cell.effect != TrackerEffect.none
            ? _effectCode(cell.effect)
            : '·');
    return GestureDetector(
      onTap: () {
        if (_marking) {
          _extendTo(channel, row);
        } else {
          _moveCursorClearing(channel, row);
        }
        _focus.requestFocus();
      },
      onLongPress: () => _cellMenu(channel, row),
      child: Container(
        width: _cellWidth,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? scheme.secondaryContainer.withValues(alpha: 0.6)
              : null,
          border: Border.all(
            color: isCursor ? scheme.primary : scheme.outlineVariant,
            width: isCursor ? 2 : 0.5,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                note,
                style: TextStyle(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontSize: 14,
                  color: hasNote
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  fontWeight: hasNote ? FontWeight.w600 : FontWeight.w400,
                  decoration: isCursor && _field == _CellField.note
                      ? TextDecoration.underline
                      : null,
                  decorationColor: scheme.primary,
                  decorationThickness: 2,
                ),
              ),
              const SizedBox(width: 4),
              // Volume + effect sub-columns; the active field underlines when the
              // cell holds the cursor (the FT2 column cursor).
              Text(
                vol,
                style: _subColStyle(
                  scheme,
                  isCursor && _field == _CellField.volume,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                fx,
                style: _subColStyle(
                  scheme,
                  isCursor && _field == _CellField.effect,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _subColStyle(ColorScheme scheme, bool active) => TextStyle(
        fontFeatures: const [FontFeature.tabularFigures()],
        fontSize: 10,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
        decoration: active ? TextDecoration.underline : null,
        decorationColor: scheme.primary,
        decorationThickness: 2,
      );

  /// The effect column as a 3-char hex code (command nibble + param byte).
  static String _commandHex(TrackerCell c) {
    final cmd = c.fxCmd.toRadixString(16).toUpperCase();
    final p = c.fxParam.toRadixString(16).toUpperCase().padLeft(2, '0');
    return '$cmd$p';
  }

  static String _effectCode(TrackerEffect fx) => switch (fx) {
        TrackerEffect.none => '·',
        TrackerEffect.arpeggio => 'A',
        TrackerEffect.vibrato => 'V',
        TrackerEffect.slideUp => 'U',
        TrackerEffect.slideDown => 'D',
      };

  Widget _pianoBar(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Which computer-keyboard scheme enters notes.
              SegmentedButton<_NoteEntry>(
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _NoteEntry.pianoKeys,
                    label: Text(l10n.trackerEntryPiano),
                  ),
                  ButtonSegment(
                    value: _NoteEntry.noteNames,
                    label: Text(l10n.trackerEntryNames),
                  ),
                ],
                selected: {_entryMode},
                onSelectionChanged: (s) => setState(() {
                  _entryMode = s.first;
                  _pendingSemi = null;
                }),
              ),
              const SizedBox(width: 8),
              // Base octave for the computer keyboard.
              IconButton(
                icon: const Icon(Icons.remove),
                tooltip: '${l10n.trackerOctave} −',
                onPressed: () =>
                    setState(() => _octave = (_octave - 1).clamp(0, 8)),
              ),
              Text('${l10n.trackerOctave} $_octave'),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: '${l10n.trackerOctave} +',
                onPressed: () =>
                    setState(() => _octave = (_octave + 1).clamp(0, 8)),
              ),
              if (_pendingLabel.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    _pendingLabel,
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const Spacer(),
              // The edit column (note/vol/fx) — Tab cycles it; tap for touch.
              Tooltip(
                message: l10n.trackerField,
                child: OutlinedButton(
                  onPressed: () => setState(
                    () => _field = _CellField
                        .values[(_field.index + 1) % _CellField.values.length],
                  ),
                  child: Text(
                    switch (_field) {
                      _CellField.note => '♪',
                      _CellField.volume => 'vol',
                      _CellField.effect => 'fx',
                    },
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Clear-at-cursor + advance (the "===" key on a real tracker).
              Tooltip(
                message: l10n.trackerClearCell,
                child: OutlinedButton(
                  onPressed: _clearAtCursorAndAdvance,
                  child: const Text('···'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard),
                color: _showKeyHints ? scheme.primary : null,
                tooltip: l10n.trackerShowKeys,
                onPressed: () => setState(() => _showKeyHints = !_showKeyHints),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: l10n.trackerKeyHelp,
                onPressed: () => _showKeyHelp(l10n),
              ),
            ],
          ),
          if (_showKeyHints)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Text(
                _entryMode == _NoteEntry.pianoKeys
                    ? 'Z S X D C V G B H N J M ,  ·  Q 2 W 3 E R 5 T 6 Y 7 U I'
                    : 'C D E F G A B  +  #  +  0–9   (e.g. F 2 = F2)',
                style: TextStyle(
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 2),
          // The sweepable multi-octave piano (same widget as the Workshop). Tap
          // a key to enter that absolute note at the cursor.
          SizedBox(
            height: 72,
            child: Scrollbar(
              controller: _pianoScroll,
              child: SingleChildScrollView(
                controller: _pianoScroll,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: _pianoWhiteKeys * _pianoKeyWidth,
                  child: PianoKeyboard(
                    startMidi: _pianoStartMidi,
                    whiteKeyCount: _pianoWhiteKeys,
                    showLabels: true,
                    showOctaveNumbers: true,
                    onKeyTap: (midi) {
                      _enterNoteAtCursor(midi);
                      _focus.requestFocus();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A legend for the keyboard editing — the authentic classic-tracker piano
  /// map plus the note-name shortcut and navigation keys.
  void _showKeyHelp(AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.trackerKeyHelp,
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              _helpRow(
                ctx,
                l10n.trackerEntryPiano,
                'Z S X D C V G B H N J M ,   ·   Q 2 W 3 E R 5 T 6 Y 7 U I',
              ),
              _helpRow(
                ctx,
                l10n.trackerEntryNames,
                'C D E F G A B  +  # ?  +  0–9',
              ),
              _helpRow(ctx, l10n.trackerOctave, 'Page Up / Page Down'),
              _helpRow(ctx, l10n.trackerCursor, '↑ ↓ ← →'),
              _helpRow(ctx, l10n.trackerClear, 'Delete / Backspace'),
              _helpRow(ctx, l10n.trackerEditStep, l10n.trackerEditStepHelp),
              const Divider(height: 20),
              _helpRow(ctx, l10n.trackerBlock, 'Shift + ↑↓←→'),
              _helpRow(ctx, l10n.trackerBlockTrack, 'Ctrl/⌘ + A'),
              _helpRow(
                ctx,
                '${l10n.trackerBlockCopy} / ${l10n.trackerBlockCut}',
                'Ctrl/⌘ + C / X',
              ),
              _helpRow(
                ctx,
                '${l10n.trackerBlockPaste} / ${l10n.trackerBlockPasteMix}',
                'Ctrl/⌘ + V / M',
              ),
              _helpRow(
                ctx,
                l10n.trackerBlockTransUp,
                'Alt + ↑↓  ·  Alt + PgUp/PgDn',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _helpRow(BuildContext ctx, String label, String keys) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: Text(
                keys,
                style: TextStyle(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
}

/// The optional onboarding for the Advanced Tracker — opens once on first entry
/// and from the app-bar "?" button. Explains the grid, the keyboard, transport
/// and song arrangement. Localized (de/en).
Tutorial advancedTrackerPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.trackerAdvancedTitle,
      steps: [
        TutorialStep(text: l10n.trackerTutGrid),
        TutorialStep(text: l10n.trackerTutKeys),
        TutorialStep(text: l10n.trackerTutStep),
        TutorialStep(text: l10n.trackerTutTransport),
        TutorialStep(text: l10n.trackerTutArrange),
        TutorialStep(text: l10n.trackerTutTracks),
      ],
    );

/// A thin per-channel VU meter that repaints only on level changes (listens to
/// the shared [levels] notifier for its [channel]).
class _ChannelMeter extends StatelessWidget {
  const _ChannelMeter({
    required this.levels,
    required this.channel,
    required this.muted,
  });

  final ValueNotifier<List<double>> levels;
  final int channel;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<List<double>>(
      valueListenable: levels,
      builder: (context, values, _) {
        final level =
            (channel < values.length && !muted) ? values[channel] : 0.0;
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: level,
              minHeight: 4,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(
                Color.lerp(scheme.primary, scheme.error, level) ??
                    scheme.primary,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The MOD effect-column editor for one cell: a command dropdown + a hex param
/// slider, applied live. Phase 1 exposes the working commands (None · C set-
/// volume · A volume-slide); more appear as the replayer (tracker_replay.dart)
/// gains them.
class _CommandEditor extends StatefulWidget {
  const _CommandEditor({
    required this.l10n,
    required this.initialCmd,
    required this.initialParam,
    required this.onChanged,
  });

  final AppLocalizations l10n;
  final int initialCmd;
  final int initialParam;
  final void Function(int cmd, int param) onChanged;

  @override
  State<_CommandEditor> createState() => _CommandEditorState();
}

class _CommandEditorState extends State<_CommandEditor> {
  late int _cmd = widget.initialCmd;
  late int _param = widget.initialParam;

  // Supported commands (nibble → label). 0 with param 0 = none.
  static const _commands = <int, String>{
    0x0: 'None',
    0xC: 'Cxx  Set volume',
    0xA: 'Axy  Volume slide',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.l10n.trackerFxColumn),
        Row(
          children: [
            DropdownButton<int>(
              value: _commands.containsKey(_cmd) ? _cmd : 0x0,
              items: [
                for (final e in _commands.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) {
                setState(() {
                  _cmd = v ?? 0;
                  if (_cmd == 0) _param = 0;
                });
                widget.onChanged(_cmd, _param);
              },
            ),
            const SizedBox(width: 12),
            Text(
              _param.toRadixString(16).toUpperCase().padLeft(2, '0'),
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (_cmd != 0)
          Slider(
            value: _param.toDouble(),
            max: 255,
            divisions: 255,
            label: _param.toRadixString(16).toUpperCase().padLeft(2, '0'),
            onChanged: (v) {
              setState(() => _param = v.round());
              widget.onChanged(_cmd, _param);
            },
          ),
      ],
    );
  }
}
