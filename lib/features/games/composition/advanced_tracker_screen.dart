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

import 'package:comet_beat/core/audio/chroma_analysis.dart'
    show ChordTemplate, kChordTemplates;
import 'package:comet_beat/core/audio/crisp_dsp/sample_edit.dart';
import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart';
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart';
import 'package:comet_beat/core/audio/daw_sources.dart' show TrackerSource;
import 'package:comet_beat/core/audio/mod/module_convert.dart'
    show convertDocTo;
import 'package:comet_beat/core/audio/mod/module_doc.dart' show ModuleFormat;
import 'package:comet_beat/core/audio/sample_pitch.dart';
import 'package:comet_beat/core/audio/sound_library.dart';
import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart'
    show
        RowTiming,
        kFxGlobalVolSlide,
        kFxPanSlide,
        kFxSetGlobalVolume,
        kFxTempoSlide,
        resolveTimingMap,
        rowIndexAtMs;
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/audio/tracker_song_codec.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:comet_beat/core/audio/voice_clip_recorder.dart';
import 'package:comet_beat/core/audio/wav_io.dart'
    show readWavPcm16, wavToMonoFloat;
import 'package:comet_beat/core/notation/multi_part_export.dart'
    show multiPartToAbc, multiPartToMidi, multiTrackMidiToMultiPart;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/gapless_loop_player.dart';
import 'package:comet_beat/features/games/composition/multipart_to_tracker.dart';
import 'package:comet_beat/features/games/composition/music_inspect.dart';
import 'package:comet_beat/features/games/composition/tracker_notation.dart';
import 'package:comet_beat/features/games/composition/tracker_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/library/modarchive_sheet.dart';
import 'package:comet_beat/features/library/sample_library_sheet.dart';
import 'package:comet_beat/features/library/soundfont_sheet.dart';
import 'package:comet_beat/features/library/starter_pattern.dart';
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';
import 'package:comet_beat/features/sound_lab/my_instruments_sheet.dart';
import 'package:comet_beat/features/sound_lab/my_samples_sheet.dart';
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart'
    show CompositionWorkshopScreen;
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/daw/send_to_daw.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart'
    show showAudioExportSheet;
import 'package:comet_beat/shared/tutorial/tutorial.dart';
import 'package:comet_beat/shared/tutorial/tutorial_sheet.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show
        MultiPartScore,
        Pitch,
        chordSymbolFor,
        multiPartScoreFromAbc,
        multiPartScoreFromKern,
        multiPartScoreFromMei,
        multiPartScoreFromMusicXml,
        multiPartToMusicXml,
        readMusicXmlFromMxl;
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

/// Swing presets: 0 = straight, up to ~0.66 = a triplet shuffle. Delays each
/// off-beat step by `swing * stepMs` (see [TrackerTiming.swing]).
const _kSwingOptions = [0.0, 0.16, 0.33, 0.5, 0.66];

/// Pitch-class names for the chord-helper root picker (0 = C … 11 = B).
const _kRootNames = [
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

/// Per-channel volume-envelope shapes offered in the mixer — the friendly form
/// of the FT2/IT envelope editor. `null` = flat (no envelope). Breakpoints are
/// `(ms, level 0..1)`; the replayer holds the last level after the final point,
/// so a "fade out over 400 ms" also silences anything longer.
const _kEnvelopePresets = <String, VolumeEnvelope?>{
  'flat': null,
  'fadeIn': VolumeEnvelope([(ms: 0, level: 0.0), (ms: 300, level: 1.0)]),
  'fadeOut': VolumeEnvelope([(ms: 0, level: 1.0), (ms: 400, level: 0.0)]),
  'pluck': VolumeEnvelope([
    (ms: 0, level: 1.0),
    (ms: 120, level: 0.3),
    (ms: 600, level: 0.0),
  ]),
  'swell': VolumeEnvelope([(ms: 0, level: 0.2), (ms: 500, level: 1.0)]),
};

/// Per-channel AUTO-PAN shapes (the pan envelope). `null` = fixed pan.
/// Breakpoints are `(ms, pan −1..1)`.
const _kPanPresets = <String, PanEnvelope?>{
  'off': null,
  'lr': PanEnvelope([(ms: 0, pan: -1.0), (ms: 500, pan: 1.0)]),
  'rl': PanEnvelope([(ms: 0, pan: 1.0), (ms: 500, pan: -1.0)]),
  'pingpong': PanEnvelope([
    (ms: 0, pan: -1.0),
    (ms: 250, pan: 1.0),
    (ms: 500, pan: -1.0),
  ]),
};

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
enum _CellField { note, volume, effect, instrument }

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
  const AdvancedTrackerScreen({super.key, this.initialSong});

  /// An optional song to open with — the Beginner→Advanced "promote" hands its
  /// groove over here so the switch keeps the kid's work instead of starting
  /// fresh. Null = a new empty song.
  final TrackerSong? initialSong;

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

  /// Rename a pattern to a song-section label; read any pattern's name.
  void renamePattern(int index, String name);
  String patternName(int index);
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

  /// Per-channel stereo pan (−1 left … 0 centre … +1 right).
  double panOf(int channel);
  void setPan(int channel, double pan);
  bool get songUsesPan;

  /// Per-channel volume envelope by preset key ('flat'/'fadeIn'/'fadeOut'/
  /// 'pluck'/'swell'); whether the channel currently has an envelope; and whether
  /// the song carries any envelope (routes it through the replayer).
  void setEnvelopePreset(int channel, String key);
  bool hasEnvelope(int channel);
  bool get songUsesEnvelopes;

  /// Per-channel auto-pan (pan envelope) by preset key ('off'/'lr'/'rl'/
  /// 'pingpong'); whether the channel has one.
  void setPanPreset(int channel, String key);
  bool hasPanEnvelope(int channel);

  /// Import a module (.mod/.s3m/.xm/.it) from raw [bytes]; save to the Song Book.
  void importModuleBytes(Uint8List bytes);
  bool debugSaveToSongBook(UserSongsService songs);

  /// Export the whole song as MIDI / MusicXML bytes (null when nothing pitched).
  Uint8List? debugExportMidi();
  String? debugExportMusicXml();

  /// Export the whole song as ABC text (null when nothing pitched); and import
  /// an ABC string as a new tracker song (the reverse).
  String? debugExportAbc();
  void debugImportAbc(String abc);

  /// Import a Humdrum **kern string as a new tracker song (the multi-part path
  /// the file picker uses, minus the picker).
  void debugImportKern(String kern);

  /// Export the whole song as a module file of [format] ('mod'/'xm'/'s3m'/'it').
  Uint8List? debugExportModule(String format);

  /// Assign a recorded/edited [raw] clip (with voice [fx]) to [channel] — the
  /// device-free path onto the sample editor (the mic is device-only).
  void injectRecording(int channel, Float64List raw, VoiceEffect fx);

  /// Copy [from]'s instrument (a recorded sample, sfxr, or additive voice) onto
  /// channel [to] — reuse a sound across tracks without re-recording.
  void copyInstrument(int from, int to);

  /// The id of [channel]'s current instrument (for asserting a copy landed).
  String debugInstrumentId(int channel);

  /// Undo / redo of pattern cell edits.
  bool get canUndo;
  bool get canRedo;
  void undo();
  void redo();

  /// FT2 feel: live record (jam at the playhead) + block interpolate.
  bool get isRecording;
  void toggleRecord();
  void interpolateBlock();

  /// Live-record quantize: snap a jammed note to the nearest beat.
  bool get isQuantize;
  void toggleQuantize();

  /// Fill each selected channel's per-cell instrument from its top selected row.
  void fillInstrumentBlock();

  /// Fill a chromatic run between the selection's top and bottom notes.
  void interpolateNotesBlock();

  /// Stamp a chord at the cursor: root pitch-class + octave + intervals, either
  /// across tracks or as an arpeggio down the column.
  void applyChordAtCursor(
    int pc,
    int octave,
    List<int> intervals, {
    required bool arp,
  });

  /// Play the current pattern from the cursor row (FT2 F7).
  void playFromCursor();

  /// Insert / delete a whole row at the cursor.
  void insertRow();
  void deleteRow();

  /// Look: classic skin + grid zoom.
  void toggleClassic();
  void setZoom(double z);

  /// Master oscilloscope strip + a built-in demo song.
  bool get showScope;
  void toggleScope();
  void loadDemo();

  /// Test: author an effect-column command (e.g. Dxx break) at a cell, and read
  /// the `(orderIndex, row)` the song-mode playhead resolves at song-time
  /// [songMs] — proves the highlight follows Bxx/Dxx/E6x flow jumps.
  void debugSetCommand(int channel, int row, int cmd, int param);
  (int, int) debugPlayheadAt(int songMs);
  int get debugSongTotalMs;

  /// Order-list editing.
  List<int> get orderList;
  void selectOrderSlot(int i);
  void orderMove(int delta);
  void orderInsert();

  /// In-grid volume-column editing (the FT2 field cursor).
  void cycleField();
  void typeVolume(String hexChar);
  double? volumeAt(int channel, int row);

  /// In-grid effect-column hex entry; read the cell's (cmd, param).
  void typeEffect(String hexChar);
  (int, int) effectAt(int channel, int row);

  /// In-grid instrument-column decimal entry (into the field-cursor cell).
  void typeInstrument(String digit);

  /// Move the field cursor to a specific column (for keyboard-entry tests).
  void selectField(int index);

  /// The MIDI note at a cell (null = empty).
  int? noteAt(int channel, int row);

  /// Per-pattern length: set the CURRENT pattern's rows only, and read any
  /// pattern's rows — so patterns can differ in length (tracker-style).
  void setPatternLength(int rows);
  int patternRows(int patternIndex);

  /// Apply a CUSTOM volume/pan envelope to [channel] from `(ms, value)`
  /// breakpoints (level 0..1 for volume, pan −1..1 for pan); empty clears it.
  void setChannelEnvelopePoints(
    int channel,
    bool isVolume,
    List<(int, double)> points,
  );

  /// The channel's envelope breakpoint count (0 = none) — for tests.
  int channelEnvelopePointCount(int channel, bool isVolume);

  /// Groove/swing (0 = straight … ~0.66 = triplet shuffle) — set + read.
  void setSwing(double swing);
  double get swing;

  /// The instrument-picker state: the active pool instrument stamped on new
  /// notes (0 = channel default), the pool size, and a cell's stamped instrument.
  int get activeInstrument;
  void setActiveInstrument(int index);
  int get instrumentPoolSize;
  int instrumentAt(int channel, int row);

  /// Append [inst] to the pool + select it (what "Load SoundFont" does with the
  /// picked preset, minus the file dialog).
  void debugAddInstrument(TrackerInstrument inst);

  /// Resolve a "My Instruments" library entry + add it to the pool (what the
  /// picker does, minus the sheet).
  void debugAddSavedInstrument(SavedInstrument saved);

  /// The song's shareable CBS1. token; [debugLoadToken] loads one back (true on
  /// success). What "Share song" / "Load song" do minus the dialogs.
  String debugSongToken();
  bool debugLoadToken(String token);

  /// Open the built-in Sound Library browser sheet (for a widget test).
  void debugShowSoundLibrary();

  /// Remove pool instrument [poolIndex] (what the panel's 🗑 does).
  void debugRemovePoolInstrument(int poolIndex);

  /// Set the per-cell instrument column (what the cell menu's picker does).
  void debugSetCellInstrument(int channel, int row, int inst);

  /// The midis the on-screen piano lights up for pattern [row] (un-muted
  /// channels) — the "keys glow as they play" highlight.
  List<int> debugSoundingMidis(int row);

  /// 🔍 Looking Glass: whether inspect mode is on, toggle it, and (for a test)
  /// the `(noteNames, rowChord)` the inspector reports for a cell (null = no
  /// notes in the row).
  bool get inspectMode;
  void toggleInspectMode();
  (String, String?)? debugInspectInfo(int channel, int row);

  /// 🔍 Desktop hover: drive the hover over a cell and read whether the corner
  /// card is showing (a note cell shows it; an empty cell clears it).
  void debugHoverCell(int channel, int row);
  bool get debugHoverCardShown;

  /// Send the whole song to the Multitrack (DAW) as a clip.
  void sendToDaw();

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
  late TrackerSong _song = widget.initialSong ?? TrackerSong();
  final _loop = GaplessLoopPlayer();
  final _samplePreview = GaplessLoopPlayer(); // sample auditions (record sheet)
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

  /// 🔍 Looking Glass: while on, tapping a cell describes its note + the chord
  /// the whole row sounds (+ instrument/effect) instead of only moving the cursor.
  bool _inspect = false;

  /// 🔍 Desktop hover-inspect: the info for the cell under the mouse while
  /// Inspect is on (shown as a card pinned to the grid's corner — the grid is a
  /// dense scroller, so a cursor-anchored card would drift). Null on touch.
  InspectInfo? _hoverInfo;

  /// The copied block (row-major), for paste / paste-mix.
  List<List<TrackerCell>>? _clipboard;

  bool get _hasSelection => _anchorChannel != null && _anchorRow != null;

  /// Keyboard/piano entry state.
  int _octave = 4;
  int _editStep = 1;
  _NoteEntry _entryMode = _NoteEntry.pianoKeys;

  /// The instrument stamped onto notes as you place them — 1-based into
  /// `_song.instruments`, or 0 for "channel default". Picked in the instrument
  /// panel; the FT2 instrument column, made touch-friendly.
  int _activeInstrument = 0;

  /// FT2-style live record: while ON and playing, notes land at the SOUNDING row
  /// (the playhead) instead of the edit cursor — jam straight into the pattern.
  bool _recording = false;

  /// Which sub-column the cursor edits in-grid (FT2 note/vol/fx columns). Typing
  /// hex into vol/fx edits that column directly; Tab / ←→ move between fields.
  _CellField _field = _CellField.note;

  /// The number of rows between highlighted "beat" lines in the grid (FT2's
  /// row-highlight spacing; default = the beat, i.e. stepsPerBeat).
  int? _highlightEvery;

  /// The selected position in the order list (for reorder/insert/delete).
  int _orderCursor = 0;

  /// Metronome: click on beat crossings during playback.
  bool _metronome = false;
  int _lastTickStep = -1;

  /// Live-record quantize: snap a jammed note to the nearest beat instead of
  /// the exact sounding row.
  bool _quantize = false;

  /// The playhead's fractional position within the current row (0..1), updated
  /// each tick — feeds [quantizeRowToBeat] so a slightly-early hit rounds up.
  double _rowPhase = 0.0;

  /// Whether the grid auto-scrolls to follow the playhead during playback.
  bool _followPlay = true;

  /// Song-mode playhead map: the flow-resolved `(startMs, order, pattern, row)`
  /// sequence, so the highlight follows Bxx/Dxx/E6x jumps + per-pattern lengths
  /// instead of assuming a fixed pattern length. Rebuilt lazily (nulled by every
  /// edit via `_syncPlayback`, and on stop).
  List<RowTiming>? _timingMap;

  /// Master oscilloscope: a waveform strip of the current pattern's mix.
  bool _showScope = false;
  Int16List? _scopePcm;
  bool _scopeDirty = true;

  /// Two-digit hex volume entry (FT2's 00–40 volume column): the accumulator and
  /// how many digits have been typed in the current cell (resets on a move).
  int _volAccum = 0;
  int _volDigits = 0;

  /// In-grid effect entry: cmd nibble then two param nibbles (resets on a move).
  int _fxCmd = 0;
  int _fxParam = 0;
  int _fxDigits = 0;

  /// Two-digit DECIMAL instrument entry (the FT2 instrument column, a 1-based
  /// pool index; 0 = channel default): accumulator + digits typed (resets on a
  /// move).
  int _instAccum = 0;
  int _instDigits = 0;

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

  /// Zoom for the on-screen piano key WIDTH (independent of the grid zoom).
  double _pianoZoom = 1.0;
  double get _pianoKW => _pianoKeyWidth * _pianoZoom;

  final _pianoScroll =
      ScrollController(initialScrollOffset: 14 * _pianoKeyWidth);
  int _lastFollowedRow = -1;

  /// Grid zoom (0.75–1.6) — scales the row height, cell width and fonts.
  double _zoom = 1.0;

  /// The classic-tracker skin (dark, monospace, colour-coded notes).
  bool _classic = false;

  double get _rowNumWidth => 44.0 * _zoom;
  double get _cellWidth => 74.0 * _zoom;
  double get _rowHeight => 30.0 * _zoom;

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
        // The flow-resolved map follows Bxx/Dxx/E6x jumps + per-pattern lengths;
        // the old `pos ~/ totalMs` assumed every pattern had the same length and
        // that the order played straight through — wrong on jumps + imports.
        final map = _timingMap ??= resolveTimingMap(_song);
        if (map.isEmpty) {
          posInPattern = 0;
        } else {
          final e = map[rowIndexAtMs(map, pos)];
          if (e.orderIndex != _playingOrder.value) {
            _playingOrder.value = e.orderIndex;
          }
          if (e.row != _row.value) {
            _row.value = e.row;
            _maybeTick(e.row);
          }
          // Position within the currently-sounding pattern (for the meters).
          posInPattern = e.row * t.stepMs + (pos - e.startMs);
          // Sub-row phase for live-record quantize (uniform step assumption).
          _rowPhase = t.stepMs > 0 ? (pos - e.startMs) / t.stepMs : 0.0;
        }
      } else {
        if (_playingOrder.value != -1) _playingOrder.value = -1;
        posInPattern = _elapsedMs % t.totalMs;
        final step = posInPattern ~/ t.stepMs;
        _rowPhase = t.stepMs > 0 ? (posInPattern % t.stepMs) / t.stepMs : 0.0;
        if (step != _row.value) {
          _row.value = step;
          _followPlayhead(step);
          _maybeTick(step);
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
    _samplePreview.dispose();
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
  void setNote(int channel, int row, int midi) => _setCell(
        channel,
        row,
        TrackerCell(midi: midi, instrument: _activeInstrument),
      );
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

  /// Set the CURRENT pattern's length only (tracker-style per-pattern length —
  /// the engine now supports variable lengths and the playhead map follows
  /// them). This is what the length control uses; [setRows] resizes every
  /// pattern (kept for the test seam + a future "resize all").
  void _setPatternLength(int rows) {
    _clearUndo();
    setState(() {
      _song.setPatternRows(_song.currentIndex, rows.clamp(1, 1024));
      if (_cursorRow >= _song.rows) _cursorRow = _song.rows - 1;
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

  // --- Order-list editing (reorder / insert / retarget) ------------------
  // Mutates `_song.order` directly (a public list) — screen-side, no model file.

  void _orderMove(int delta) {
    final j = _orderCursor + delta;
    if (j < 0 || j >= _song.order.length) return;
    setState(() {
      final tmp = _song.order[_orderCursor];
      _song.order[_orderCursor] = _song.order[j];
      _song.order[j] = tmp;
      _orderCursor = j;
    });
    _syncPlayback();
  }

  void _orderInsert() {
    setState(() {
      _song.order.insert(_orderCursor + 1, _song.order[_orderCursor]);
      _orderCursor += 1;
    });
    _syncPlayback();
  }

  void _orderDelete(int i) {
    if (_song.order.length <= 1) return;
    setState(() {
      _song.order.removeAt(i);
      _orderCursor = _orderCursor.clamp(0, _song.order.length - 1);
    });
    _syncPlayback();
  }

  /// Retarget the selected order slot to the prev/next pattern (FT2 sets the
  /// order value), and load that pattern for editing.
  void _orderRetarget(int delta) {
    if (_song.order.isEmpty) return;
    final n = _song.patterns.length;
    setState(() {
      _song.order[_orderCursor] = (_song.order[_orderCursor] + delta + n) % n;
    });
    selectPattern(_song.order[_orderCursor]);
  }

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
      final margin = _rowHeight * 2;
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

  /// Plays a short one-shot of [midi] so you HEAR a note as you place it (FT2
  /// preview). Skipped while playing — the loop already sounds the pattern.
  void _preview(int midi) {
    if (_clock.isRunning) return;
    final audio = context.read<AudioService>();
    if (audio.soundOn) audio.playMidiNote(midi, ms: 350);
  }

  /// Enters [midi] at the cursor and advances by the edit-step (wrapping). In
  /// live-record mode (playing) it lands at the SOUNDING row instead, preserving
  /// any existing volume/effect on that cell, and doesn't move the edit cursor —
  /// jam straight into the pattern.
  void _enterNoteAtCursor(int midi) {
    _preview(midi);
    _pushUndo();
    if (_recording && _clock.isRunning && _row.value >= 0) {
      final row = _quantize
          ? quantizeRowToBeat(
              _row.value,
              _rowPhase,
              _song.timing.stepsPerBeat,
              _song.rows,
            )
          : _row.value;
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
          instrument: _activeInstrument,
        ),
      );
      setState(() {});
      _syncPlayback();
      return;
    }
    _song.engine.setCell(
      _cursorChannel,
      _cursorRow,
      TrackerCell(midi: midi, instrument: _activeInstrument),
    );
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

  /// 🔍 Build the inspector card data for a cell: this cell's note name, the
  /// chord the whole ROW sounds (across channels), and its instrument/effect
  /// detail. Null when the row has no notes (nothing to inspect).
  InspectInfo? _inspectInfoFor(int channel, int row) {
    final rowMidis = <int>[
      for (var c = 0; c < _song.channelCount; c++)
        if (_song.engine.cellAt(c, row).midi case final int m) m,
    ];
    if (rowMidis.isEmpty) return null;
    final cell = _song.engine.cellAt(channel, row);
    final names = cell.midi != null
        ? trackerNoteName(cell.midi!)
        : rowMidis.map(trackerNoteName).join(' ');
    final parts = <String>[
      if (cell.instrument > 0) 'instrument ${cell.instrument}',
      if (cell.hasCommand)
        'fx ${_commandHex(cell)}'
      else if (cell.effect != TrackerEffect.none)
        'fx ${_effectCode(cell.effect)}',
    ];
    return InspectInfo(
      noteNames: names,
      chordSymbol:
          chordSymbolFor([for (final m in rowMidis) Pitch.fromMidi(m)]),
      detail: parts.isEmpty ? null : parts.join(' · '),
    );
  }

  /// 🔍 Desktop hover over a cell (Inspect on): show its info in the corner
  /// card. A no-note cell clears the card.
  void _onCellHover(int channel, int row) {
    if (!_inspect) return;
    final info = _inspectInfoFor(channel, row);
    if (info != _hoverInfo) setState(() => _hoverInfo = info);
  }

  /// A cell tap: inspect it in Looking-Glass mode, else move/extend the cursor.
  void _onCellTap(int channel, int row) {
    if (_inspect) {
      _moveCursorClearing(channel, row); // show which cell, then describe it
      final info = _inspectInfoFor(channel, row);
      if (info != null) showInspect(context, info);
      return;
    }
    if (_marking) {
      _extendTo(channel, row);
    } else {
      _moveCursorClearing(channel, row);
    }
    _focus.requestFocus();
  }

  /// Move the cursor and drop any selection (a plain move / click).
  void _moveCursorClearing(int channel, int row) {
    _resetVolEntry();
    _resetFxEntry();
    _resetInstEntry();
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
    _resetVolEntry();
    _resetFxEntry();
    _resetInstEntry();
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
  /// Inserts a blank row at the cursor across every channel — the rows below
  /// shift down one and the last row falls off (row count stays fixed).
  void _insertRow() {
    _pushUndo();
    setState(() {
      for (var c = 0; c < _song.channelCount; c++) {
        for (var r = _song.rows - 1; r > _cursorRow; r--) {
          _song.engine.setCell(c, r, _song.engine.cellAt(c, r - 1));
        }
        _song.engine.clearCell(c, _cursorRow);
      }
    });
    _syncPlayback();
  }

  /// Deletes the cursor row across every channel — the rows below shift up one
  /// and the last row becomes blank.
  void _deleteRow() {
    _pushUndo();
    setState(() {
      for (var c = 0; c < _song.channelCount; c++) {
        for (var r = _cursorRow; r < _song.rows - 1; r++) {
          _song.engine.setCell(c, r, _song.engine.cellAt(c, r + 1));
        }
        _song.engine.clearCell(c, _song.rows - 1);
      }
    });
    _syncPlayback();
  }

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

  /// Fill each selected channel's per-cell instrument from its TOP selected
  /// row down over the block (the cursor cell alone when nothing is marked) —
  /// set a voice once at the top, then stamp it across the whole column. Like
  /// interpolate, it works per-channel; empty cells are left untouched.
  void _fillInstrumentBlock() {
    final s = _selRect;
    _pushUndo();
    setState(() {
      for (var c = s.cLo; c <= s.cHi; c++) {
        final inst = _song.engine.cellAt(c, s.rLo).instrument;
        for (var r = s.rLo; r <= s.rHi; r++) {
          if (_song.engine.cellAt(c, r).midi == null) continue;
          _song.engine.setCellInstrument(c, r, inst);
        }
      }
    });
    _syncPlayback();
  }

  /// Fills a chromatic run down the selection: from each channel's top selected
  /// note to its bottom selected note (a glissando). No-op without a marked
  /// block spanning ≥2 rows.
  void _interpolateNotesBlock() {
    if (!_hasSelection) return;
    final s = _selRect;
    if (s.rHi <= s.rLo) return;
    _pushUndo();
    setState(
      () => _song.interpolateNotesBlock(s.cLo, s.rLo, s.cHi, s.rHi),
    );
    _syncPlayback();
  }

  /// Stamps a chord at the cursor: root pitch-class [pc] + [octave] set the root
  /// MIDI, [intervals] the chord shape. [arp] lays it down the cursor column at
  /// the edit-step spacing; otherwise across consecutive tracks. New notes take
  /// the active pool voice.
  void _applyChordAtCursor(
    int pc,
    int octave,
    List<int> intervals, {
    required bool arp,
  }) {
    final rootMidi = ((octave + 1) * 12 + pc).clamp(0, 127);
    _pushUndo();
    setState(() {
      if (arp) {
        final step = _editStep < 1 ? 1 : _editStep;
        _song.stampArpeggio(
          _cursorChannel,
          _cursorRow,
          rootMidi,
          intervals,
          step: step,
          instrument: _activeInstrument,
        );
      } else {
        _song.stampChordAcross(
          _cursorChannel,
          _cursorRow,
          rootMidi,
          intervals,
          instrument: _activeInstrument,
        );
      }
    });
    _syncPlayback();
  }

  String _chordQualityLabel(ChordTemplate t) =>
      t.suffix.isEmpty ? 'maj' : t.suffix;

  /// A quick chord/arpeggio stamper at the cursor: pick a root + quality, then
  /// lay it across tracks or as an arpeggio down the column.
  void _showChordSheet() {
    final l10n = AppLocalizations.of(context)!;
    // Seed the root from the cursor note when present.
    final cur = _song.engine.cellAt(_cursorChannel, _cursorRow).midi;
    var pc = cur != null ? cur % 12 : 0;
    var octave = cur != null ? ((cur ~/ 12) - 1).clamp(2, 6) : 4;
    var quality = 0; // index into kChordTemplates
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.trackerChord,
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('${l10n.trackerChordRoot}: '),
                    DropdownButton<int>(
                      value: pc,
                      items: [
                        for (var i = 0; i < 12; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(_kRootNames[i]),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setSheet(() => pc = v);
                      },
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: octave,
                      items: [
                        for (var o = 2; o <= 6; o++)
                          DropdownMenuItem(value: o, child: Text('$o')),
                      ],
                      onChanged: (v) {
                        if (v != null) setSheet(() => octave = v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < kChordTemplates.length; i++)
                      ChoiceChip(
                        label: Text(_chordQualityLabel(kChordTemplates[i])),
                        selected: quality == i,
                        onSelected: (_) => setSheet(() => quality = i),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.view_column, size: 18),
                      label: Text(l10n.trackerChordAcross),
                      onPressed: () {
                        _applyChordAtCursor(
                          pc,
                          octave,
                          kChordTemplates[quality].intervals,
                          arp: false,
                        );
                        Navigator.of(ctx).pop();
                      },
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.stairs, size: 18),
                      label: Text(l10n.trackerChordArp),
                      onPressed: () {
                        _applyChordAtCursor(
                          pc,
                          octave,
                          kChordTemplates[quality].intervals,
                          arp: true,
                        );
                        Navigator.of(ctx).pop();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Keyboard ---

  void _resetVolEntry() {
    _volAccum = 0;
    _volDigits = 0;
  }

  void _resetFxEntry() {
    _fxCmd = 0;
    _fxParam = 0;
    _fxDigits = 0;
  }

  void _resetInstEntry() {
    _instAccum = 0;
    _instDigits = 0;
  }

  /// Feeds one decimal digit into the per-cell instrument column (a 1-based
  /// pool index; value clamps to the pool size, 0 = channel default). No-op on
  /// a cell without a note — the instrument column belongs to a note.
  void _enterInstrumentDigit(int d) {
    if (_song.engine.cellAt(_cursorChannel, _cursorRow).midi == null) return;
    _pushUndo();
    final raw = _instDigits == 0 ? d : _instAccum * 10 + d;
    _instAccum = raw.clamp(0, _song.instruments.length);
    _instDigits = (_instDigits + 1) % 2;
    setState(
      () => _song.engine
          .setCellInstrument(_cursorChannel, _cursorRow, _instAccum),
    );
    _syncPlayback();
  }

  /// Types the effect column in-grid, FT2-style: the first hex digit is the
  /// command nibble, the next two build the parameter byte (resets after 3 or on
  /// a move). Applies progressively so it builds visibly.
  void _enterEffectHex(int hex) {
    switch (_fxDigits) {
      case 0:
        _fxCmd = hex;
        _fxParam = 0;
      case 1:
        _fxParam = hex;
      default:
        _fxParam = (_fxParam * 16 + hex) & 0xFF;
    }
    _fxDigits = (_fxDigits + 1) % 3;
    _setCellCommand(_cursorChannel, _cursorRow, _fxCmd, _fxParam);
  }

  /// Feeds one hex digit into the FT2 volume column (high nibble then low →
  /// value 00–40 = 0–64). No-op on a cell without a note.
  void _enterVolumeHex(int hex) {
    if (_song.engine.cellAt(_cursorChannel, _cursorRow).midi == null) return;
    _pushUndo();
    _volAccum = (_volDigits == 0 ? hex : (_volAccum * 16 + hex)).clamp(0, 64);
    _volDigits = (_volDigits + 1) % 2;
    final v = _volAccum / 64.0;
    setState(
      () => _song.engine
          .setCellVolume(_cursorChannel, _cursorRow, v >= 0.999 ? null : v),
    );
    _syncPlayback();
  }

  /// Field-cursor editing: Tab cycles note→volume→effect→instrument; hex digits
  /// in the volume/effect fields and a decimal digit in the instrument field
  /// edit the cursor note's columns. Returns non-null when the key was part of
  /// field editing.
  KeyEventResult? _handleFieldKey(KeyEvent event, LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.tab) {
      const vals = _CellField.values;
      final next = HardwareKeyboard.instance.isShiftPressed
          ? (_field.index - 1 + vals.length) % vals.length
          : (_field.index + 1) % vals.length;
      setState(() => _field = vals[next]);
      _resetVolEntry();
      _resetFxEntry();
      _resetInstEntry();
      return KeyEventResult.handled;
    }
    if (_field == _CellField.volume) {
      final hex = _hexOf(event.character);
      if (hex != null) {
        _enterVolumeHex(hex);
        return KeyEventResult.handled;
      }
      // Swallow other printable keys so they don't become notes in this field.
      if (event.character != null && event.character!.trim().isNotEmpty) {
        return KeyEventResult.handled;
      }
    }
    if (_field == _CellField.effect) {
      final hex = _hexOf(event.character);
      if (hex != null) {
        _enterEffectHex(hex);
        return KeyEventResult.handled;
      }
      // Backspace/Delete clears the effect column (leaving the note).
      if (key == LogicalKeyboardKey.backspace ||
          key == LogicalKeyboardKey.delete) {
        _resetFxEntry();
        _setCellCommand(_cursorChannel, _cursorRow, 0, 0);
        return KeyEventResult.handled;
      }
      // Swallow other printable keys so they don't become notes here.
      if (event.character != null && event.character!.trim().isNotEmpty) {
        return KeyEventResult.handled;
      }
    }
    if (_field == _CellField.instrument) {
      final d = _decOf(event.character);
      if (d != null) {
        _enterInstrumentDigit(d);
        return KeyEventResult.handled;
      }
      // Backspace/Delete resets the cell to the channel default voice.
      if (key == LogicalKeyboardKey.backspace ||
          key == LogicalKeyboardKey.delete) {
        _resetInstEntry();
        setState(
          () => _song.engine.setCellInstrument(_cursorChannel, _cursorRow, 0),
        );
        _syncPlayback();
        return KeyEventResult.handled;
      }
      // Swallow other printable keys so they don't become notes here.
      if (event.character != null && event.character!.trim().isNotEmpty) {
        return KeyEventResult.handled;
      }
    }
    return null;
  }

  /// A single decimal digit 0–9 (for the instrument column), or null.
  int? _decOf(String? ch) {
    if (ch == null || ch.isEmpty) return null;
    final c = ch.codeUnitAt(0);
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
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

    // FT2 function-key transport: F5 song · F6 pattern · F7 pattern-from-cursor ·
    // F8 stop.
    if (key == LogicalKeyboardKey.f5) {
      _playSong();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f6) {
      _playPattern();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f7) {
      _playPattern(fromRow: _cursorRow);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f8) {
      _stop();
      return KeyEventResult.handled;
    }

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
    // Insert / Shift+Delete: insert / delete a whole row at the cursor.
    if (key == LogicalKeyboardKey.insert) {
      _insertRow();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete && shift) {
      _deleteRow();
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
      _setOctave(_octave + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      _setOctave(_octave - 1);
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
    _timingMap = null;
    _row.value = -1;
    _playingOrder.value = -1;
    setState(() => _songMode = false);
  }

  /// Loop the current pattern, starting at row [fromRow] (FT2's play-from-cursor
  /// = F7; 0 = from the top = F6).
  void _playPattern({int fromRow = 0}) {
    _songMode = false;
    _paused = false;
    _baseMs = fromRow > 0 ? fromRow * _song.timing.stepMs : 0;
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
    _scopeDirty = true; // the mix changed → the scope waveform is stale
    _timingMap = null; // structure/tempo may have changed → rebuild lazily
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
  /// Clicks the metronome on beat crossings (once per beat step).
  void _maybeTick(int step) {
    if (!_metronome) return;
    final spb = _song.timing.stepsPerBeat;
    if (step % spb != 0 || step == _lastTickStep) return;
    _lastTickStep = step;
    final audio = context.read<AudioService>();
    if (audio.soundOn) audio.playTick(accent: step == 0);
  }

  /// The midis sounding at pattern [row] across un-muted channels — the keys the
  /// on-screen piano lights up as playback crosses that row.
  List<int> _soundingMidisAt(int row) {
    if (row < 0 || row >= _song.rows) return const [];
    final out = <int>[];
    for (var c = 0; c < _song.channelCount; c++) {
      if (_song.isMuted(c)) continue;
      final midi = _song.engine.cellAt(c, row).midi;
      if (midi != null) out.add(midi);
    }
    return out;
  }

  Map<int, Color> _soundingKeys() {
    final color = Theme.of(context).colorScheme.primary;
    return {for (final m in _soundingMidisAt(_row.value)) m: color};
  }

  /// The computer-key hint for each piano key at the current base octave — so
  /// the FT2 key map shows ON the keys (D1c), and moves with the octave.
  Map<int, String> _pianoKeyHints() {
    if (!_showKeyHints || _entryMode != _NoteEntry.pianoKeys) return const {};
    final base = (_octave + 1) * 12;
    final out = <int, String>{};
    for (final e in _kKeyToSemitone.entries) {
      final midi = base + e.value;
      out[midi] ??= e.key.toUpperCase(); // first (lower-row) key wins
    }
    return out;
  }

  /// Change the base octave and slide the piano so that octave is in view (D1d).
  void _setOctave(int octave) {
    setState(() => _octave = octave.clamp(0, 8));
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerPianoOnOctave());
  }

  void _centerPianoOnOctave() {
    if (!_pianoScroll.hasClients) return;
    final cMidi = (_octave + 1) * 12; // C of the base octave
    final whiteIndex = ((cMidi - _pianoStartMidi) ~/ 12) * 7; // 7 whites/octave
    final target = whiteIndex * _pianoKW - 80; // a little context to the left
    _pianoScroll.animateTo(
      target.clamp(0.0, _pianoScroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

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
    if (!_followPlay || !_vScroll.hasClients || step == _lastFollowedRow) {
      return;
    }
    _lastFollowedRow = step;
    final target = (step * _rowHeight) - 120;
    final max = _vScroll.position.maxScrollExtent;
    _vScroll.jumpTo(target.clamp(0.0, max));
  }

  // --- Mixer / instrument panel (per-track instrument + gain + mute/solo) ---

  /// The instrument-list panel: pick which pool instrument new notes carry (the
  /// FT2 instrument column as a touch-friendly picker). `_song.instruments` is
  /// the shared 1-based pool; 0 = the channel's own default voice.
  void _showInstrumentPanel() {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  l10n.trackerInstruments,
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
              ),
              // Add a built-in / SoundFont voice to the pool.
              ListTile(
                leading: const Icon(Icons.library_music),
                title: Text(l10n.trackerAddFromLibrary),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showSoundLibrary();
                },
              ),
              ListTile(
                leading: const Icon(Icons.piano),
                title: Text(l10n.trackerLoadSoundFont),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _loadSoundFont();
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmarks_outlined),
                title: Text(l10n.trackerMyInstruments),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _loadFromMyInstruments();
                },
              ),
              const Divider(height: 1),
              for (var i = 0; i <= _song.instruments.length; i++)
                ListTile(
                  leading: Icon(
                    _activeInstrument == i
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: _activeInstrument == i
                        ? Theme.of(ctx).colorScheme.primary
                        : null,
                  ),
                  title: Text(
                    i == 0
                        ? l10n.trackerInstrumentDefault
                        : '$i   ${_instrumentLabel(_song.instruments[i - 1].id)}',
                  ),
                  // Pool voices can be auditioned and removed (the default row
                  // can't). Removing remaps the cell instrument column.
                  trailing: i == 0
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.volume_up),
                              tooltip: l10n.trackerPreview,
                              onPressed: () =>
                                  _auditionInstrument(_song.instruments[i - 1]),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: l10n.trackerRemove,
                              onPressed: () {
                                _removePoolInstrument(i - 1);
                                setSheet(() {});
                              },
                            ),
                          ],
                        ),
                  onTap: () {
                    setState(() => _activeInstrument = i);
                    Navigator.of(ctx).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Remove pool instrument [poolIndex] (the model remaps the cell instrument
  /// column) and keep the active-instrument selection valid across the shift.
  void _removePoolInstrument(int poolIndex) {
    setState(() {
      _song.removeInstrument(poolIndex);
      final removed = poolIndex + 1; // 1-based
      if (_activeInstrument == removed) {
        _activeInstrument = 0;
      } else if (_activeInstrument > removed) {
        _activeInstrument -= 1;
      }
    });
    _syncPlayback();
  }

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
            child: Tooltip(
              message: l10n.trackerGain,
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
          ),
          // Pan slider (L ↔ R; centre = 0). Routes the song to the stereo render.
          const Icon(Icons.surround_sound, size: 14),
          Expanded(
            child: Tooltip(
              message: l10n.trackerPan,
              child: Slider(
                value: ch.pan.clamp(-1.0, 1.0),
                min: -1.0,
                onChanged: (v) {
                  // Snap a near-centre pan to dead centre so a song stays mono
                  // (and byte-identical) unless the user really pans.
                  _song.engine.setChannelPan(c, v.abs() < 0.05 ? 0.0 : v);
                  _syncPlayback();
                  setSheet(() {});
                },
              ),
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.show_chart, size: 20),
            tooltip: l10n.trackerEnvelope,
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  l10n.trackerEnvelope,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              for (final key in _kEnvelopePresets.keys)
                CheckedPopupMenuItem(
                  value: 'vol:$key',
                  checked: identical(ch.volumeEnvelope, _kEnvelopePresets[key]),
                  child: Text(_envelopeLabel(l10n, key)),
                ),
              PopupMenuItem(
                value: 'volCustom',
                child: Text('${l10n.trackerEnvCustom}…'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                enabled: false,
                child: Text(
                  l10n.trackerAutoPan,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              for (final key in _kPanPresets.keys)
                CheckedPopupMenuItem(
                  value: 'pan:$key',
                  checked: identical(ch.panEnvelope, _kPanPresets[key]),
                  child: Text(_panLabel(l10n, key)),
                ),
              PopupMenuItem(
                value: 'panCustom',
                child: Text('${l10n.trackerEnvCustom}…'),
              ),
            ],
            onSelected: (v) async {
              if (v == 'volCustom' || v == 'panCustom') {
                await _showEnvelopeEditor(c, isVolume: v == 'volCustom');
                setSheet(() {});
                return;
              }
              final key = v.substring(4);
              if (v.startsWith('vol:')) {
                _song.engine
                    .setChannelVolumeEnvelope(c, _kEnvelopePresets[key]);
              } else {
                _song.engine.setChannelPanEnvelope(c, _kPanPresets[key]);
              }
              _syncPlayback();
              setSheet(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.mic, size: 20),
            tooltip: l10n.trackerRecordSample,
            onPressed: () async {
              await _recordSampleSheet(c);
              setSheet(() {});
            },
          ),
          if (_song.channelCount > 1)
            PopupMenuButton<int>(
              icon: const Icon(Icons.copy_all_outlined, size: 20),
              tooltip: l10n.trackerCopyInstrument,
              itemBuilder: (_) => [
                for (var t = 0; t < _song.channelCount; t++)
                  if (t != c)
                    PopupMenuItem(
                      value: t,
                      child: Text(
                        '${t + 1}  ${_instrumentLabel(_song.channels[t].instrument.id)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              onSelected: (t) {
                copyInstrument(c, t);
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
    bool sustain = false,
    double start = 0.0,
    double end = 1.0,
  }) {
    // Manual trim handles first (crop to the dragged region), then the
    // non-destructive edits — each returns a new buffer — then the voice.
    var pcm = sliceFraction(raw, start, end);
    if (stretch != 1.0 && pcm.isNotEmpty) pcm = timeStretch(pcm, stretch);
    if (trim && pcm.isNotEmpty) pcm = trimSilence(pcm);
    if (normalize && pcm.isNotEmpty) pcm = normalizePcm(pcm);
    if (reverse && pcm.isNotEmpty) pcm = reversePcm(pcm);
    // "Sustain": apply the voice fx, then auto base-pitch (plays in tune) + a
    // crossfaded auto-loop (a held note rings) → a playable instrument, not a
    // one-shot. Otherwise the classic one-shot recorded voice.
    if (sustain && pcm.isNotEmpty) {
      return tunedRecordedSample(
        'rec',
        applyVoiceEffect(pcm, fx),
        crossfade: true,
      );
    }
    return SampleInstrument.recorded('rec', pcm, fx);
  }

  void _assignSample(int channel, SampleInstrument inst) {
    setState(() => _song.setChannelInstrument(channel, inst));
    _syncPlayback();
  }

  /// Load a SoundFont (.sf2/.sf3) and add the chosen GM preset to the shared
  /// instrument pool as the active instrument (so notes placed next use it).
  /// The whole browse/decode flow lives in showSoundFontSheet.
  Future<void> _loadSoundFont() async {
    final inst = await showSoundFontSheet(context);
    if (inst != null && mounted) _addPoolInstrument(inst);
  }

  /// Pick a voice saved in the shared "My Instruments" library and add it to
  /// the pool (Voice Lab voices etc. — embedded, so they resolve synchronously;
  /// a SoundFont reference would need its font bytes and is skipped here).
  Future<void> _loadFromMyInstruments() async {
    final saved = await showMyInstrumentsSheet(context);
    if (saved == null || !mounted) return;
    _addSavedInstrument(saved);
  }

  void _addSavedInstrument(SavedInstrument saved) {
    final inst = saved.instrument;
    if (inst != null) _addPoolInstrument(inst);
  }

  /// Append [inst] to the 1-based pool and make it the active instrument.
  void _addPoolInstrument(TrackerInstrument inst) {
    setState(() {
      _song.instruments.add(inst);
      _activeInstrument = _song.instruments.length;
    });
    _syncPlayback();
  }

  @override
  void debugAddInstrument(TrackerInstrument inst) => _addPoolInstrument(inst);

  @override
  void debugAddSavedInstrument(SavedInstrument saved) =>
      _addSavedInstrument(saved);

  /// Audition any instrument — render a middle-C note and loop-preview it.
  void _auditionInstrument(TrackerInstrument inst) {
    const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
    final pcm = inst.renderChannel(
      const [
        TrackerCell(midi: 60),
        TrackerCell.empty,
        TrackerCell.empty,
        TrackerCell.empty,
      ],
      timing,
    );
    if (!pcm.any((v) => v != 0)) return;
    final i16 = Int16List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      i16[i] = (pcm[i].clamp(-1.0, 1.0) * 32767).round();
    }
    _samplePreview.playLoop(wavBytes(i16));
  }

  String _categoryLabel(AppLocalizations l10n, SoundCategory c) => switch (c) {
        SoundCategory.tonal => l10n.trackerLibTonal,
        SoundCategory.plucked => l10n.trackerLibPlucked,
        SoundCategory.chiptune => l10n.trackerLibChiptune,
        SoundCategory.drum => l10n.trackerLibDrum,
        SoundCategory.recorded => l10n.trackerLibRecorded,
      };

  /// Load a bundled CC0 percussion sample (from assets) → hand it to [onPick]
  /// (defaults to appending it to the pool).
  Future<void> _addBundledPercussion(
    BundledSampleInfo info, {
    void Function(TrackerInstrument)? onPick,
  }) async {
    final data = await rootBundle.load(info.assetPath);
    if (!mounted) return;
    final bytes = data.buffer.asUint8List();
    (onPick ?? _addPoolInstrument)(bundledSampleInstrument(info, bytes));
  }

  Widget _libraryHeader(BuildContext ctx, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          label,
          style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                color: Theme.of(ctx).colorScheme.primary,
              ),
        ),
      );

  Widget _libraryTile(
    BuildContext ctx,
    String label, {
    VoidCallback? audition,
    required VoidCallback onAdd,
  }) =>
      ListTile(
        dense: true,
        leading: audition == null
            ? const Icon(Icons.music_note)
            : IconButton(
                icon: const Icon(Icons.volume_up),
                tooltip: AppLocalizations.of(ctx)!.trackerPreview,
                onPressed: audition,
              ),
        title: Text(label),
        trailing: const Icon(Icons.add),
        onTap: onAdd,
      );

  @override
  void debugShowSoundLibrary() => _showSoundLibrary();

  @override
  void debugRemovePoolInstrument(int poolIndex) =>
      _removePoolInstrument(poolIndex);

  /// Browse the built-in Sound Library (procedural voices by category + CC0
  /// percussion). Tap ▶ to audition, tap the row to pick a voice — by default it
  /// is added to the shared pool; [onPick] overrides that (e.g. to set a
  /// channel's default instrument).
  void _showSoundLibrary({void Function(TrackerInstrument)? onPick}) {
    final l10n = AppLocalizations.of(context)!;
    final add = onPick ?? _addPoolInstrument;
    final byCat = soundLibraryByCategory();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          maxChildSize: 0.85,
          builder: (sheetCtx, scroll) => ListView(
            controller: scroll,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  l10n.trackerSoundLibrary,
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
              ),
              for (final cat in SoundCategory.values)
                if ((byCat[cat] ?? const []).isNotEmpty) ...[
                  _libraryHeader(ctx, _categoryLabel(l10n, cat)),
                  for (final o in byCat[cat]!)
                    _libraryTile(
                      ctx,
                      _instrumentLabel(o.id),
                      audition: () => _auditionInstrument(o.build()),
                      onAdd: () {
                        add(o.build());
                        Navigator.of(ctx).pop();
                      },
                    ),
                ],
              _libraryHeader(ctx, l10n.trackerLibPercussion),
              for (final info in kBundledPercussion)
                _libraryTile(
                  ctx,
                  info.id,
                  onAdd: () async {
                    await _addBundledPercussion(info, onPick: onPick);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Audition an edited sample before assigning it — plays its PCM (voice fx +
  /// trim/stretch already baked into `inst.sample`) once on the preview player.
  void _playPreview(SampleInstrument inst) {
    final pcm = inst.sample;
    if (pcm.isEmpty) return;
    final i16 = Int16List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      i16[i] = (pcm[i].clamp(-1.0, 1.0) * 32767).round();
    }
    _samplePreview.playLoop(wavBytes(i16));
  }

  /// Read a WAV file into the sample editor (the file path onto the same edit
  /// pipeline as a mic recording). Returns the mono PCM, or null on failure.
  Future<Float64List?> _loadWavClip() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'WAV', extensions: ['wav']),
        ],
      );
      if (file == null) return null;
      return wavToMonoFloat(readWavPcm16(await file.readAsBytes()));
    } catch (_) {
      return null;
    }
  }

  @override
  void injectRecording(int channel, Float64List raw, VoiceEffect fx) =>
      _assignSample(channel, _sampleFrom(raw, fx: fx));

  @override
  void copyInstrument(int from, int to) {
    setState(
      () => _song.setChannelInstrument(to, _song.channels[from].instrument),
    );
    _syncPlayback();
  }

  @override
  String debugInstrumentId(int channel) =>
      _song.channels[channel].instrument.id;

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
  bool get isQuantize => _quantize;
  @override
  void toggleQuantize() => setState(() => _quantize = !_quantize);
  @override
  void interpolateBlock() => _interpolateBlock();
  @override
  void fillInstrumentBlock() => _fillInstrumentBlock();
  @override
  void interpolateNotesBlock() => _interpolateNotesBlock();
  @override
  void applyChordAtCursor(
    int pc,
    int octave,
    List<int> intervals, {
    required bool arp,
  }) =>
      _applyChordAtCursor(pc, octave, intervals, arp: arp);
  @override
  void playFromCursor() => _playPattern(fromRow: _cursorRow);
  @override
  void insertRow() => _insertRow();
  @override
  void deleteRow() => _deleteRow();
  @override
  void toggleClassic() => setState(() => _classic = !_classic);
  @override
  void setZoom(double z) => setState(() => _zoom = z.clamp(0.75, 1.6));
  @override
  bool get showScope => _showScope;
  @override
  void toggleScope() => setState(() => _showScope = !_showScope);
  @override
  void loadDemo() => _loadDemo();
  @override
  void debugSetCommand(int channel, int row, int cmd, int param) {
    final cur = _song.engine.cellAt(channel, row);
    setState(() {
      _song.engine.setCell(
        channel,
        row,
        TrackerCell(
          midi: cur.midi,
          volume: cur.volume,
          effect: cur.effect,
          fxCmd: cmd,
          fxParam: param,
          instrument: cur.instrument,
        ),
      );
    });
    _syncPlayback();
  }

  @override
  (int, int) debugPlayheadAt(int songMs) {
    final map = resolveTimingMap(_song);
    if (map.isEmpty) return (-1, -1);
    final total = _song.songTotalMs;
    final pos = total > 0 ? songMs % total : 0;
    final e = map[rowIndexAtMs(map, pos)];
    return (e.orderIndex, e.row);
  }

  @override
  int get debugSongTotalMs => _song.songTotalMs;

  @override
  List<int> get orderList => List.unmodifiable(_song.order);
  @override
  void selectOrderSlot(int i) => setState(() => _orderCursor = i);
  @override
  void orderMove(int delta) => _orderMove(delta);
  @override
  void orderInsert() => _orderInsert();
  @override
  void cycleField() => setState(
        () => _field =
            _CellField.values[(_field.index + 1) % _CellField.values.length],
      );
  @override
  void typeVolume(String hexChar) {
    final hex = _hexOf(hexChar);
    if (hex != null) _enterVolumeHex(hex);
  }

  @override
  double? volumeAt(int channel, int row) =>
      _song.engine.cellAt(channel, row).volume;
  @override
  void typeEffect(String hexChar) {
    final hex = _hexOf(hexChar);
    if (hex != null) _enterEffectHex(hex);
  }

  @override
  (int, int) effectAt(int channel, int row) {
    final c = _song.engine.cellAt(channel, row);
    return (c.fxCmd, c.fxParam);
  }

  @override
  void typeInstrument(String digit) {
    final d = _decOf(digit);
    if (d != null) _enterInstrumentDigit(d);
  }

  @override
  void selectField(int index) =>
      setState(() => _field = _CellField.values[index]);

  @override
  int? noteAt(int channel, int row) => _song.engine.cellAt(channel, row).midi;
  @override
  void setPatternLength(int rows) => _setPatternLength(rows);
  @override
  int patternRows(int patternIndex) => _song.patterns[patternIndex].rows;
  @override
  void renamePattern(int index, String name) =>
      setState(() => _song.renamePattern(index, name));
  @override
  String patternName(int index) => _song.patterns[index].name;
  @override
  double get swing => _song.timing.swing;
  @override
  void setSwing(double swing) {
    setState(() => _song.setSwing(swing));
    _syncPlayback();
  }

  @override
  int get activeInstrument => _activeInstrument;
  @override
  void setActiveInstrument(int index) => setState(
        () => _activeInstrument = index.clamp(0, _song.instruments.length),
      );
  @override
  int get instrumentPoolSize => _song.instruments.length;
  @override
  int instrumentAt(int channel, int row) =>
      _song.engine.cellAt(channel, row).instrument;
  @override
  List<int> debugSoundingMidis(int row) => _soundingMidisAt(row);

  @override
  bool get inspectMode => _inspect;
  @override
  void toggleInspectMode() => setState(() => _inspect = !_inspect);
  @override
  (String, String?)? debugInspectInfo(int channel, int row) {
    final info = _inspectInfoFor(channel, row);
    return info == null ? null : (info.noteNames, info.chordSymbol);
  }

  @override
  void debugHoverCell(int channel, int row) => _onCellHover(channel, row);
  @override
  bool get debugHoverCardShown => _inspect && _hoverInfo != null;

  @override
  void sendToDaw() => sendToMultitrack(context, TrackerSource(_song));

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
    var sustain = false;
    var sampStart = 0.0, sampEnd = 1.0; // manual trim-handle fractions
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
                            sampStart = 0.0;
                            sampEnd = 1.0;
                          } catch (_) {
                            error = l10n.trackerRecordFailed;
                          } finally {
                            if (ctx.mounted) setSheet(() => recording = false);
                          }
                        },
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.audio_file_outlined),
                  label: Text(l10n.trackerLoadWav),
                  onPressed: recording
                      ? null
                      : () async {
                          final loaded = await _loadWavClip();
                          if (!ctx.mounted) return;
                          if (loaded == null || loaded.isEmpty) {
                            setSheet(() => error = l10n.trackerRecordFailed);
                            return;
                          }
                          setSheet(() {
                            clip = loaded;
                            sampStart = 0.0;
                            sampEnd = 1.0;
                            error = null;
                          });
                        },
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.travel_explore),
                  label: Text(l10n.trackerFreeSounds),
                  onPressed: recording
                      ? null
                      : () async {
                          final loaded = await showSampleLibrarySheet(ctx);
                          if (!ctx.mounted) return;
                          if (loaded == null || loaded.isEmpty) {
                            setSheet(() => error = l10n.trackerRecordFailed);
                            return;
                          }
                          setSheet(() {
                            clip = loaded;
                            sampStart = 0.0;
                            sampEnd = 1.0;
                            error = null;
                          });
                        },
                ),
                const SizedBox(height: 8),
                // Anything the user already collected — samples extracted from
                // their own modules/packs, or a voice shaped in the Voice Lab.
                OutlinedButton.icon(
                  icon: const Icon(Icons.bookmarks_outlined),
                  label: Text(l10n.trackerMySamples),
                  onPressed: recording
                      ? null
                      : () async {
                          final picked = await showMySamplesSheet(ctx);
                          if (!ctx.mounted) return;
                          if (picked == null || picked.pcm.isEmpty) return;
                          setSheet(() {
                            clip = picked.pcm;
                            sampStart = 0.0;
                            sampEnd = 1.0;
                            error = null;
                          });
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
                  Text(
                    l10n.trackerSampleTrimDrag,
                    style: Theme.of(ctx).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 6),
                  _SampleWaveform(
                    pcm: clip!,
                    start: sampStart,
                    end: sampEnd,
                    wave: Theme.of(ctx).colorScheme.primary,
                    bg: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    onChanged: (s, e) => setSheet(() {
                      sampStart = s;
                      sampEnd = e;
                    }),
                  ),
                  const SizedBox(height: 12),
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
                      FilterChip(
                        avatar: const Icon(Icons.all_inclusive, size: 18),
                        label: Text(l10n.trackerSampleSustain),
                        selected: sustain,
                        onSelected: (v) => setSheet(() => sustain = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: Text(l10n.trackerPreview),
                        onPressed: () => _playPreview(
                          _sampleFrom(
                            clip!,
                            fx: fx,
                            stretch: stretch,
                            trim: trim,
                            normalize: normalize,
                            reverse: reverse,
                            sustain: sustain,
                            start: sampStart,
                            end: sampEnd,
                          ),
                        ),
                      ),
                      const Spacer(),
                      FilledButton(
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
                              sustain: sustain,
                              start: sampStart,
                              end: sampEnd,
                            ),
                          );
                          Navigator.of(ctx).pop();
                        },
                        child: Text(l10n.trackerAssignSample),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    await _samplePreview.stop(); // stop any audition when the sheet closes
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
                    GestureDetector(
                      // Long-press to audition the voice before assigning it.
                      onLongPress: () => _auditionInstrument(opt.build()),
                      child: ChoiceChip(
                        label: Text(_instrumentLabel(opt.id)),
                        selected: opt.id == currentId,
                        onSelected: (_) {
                          setChannelInstrument(channel, opt.id);
                          Navigator.of(ctx).pop();
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.trackerLongPressToHear,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              // Set the channel's default voice from the Sound Library or a
              // SoundFont (not just the built-in chips above).
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.library_music, size: 18),
                    label: Text(l10n.trackerSoundLibrary),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _showSoundLibrary(
                        onPick: (inst) =>
                            _setChannelInstrumentVoice(channel, inst),
                      );
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.piano, size: 18),
                    label: Text(l10n.trackerLoadSoundFont),
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      final inst = await showSoundFontSheet(context);
                      if (inst != null && mounted) {
                        _setChannelInstrumentVoice(channel, inst);
                      }
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

  /// Set [channel]'s default instrument to [inst] (from the library / a
  /// SoundFont) and refresh playback.
  void _setChannelInstrumentVoice(int channel, TrackerInstrument inst) {
    setState(() => _song.setChannelInstrument(channel, inst));
    _syncPlayback();
  }

  @override
  void setChannelEnvelopePoints(
    int channel,
    bool isVolume,
    List<(int, double)> points,
  ) {
    setState(() {
      if (isVolume) {
        _song.engine.setChannelVolumeEnvelope(
          channel,
          points.isEmpty
              ? null
              : VolumeEnvelope([
                  for (final p in points)
                    (ms: p.$1, level: p.$2.clamp(0.0, 1.0)),
                ]),
        );
      } else {
        _song.engine.setChannelPanEnvelope(
          channel,
          points.isEmpty
              ? null
              : PanEnvelope([
                  for (final p in points)
                    (ms: p.$1, pan: p.$2.clamp(-1.0, 1.0)),
                ]),
        );
      }
    });
    _syncPlayback();
  }

  @override
  int channelEnvelopePointCount(int channel, bool isVolume) {
    final ch = _song.channels[channel];
    return isVolume
        ? (ch.volumeEnvelope?.points.length ?? 0)
        : (ch.panEnvelope?.points.length ?? 0);
  }

  /// A custom volume/pan envelope editor: a live preview plus one (time, value)
  /// breakpoint row per point, editable via sliders. Applies as a
  /// [VolumeEnvelope]/[PanEnvelope] the replayer already honours.
  Future<void> _showEnvelopeEditor(
    int channel, {
    required bool isVolume,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final ch = _song.channels[channel];
    final points = <({int ms, double value})>[];
    if (isVolume) {
      final env = ch.volumeEnvelope;
      if (env != null && env.points.isNotEmpty) {
        points.addAll([for (final p in env.points) (ms: p.ms, value: p.level)]);
      } else {
        points.addAll(const [(ms: 0, value: 1.0), (ms: 500, value: 0.0)]);
      }
    } else {
      final env = ch.panEnvelope;
      if (env != null && env.points.isNotEmpty) {
        points.addAll([for (final p in env.points) (ms: p.ms, value: p.pan)]);
      } else {
        points.addAll(const [(ms: 0, value: -1.0), (ms: 500, value: 1.0)]);
      }
    }
    final minV = isVolume ? 0.0 : -1.0;
    final scheme = Theme.of(context).colorScheme;
    int? dragIdx; // the breakpoint being dragged on the canvas

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isVolume
                      ? l10n.trackerEnvVolCustom
                      : l10n.trackerEnvPanCustom,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                // Drag a dot to move a breakpoint; the sliders below are the
                // precise editor. Both mutate the same `points` list.
                SizedBox(
                  height: 72,
                  width: double.infinity,
                  child: LayoutBuilder(
                    builder: (ctx, cons) {
                      final box = Size(cons.maxWidth, 72);
                      void moveTo(Offset local) {
                        final idx = dragIdx;
                        if (idx == null || idx >= points.length) return;
                        final (ms, value) = envPointFromLocal(local, box, minV);
                        setSheet(() => points[idx] = (ms: ms, value: value));
                      }

                      return GestureDetector(
                        onPanDown: (d) => dragIdx = nearestEnvPointIndex(
                          [for (final p in points) (p.ms, p.value)],
                          d.localPosition,
                          box,
                        ),
                        onPanUpdate: (d) => moveTo(d.localPosition),
                        onPanEnd: (_) => dragIdx = null,
                        onPanCancel: () => dragIdx = null,
                        child: CustomPaint(
                          size: box,
                          painter: _EnvelopePainter(
                            points: [for (final p in points) (p.ms, p.value)],
                            minV: minV,
                            line: scheme.primary,
                            grid: scheme.outlineVariant,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: points.length,
                    itemBuilder: (_, i) => Row(
                      children: [
                        SizedBox(width: 28, child: Text('${i + 1}')),
                        Expanded(
                          child: Slider(
                            value: points[i].ms.toDouble().clamp(0, 2000),
                            max: 2000,
                            divisions: 40,
                            label: '${points[i].ms} ms',
                            onChanged: (v) => setSheet(
                              () => points[i] =
                                  (ms: v.round(), value: points[i].value),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: points[i].value.clamp(minV, 1.0),
                            min: minV,
                            divisions: 20,
                            label: points[i].value.toStringAsFixed(2),
                            onChanged: (v) => setSheet(
                              () => points[i] = (ms: points[i].ms, value: v),
                            ),
                          ),
                        ),
                        IconButton(
                          icon:
                              const Icon(Icons.remove_circle_outline, size: 20),
                          onPressed: points.length > 2
                              ? () => setSheet(() => points.removeAt(i))
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(l10n.trackerEnvAddPoint),
                      onPressed: points.length < 8
                          ? () => setSheet(() {
                                final lastMs =
                                    points.isEmpty ? 0 : points.last.ms;
                                final ms = (lastMs + 250).clamp(0, 2000);
                                points.add(
                                  (ms: ms, value: isVolume ? 0.5 : 0.0),
                                );
                              })
                          : null,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setChannelEnvelopePoints(channel, isVolume, const []);
                        Navigator.of(ctx).pop();
                      },
                      child: Text(l10n.trackerClear),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        points.sort((a, b) => a.ms.compareTo(b.ms));
                        setChannelEnvelopePoints(
                          channel,
                          isVolume,
                          [for (final p in points) (p.ms, p.value)],
                        );
                        Navigator.of(ctx).pop();
                      },
                      child: Text(l10n.trackerOk),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _envelopeLabel(AppLocalizations l10n, String key) => switch (key) {
        'flat' => l10n.trackerEnvFlat,
        'fadeIn' => l10n.trackerEnvFadeIn,
        'fadeOut' => l10n.trackerEnvFadeOut,
        'pluck' => l10n.trackerEnvPluck,
        'swell' => l10n.trackerEnvSwell,
        _ => key,
      };

  String _panLabel(AppLocalizations l10n, String key) => switch (key) {
        'off' => l10n.trackerPanOff,
        'lr' => l10n.trackerPanLR,
        'rl' => l10n.trackerPanRL,
        'pingpong' => l10n.trackerPanPingPong,
        _ => key,
      };

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
              const SizedBox(height: 12),
              // Per-cell INSTRUMENT column: this note can use any pool voice
              // (the FT2 instrument column), independent of the channel default.
              Text(l10n.trackerInstruments),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(l10n.trackerInstrumentDefault),
                    selected: cell.instrument == 0,
                    onSelected: (_) =>
                        _pickCellInstrument(ctx, channel, row, 0),
                  ),
                  for (var p = 0; p < _song.instruments.length; p++)
                    GestureDetector(
                      // Long-press to audition this pool voice before assigning.
                      onLongPress: () =>
                          _auditionInstrument(_song.instruments[p]),
                      child: ChoiceChip(
                        label: Text(
                          '${p + 1} ${_instrumentLabel(_song.instruments[p].id)}',
                        ),
                        selected: cell.instrument == p + 1,
                        onSelected: (_) =>
                            _pickCellInstrument(ctx, channel, row, p + 1),
                      ),
                    ),
                ],
              ),
              if (_song.instruments.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.trackerLongPressToHear,
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
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
          instrument: cur.instrument, // don't drop the per-cell instrument
        ),
      ),
    );
    _syncPlayback();
  }

  /// Set the cell's instrument column (0 = channel default, else a 1-based pool
  /// index) from the cell menu, then close it.
  void _pickCellInstrument(BuildContext ctx, int channel, int row, int inst) {
    _pushUndo();
    setState(() => _song.engine.setCellInstrument(channel, row, inst));
    _syncPlayback();
    Navigator.of(ctx).pop();
  }

  @override
  void debugSetCellInstrument(int channel, int row, int inst) {
    setState(() => _song.engine.setCellInstrument(channel, row, inst));
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
        MaterialPageRoute(
          builder: (_) => TrackerScreen(initialSong: _song),
        ),
      );

  // --- Import / export (reuses the existing module + notation bridges) ---

  void _replaceSong(TrackerSong song) {
    _stop();
    _clearUndo();
    setState(() {
      _song = song;
      _cursorChannel = 0;
      _cursorRow = 0;
      _scopeDirty = true;
    });
  }

  @override
  void importModuleBytes(Uint8List bytes) =>
      _replaceSong(songFromModuleBytes(bytes));

  // --- Native lossless save / share (the CBS1. token, tracker_song_codec) ---

  @override
  String debugSongToken() => trackerSongToToken(_song);

  @override
  bool debugLoadToken(String token) {
    final song = tryTrackerSongFromToken(token);
    if (song == null) return false;
    _replaceSong(song);
    return true;
  }

  /// Show the song's shareable [CBS1.] token (copy to clipboard). Lossless — the
  /// exact document (notes, effects, per-cell instruments, channels, envelopes).
  Future<void> _shareSong() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final token = trackerSongToToken(_song);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.trackerShareSong),
        content: SingleChildScrollView(
          child: SelectableText(token),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: token));
              if (ctx.mounted) Navigator.of(ctx).pop();
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.trackerSongCopied)),
              );
            },
            child: Text(l10n.trackerCopy),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.trackerClose),
          ),
        ],
      ),
    );
  }

  /// Paste a [CBS1.] token to load a shared song (replaces the current one).
  Future<void> _loadSong() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.trackerLoadSong),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: InputDecoration(hintText: l10n.trackerPasteToken),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.trackerCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l10n.trackerLoad),
          ),
        ],
      ),
    );
    controller.dispose();
    if (token == null || !mounted) return;
    if (!debugLoadToken(token.trim())) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.trackerTokenInvalid)),
      );
    }
  }

  /// BYOK browse of The Mod Archive's CC0/Public-Domain modules → import the
  /// picked one via the same [importModuleBytes] seam as file/module import.
  Future<void> _browseModArchive() async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context)!.trackerModFailed;
    try {
      final bytes = await showModArchiveSheet(context);
      if (bytes == null || !mounted) return;
      importModuleBytes(bytes);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

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

  @override
  String? debugExportAbc() {
    final mp = _songMultiPart();
    return mp == null ? null : multiPartToAbc(mp.score, partNames: mp.names);
  }

  @override
  void debugImportAbc(String abc) =>
      _replaceSong(_songFromMultiPart(multiPartScoreFromAbc(abc)));

  @override
  void debugImportKern(String kern) =>
      _replaceSong(_songFromMultiPart(multiPartScoreFromKern(kern)));

  @override
  Uint8List? debugExportModule(String format) {
    _song.syncCurrent(); // fold live edits into the snapshot before isEmpty
    if (_song.isEmpty) return null;
    final fmt = ModuleFormat.values.firstWhere((f) => f.name == format);
    // PCM-preserving: straight from the song (real sample PCM + effect column).
    return convertDocTo(moduleDocFromSong(_song), fmt);
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

  /// Render the whole song and offer it as WAV or MP3 (pure-Dart, web-safe).
  Future<void> _exportAudio() async {
    final pcm = wavToMonoFloat(readWavPcm16(_song.renderSongWav()));
    if (!mounted) return;
    await showAudioExportSheet(context, pcm: pcm, baseName: 'tracker');
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

  Future<void> _exportAbc() async {
    final mp = _songMultiPart();
    final l10n = AppLocalizations.of(context)!;
    if (mp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.trackerSaveEmpty)),
      );
      return;
    }
    final abc = multiPartToAbc(mp.score, partNames: mp.names);
    await _saveBytes(
      Uint8List.fromList(utf8.encode(abc)),
      'tracker.abc',
      'ABC',
      ['abc'],
    );
  }

  /// Exports the whole song as a tracker MODULE (.mod/.xm/.s3m/.it). Built
  /// DIRECTLY from the song via moduleDocFromSong, so each SampleInstrument's
  /// REAL PCM and the authored effect column survive (unlike the Score bridge,
  /// which re-synthesizes a timbre and drops effects). Also exports drum-only
  /// songs the Score path couldn't.
  Future<void> _exportModule(ModuleFormat fmt) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    _song.syncCurrent(); // fold live edits into the snapshot before isEmpty
    if (_song.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.trackerSaveEmpty)));
      return;
    }
    try {
      final bytes = convertDocTo(moduleDocFromSong(_song), fmt);
      await _saveBytes(bytes, 'tracker.${fmt.name}', fmt.name.toUpperCase(), [
        fmt.name,
      ]);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.trackerModFailed)));
    }
  }

  Future<void> _pickModuleFormat() async {
    final l10n = AppLocalizations.of(context)!;
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
                l10n.trackerExportModule,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in ModuleFormat.values)
                    ActionChip(
                      label: Text('.${f.name}'),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _exportModule(f);
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
            extensions: [
              'musicxml',
              'xml',
              'mxl',
              'abc',
              'mei',
              'krn',
              'mid',
              'midi',
            ],
          ),
        ],
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      final name = file.name.toLowerCase();
      // All multi-part readers, so every voice becomes its own tracker channel.
      final mp = switch (name.split('.').last) {
        'mid' || 'midi' => multiTrackMidiToMultiPart(bytes),
        'abc' => multiPartScoreFromAbc(utf8.decode(bytes)),
        'mei' => multiPartScoreFromMei(utf8.decode(bytes)),
        'krn' => multiPartScoreFromKern(utf8.decode(bytes)),
        'mxl' => multiPartScoreFromMusicXml(readMusicXmlFromMxl(bytes)),
        _ => multiPartScoreFromMusicXml(utf8.decode(bytes)),
      };
      _replaceSong(_songFromMultiPart(mp));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.trackerModFailed)));
    }
  }

  TrackerSong _songFromMultiPart(MultiPartScore mp) =>
      trackerSongFromMultiPart(mp);

  /// A built-in two-pattern demo groove so newcomers instantly see + hear a full
  /// tune (melody + sparkle + bass on the default band; pattern 01 lifts the
  /// melody a third for a call/response).
  /// Lays a simple backbeat across the current pattern using each channel's
  /// assigned instrument — pairs with "Browse free sounds" (assign CC0 samples,
  /// then one-tap a groove). Additive: reuses the per-cell [setNote] path.
  void _applyStarterBeat() {
    final hits =
        starterBeatHits(channels: _song.channels.length, rows: _song.rows);
    for (final h in hits) {
      setNote(h.channel, h.row, 60); // C4; drum/one-shot samples ignore pitch
    }
  }

  void _loadDemo() {
    final song = TrackerSong(); // default band, 32 rows @ 4 steps/beat
    void put(int ch, int row, int midi) =>
        song.engine.setCell(ch, row, TrackerCell(midi: midi));
    const mel = [72, 76, 79, 76, 74, 77, 79, 74]; // C E G E · D F G D
    const bass = [48, 48, 43, 43, 41, 41, 43, 43]; // C C G G F F G G
    for (var i = 0; i < 8; i++) {
      put(0, i * 4, mel[i]); // melody (piano)
      put(3, i * 4, bass[i]); // bass (cello)
      put(1, i * 4 + 2, mel[i] + 12); // sparkle (music box), offbeat, +8ve
    }
    final p1 = song.addPattern(cloneCurrent: true); // pattern 01 = a variation
    song.selectPattern(p1);
    song.transposeBlock(0, 0, 0, song.rows - 1, 3); // lift the melody a third
    song.selectPattern(0);
    song.addToOrder(p1); // order: 00 · 01
    _replaceSong(song);
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
            icon: Icon(_inspect ? Icons.search_off : Icons.search),
            isSelected: _inspect,
            tooltip: l10n.inspectMode,
            onPressed: () => setState(() => _inspect = !_inspect),
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
          IconButton(
            icon: Badge(
              isLabelVisible: _activeInstrument > 0,
              label: Text('$_activeInstrument'),
              child: const Icon(Icons.queue_music),
            ),
            tooltip: l10n.trackerInstruments,
            onPressed: _showInstrumentPanel,
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
                case 'modArchive':
                  _browseModArchive();
                case 'importScore':
                  _importScore();
                case 'demo':
                  _loadDemo();
                case 'starterBeat':
                  _applyStarterBeat();
                case 'loadSoundFont':
                  _loadSoundFont();
                case 'soundLibrary':
                  _showSoundLibrary();
                case 'shareSong':
                  _shareSong();
                case 'loadSong':
                  _loadSong();
                case 'saveSong':
                  _saveToSongBook();
                case 'exportMidi':
                  _exportMidi();
                case 'exportXml':
                  _exportMusicXml();
                case 'exportAbc':
                  _exportAbc();
                case 'exportModule':
                  _pickModuleFormat();
                case 'exportAudio':
                  _exportAudio();
                case 'daw':
                  sendToDaw();
                case 'workshop':
                  _openInWorkshop();
              }
            },
            itemBuilder: (ctx) => [
              _menuRow('import', Icons.library_music, l10n.trackerImportMod),
              _menuRow(
                'modArchive',
                Icons.travel_explore,
                l10n.trackerModArchive,
              ),
              _menuRow(
                'importScore',
                Icons.file_open_outlined,
                l10n.trackerImportScore,
              ),
              _menuRow('demo', Icons.auto_awesome, l10n.trackerLoadDemo),
              _menuRow(
                'starterBeat',
                Icons.auto_fix_high,
                l10n.trackerStarterBeat,
              ),
              _menuRow(
                'soundLibrary',
                Icons.library_music,
                l10n.trackerSoundLibrary,
              ),
              _menuRow(
                'loadSoundFont',
                Icons.piano,
                l10n.trackerLoadSoundFont,
              ),
              const PopupMenuDivider(),
              _menuRow(
                'saveSong',
                Icons.bookmark_add_outlined,
                l10n.trackerSaveSong,
              ),
              _menuRow('shareSong', Icons.ios_share, l10n.trackerShareSong),
              _menuRow(
                'loadSong',
                Icons.download_outlined,
                l10n.trackerLoadSong,
              ),
              _menuRow('exportMidi', Icons.piano, l10n.trackerExportMidi),
              _menuRow('exportXml', Icons.description, l10n.trackerExportXml),
              _menuRow(
                'exportAbc',
                Icons.text_snippet_outlined,
                l10n.trackerExportAbc,
              ),
              _menuRow(
                'exportModule',
                Icons.grid_on,
                l10n.trackerExportModule,
              ),
              _menuRow('exportAudio', Icons.download, l10n.audioExportTitle),
              _menuRow('daw', Icons.library_add, l10n.dawSend),
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
                if (_showScope) _scopeStrip(context),
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
            case 'interpNotes':
              _interpolateNotesBlock();
            case 'fillVoice':
              _fillInstrumentBlock();
            case 'insRow':
              _insertRow();
            case 'delRow':
              _deleteRow();
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
          PopupMenuItem(
            value: 'interpNotes',
            child: Text(l10n.trackerInterpNotes),
          ),
          PopupMenuItem(
            value: 'fillVoice',
            child: Text(l10n.trackerBlockFillVoice),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'insRow', child: Text(l10n.trackerInsertRow)),
          PopupMenuItem(value: 'delRow', child: Text(l10n.trackerDeleteRow)),
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
  /// The master oscilloscope strip — the current pattern's mixed waveform with a
  /// red playhead sweeping across it during playback.
  Widget _scopeStrip(BuildContext context) {
    if (_scopeDirty || _scopePcm == null) {
      _scopePcm = _song.engine.renderLoopPcm();
      _scopeDirty = false;
    }
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: RepaintBoundary(
        child: ValueListenableBuilder<int>(
          valueListenable: _row,
          builder: (context, row, _) => CustomPaint(
            size: Size.infinite,
            painter: _ScopePainter(
              pcm: _scopePcm!,
              progress: row < 0 ? -1.0 : row / _song.rows,
              wave: _classic ? const Color(0xFF6EE787) : scheme.primary,
              bg: _classic
                  ? const Color(0xFF08120A)
                  : scheme.surfaceContainerLowest,
            ),
          ),
        ),
      ),
    );
  }

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
            IconButton(
              icon: Icon(
                _metronome ? Icons.av_timer : Icons.av_timer_outlined,
              ),
              tooltip: l10n.trackerMetronome,
              color: _metronome ? scheme.primary : null,
              onPressed: () => setState(() => _metronome = !_metronome),
            ),
            IconButton(
              icon: Icon(_quantize ? Icons.grid_on : Icons.grid_off),
              tooltip: l10n.trackerQuantize,
              color: _quantize ? scheme.primary : null,
              onPressed: () => setState(() => _quantize = !_quantize),
            ),
            IconButton(
              icon: Icon(
                _followPlay ? Icons.my_location : Icons.location_searching,
              ),
              tooltip: l10n.trackerFollow,
              color: _followPlay ? scheme.primary : null,
              onPressed: () => setState(() => _followPlay = !_followPlay),
            ),
            IconButton(
              icon: Icon(_showScope ? Icons.graphic_eq : Icons.show_chart),
              tooltip: l10n.trackerScope,
              color: _showScope ? scheme.primary : null,
              onPressed: () => setState(() => _showScope = !_showScope),
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
                      child: GestureDetector(
                        // Long-press a pattern to rename it (a song section).
                        onLongPress: () => _promptRenamePattern(i),
                        child: ChoiceChip(
                          label: Text(_song.patterns[i].name),
                          selected: i == _song.currentIndex,
                          onSelected: (_) => selectPattern(i),
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: l10n.trackerRenamePattern,
                    onPressed: () => _promptRenamePattern(_song.currentIndex),
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
          // Order list: the play sequence; the sounding entry lights up, the
          // selected slot (for reorder/retarget) is outlined.
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
                          selected:
                              playing >= 0 ? i == playing : i == _orderCursor,
                          side: (playing < 0 && i == _orderCursor)
                              ? BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 1.5,
                                )
                              : null,
                          onPressed: () {
                            setState(() => _orderCursor = i);
                            selectPattern(_song.order[i]);
                          },
                          onDeleted: () => _orderDelete(i),
                        ),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: Text(_song.current.name),
                      onPressed: () => addToOrder(_song.currentIndex),
                    ),
                    // Order-slot edit cluster (retarget · move · insert).
                    IconButton(
                      icon: const Icon(Icons.expand_more, size: 18),
                      tooltip: l10n.trackerOrderPrevPat,
                      onPressed: () => _orderRetarget(-1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.expand_less, size: 18),
                      tooltip: l10n.trackerOrderNextPat,
                      onPressed: () => _orderRetarget(1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 20),
                      tooltip: l10n.trackerOrderMoveLeft,
                      onPressed: () => _orderMove(-1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 20),
                      tooltip: l10n.trackerOrderMoveRight,
                      onPressed: () => _orderMove(1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.control_point_duplicate, size: 18),
                      tooltip: l10n.trackerOrderInsert,
                      onPressed: _orderInsert,
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
                  _setPatternLength(v);
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
            // Swing / groove — delays off-beat steps for a shuffle feel.
            Tooltip(
              message: l10n.trackerSwingHelp,
              child: Row(
                children: [
                  const Icon(Icons.waves, size: 16),
                  const SizedBox(width: 2),
                  Text('${l10n.trackerSwing}: '),
                  DropdownButton<double>(
                    value: _kSwingOptions.contains(_song.timing.swing)
                        ? _song.timing.swing
                        : null,
                    hint: Text('${(_song.timing.swing * 100).round()}%'),
                    items: [
                      for (final s in _kSwingOptions)
                        DropdownMenuItem(
                          value: s,
                          child: Text(
                            s == 0
                                ? l10n.trackerSwingOff
                                : '${(s * 100).round()}%',
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _song.setSwing(v));
                        _syncPlayback();
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Chord / arpeggio helper — stamp a chord at the cursor.
            OutlinedButton.icon(
              icon: const Icon(Icons.queue_music, size: 18),
              label: Text(l10n.trackerChord),
              onPressed: _showChordSheet,
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
            const SizedBox(width: 12),
            // Zoom + classic skin.
            IconButton(
              icon: const Icon(Icons.zoom_out, size: 20),
              tooltip: l10n.trackerZoomOut,
              onPressed: () =>
                  setState(() => _zoom = (_zoom - 0.15).clamp(0.75, 1.6)),
            ),
            IconButton(
              icon: const Icon(Icons.zoom_in, size: 20),
              tooltip: l10n.trackerZoomIn,
              onPressed: () =>
                  setState(() => _zoom = (_zoom + 0.15).clamp(0.75, 1.6)),
            ),
            IconButton(
              icon: Icon(_classic ? Icons.dark_mode : Icons.dark_mode_outlined),
              tooltip: l10n.trackerClassicSkin,
              color: _classic ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => setState(() => _classic = !_classic),
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
    if (value != null && value > 0) _setPatternLength(value);
  }

  /// Renames pattern [index] to a song-section label (Intro / Verse / Chorus …).
  Future<void> _promptRenamePattern(int index) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: _song.patterns[index].name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.trackerRenamePattern),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: l10n.trackerRenamePatternHint),
          onSubmitted: (t) => Navigator.of(ctx).pop(t),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.trackerCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l10n.trackerOk),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      setState(() => _song.renamePattern(index, name));
    }
  }

  Widget _grid(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stepsPerBeat = _song.timing.stepsPerBeat;
    final gridWidth = _rowNumWidth + _song.channelCount * _cellWidth;

    final grid = ColoredBox(
      color: _classic ? const Color(0xFF0A130A) : Colors.transparent,
      child: Scrollbar(
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
      ),
    );
    // 🔍 On desktop, the corner card shows the hovered cell's note + row chord;
    // leaving the grid clears it. No-op on touch.
    return MouseRegion(
      onExit: _inspect
          ? (_) {
              if (_hoverInfo != null) setState(() => _hoverInfo = null);
            }
          : null,
      child: Stack(
        children: [
          grid,
          if (_inspect && _hoverInfo != null)
            Positioned(top: 8, right: 8, child: _hoverInspectCard()),
        ],
      ),
    );
  }

  /// The desktop hover card (Inspect mode), pinned to the grid corner.
  Widget _hoverInspectCard() => IgnorePointer(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Card(
            elevation: 4,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: inspectBody(context, _hoverInfo!),
            ),
          ),
        ),
      );

  static const _headerHeight = 56.0;

  Widget _headerRow(ColorScheme scheme) {
    return Container(
      height: _headerHeight,
      color: scheme.surfaceContainerHigh,
      child: Row(
        children: [
          SizedBox(width: _rowNumWidth),
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
  double panOf(int channel) => _song.channels[channel].pan;
  @override
  void setPan(int channel, double pan) {
    setState(() => _song.engine.setChannelPan(channel, pan));
    _syncPlayback();
  }

  @override
  bool get songUsesPan => _song.usesPan;
  @override
  void setEnvelopePreset(int channel, String key) {
    setState(
      () => _song.engine
          .setChannelVolumeEnvelope(channel, _kEnvelopePresets[key]),
    );
    _syncPlayback();
  }

  @override
  bool hasEnvelope(int channel) =>
      _song.channels[channel].volumeEnvelope != null;
  @override
  bool get songUsesEnvelopes => _song.usesEnvelopes;
  @override
  void setPanPreset(int channel, String key) {
    setState(
      () => _song.engine.setChannelPanEnvelope(channel, _kPanPresets[key]),
    );
    _syncPlayback();
  }

  @override
  bool hasPanEnvelope(int channel) =>
      _song.channels[channel].panEnvelope != null;

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
    final Color? rowBg;
    if (_classic) {
      rowBg = isActive
          ? const Color(0xFF224A2C)
          : isMeasure
              ? const Color(0xFF12240F)
              : (isBeat ? const Color(0xFF0E1B0C) : const Color(0xFF0A130A));
    } else {
      rowBg = isActive
          ? scheme.primaryContainer
          : isMeasure
              ? scheme.surfaceContainerHigh
              : (isBeat ? scheme.surfaceContainerHighest : null);
    }
    final rowNumColor = _classic
        ? (isBeat ? const Color(0xFFE3B341) : const Color(0xFF3C6B44))
        : (isBeat ? scheme.primary : scheme.onSurfaceVariant);
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
                fontSize: 12 * _zoom,
                color: rowNumColor,
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
        ? (cell.volume! * 64)
            .round()
            .toRadixString(16)
            .toUpperCase()
            .padLeft(2, '0')
        : '··';
    // Effect column: the classic hex command (e.g. C20/A04) when present, else
    // the legacy arp/vibrato/slide letter, else a dot.
    final fx = cell.hasCommand
        ? _commandHex(cell)
        : (hasNote && cell.effect != TrackerEffect.none
            ? _effectCode(cell.effect)
            : '·');
    // Instrument column: the 1-based pool voice this note uses (blank/dot = the
    // channel default), so per-cell voices are visible at a glance.
    final inst = cell.instrument > 0 ? cell.instrument.toString() : '·';
    return MouseRegion(
      onEnter:
          _inspect ? (_) => _onCellHover(channel, row) : null, // 🔍 desktop
      child: GestureDetector(
        onTap: () => _onCellTap(channel, row),
        onLongPress: () => _cellMenu(channel, row),
        child: Container(
          width: _cellWidth,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? (_classic
                    ? const Color(0x553B5BDB)
                    : scheme.secondaryContainer.withValues(alpha: 0.6))
                : null,
            border: Border.all(
              color: isCursor
                  ? (_classic ? const Color(0xFFE3B341) : scheme.primary)
                  : (_classic
                      ? const Color(0xFF17301A)
                      : scheme.outlineVariant),
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
                    fontSize: 14 * _zoom,
                    color: hasNote
                        ? (_classic
                            ? _classicNoteColor(cell.midi!)
                            : scheme.onSurface)
                        : (_classic
                            ? const Color(0xFF2C4A32)
                            : scheme.onSurfaceVariant.withValues(alpha: 0.4)),
                    fontWeight: hasNote ? FontWeight.w600 : FontWeight.w400,
                    decoration: isCursor && _field == _CellField.note
                        ? TextDecoration.underline
                        : null,
                    decorationColor:
                        _classic ? const Color(0xFFE3B341) : scheme.primary,
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
                const SizedBox(width: 2),
                Text(
                  inst,
                  style: _instColStyle(
                    scheme,
                    cell.instrument > 0,
                    isCursor && _field == _CellField.instrument,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Style for the in-grid instrument column: a distinct accent (so per-cell
  /// voices stand out) when set, a faint dot for the channel default.
  TextStyle _instColStyle(ColorScheme scheme, bool set, bool active) =>
      TextStyle(
        fontFeatures: const [FontFeature.tabularFigures()],
        fontSize: 10 * _zoom,
        fontWeight: set ? FontWeight.w700 : FontWeight.w400,
        color: set
            ? (_classic ? const Color(0xFF7CE38B) : scheme.tertiary)
            : (_classic
                ? const Color(0xFF2C4A32)
                : scheme.onSurfaceVariant.withValues(alpha: 0.4)),
        decoration: active ? TextDecoration.underline : null,
        decorationColor: _classic ? const Color(0xFFE3B341) : scheme.primary,
        decorationThickness: 2,
      );

  TextStyle _subColStyle(ColorScheme scheme, bool active) => TextStyle(
        fontFeatures: const [FontFeature.tabularFigures()],
        fontSize: 10 * _zoom,
        color: _classic
            ? const Color(0xFF79A8FF)
            : scheme.onSurfaceVariant.withValues(alpha: 0.75),
        decoration: active ? TextDecoration.underline : null,
        decorationColor: _classic ? const Color(0xFFE3B341) : scheme.primary,
        decorationThickness: 2,
      );

  /// A per-pitch-class hue for classic-skin note text (readable, colour-coded).
  static Color _classicNoteColor(int midi) =>
      HSVColor.fromAHSV(1, (midi % 12) / 12 * 360, 0.55, 0.95).toColor();

  /// The effect column as a 3-char code: a single command char + a 2-hex param.
  /// Radix-36 gives the classic tracker letter scheme — 0–9 then A–F for the MOD
  /// nibbles, and G, H, P, T… for the extended (>0xF) effects (global volume,
  /// pan/tempo slide) — so an extended command still fits the column (e.g. G20).
  static String _commandHex(TrackerCell c) {
    final cmd = c.fxCmd.toRadixString(36).toUpperCase();
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
              // Base octave for the computer keyboard (also slides the piano).
              IconButton(
                icon: const Icon(Icons.remove),
                tooltip: '${l10n.trackerOctave} −',
                onPressed: () => _setOctave(_octave - 1),
              ),
              Text('${l10n.trackerOctave} $_octave'),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: '${l10n.trackerOctave} +',
                onPressed: () => _setOctave(_octave + 1),
              ),
              // Piano key-size zoom.
              IconButton(
                icon: const Icon(Icons.zoom_out, size: 20),
                tooltip: l10n.trackerZoomOut,
                onPressed: () => setState(
                  () => _pianoZoom = (_pianoZoom - 0.2).clamp(0.6, 2.2),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.zoom_in, size: 20),
                tooltip: l10n.trackerZoomIn,
                onPressed: () => setState(
                  () => _pianoZoom = (_pianoZoom + 0.2).clamp(0.6, 2.2),
                ),
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
                      _CellField.instrument => 'ins',
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
                  width: _pianoWhiteKeys * _pianoKW,
                  // Rebuild only the keyboard as the playhead crosses rows, so
                  // the keys of the sounding notes light up in time.
                  child: ValueListenableBuilder<int>(
                    valueListenable: _row,
                    builder: (context, _, __) => PianoKeyboard(
                      startMidi: _pianoStartMidi,
                      whiteKeyCount: _pianoWhiteKeys,
                      showLabels: true,
                      showOctaveNumbers: true,
                      keyColors: _soundingKeys(),
                      keyHints: _pianoKeyHints(),
                      onKeyTap: (midi) {
                        _enterNoteAtCursor(midi);
                        _focus.requestFocus();
                      },
                    ),
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
              _helpRow(ctx, l10n.trackerField, 'Tab / Shift+Tab'),
              _helpRow(ctx, l10n.trackerInstColumn, l10n.trackerInstColumnHelp),
              const Divider(height: 20),
              _helpRow(ctx, l10n.trackerPlay, 'F5 song · F6 pattern'),
              _helpRow(
                ctx,
                l10n.trackerPlayFromCursor,
                'F7  ·  F8 ${l10n.trackerStop}',
              ),
              _helpRow(ctx, l10n.trackerInterpolate, 'Ctrl/⌘ + I'),
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
              _helpRow(
                ctx,
                l10n.trackerBlockFillVoice,
                l10n.trackerBlockFillVoiceHelp,
              ),
              const Divider(height: 20),
              _helpRow(ctx, l10n.trackerFxColumn, l10n.trackerFxHelp),
              _helpRow(ctx, '0 1 2 3 4', l10n.trackerFxPitch),
              _helpRow(ctx, '7 A C', l10n.trackerFxTremVolSet),
              _helpRow(ctx, 'B D F E', l10n.trackerFxFlow),
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

  // The full MOD command set the replayer implements (nibble → label).
  // 0x0 with param 0 = none; 0x0 with param != 0 = arpeggio.
  static const _commands = <int, String>{
    0x0: '0xy  Arpeggio / None',
    0x1: '1xx  Portamento up',
    0x2: '2xx  Portamento down',
    0x3: '3xx  Tone portamento',
    0x4: '4xy  Vibrato',
    0x5: '5xy  Tone-porta + vol slide',
    0x6: '6xy  Vibrato + vol slide',
    0x7: '7xy  Tremolo',
    0xA: 'Axy  Volume slide',
    0xB: 'Bxx  Position jump',
    0xC: 'Cxx  Set volume',
    0xD: 'Dxx  Pattern break',
    0xE: 'Exy  Extended',
    0xF: 'Fxx  Set speed / tempo',
    // Extended (letter) effects the replayer supports; shown G../H../P../T..
    kFxSetGlobalVolume: 'Gxx  Set global volume',
    kFxGlobalVolSlide: 'Hxy  Global volume slide',
    kFxPanSlide: 'Pxy  Pan slide',
    kFxTempoSlide: 'Txy  Tempo slide',
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
                setState(() => _cmd = v ?? 0);
                widget.onChanged(_cmd, _param);
              },
            ),
            const SizedBox(width: 12),
            // Full hex code (cmd nibble + param byte), FT2-style.
            Text(
              '${_cmd.toRadixString(16).toUpperCase()}'
              '${_param.toRadixString(16).toUpperCase().padLeft(2, '0')}',
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        // Param 00–FF (0 with cmd 0 = no command).
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

/// Draws a pattern's mixed PCM as a vertical-bar waveform with a playhead line.
/// Maps a local tap [pos] inside an envelope canvas of [size] to a
/// `(ms 0..2000, value minV..1)` breakpoint — x → ms, y inverted (top = 1).
(int, double) envPointFromLocal(Offset pos, Size size, double minV) {
  final ms =
      size.width <= 0 ? 0 : (pos.dx / size.width * 2000).round().clamp(0, 2000);
  final t = size.height <= 0 ? 1.0 : (1 - pos.dy / size.height).clamp(0.0, 1.0);
  final value = (minV + t * (1 - minV)).clamp(minV, 1.0);
  return (ms, value);
}

/// The index of the [points] breakpoint whose canvas x is nearest [pos] within
/// [thresholdPx] (drag-to-move hit test), or null if the tap missed them all.
int? nearestEnvPointIndex(
  List<(int, double)> points,
  Offset pos,
  Size size, {
  double thresholdPx = 32,
}) {
  if (points.isEmpty || size.width <= 0) return null;
  int? best;
  var bestDx = thresholdPx;
  for (var i = 0; i < points.length; i++) {
    final x = points[i].$1.clamp(0, 2000) / 2000 * size.width;
    final dx = (x - pos.dx).abs();
    if (dx <= bestDx) {
      bestDx = dx;
      best = i;
    }
  }
  return best;
}

/// Draws a custom envelope's `(ms, value)` breakpoints as a line with dots over
/// a 0–2000 ms axis, value from [minV]..1 mapped top(1)→bottom(minV).
class _EnvelopePainter extends CustomPainter {
  _EnvelopePainter({
    required this.points,
    required this.minV,
    required this.line,
    required this.grid,
  });

  final List<(int, double)> points;
  final double minV;
  final Color line;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    // A baseline (value 0 for pan, or bottom for volume) + top/bottom frame.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = grid.withValues(alpha: 0.15),
    );
    final zeroY = _y(0, size);
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), gridPaint);
    if (points.isEmpty) return;

    final path = Path();
    final dot = Paint()..color = line;
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < points.length; i++) {
      final x = (points[i].$1.clamp(0, 2000) / 2000) * size.width;
      final y = _y(points[i].$2, size);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3, dot);
    }
    canvas.drawPath(path, stroke);
  }

  double _y(double value, Size size) {
    final t = ((value - minV) / (1.0 - minV)).clamp(0.0, 1.0);
    return size.height - t * size.height;
  }

  @override
  bool shouldRepaint(_EnvelopePainter old) =>
      old.points != points || old.minV != minV;
}

class _ScopePainter extends CustomPainter {
  _ScopePainter({
    required this.pcm,
    required this.progress,
    required this.wave,
    required this.bg,
  });

  final Int16List pcm;
  final double progress; // 0..1, or <0 when stopped
  final Color wave;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    if (pcm.isEmpty) return;
    final mid = size.height / 2;
    final p = Paint()
      ..color = wave
      ..strokeWidth = 1;
    final cols = size.width.round().clamp(1, 4000);
    final n = pcm.length;
    for (var x = 0; x < cols; x++) {
      final i0 = (x * n / cols).floor();
      final i1 = ((x + 1) * n / cols).floor().clamp(i0 + 1, n);
      var peak = 0;
      for (var i = i0; i < i1; i++) {
        final a = pcm[i].abs();
        if (a > peak) peak = a;
      }
      final h = (peak / 32768) * mid;
      final xx = x * size.width / cols;
      canvas.drawLine(Offset(xx, mid - h), Offset(xx, mid + h), p);
    }
    if (progress >= 0) {
      canvas.drawLine(
        Offset(progress * size.width, 0),
        Offset(progress * size.width, size.height),
        Paint()
          ..color = const Color(0xFFFF5252)
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_ScopePainter old) =>
      old.progress != progress ||
      !identical(old.pcm, pcm) ||
      old.bg != bg ||
      old.wave != wave;
}

/// Crops [pcm] to the fractional region [start]..[end] (0..1). Returns the whole
/// buffer for the full range and a copy of the slice otherwise — never mutates
/// the source (the sheet keeps the original clip for re-trimming).
Float64List sliceFraction(Float64List pcm, double start, double end) {
  if (pcm.isEmpty) return pcm;
  final s = start.clamp(0.0, 1.0);
  final e = end.clamp(s, 1.0);
  if (s <= 0.0 && e >= 1.0) return pcm;
  final i0 = (s * pcm.length).floor().clamp(0, pcm.length);
  final i1 = (e * pcm.length).ceil().clamp(i0, pcm.length);
  return Float64List.sublistView(pcm, i0, i1);
}

/// The sample editor's waveform strip: a peak-per-column render of the recorded
/// clip with two draggable trim handles; the kept region is bright, the cropped
/// tails dim. Reports the new [start]/[end] fractions as the user drags.
class _SampleWaveform extends StatefulWidget {
  const _SampleWaveform({
    required this.pcm,
    required this.start,
    required this.end,
    required this.onChanged,
    required this.wave,
    required this.bg,
  });

  final Float64List pcm;
  final double start;
  final double end;
  final void Function(double start, double end) onChanged;
  final Color wave;
  final Color bg;

  @override
  State<_SampleWaveform> createState() => _SampleWaveformState();
}

class _SampleWaveformState extends State<_SampleWaveform> {
  int _handle = 0; // 0 = start, 1 = end — whichever the drag grabbed

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        double fracAt(double dx) => (dx / w).clamp(0.0, 1.0);
        void grab(double dx) {
          final f = fracAt(dx);
          _handle = (f - widget.start).abs() <= (f - widget.end).abs() ? 0 : 1;
        }

        void drag(double dx) {
          final f = fracAt(dx);
          if (_handle == 0) {
            widget.onChanged(f.clamp(0.0, widget.end - 0.02), widget.end);
          } else {
            widget.onChanged(widget.start, f.clamp(widget.start + 0.02, 1.0));
          }
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => grab(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => drag(d.localPosition.dx),
          onTapDown: (d) {
            grab(d.localPosition.dx);
            drag(d.localPosition.dx);
          },
          child: CustomPaint(
            size: Size(w, 64),
            painter: _WaveformPainter(
              pcm: widget.pcm,
              start: widget.start,
              end: widget.end,
              wave: widget.wave,
              bg: widget.bg,
            ),
          ),
        );
      },
    );
  }
}

/// Paints [pcm] (−1..1 floats) as a peak-per-column waveform, dimming the
/// cropped tails outside [start]..[end] and drawing a knob at each handle.
class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.pcm,
    required this.start,
    required this.end,
    required this.wave,
    required this.bg,
  });

  final Float64List pcm;
  final double start;
  final double end;
  final Color wave;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );
    canvas.drawRRect(r, Paint()..color = bg);
    canvas.save();
    canvas.clipRRect(r);
    final mid = size.height / 2;
    if (pcm.isNotEmpty) {
      final cols = size.width.round().clamp(1, 4000);
      final n = pcm.length;
      final keep = Paint()
        ..color = wave
        ..strokeWidth = 1;
      final drop = Paint()
        ..color = wave.withValues(alpha: 0.28)
        ..strokeWidth = 1;
      for (var x = 0; x < cols; x++) {
        final frac = x / cols;
        final i0 = (x * n / cols).floor();
        final i1 = ((x + 1) * n / cols).floor().clamp(i0 + 1, n);
        var peak = 0.0;
        for (var i = i0; i < i1; i++) {
          final a = pcm[i].abs();
          if (a > peak) peak = a;
        }
        final h = peak.clamp(0.0, 1.0) * mid;
        final xx = x * size.width / cols;
        canvas.drawLine(
          Offset(xx, mid - h),
          Offset(xx, mid + h),
          frac >= start && frac <= end ? keep : drop,
        );
      }
    }
    // Shade the cropped tails.
    final shade = Paint()..color = bg.withValues(alpha: 0.5);
    if (start > 0) {
      canvas.drawRect(
        Rect.fromLTRB(0, 0, start * size.width, size.height),
        shade,
      );
    }
    if (end < 1) {
      canvas.drawRect(
        Rect.fromLTRB(end * size.width, 0, size.width, size.height),
        shade,
      );
    }
    // Handles.
    final line = Paint()
      ..color = const Color(0xFFFF5252)
      ..strokeWidth = 2;
    for (final f in [start, end]) {
      final x = f * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      canvas.drawCircle(Offset(x, mid), 6, line..style = PaintingStyle.fill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.start != start ||
      old.end != end ||
      !identical(old.pcm, pcm) ||
      old.wave != wave ||
      old.bg != bg;
}
