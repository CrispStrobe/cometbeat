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

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/beat_to_tracker.dart';
import 'package:comet_beat/core/audio/chroma_analysis.dart'
    show ChordTemplate, kChordTemplates;
import 'package:comet_beat/core/audio/crisp_dsp/sample_edit.dart';
import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart';
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart';
import 'package:comet_beat/core/audio/daw_sources.dart' show TrackerSource;
import 'package:comet_beat/core/audio/mod/module_convert.dart'
    show convertDocTo;
import 'package:comet_beat/core/audio/mod/module_doc.dart' show ModuleFormat;
import 'package:comet_beat/core/audio/mod/module_export_report.dart'
    show moduleExportLossReport;
import 'package:comet_beat/core/audio/mod/module_flow_timeline.dart';
import 'package:comet_beat/core/audio/pattern_record.dart';
import 'package:comet_beat/core/audio/sample_pitch.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum, wavBytes;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_native_command.dart';
import 'package:comet_beat/core/audio/tracker_pattern_fit.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart'
    show
        RowTiming,
        kFxGlobalVolSlide,
        kFxPanSlide,
        kFxPanbrello,
        kFxRetrigVolSlide,
        kFxSampleOffset,
        kFxSetPan,
        kFxSetGlobalVolume,
        kFxTempoSlide,
        kFxTremor,
        resolveTimingMap,
        rowIndexAtMs;
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/audio/tracker_song_codec.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:comet_beat/core/audio/voice_clip_recorder.dart';
import 'package:comet_beat/core/audio/wav_io.dart'
    show readWavPcm16, wavToMonoFloat;
import 'package:comet_beat/core/interop/drag_payload.dart';
import 'package:comet_beat/core/interop/project_bridge.dart';
import 'package:comet_beat/core/licensing/license_obligations.dart';
import 'package:comet_beat/core/midi/midi_input.dart';
import 'package:comet_beat/core/notation/multi_part_export.dart'
    show multiPartToAbc, multiPartToMidi, multiTrackMidiToMultiPart;
import 'package:comet_beat/core/project/project_link.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/beat_bridge.dart';
import 'package:comet_beat/core/services/gapless_loop_player.dart';
import 'package:comet_beat/core/services/melody_bridge.dart';
import 'package:comet_beat/core/services/project_service.dart';
import 'package:comet_beat/core/services/transport_service.dart';
import 'package:comet_beat/core/services/undo_service.dart';
import 'package:comet_beat/features/games/composition/instrument_editor.dart';
import 'package:comet_beat/features/games/composition/multipart_to_tracker.dart';
import 'package:comet_beat/features/games/composition/music_inspect.dart';
import 'package:comet_beat/features/games/composition/oscilloscope_widget.dart';
import 'package:comet_beat/features/games/composition/sample_waveform_widget.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:comet_beat/features/games/composition/tab_workshop_screen.dart';
import 'package:comet_beat/features/games/composition/tracker_meter.dart';
import 'package:comet_beat/features/games/composition/tracker_notation.dart';
import 'package:comet_beat/features/games/composition/tracker_piano_roll.dart';
import 'package:comet_beat/features/games/composition/tracker_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
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
import 'package:comet_beat/shared/keyboard_notes.dart';
import 'package:comet_beat/shared/keymap/intents.dart';
import 'package:comet_beat/shared/keymap/keymap.dart';
import 'package:comet_beat/shared/keymap/keymap_service.dart';
import 'package:comet_beat/shared/keymap/keymap_sheet.dart';
import 'package:comet_beat/shared/music/music_picker.dart'
    show showMusicPickerWithLicense;
import 'package:comet_beat/shared/music_io/audio_export.dart'
    show showAudioExportSheet;
import 'package:comet_beat/shared/music_io/export_sheet.dart';
import 'package:comet_beat/shared/music_io/license_gate.dart';
import 'package:comet_beat/shared/tutorial/tutorial.dart';
import 'package:comet_beat/shared/tutorial/tutorial_sheet.dart';
import 'package:comet_beat/shared/widgets/open_in_menu.dart';
import 'package:comet_beat/shared/widgets/performance_pads.dart';
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
        readMusicXmlFromMxl,
        scoreFromLilyPond;
import 'package:crisp_notation_core/crisp_notation_core.dart' show StaffSystem;
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

/// FastTracker-2 style computer-keyboard piano map, now SHARED with the Note
/// Highway (`lib/shared/keyboard_notes.dart`) — two surfaces disagreeing about
/// which key plays a D# is exactly the drift that copying it would cause. The
/// mapping is unchanged.
const _kKeyToSemitone = kKeyToSemitone;

/// How far down the viewport the playing row sits.
const double kFollowMarginPx = 120;

/// Past this, easing is the wrong answer — the song has JUMPED (a wrap, or a
/// Bxx/Dxx order jump), and gliding across the whole pattern would arrive after
/// the music has already moved on.
const double kFollowSnapPx = 400;

/// Fraction of the remaining distance covered per frame.
const double kFollowEase = 0.25;

/// WS-T1 — where the grid should scroll to for a playhead at [exactRow].
///
/// Pure, and deliberately so. Whether the VIEW moves in a widget test depends
/// on how much time each pump delivers, which made my first version of this
/// test flaky under `--concurrency`: it was measuring the harness. The
/// interesting part is this arithmetic, and it is exact.
///
/// Returns null when the view is already close enough, so a stationary playhead
/// never fights someone scrolling by hand.
double? followScrollOffset({
  required double exactRow,
  required double rowHeight,
  required double current,
  required double maxExtent,
}) {
  final target =
      ((exactRow * rowHeight) - kFollowMarginPx).clamp(0.0, maxExtent);
  final delta = target - current;
  if (delta.abs() < 0.5) return null;
  // A jump means the song wrapped or leapt, not that it advanced; gliding
  // there would arrive late.
  if (delta.abs() > kFollowSnapPx) return target;
  // Otherwise ease: a fraction of what remains, per frame.
  return current + delta * kFollowEase;
}

/// WS-W4 — this surface's slice of the shared undo history.
///
/// Public and top-level, like `DawService.kUndoScope`, because the history
/// PANEL and the tests both need to name it and the state class is private.
const String kTrackerUndoScope = 'tracker';

class AdvancedTrackerScreen extends StatefulWidget {
  const AdvancedTrackerScreen({
    super.key,
    this.initialSong,
    this.autoShareOnExit = false,
    this.onReturnToDaw,
  });

  /// When set (opened to edit an Audio Editor tracker clip), "Send to Audio
  /// Editor" calls this with the edited song and pops back — an IN-PLACE round
  /// trip that updates the source clip instead of adding a second copy of the
  /// same music. Null keeps the normal add-a-new-clip send.
  final void Function(TrackerSong edited)? onReturnToDaw;

  /// An optional song to open with — the Beginner→Advanced "promote" hands its
  /// groove over here so the switch keeps the kid's work instead of starting
  /// fresh. Null = a new empty song.
  final TrackerSong? initialSong;

  /// When true, on leaving the screen the edited melody is published back to
  /// [MelodyBridge] automatically (only if the user actually edited) — so Loop
  /// Studio's "Fine-tune in Tracker" round-trip needs no manual "Share tune"
  /// tap. Default false → every other entry point behaves exactly as before.
  final bool autoShareOnExit;

  @override
  State<AdvancedTrackerScreen> createState() => _AdvancedTrackerScreenState();
}

/// The flow/order-command kinds the editable flow timeline can author on an
/// order entry. Each maps to a pure helper in module_flow_timeline.dart.
enum _FlowEditKind {
  jump(Icons.call_split),
  brk(Icons.skip_next),
  speed(Icons.speed),
  tempo(Icons.timer_outlined),
  loop(Icons.repeat);

  const _FlowEditKind(this.icon);

  final IconData icon;

  String label(AppLocalizations l10n) => switch (this) {
        _FlowEditKind.jump => l10n.trackerFlowSetJump,
        _FlowEditKind.brk => l10n.trackerFlowSetBreak,
        _FlowEditKind.speed => l10n.trackerFlowSetSpeedCmd,
        _FlowEditKind.tempo => l10n.trackerFlowSetTempoCmd,
        _FlowEditKind.loop => l10n.trackerFlowSetLoop,
      };
}

/// A tiny numeric-entry dialog for a flow-command value. A dedicated widget so
/// its [TextEditingController] lives exactly as long as the dialog (disposing it
/// right after `showDialog` returns crashes the still-animating exit transition).
class _FlowNumberDialog extends StatefulWidget {
  const _FlowNumberDialog({
    required this.title,
    required this.initial,
    required this.min,
    required this.max,
    required this.cancelLabel,
    required this.applyLabel,
  });

  final String title;
  final int initial;
  final int min;
  final int max;
  final String cancelLabel;
  final String applyLabel;

  @override
  State<_FlowNumberDialog> createState() => _FlowNumberDialogState();
}

class _FlowNumberDialogState extends State<_FlowNumberDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration:
              InputDecoration(helperText: '${widget.min}–${widget.max}'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.cancelLabel),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(_controller.text.trim());
              Navigator.of(context).pop(v?.clamp(widget.min, widget.max));
            },
            child: Text(widget.applyLabel),
          ),
        ],
      );
}

/// Test handle onto the running screen (the state class is private) — mirrors
/// [TrackerTester] on the Beginner screen.
@visibleForTesting
abstract interface class AdvancedTrackerTester {
  int get channelCount;
  int get rows;

  /// WS-X1 — put this song in the project, then re-open that track LIVE and
  /// have edits land back in it.
  String? addSongToProject({String? name});
  bool openProjectTrack(String trackId);
  bool get hasLiveProjectLink;
  bool writeBackToProject();
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

  /// WS-T1 — whether the view follows the playing row.
  bool get followPlay;
  void setFollowPlay(bool on);

  /// The grid's scroll offset, and how far it CAN scroll. Exposed because a
  /// test cannot reliably pick the right `Scrollable` out of this screen —
  /// picking the wrong one reads `maxScrollExtent == 0` and every follow
  /// assertion then passes without running.
  double get gridScrollOffset;
  double get gridScrollExtent;
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

  /// Shared-groove bridge: publish the song's percussion channels out, and pull
  /// a shared beat in (as a fresh channel-per-drum drum song).
  void shareBeat();
  bool get canLoadSharedBeat;
  void loadSharedBeat();

  /// Shared-tune bridge (the pitched twin): publish the first melodic channel
  /// out, and pull a shared tune in onto it.
  void shareMelody();
  bool get canLoadSharedMelody;
  void loadSharedMelody();

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

  /// Import a decoded score through the shared music picker bridge.
  void debugImportMusic(MultiPartScore score);

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

  /// Test seam: run the on-exit auto-share hook as if the route were popped
  /// (drives the Loop Studio "Fine-tune in Tracker" round-trip).
  void debugSimulateExit();

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

  /// Test: open the editable flow/order-command timeline sheet.
  void debugShowFlowTimeline();

  /// Order-list editing.
  List<int> get orderList;

  /// WS-T2 — drag a slot from one position to another.
  void reorderOrderSlot(int from, int to);

  /// Open the song-overview sheet (the toolbar button's target).
  Future<void> openOrderOverview();

  /// WS-T4 — open the piano roll for the cursor's channel.
  Future<void> openPianoRoll();

  /// WS-T6 — the meter used to DRAW beat and bar lines. Null = follow the
  /// pattern's own steps-per-beat at four beats to the bar.
  TrackerMeter? get meterOverride;
  void setMeterOverride(TrackerMeter? meter);

  /// Which order slot is selected.
  int get orderCursor;
  void setOrderCursor(int index);
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

  /// WS-T7 test seam: the MIDI input the pads push into.
  ///
  /// A test sends real `MidiMessage`s rather than tapping pads, because what is
  /// under test is the RECORD path — the pads themselves have their own suite,
  /// and driving them through a modal sheet on a screen whose Ticker never
  /// settles would test the sheet instead.
  ManualMidiInput get debugMidiInput;

  /// WS-X2 test seam: drop [payload] on the pattern grid, skipping the
  /// confirmation (the dialog is the shared shape Loop Studio's target already
  /// proved). Returns whether anything landed.
  bool debugDrop(MusicDragPayload payload);

  /// WS-X2 test seam: what a drop of [payload] would warn about — empty when it
  /// costs nothing, which is when no dialog should appear.
  List<String> debugDropWarnings(MusicDragPayload payload);

  /// Whether the cell at [channel]/[row] is a key-off (a recorded release).
  bool isNoteCutAt(int channel, int row);

  /// Whether a count-in is still running (nothing is being committed yet).
  bool get isCountingIn;

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

  /// Test seams for the block ops: anchor a selection corner at [channel]/[row]
  /// (the cursor is the other corner, via [moveCursor]); read/write a cell's
  /// note volume; read a cell's raw midi. Editor-only, for [interpolateBlock] /
  /// copy / paste coverage.
  void debugMarkBlock(int channel, int row);
  double? debugCellVolume(int channel, int row);
  void debugSetCellVolume(int channel, int row, double volume);
  int? debugCellMidi(int channel, int row);
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
  ///
  /// It stays the AUTHORITY after WS-W2: the shared [TransportService] is fed
  /// FROM it (`_transport?.syncTo`), never the other way round. A Stopwatch
  /// cannot drift; an accumulated per-frame delta can, and the audio here is a
  /// free-running pre-rendered WAV that would not drift with it.
  final _clock = Stopwatch();

  /// WS-X1 — the project track this screen is editing LIVE, if any. Null means
  /// the song belongs to no track, which is the pre-project behaviour and stays
  /// perfectly valid.
  ProjectLink? _projectLink;

  /// The app-wide project, when one is provided.
  ProjectService? _projects;

  /// The app-wide transport, when one is provided. Null in the widget tests
  /// that mount this screen bare, so every use is null-safe rather than
  /// requiring every existing test to grow a provider tree.
  TransportService? _transport;
  late final Ticker _ticker;

  /// The sounding row (0-based), or -1 when stopped. Drives the playhead without
  /// a full rebuild.
  final _row = ValueNotifier<int>(-1);
  final _progress = ValueNotifier<double>(-1.0);

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

  /// WS-T7 — the pass currently being recorded, or null when not recording.
  ///
  /// It owns two things the old per-note path could not: the count-in gate (a
  /// note played during the count is heard but not kept) and the "one undo
  /// entry per pass" rule. Created on arming, dropped on disarming.
  RecordPass? _pass;

  /// Notes held on the pads/MIDI right now, so a chord recorded together is
  /// written together rather than one cell at a time.
  final _held = HeldNotes();

  /// Where each sounding note was written, so its RELEASE can be recorded too.
  ///
  /// A tracker stores a note's length as a key-off cell further down the
  /// channel, so the release needs to know which channel and row the note-on
  /// landed on — and a chord spreads across channels, so that is per note, not
  /// per pass.
  final _sounding = <int, ({int channel, int row})>{};

  /// The MIDI input the on-screen pads push into. Owned here so the pads sheet
  /// can come and go without losing the subscription — and so hardware MIDI
  /// (WS-X5 3a) lands as a second producer with nothing else to change.
  final _midi = ManualMidiInput(devices: const ['On-screen pads']);
  StreamSubscription<MidiMessage>? _midiSub;

  /// Which sub-column the cursor edits in-grid (FT2 note/vol/fx columns). Typing
  /// hex into vol/fx edits that column directly; Tab / ←→ move between fields.
  _CellField _field = _CellField.note;

  /// WS-T6 — how rows group into beats and bars, for DRAWING.
  ///
  /// Was `int? _highlightEvery`, which was declared, read once, and assigned
  /// nowhere — the "configurable" row-highlight spacing had never been
  /// configurable. And the bar line was computed as `highlight * 4`, so
  /// beats-per-bar was hardcoded: a pattern in 3/4 got its bars in the wrong
  /// place regardless.
  ///
  /// Null means "follow the pattern", i.e. `stepsPerBeat` rows to the beat and
  /// four beats to the bar. Display only — this changes no playback, which is
  /// why it is here and not in `TrackerTiming`.
  TrackerMeter? _meterOverride;

  /// The meter in force, given the pattern's own steps-per-beat.
  TrackerMeter _meterFor(int stepsPerBeat) =>
      _meterOverride ?? TrackerMeter(rowsPerBeat: stepsPerBeat);

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
  /// WS-W4 — the shared, cross-surface history.
  ///
  /// The snapshot MECHANISM is unchanged: an entry still holds a whole-pattern
  /// `exportCells()` before and after, because that is what a tracker edit is.
  /// What changed is who owns the stack, so the Tracker's work finally appears
  /// in the history panel beside every other surface's.
  ///
  /// ⚠️ A PRIVATE service when none is in scope. The games registry and most of
  /// this screen's own tests mount it bare, and undo has worked there since it
  /// shipped — one code path either way, rather than a screen that silently
  /// stops recording depending on how it was reached.
  UndoService get _history => _sharedHistory ?? _ownHistory;
  final _ownHistory = UndoService();
  UndoService? _sharedHistory;

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
    // WS-T7 — one subscription for the whole screen's lifetime, so the pads
    // sheet can open and close without notes being lost or doubled, and so
    // hardware MIDI (WS-X5 3a) lands as a second producer with nothing here to
    // change.
    _midiSub = _midi.messages.listen(_onMidi);
    _ticker = createTicker((_) {
      if (_paused) return; // freeze the playhead where it is
      if (!_clock.isRunning) {
        if (_transport != null && _transport!.isPlaying) _transport!.pause();
        if (_row.value != -1) _row.value = -1;
        if (_progress.value != -1.0) _progress.value = -1.0;
        if (_playingOrder.value != -1) _playingOrder.value = -1;
        if (_levels.value.isNotEmpty) _levels.value = const [];
        return;
      }
      // WS-W2 — publish this surface's phase into the SHARED transport so any
      // other surface can follow the Tracker's playhead. `syncTo`, not
      // `advance`: the Stopwatch above is the authority and is monotonic, while
      // accumulating per-frame deltas drifts on every dropped frame.
      _transport?.syncTo(_elapsedMs.toDouble());

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
          // ⚠️ WS-T1 — this branch (playing the ORDER, i.e. the whole song)
          // never followed the playhead at all: the old call sat only in the
          // single-pattern branch below. So "follow" silently did nothing in
          // the mode people actually listen in.
          _followPlayhead(e.row + _rowPhase);
        }
      } else {
        if (_playingOrder.value != -1) _playingOrder.value = -1;
        posInPattern = _elapsedMs % t.totalMs;
        final step = posInPattern ~/ t.stepMs;
        _rowPhase = t.stepMs > 0 ? (posInPattern % t.stepMs) / t.stepMs : 0.0;
        if (step != _row.value) {
          _row.value = step;
          _maybeTick(step);
        }
        // WS-T1 — every tick, at the SUB-ROW position, so the view moves with
        // the music instead of once per row.
        _followPlayhead(step + _rowPhase);
      }
      _progress.value = posInPattern / t.totalMs;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Optional on purpose: the existing widget tests mount this screen without
    // a provider tree, and making the transport required would mean editing
    // every one of them to prove something they are not about.
    try {
      final transport = Provider.of<TransportService>(context, listen: false);
      if (!identical(transport, _transport)) {
        _transport?.removeListener(_onTransportCommand);
        _transport = transport..addListener(_onTransportCommand);
      }
    } on ProviderNotFoundException {
      _transport = null;
    }
    try {
      _projects = Provider.of<ProjectService>(context, listen: false);
    } on ProviderNotFoundException {
      _projects = null;
    }
    try {
      _sharedHistory = Provider.of<UndoService>(context, listen: false);
    } on ProviderNotFoundException {
      _sharedHistory = null; // keeps the private one — see [_history]
    }
  }

  // --- WS-X1 live links -----------------------------------------------------

  ProjectLinker? get _linker {
    final projects = _projects;
    return projects == null ? null : ProjectLinker(projects);
  }

  /// Adds the current song to the project and links this screen to that track,
  /// so subsequent edits can be written back.
  @override
  String? addSongToProject({String? name}) {
    final linker = _linker;
    if (linker == null) return null;
    _song.syncCurrent();
    final id = linker.add(
      kind: AppMode.tracker,
      document: _song,
      name: name ?? 'Tracker',
    );
    _projectLink = ProjectLink(document: _song, trackId: id, live: true);
    return id;
  }

  /// Opens a project track here. A tracker track opens LIVE — no conversion,
  /// no copy — and anything else arrives converted, with its loss report
  /// intact, exactly as before.
  @override
  bool openProjectTrack(String trackId) {
    final linker = _linker;
    if (linker == null) return false;
    final link = linker.open(trackId, AppMode.tracker);
    final doc = link.document;
    if (doc is! TrackerSong) return false;
    setState(() {
      _song = doc;
      _timingMap = null;
      _projectLink = link;
    });
    return true;
  }

  /// WS-X1c — the menu action. `addSongToProject` existed for two slices with
  /// no caller, which meant a user could never put a track in a project at all
  /// and the mixer was permanently empty for them.
  void _addToProjectFromMenu() {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    // Null only when no ProjectService is provided, which the real app always
    // does. Saying nothing beats inventing a message for a state a user cannot
    // reach — and beats borrowing an unrelated string for it, which is what I
    // did first.
    if (addSongToProject() == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.projectAdded)));
  }

  @override
  bool get hasLiveProjectLink => _projectLink?.live ?? false;

  /// Pushes the current song back into its project track.
  @override
  bool writeBackToProject() {
    final linker = _linker;
    final link = _projectLink;
    if (linker == null || link == null) return false;
    _song.syncCurrent();
    return linker.writeBack(link, _song);
  }

  @override
  void dispose() {
    _transport?.removeListener(_onTransportCommand);
    // ⚠️ Every entry closes over this `State`, and the shared service outlives
    // the screen. Leaving them in place would let an undo pressed on another
    // surface reach into a dead screen — the trap @loop-d1d4 documented, which
    // this screen inherits and the DAW does not.
    _history.clearScope(kTrackerUndoScope);
    _midiSub?.cancel();
    _midi.dispose();
    _ticker.dispose();
    _row.dispose();
    _progress.dispose();
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
  @override
  bool get followPlay => _followPlay;

  @override
  double get gridScrollOffset =>
      _vScroll.hasClients ? _vScroll.position.pixels : -1;

  @override
  double get gridScrollExtent =>
      _vScroll.hasClients ? _vScroll.position.maxScrollExtent : -1;

  @override
  void setFollowPlay(bool on) => setState(() => _followPlay = on);

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

  /// WS-T6 — choose how rows group into beats and bars.
  ///
  /// Display only, and the sheet says so: someone changing this is asking the
  /// grid to be readable, not asking the song to play differently, and a
  /// control that looked like it re-barred the music would be a lie.
  Future<void> _pickMeter() async {
    final current = _meterFor(_song.timing.stepsPerBeat);
    final chosen = await showModalBottomSheet<TrackerMeter?>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              'Beats and bars',
              style: Theme.of(sheetCtx).textTheme.titleMedium,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Where the grid draws its beat and bar lines. This changes how '
                'the pattern READS — it does not change how it plays.',
              ),
            ),
            ListTile(
              leading: Icon(
                _meterOverride == null
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: const Text('Follow the pattern'),
              subtitle: Text(
                '${_song.timing.stepsPerBeat} rows a beat, 4 beats a bar',
              ),
              onTap: () => Navigator.of(sheetCtx).pop(),
            ),
            const Divider(),
            for (final meter in kCommonMeters)
              ListTile(
                leading: Icon(
                  _meterOverride == meter
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(meter.label),
                onTap: () => Navigator.of(sheetCtx).pop(meter),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    // A null result is ambiguous — dismissed, or "follow the pattern" chosen —
    // so both land on the same, harmless outcome rather than guessing.
    setState(() => _meterOverride = chosen);
    if (chosen != null && chosen != current) _syncPlayback();
  }

  /// WS-T4 — the cursor's channel as a piano roll.
  ///
  /// A view beside the grid, not a replacement for it: the grid is exact and
  /// this is legible, and they are answering different questions. Read-only —
  /// a roll you could edit that silently disagreed with the grid would be worse
  /// than no roll, and making them agree is its own piece of work.
  Future<void> _showPianoRoll() async {
    final channel = _cursorChannel;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (_, controller) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Channel ${channel + 1} — ${_song.current.name}',
                        style: Theme.of(sheetCtx).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Higher notes to the right; time runs downward.'),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  // Repaints as the song plays, so the playhead line tracks it.
                  child: ValueListenableBuilder<int>(
                    valueListenable: _row,
                    builder: (context, row, _) => TrackerPianoRoll(
                      cells: [
                        for (var r = 0; r < _song.rows; r++)
                          _song.engine.cellAt(channel, r),
                      ],
                      playingRow: _clock.isRunning ? row : null,
                      meter: _meterFor(_song.timing.stepsPerBeat),
                      rowHeight: 10,
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

  /// WS-T2 — the song at a glance: every order slot as a block, in a grid.
  ///
  /// The strip in the toolbar is a horizontal `Wrap` of chips. At eight
  /// patterns that is perfectly good; at sixty-four it is a wall of chips you
  /// scroll sideways through, and there is no way to see the SHAPE of the song
  /// — that the chorus pattern recurs four times, say. A grid of small blocks
  /// shows that in one look.
  ///
  /// It also carries the drag: the strip's move buttons swap with a neighbour,
  /// which is sixty presses to move something to the end.
  Future<void> _showOrderOverview() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final scheme = Theme.of(sheetCtx).colorScheme;
          final playing = _playingOrder.value;
          return SafeArea(
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              builder: (_, controller) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Song order — ${_song.order.length} slots',
                            style: Theme.of(sheetCtx).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Tap to jump there. Press and drag a block to move it.',
                    ),
                  ),
                  Expanded(
                    // ReorderableListView gives the drag for free, and a wrap
                    // of it does not exist — so the grid is rows of a fixed
                    // width, which also makes the song's shape readable
                    // (a recurring chorus lines up in a column).
                    child: ReorderableListView.builder(
                      scrollController: controller,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _song.order.length,
                      // `onReorderItem`, not the deprecated `onReorder`: it
                      // already accounts for the removed item, so the classic
                      // `to > from ? to - 1 : to` correction is not only
                      // unnecessary here, it would be an off-by-one.
                      onReorderItem: (from, to) {
                        reorderOrderSlot(from, to);
                        setSheet(() {});
                      },
                      itemBuilder: (context, i) {
                        final pattern = _song.order[i];
                        final isPlaying = playing == i;
                        final isCursor = _orderCursor == i;
                        return ListTile(
                          key: ValueKey('order-slot-$i'),
                          dense: true,
                          leading: Container(
                            width: 44,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isPlaying
                                  ? scheme.primary
                                  : isCursor
                                      ? scheme.primaryContainer
                                      : scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '$pattern',
                              style: TextStyle(
                                color: isPlaying
                                    ? scheme.onPrimary
                                    : scheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(_patternNameAt(pattern)),
                          subtitle: Text('Slot ${i + 1}'),
                          onTap: () {
                            setState(() => _orderCursor = i);
                            selectPattern(pattern);
                            setSheet(() {});
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// The name of pattern [index], or a stable fallback — a song imported from a
  /// module often has unnamed patterns, and "Pattern 12" reads better than an
  /// empty row.
  String _patternNameAt(int index) {
    if (index < 0 || index >= _song.patterns.length) return 'Pattern $index';
    final name = _song.patterns[index].name;
    return name.isEmpty ? 'Pattern $index' : name;
  }

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

  /// WS-T2 — move the slot at [from] to [to], as a drag does.
  ///
  /// The existing move buttons swap with a NEIGHBOUR, which is the right verb
  /// for a nudge and a poor one for "this chorus belongs at the end": at sixty
  /// slots that is sixty presses. A drag is a remove-and-insert, so the slots
  /// in between shift rather than one of them being displaced.
  @override
  void reorderOrderSlot(int from, int to) {
    if (from == to) return;
    if (from < 0 || from >= _song.order.length) return;
    if (to < 0 || to >= _song.order.length) return;
    setState(() {
      final moved = _song.order.removeAt(from);
      _song.order.insert(to, moved);
      // Keep the cursor on the slot the user was holding, wherever it landed.
      if (_orderCursor == from) {
        _orderCursor = to;
      } else if (from < _orderCursor && to >= _orderCursor) {
        _orderCursor -= 1;
      } else if (from > _orderCursor && to <= _orderCursor) {
        _orderCursor += 1;
      }
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

  bool get _canUndo => _history.canUndoScope(kTrackerUndoScope);
  bool get _canRedo => _history.canRedoScope(kTrackerUndoScope);

  /// Snapshot the current pattern's cells before a cell edit.
  ///
  /// The `before` snapshot is taken now and the `after` one lazily, on the first
  /// undo — the same shape the DAW fold-in uses, and for the same reason: at
  /// push time the edit has not happened yet, so there is nothing to record as
  /// its result.
  void _pushUndo([String? label]) {
    final before = _song.engine.exportCells();
    List<List<TrackerCell>>? after;
    _history.push(
      UndoEntry(
        label: label ?? _labelForEdit(),
        scope: kTrackerUndoScope,
        undo: () {
          // ⚠️ The trap this screen inherits and the DAW does not: it is a
          // games-registry screen, pushed and popped, while the service
          // outlives it — and every entry closes over this `State`. An undo
          // pressed on another surface afterwards would `setState` on a dead
          // screen.
          if (!mounted) return;
          after = _song.engine.exportCells();
          setState(() => _song.engine.importCells(before));
          _syncPlayback();
        },
        redo: () {
          final restore = after;
          if (!mounted || restore == null) return;
          setState(() => _song.engine.importCells(restore));
          _syncPlayback();
        },
      ),
    );
  }

  /// What the edit about to happen should be called in the history.
  ///
  /// Coarse on purpose. Naming it at every one of the ~30 call sites would be
  /// this ladder's recurring inert seam: the site that forgets does not fail, it
  /// files its edit under the wrong name. "Pattern edit" is missing detail;
  /// a wrong name is worse.
  String _labelForEdit() => _recording ? 'Recorded notes' : 'Pattern edit';

  /// Drop the history — after a structural change a snapshot can't be restored.
  ///
  /// `clearScope`, not `clear`: another surface's entries are still perfectly
  /// good, and this screen has no business dropping them.
  void _clearUndo() => _history.clearScope(kTrackerUndoScope);

  void _undo() => _history.undoScope(kTrackerUndoScope);

  void _redo() => _history.redoScope(kTrackerUndoScope);

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
  /// Sound a note the player just triggered.
  ///
  /// ⚠️ This used to return early while the clock was running, which meant live
  /// record was SILENT: you played, and heard nothing until the loop re-rendered
  /// and came round again. You cannot perform into something you cannot hear, so
  /// a note now auditions whether or not the pattern is playing. (The early
  /// return was right for its original job — auditioning a note you TYPED, where
  /// the pattern's own voice would double it — but that job is the non-recording
  /// branch, which still gets the same call.)
  void _preview(int midi) {
    final audio = context.read<AudioService>();
    if (audio.soundOn) audio.playMidiNote(midi, ms: 350);
  }

  /// Enters [midi] at the cursor and advances by the edit-step (wrapping). In
  /// live-record mode (playing) it lands at the SOUNDING row instead, preserving
  /// any existing volume/effect on that cell, and doesn't move the edit cursor —
  /// jam straight into the pattern.
  void _enterNoteAtCursor(int midi) {
    _preview(midi);
    if (_isLiveRecording) {
      _recordNotes([midi]);
      return;
    }
    _pushUndo();
    _song.engine.setCell(
      _cursorChannel,
      _cursorRow,
      TrackerCell(midi: midi, instrument: _activeInstrument),
    );
    setState(() => _cursorRow = (_cursorRow + _editStep) % _song.rows);
    _ensureCursorVisible();
    _syncPlayback();
  }

  /// Whether a played note should land at the playhead rather than the cursor.
  bool get _isLiveRecording =>
      _recording && _clock.isRunning && _row.value >= 0;

  /// WS-T7 — commit [notes] played together at the sounding row.
  ///
  /// Everything that makes this different from typing lives in
  /// `pattern_record.dart`, deliberately: the screen cannot be unit-tested at
  /// speed (its playhead Ticker never stops, so `pumpAndSettle` hangs), and
  /// these are the parts worth testing.
  ///   * the count-in **gates the writes, not the clock** — the pattern keeps
  ///     playing through the count so you can play along, and nothing is kept
  ///     until it ends;
  ///   * a chord **spreads across consecutive channels** — every note used to
  ///     go to the cursor channel, so a triad became one cell and two notes
  ///     vanished;
  ///   * the whole pass is **one undo entry**. It used to be one per note, and
  ///     each entry snapshots the entire pattern against an 80-entry cap, so
  ///     ten seconds of jamming pushed every earlier edit off the end.
  void _recordNotes(List<int> notes) {
    final pass = _pass;
    if (pass == null || notes.isEmpty) return;
    final commit = pass.commit(_elapsedMs.toDouble());
    if (commit == null) return; // still counting in — heard, not kept
    if (commit.needsSnapshot) _pushUndo();

    final row = recordRow(
      row: _row.value,
      phase: _rowPhase,
      quantize: _quantize,
      stepsPerBeat: _song.timing.stepsPerBeat,
      totalRows: _song.rows,
    );
    for (final note in allocateChord(
      notes: notes,
      row: row,
      startChannel: _cursorChannel,
      channelCount: _song.channelCount,
    )) {
      // copyWith, not a fresh cell: an existing volume or effect on that row is
      // the arrangement, and a jam should not silently strip it.
      final cur = _song.engine.cellAt(note.channel, note.row);
      _song.engine.setCell(
        note.channel,
        note.row,
        cur.copyWith(midi: note.midi, instrument: _activeInstrument),
      );
      _sounding[note.midi] = (channel: note.channel, row: note.row);
    }
    setState(() {});
    _syncPlayback();
  }

  /// WS-T7 — the pads, which are the first thing in the app to play REAL notes.
  ///
  /// Not the on-screen piano this screen already has: that emits `onKeyTap`, a
  /// TAP, and a tap has no duration, so it can never produce a held note or a
  /// chord held together. These press and release, into the same
  /// `ManualMidiInput` a hardware keyboard will push into once WS-X5 3a lands —
  /// so recording is written against MIDI once, not twice.
  Future<void> _showPads() async {
    final l10n = AppLocalizations.of(context)!;
    final padsKey = GlobalKey<PerformancePadsState>();
    await showModalBottomSheet<void>(
      context: context,
      // The pattern has to stay visible and audible: you are playing ALONG with
      // it, and a sheet that covers the grid hides the playhead you are aiming
      // at.
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.trackerPads,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.trackerPadsHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              PerformancePads(
                key: padsKey,
                pads: chromaticPads((_octave + 1) * 12, 12),
                input: _midi,
              ),
            ],
          ),
        ),
      ),
    );
    // A finger still down when the sheet is dismissed never sends its release,
    // and a note whose release never arrives sounds forever.
    padsKey.currentState?.releaseAll();
    _held.clear();
  }

  /// WS-T7 — record how LONG a note was held, as a key-off cell.
  ///
  /// Without this a performance has no note lengths: every note runs until the
  /// next one on its channel, so a staccato stab and a held pad come out
  /// identical. `cellRuns` already reads a key-off as a release, so this is a
  /// real length rather than a marking.
  ///
  /// It never overwrites a cell that has a NOTE in it: by the time you let go,
  /// the next note may already be recorded there, and cutting it would delete a
  /// note you played to end one you had finished.
  void _recordRelease(int midi) {
    final start = _sounding.remove(midi);
    if (start == null || !_isLiveRecording) return;
    // The row that is SOUNDING as you let go — not a wall-clock duration. The
    // playhead already knows where we are, and a measured duration disagrees
    // with it the moment a frame is dropped.
    final cut = releaseRowFor(
      startRow: start.row,
      releaseRow: _row.value,
      totalRows: _song.rows,
    );
    if (cut == null) return;
    final cell = _song.engine.cellAt(start.channel, cut);
    if (cell.midi != null) return;
    _song.engine.setCell(start.channel, cut, TrackerCell.noteCut);
    setState(() {});
    _syncPlayback();
  }

  /// Arm or disarm live record, and tell the shared transport.
  ///
  /// The transport is told rather than asked because this screen's Stopwatch is
  /// the clock the transport follows (`syncTo`) — so record-arm belongs to the
  /// same direction of travel. A count-in is taken from
  /// `TransportService.countInBars`, so the two surfaces share one preference
  /// instead of growing a second one.
  void _setRecording(bool value) {
    setState(() {
      _recording = value;
      if (value) {
        final bars = _transport?.countInBars ?? 0;
        _pass = RecordPass(
          countIn: bars > 0 && _clock.isRunning
              ? RecordCountIn(
                  startedAtMs: _elapsedMs.toDouble(),
                  bars: bars,
                  // The meter the GRID is drawn to, not a hard-coded 4 — a
                  // count-in that disagrees with the bar lines counts the
                  // wrong length.
                  barMs: (_song.timing.beatMs *
                          _meterFor(_song.timing.stepsPerBeat).beatsPerBar)
                      .toDouble(),
                )
              : RecordCountIn.none,
        );
      } else {
        _pass = null;
        _held.clear();
        _sounding.clear();
      }
    });
    _transport?.setRecordArmed(value);
  }

  /// Notes arriving from the pads (and, when WS-X5 3a lands, from hardware).
  ///
  /// Held notes are tracked through `HeldNotes` rather than counted here,
  /// because a note-on with velocity 0 IS a note-off — the standard's most
  /// common trap, and the reason that class exists.
  void _onMidi(MidiMessage message) {
    if (!message.isNoteOn && !message.isNoteOff) return;
    _held.apply(message);
    if (message.isNoteOff) {
      _recordRelease(message.note);
      return;
    }
    if (_isLiveRecording) {
      _preview(message.note);
      // Everything currently down, so a chord struck together lands together.
      // `notesOn` is sorted and includes the note just applied.
      _recordNotes(_held.notesOn());
    } else {
      // Not recording: the pads are an instrument, and a played note goes in at
      // the cursor exactly as a typed one does (which auditions it).
      _enterNoteAtCursor(message.note);
    }
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

  /// WS-T3 — the shared binding table. A field rather than a constant so a
  /// user's rebindings can replace it without touching the dispatch below.
  /// WS-T3 — the shared bindings, loaded once so a rebinding persists.
  final KeymapService _keymapService = KeymapService()..load();
  Keymap get _keymap => _keymapService.keymap;

  /// Everything the Tracker handles — the full table, which is where these
  /// bindings came from.
  static final Set<AppIntent> kTrackerIntents = AppIntent.values.toSet()
    ..remove(AppIntent.transportToggle);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final hw = HardwareKeyboard.instance;
    final ctrl = hw.isControlPressed || hw.isMetaPressed;
    final shift = hw.isShiftPressed;
    // NB: `alt` is no longer read here — the Alt-modified chords resolve
    // through the keymap now, which is the point of the extraction.

    // WS-T3 — the BINDING now lives in `lib/shared/keymap/`; what stays here is
    // the dispatch, and the ORDER of the checks below, which is behaviour: the
    // block ops are resolved before note entry, or Ctrl+C would type a C.
    final intent = _keymap.intentFor(chordOf(key, hw));

    // FT2 function-key transport: F5 song · F6 pattern · F7 pattern-from-cursor ·
    // F8 stop.
    switch (intent) {
      case AppIntent.transportPlaySong:
        _playSong();
        return KeyEventResult.handled;
      case AppIntent.transportPlayPattern:
        _playPattern();
        return KeyEventResult.handled;
      case AppIntent.transportPlayFromCursor:
        _playPattern(fromRow: _cursorRow);
        return KeyEventResult.handled;
      case AppIntent.transportStop:
        _stop();
        return KeyEventResult.handled;
      default:
        break;
    }

    // Block ops (Ctrl/⌘ + …). Checked before note entry so Ctrl+C isn't a note.
    if (ctrl) {
      switch (intent) {
        case AppIntent.clipCopy:
          _copyBlock();
          return KeyEventResult.handled;
        case AppIntent.clipCut:
          _cutBlock();
          return KeyEventResult.handled;
        case AppIntent.clipPaste:
          _pasteBlock();
          return KeyEventResult.handled;
        case AppIntent.clipPasteMix:
          _pasteBlock(mix: true);
          return KeyEventResult.handled;
        case AppIntent.selectAll:
          // First Ctrl+A = the track column; a second widens to the pattern.
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
        case AppIntent.editInterpolate:
          _interpolateBlock();
          return KeyEventResult.handled;
        case AppIntent.editUndo:
          _undo();
          return KeyEventResult.handled;
        case AppIntent.editRedo:
          _redo();
          return KeyEventResult.handled;
        default:
          break;
      }
    }
    if (intent == AppIntent.selectNone) {
      _unmark();
      return KeyEventResult.handled;
    }

    // In-grid field cursor (Tab cycles note/vol/fx; hex edits the volume field).
    final fieldResult = _handleFieldKey(event, key);
    if (fieldResult != null) return fieldResult;

    // Alt+Arrows / Alt+PageUp/Down: transpose the block (semitone / octave).
    switch (intent) {
      case AppIntent.transposeUp:
        _transposeBlock(1);
        return KeyEventResult.handled;
      case AppIntent.transposeDown:
        _transposeBlock(-1);
        return KeyEventResult.handled;
      case AppIntent.transposeOctaveUp:
        _transposeBlock(12);
        return KeyEventResult.handled;
      case AppIntent.transposeOctaveDown:
        _transposeBlock(-12);
        return KeyEventResult.handled;
      default:
        break;
    }

    // Navigation. The SELECT variants are the same keys with Shift, so both
    // land here; `shift` still decides whether the block extends or drops.
    void go(int channel, int row) =>
        shift ? _extendTo(channel, row) : _moveCursorClearing(channel, row);
    switch (intent) {
      case AppIntent.cursorDown:
      case AppIntent.selectDown:
        go(_cursorChannel, (_cursorRow + 1) % _song.rows);
        return KeyEventResult.handled;
      case AppIntent.cursorUp:
      case AppIntent.selectUp:
        go(_cursorChannel, (_cursorRow - 1 + _song.rows) % _song.rows);
        return KeyEventResult.handled;
      case AppIntent.cursorRight:
      case AppIntent.selectRight:
        go((_cursorChannel + 1) % _song.channelCount, _cursorRow);
        return KeyEventResult.handled;
      case AppIntent.cursorLeft:
      case AppIntent.selectLeft:
        go(
          (_cursorChannel - 1 + _song.channelCount) % _song.channelCount,
          _cursorRow,
        );
        return KeyEventResult.handled;
      // Insert / Shift+Delete: insert / delete a whole row at the cursor.
      case AppIntent.rowInsert:
        _insertRow();
        return KeyEventResult.handled;
      case AppIntent.rowDelete:
        _deleteRow();
        return KeyEventResult.handled;
      case AppIntent.editDelete:
        if (_hasSelection) {
          _clearBlock();
        } else {
          _clearAtCursorAndAdvance();
        }
        return KeyEventResult.handled;
      case AppIntent.octaveUp:
        _setOctave(_octave + 1);
        return KeyEventResult.handled;
      case AppIntent.octaveDown:
        _setOctave(_octave - 1);
        return KeyEventResult.handled;
      default:
        break;
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

  /// WS-W2 step 2 — the transport can DRIVE this surface, not only mirror it.
  ///
  /// ⚠️ Until now every surface published its state through `syncTo` and
  /// listened to nothing, so the shared `TransportBar` — which calls
  /// `transport.togglePlay` directly — would have moved a readout and sounded
  /// nothing wherever it was hosted. Accepting play/stop closes that without
  /// moving position authority: this screen's `Stopwatch` stays the clock,
  /// which is what `syncTo` documents it must be for a pre-rendered loop.
  ///
  /// [_applyingTransport] breaks the loop: our own `_playPattern` tells the
  /// transport, which notifies us, which would tell it again.
  bool _applyingTransport = false;

  void _onTransportCommand() {
    final transport = _transport;
    if (transport == null || _applyingTransport || !mounted) return;

    // ⚠️ Record-arm was ONE-WAY, which I introduced in WS-T7: arming here told
    // the transport, and arming the transport told nobody. That is the shape of
    // an inert control on the other end — a shared record button that lights up
    // and records nothing — so it goes both ways now.
    if (transport.isRecordArmed != _recording) {
      _applyingTransport = true;
      try {
        _setRecording(transport.isRecordArmed);
      } finally {
        _applyingTransport = false;
      }
    }

    final running = _clock.isRunning;
    if (transport.isPlaying == running) return;
    _applyingTransport = true;
    try {
      if (transport.isPlaying) {
        // Resume where we were if this was a pause; otherwise start the pattern.
        if (_paused) {
          _resume();
        } else {
          _playPattern();
        }
      } else {
        _stop();
      }
    } finally {
      _applyingTransport = false;
    }
  }

  void _pause() {
    _clock.stop();
    _loop.pause();
    _transport?.pause();
    setState(() => _paused = true);
  }

  void _resume() {
    _clock.start();
    _loop.resume();
    _transport?.play();
    setState(() => _paused = false);
  }

  void _stop() {
    _clock
      ..stop()
      ..reset();
    _loop.stop();
    _transport?.stop();
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
    _transport?.play();
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
    _transport?.play();
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

  /// WS-T1 — keep the playing row in view, moving with the music rather than a
  /// row at a time.
  ///
  /// The old version was called only when the INTEGER row changed, so the view
  /// sat still for a whole row and then lurched a row's height — most visible
  /// at slow tempos, which is exactly when someone is reading along. `_rowPhase`
  /// already knew where between rows the music was; nothing used it here.
  ///
  /// Two things this deliberately is NOT:
  ///   * not `animateTo` — an animation per frame fights the next frame's, and
  ///     the position is already continuous. What makes it smooth is that the
  ///     TARGET moves continuously; the easing below only softens the catch-up.
  ///   * not applied to the cursor-into-view scroll (the other `jumpTo` in this
  ///     file). That is a discrete response to a key press, where landing
  ///     immediately is correct and easing would lag behind key-repeat.
  void _followPlayhead(double exactRow) {
    if (!_followPlay || !_vScroll.hasClients) return;
    final next = followScrollOffset(
      exactRow: exactRow,
      rowHeight: _rowHeight,
      current: _vScroll.position.pixels,
      maxExtent: _vScroll.position.maxScrollExtent,
    );
    if (next != null) _vScroll.jumpTo(next);
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
          IconButton(
            icon: const Icon(Icons.edit, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () async {
              final newInst = await showInstrumentEditor(
                context,
                ch.instrument,
                candidates: [
                  for (final other in _song.channels) other.instrument,
                ],
              );
              if (newInst != null && mounted) {
                // Re-voice the whole track and rebuild
                setState(() => _song.revoiceChannel(c, newInst));
                _syncPlayback();
                setSheet(() {});
              }
            },
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
    setState(() => _song.revoiceChannel(channel, inst));
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

  /// Licence provenance for pool instruments that came from the library, keyed
  /// by the instrument identity actually in the pool. Populated at the ONE
  /// funnel below, so an imported instrument's obligation can't enter the song
  /// unrecorded.
  final Map<TrackerInstrument, LicensedWork> _instrumentProvenance = {};

  void _addSavedInstrument(SavedInstrument saved) {
    final inst = saved.instrument;
    if (inst == null) return;
    final work = saved.licensedWork;
    if (work != null) _instrumentProvenance[inst] = work;
    _addPoolInstrument(inst);
  }

  /// Licence provenance for MUSIC loaded from the library (as opposed to the
  /// instrument pool, which is tracked per instrument above).
  final List<LicensedWork> _scoreProvenance = [];

  void _noteScoreProvenance(LicensedWork? work) {
    if (work != null && !_scoreProvenance.contains(work)) {
      _scoreProvenance.add(work);
    }
  }

  /// What exporting this song owes. Read from the CURRENT pool, so removing an
  /// instrument removes its obligation — the same rule the Audio Editor uses.
  LicenseObligations licenseObligations() => obligationsFor([
        for (final inst in _song.instruments)
          if (_instrumentProvenance[inst] case final work?) work,
        ..._scoreProvenance,
      ]);

  /// Every export routes through here first: it states share-alike terms on the
  /// OUTPUT and refuses outright when the song can't lawfully be exported.
  Future<bool> _licenseGate() =>
      confirmLicenseObligations(context, licenseObligations());

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

  @override
  void debugShowSoundLibrary() => _showSoundLibrary();

  @override
  void debugRemovePoolInstrument(int poolIndex) =>
      _removePoolInstrument(poolIndex);

  /// Browse the unified Sound Library: built-in voices, saved/catalog
  /// instruments, SoundFonts, samples, and generated FX. By default a pick is
  /// added to the shared pool; [onPick] overrides that for channel assignment.
  void _showSoundLibrary({void Function(TrackerInstrument)? onPick}) {
    unawaited(_pickFromUnifiedSoundLibrary(onPick: onPick));
  }

  Future<void> _pickFromUnifiedSoundLibrary({
    void Function(TrackerInstrument)? onPick,
  }) async {
    final saved = await showMyInstrumentsSheet(
      context,
      includeBuiltIns: true,
      onMusicSelected: (score) async {
        if (!_replaceMusicScore(score)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.musicPickerFailed),
            ),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.importDone)),
        );
      },
      onModuleSelected: (bytes) async {
        final l10n = AppLocalizations.of(context)!;
        try {
          importModuleBytes(bytes);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.importDone)),
          );
        } on FormatException {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.trackerModFailed)),
          );
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.trackerModFailed)),
          );
        }
      },
      onSoundFontSelected: (instrument) async => _addPoolInstrument(instrument),
    );
    if (saved == null || !mounted) return;
    final inst = saved.instrument;
    if (inst == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.drumkitSoundUnavailable),
        ),
      );
      return;
    }
    (onPick ?? _addPoolInstrument)(inst);
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
  void debugSimulateExit() => _onPopMaybeShare(true, null);
  @override
  bool get canRedo => _canRedo;
  @override
  void undo() => _undo();
  @override
  void redo() => _redo();
  @override
  bool get isRecording => _recording;
  @override
  void toggleRecord() => _setRecording(!_recording);
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
        cur.copyWith(fxCmd: cmd, fxParam: param),
      );
    });
    _syncPlayback();
  }

  @override
  void debugShowFlowTimeline() => _showFlowTimeline();

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
  int get orderCursor => _orderCursor;

  @override
  void setOrderCursor(int index) => setState(
        () => _orderCursor = index.clamp(0, _song.order.length - 1),
      );

  @override
  Future<void> openOrderOverview() => _showOrderOverview();

  @override
  Future<void> openPianoRoll() => _showPianoRoll();

  @override
  TrackerMeter? get meterOverride => _meterOverride;

  @override
  void setMeterOverride(TrackerMeter? meter) =>
      setState(() => _meterOverride = meter);
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
  ManualMidiInput get debugMidiInput => _midi;
  @override
  bool debugDrop(MusicDragPayload payload) {
    final plan = _dropPlan(payload);
    if (plan == null) return false;
    _commitDrop(plan.fitted);
    return true;
  }

  @override
  List<String> debugDropWarnings(MusicDragPayload payload) =>
      _dropPlan(payload)?.warnings ?? const [];
  @override
  bool isNoteCutAt(int channel, int row) =>
      _song.engine.cellAt(channel, row).isNoteCut;
  @override
  bool get isCountingIn =>
      _pass != null && !_pass!.countIn.commits(_elapsedMs.toDouble());
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
  void sendToDaw() {
    // In-place round-trip: update the source Audio Editor clip and go back
    // (same shape as the Score and Tab workshops). Without the callback this
    // stays the plain "add a new clip" send.
    final onReturn = widget.onReturnToDaw;
    if (onReturn != null) {
      onReturn(_song);
      Navigator.of(context).pop();
    } else {
      sendToMultitrack(context, TrackerSource(_song));
    }
  }

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
                  SampleWaveform(
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
                          _setChannelInstrumentVoice(channel, opt.build());
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

  /// Re-voice the whole track [channel] to [inst] (from the library / a
  /// SoundFont / a built-in chip) and refresh playback. Clears the channel's
  /// per-cell instrument column so the change is audible even when the cells
  /// carry explicit pool references (as imported modules always do).
  void _setChannelInstrumentVoice(int channel, TrackerInstrument inst) {
    setState(() => _song.revoiceChannel(channel, inst));
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
              const Divider(height: 20),
              // The RAW native command this cell was imported with (its original
              // format byte/letter-command), preserved for a same-format export.
              // Editing it writes provenance directly, independent of the
              // normalized effect column above.
              _NativeCommandEditor(
                l10n: l10n,
                initialFormat: cell.nativeFormat,
                initialEffect: cell.nativeEffect,
                initialParam: cell.nativeEffectParam,
                initialVolpan: cell.nativeVolpan,
                onChanged: (format, effect, param) =>
                    _setNativeCommand(channel, row, format, effect, param),
                onClear: () => _clearNativeCommand(channel, row),
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
        cur.copyWith(
          fxCmd: cmd,
          fxParam: param,
        ),
      ),
    );
    _syncPlayback();
  }

  /// Writes the RAW native effect provenance onto a cell (the original format
  /// command bytes preserved for same-format export). Does not touch the
  /// normalized effect column.
  void _setNativeCommand(
    int channel,
    int row,
    String format,
    int effect,
    int param,
  ) {
    _pushUndo();
    final cur = _song.engine.cellAt(channel, row);
    setState(
      () => _song.engine.setCell(
        channel,
        row,
        setNativeEffect(cur, format: format, effect: effect, param: param),
      ),
    );
    _syncPlayback();
  }

  void _clearNativeCommand(int channel, int row) {
    _pushUndo();
    final cur = _song.engine.cellAt(channel, row);
    setState(
      () => _song.engine.setCell(channel, row, clearNativeProvenance(cur)),
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

  /// Replaces the document from a notation selection and reports whether it
  /// produced actual tracker notes. An empty decoded container otherwise looks
  /// like a no-op after the Sound Library sheet closes.
  bool _replaceMusicScore(MultiPartScore score) {
    final song = _songFromMultiPart(score);
    if (song.isEmpty) return false;
    _replaceSong(song);
    return true;
  }

  @override
  void importModuleBytes(Uint8List bytes) =>
      _replaceSong(songFromModuleBytes(bytes));

  // --- Shared-groove bridge --------------------------------------------------
  //
  // The Advanced Tracker is polyphonic, so unlike the Beginner one it can carry
  // a shared beat LOSSLESSLY: load builds a fresh drum song with one percussion
  // channel per active drum (kick+hat on the same step just live on two
  // channels); share reads every percussion channel back out.

  @override
  void shareBeat() {
    final steps = _song.rows;
    final rows = <Drum, List<bool>>{};
    for (final ch in _song.channels) {
      if (ch.instrument is! PercussionInstrument) continue;
      for (var s = 0; s < steps && s < ch.cells.length; s++) {
        final midi = ch.cells[s].midi;
        if (midi == null) continue;
        final drum = Drum.values[midi.clamp(0, Drum.values.length - 1)];
        (rows[drum] ??= List<bool>.filled(steps, false))[s] = true;
      }
    }
    if (rows.isEmpty) return;
    BeatBridge.instance.publish(
      SharedBeat(
        rows: rows,
        tempoBpm: _song.timing.tempoBpm,
        swing: _song.timing.swing,
        source: 'advtracker',
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.beatShared)),
    );
  }

  @override
  bool get canLoadSharedBeat => BeatBridge.instance.hasBeat;

  @override
  void loadSharedBeat() {
    final shared = BeatBridge.instance.current;
    if (shared == null || shared.isEmpty) return;
    _replaceSong(drumSongFromBeat(shared));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.beatLoaded)),
    );
  }

  // ── Shared-tune bridge (pitched twin of the beat bridge) ───────────────────

  /// The first melodic (non-percussion) channel, or -1 if the song is all drums.
  int _melodicIndex() =>
      _song.channels.indexWhere((c) => c.instrument is! PercussionInstrument);

  /// Publish the first melodic channel to [MelodyBridge]. Returns true if it
  /// published (there was a non-empty melodic channel). The pure half of
  /// [shareMelody], reused by the auto-publish-on-exit round-trip (no snackbar,
  /// no context needed — safe to call while leaving the screen).
  bool _publishMelodyToBridge() {
    final ch = _melodicIndex();
    if (ch < 0) return false;
    final steps = _song.rows;
    final cells = _song.channels[ch].cells;
    final rows = <int?>[
      for (var s = 0; s < steps; s++) s < cells.length ? cells[s].midi : null,
    ];
    if (rows.every((m) => m == null)) return false;
    // Carry each note's dynamics (the tracker's per-cell volume) so a soft note
    // edited in the pro tracker returns to the Loop as a soft note.
    final vels = <double>[
      for (var s = 0; s < steps; s++)
        s < cells.length ? (cells[s].volume ?? 1.0) : 1.0,
    ];
    MelodyBridge.instance.publish(
      SharedMelody(
        cells: patternCellsFromMidiRows(rows, velocities: vels),
        tempoBpm: _song.timing.tempoBpm,
        source: 'advtracker',
      ),
    );
    return true;
  }

  @override
  void shareMelody() {
    if (!_publishMelodyToBridge()) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.tuneShared)),
    );
  }

  @override
  bool get canLoadSharedMelody =>
      MelodyBridge.instance.hasMelody && _melodicIndex() >= 0;

  @override
  void loadSharedMelody() {
    final shared = MelodyBridge.instance.current;
    if (shared == null || shared.isEmpty) return;
    final ch = _melodicIndex();
    if (ch < 0) return;
    final steps = _song.rows;
    final rows = midiRowsFromPatternCells(
      shared.toCells(),
      steps,
      transpose: shared.key,
    );
    setState(() {
      for (var s = 0; s < steps; s++) {
        final midi = rows[s];
        _song.engine.setCell(
          ch,
          s,
          midi == null ? TrackerCell.empty : TrackerCell(midi: midi, volume: 1),
        );
      }
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.tuneLoaded)),
    );
  }

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

  /// One entry point for built-in songs, saved songs, local files, and the
  /// online catalog. All sources return a decoded score and use the same bridge.
  Future<void> _addMusic() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await showMusicPickerWithLicense(context);
      if (!mounted || picked == null) return;
      final score = picked.score;
      _noteScoreProvenance(picked.provenance);
      if (!_replaceMusicScore(score)) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.musicPickerFailed),
          ),
        );
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.importDone)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.musicPickerFailed),
        ),
      );
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
  void debugImportMusic(MultiPartScore score) =>
      _replaceSong(_songFromMultiPart(score));

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
    if (!await _licenseGate() || !mounted) return;

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

  /// WS-X6 — one export door for the Tracker.
  ///
  /// A tracker song can leave as five quite different things, and they were
  /// five sibling rows in one flat menu. The MODULE export in particular is the
  /// format this editor is native to, and it sat between "MusicXML" and "audio"
  /// with nothing to say it was different in kind.
  /// Test seam: open the WS-X6 export door. The menu that hosts it is a
  /// PopupMenu, which a widget test cannot drive without the route.
  @visibleForTesting
  Future<void> debugOpenExportDoor() => _exportDoor();

  Future<void> _exportDoor() async {
    await showExportSheet(
      context,
      options: [
        ExportOption(
          kind: ExportKind.audio,
          label: 'Sound file',
          detail: 'The whole song, rendered',
          run: _exportAudio,
        ),
        ExportOption(
          kind: ExportKind.symbolic,
          label: 'Tracker module',
          detail: '.mod · .xm · .it · .s3m — what other trackers read',
          run: () async => _pickModuleFormat(),
        ),
        ExportOption(
          kind: ExportKind.symbolic,
          label: 'MusicXML',
          detail: 'For notation programs',
          run: _exportMusicXml,
        ),
        ExportOption(
          kind: ExportKind.symbolic,
          label: 'MIDI',
          run: _exportMidi,
        ),
        ExportOption(
          kind: ExportKind.symbolic,
          label: 'ABC',
          run: _exportAbc,
        ),
      ],
    );
  }

  /// Render the whole song and offer it as WAV or MP3 (pure-Dart, web-safe).
  Future<void> _exportAudio() async {
    if (!await _licenseGate() || !mounted) return;

    final pcm = wavToMonoFloat(readWavPcm16(_song.renderSongWav()));
    if (!mounted) return;
    await showAudioExportSheet(context, pcm: pcm, baseName: 'tracker');
  }

  Future<void> _exportMusicXml() async {
    if (!await _licenseGate() || !mounted) return;

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
    if (!await _licenseGate() || !mounted) return;

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
  Future<void> _exportModule(ModuleFormat fmt, {bool sixteenBit = true}) async {
    if (!await _licenseGate() || !mounted) return;

    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    _song.syncCurrent(); // fold live edits into the snapshot before isEmpty
    if (_song.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.trackerSaveEmpty)));
      return;
    }
    try {
      final doc = moduleDocFromSong(
        _song,
        sixteenBit: sixteenBit,
        targetFormat: fmt,
      );
      // Show what the target format cannot represent BEFORE writing anything.
      final losses = moduleExportLossReport(doc, fmt);
      if (losses.isNotEmpty) {
        final go = await _confirmExportLosses(fmt, losses);
        if (go != true || !mounted) return;
      }
      final bytes = convertDocTo(doc, fmt);
      await _saveBytes(bytes, 'tracker.${fmt.name}', fmt.name.toUpperCase(), [
        fmt.name,
      ]);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.trackerModFailed)));
    }
  }

  /// Confirm an export that loses information: list what the [fmt] container
  /// can't represent (the [losses] from [moduleExportLossReport]) and let the
  /// user proceed or cancel. Returns true to export anyway.
  Future<bool?> _confirmExportLosses(ModuleFormat fmt, List<String> losses) {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.trackerExportLossTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.trackerExportLossBody('.${fmt.name}')),
            const SizedBox(height: 12),
            for (final line in losses)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('•  $line'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.trackerCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.trackerExportLossContinue),
          ),
        ],
      ),
    );
  }

  /// The native flow/order timeline: how the current song ACTUALLY plays once its
  /// flow commands (Bxx jump, Dxx break, E6x loop, Fxx speed/tempo) are followed.
  /// Derived from [songFlowTimeline] — the same pure function the tests pin — so a
  /// jumped/looped song shows the same order more than once, in play order. Each
  /// entry is now EDITABLE: an edit affordance authors/changes its order-command
  /// (via the pure helpers in module_flow_timeline.dart) and every command chip
  /// can be removed. Edits mutate the live [_song], refresh the sheet, and mark
  /// playback stale.
  void _showFlowTimeline() {
    final l10n = AppLocalizations.of(context)!;
    _song.syncCurrent(); // fold live edits into the snapshot before walking
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            // Recompute each rebuild so an authored/removed command shows at once.
            final timeline = songFlowTimeline(_song);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.trackerFlowTimeline,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.trackerFlowTimelineHint,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: timeline.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => _flowTimelineTile(
                          l10n,
                          timeline[i],
                          i,
                          setSheet,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// One timeline row: the order/pattern/row range + timing, each flow command as
  /// a removable chip, and a trailing edit button that authors/changes the entry's
  /// order-command. [setSheet] rebuilds the sheet after an edit.
  Widget _flowTimelineTile(
    AppLocalizations l10n,
    FlowTimelineEntry e,
    int index,
    StateSetter setSheet,
  ) {
    return ListTile(
      key: ValueKey('flowTile_$index'),
      dense: true,
      leading: CircleAvatar(radius: 14, child: Text('${e.orderIndex}')),
      title: Text(
        l10n.trackerFlowEntry(
          e.orderIndex,
          e.patternIndex,
          e.firstRow,
          e.lastRow,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.trackerFlowTiming(e.tempoBpm, e.ticksPerRow)),
          if (e.commands.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final c in e.commands)
                    InputChip(
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      label: Text(_flowCommandLabel(l10n, c)),
                      onDeleted: () {
                        _applyFlowEdit(
                          () => clearFlowCommand(_song, e.orderIndex, c.kind),
                        );
                        setSheet(() {});
                      },
                    ),
                ],
              ),
            ),
        ],
      ),
      trailing: IconButton(
        key: ValueKey('flowEdit_$index'),
        icon: const Icon(Icons.edit_outlined),
        tooltip: l10n.trackerFlowEdit,
        onPressed: () => _editFlowEntry(e.orderIndex, setSheet),
      ),
    );
  }

  /// Runs a pure flow-edit helper against the live [_song] as an undoable edit:
  /// snapshots undo, applies inside [setState], then marks playback stale so the
  /// next render/transport reflects the new order-command.
  void _applyFlowEdit(void Function() edit) {
    _pushUndo();
    setState(edit);
    _syncPlayback();
  }

  /// Opens the per-entry flow-command picker for order entry [orderIndex]: choose
  /// a command kind, enter its value, and author it via the pure helpers. Rebuilds
  /// the timeline sheet ([setSheet]) after applying.
  Future<void> _editFlowEntry(int orderIndex, StateSetter setSheet) async {
    final l10n = AppLocalizations.of(context)!;
    final kind = await showModalBottomSheet<_FlowEditKind>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l10n.trackerFlowEditTitle(orderIndex)),
              subtitle: Text(l10n.trackerFlowEditHint),
            ),
            const Divider(height: 1),
            for (final opt in _FlowEditKind.values)
              ListTile(
                leading: Icon(opt.icon),
                title: Text(opt.label(l10n)),
                onTap: () => Navigator.of(ctx).pop(opt),
              ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    await _applyFlowChoice(orderIndex, kind);
    setSheet(() {});
  }

  /// Prompts for the [kind]'s value and authors it on order entry [orderIndex].
  Future<void> _applyFlowChoice(int orderIndex, _FlowEditKind kind) async {
    final l10n = AppLocalizations.of(context)!;
    switch (kind) {
      case _FlowEditKind.jump:
        final target = await _flowNumberDialog(
          l10n.trackerFlowPickOrder,
          initial: 0,
          min: 0,
          max: (_song.order.length - 1).clamp(0, 255),
        );
        if (target != null) {
          _applyFlowEdit(() => setPositionJump(_song, orderIndex, target));
        }
      case _FlowEditKind.brk:
        final row = await _flowNumberDialog(
          l10n.trackerFlowPickRow,
          initial: 0,
          min: 0,
          max: 99,
        );
        if (row != null) {
          _applyFlowEdit(() => setPatternBreak(_song, orderIndex, row));
        }
      case _FlowEditKind.speed:
        final ticks = await _flowNumberDialog(
          l10n.trackerFlowPickSpeed,
          initial: _song.initialSpeed,
          min: 1,
          max: 31,
        );
        if (ticks != null) {
          _applyFlowEdit(() => setSpeed(_song, orderIndex, ticks));
        }
      case _FlowEditKind.tempo:
        final bpm = await _flowNumberDialog(
          l10n.trackerFlowPickTempo,
          initial: _song.timing.tempoBpm,
          min: 32,
          max: 255,
        );
        if (bpm != null) {
          _applyFlowEdit(() => setTempo(_song, orderIndex, bpm));
        }
      case _FlowEditKind.loop:
        final count = await _flowNumberDialog(
          l10n.trackerFlowPickLoop,
          initial: 1,
          min: 0,
          max: 15,
        );
        if (count != null) {
          _applyFlowEdit(() => setPatternLoop(_song, orderIndex, count));
        }
    }
  }

  /// A small numeric-entry dialog for a flow-command value, returning the clamped
  /// [min]..[max] integer or null if cancelled.
  Future<int?> _flowNumberDialog(
    String title, {
    required int initial,
    required int min,
    required int max,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<int>(
      context: context,
      builder: (ctx) => _FlowNumberDialog(
        title: title,
        initial: initial,
        min: min,
        max: max,
        cancelLabel: l10n.trackerCancel,
        applyLabel: l10n.trackerFlowApply,
      ),
    );
  }

  /// The human-readable label for one flow command.
  String _flowCommandLabel(AppLocalizations l10n, FlowCommand c) {
    switch (c.kind) {
      case FlowCommandKind.positionJump:
        return l10n.trackerFlowJump(c.target);
      case FlowCommandKind.patternBreak:
        return l10n.trackerFlowBreak(c.target);
      case FlowCommandKind.patternLoop:
        return l10n.trackerFlowLoop;
      case FlowCommandKind.speedChange:
        return l10n.trackerFlowSetSpeed(c.target);
      case FlowCommandKind.tempoChange:
        return l10n.trackerFlowSetTempo(c.target);
    }
  }

  Future<void> _pickModuleFormat() async {
    final l10n = AppLocalizations.of(context)!;
    var sixteenBit = true; // persists across the sheet's rebuilds
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return SafeArea(
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
                  // 16-bit samples: higher quality, ~2× the sample-data size.
                  // MOD ignores it (always 8-bit).
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: sixteenBit,
                    onChanged: (v) => setSheet(() => sixteenBit = v ?? true),
                    title: Text(l10n.trackerExport16Bit),
                    subtitle: Text(l10n.trackerExport16BitHint),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final f in ModuleFormat.values)
                        ActionChip(
                          label: Text('.${f.name}'),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _exportModule(f, sixteenBit: sixteenBit);
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
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

  /// E4 — pushes whichever screen [target] means, with the already-converted
  /// document. The bridge did the conversion and warned about any loss; this
  /// only has to know the route.
  void _openConvertedElsewhere(AppMode target, ConversionResult result) {
    final document = result.document;
    if (document == null) return;
    switch (target) {
      case AppMode.tab:
        if (document is! TabDocument) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TabWorkshopScreen(initialScore: document.toScore()),
          ),
        );
      case AppMode.score:
        if (document is! MultiPartScore) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CompositionWorkshopScreen(initialScore: document),
          ),
        );
      case AppMode.tracker:
      case AppMode.loop:
      case AppMode.audio:
        // Not offered — see the `targets` list on the menu.
        break;
    }
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
              'ly',
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
        'ly' => MultiPartScore.fromStaffSystem(
            StaffSystem([scoreFromLilyPond(utf8.decode(bytes))]),
          ),
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

  /// Auto-round-trip hook: as the screen leaves, publish the edited melody back
  /// to the bridge so Loop Studio's "Fine-tune in Tracker" folds it in with no
  /// manual Share tap. Gated on [AdvancedTrackerScreen.autoShareOnExit] (off for
  /// every other entry point) AND [_canUndo] (the user actually edited), so an
  /// opened-and-abandoned session leaves the loop untouched.
  void _onPopMaybeShare(bool didPop, Object? result) {
    if (didPop && widget.autoShareOnExit && _canUndo) _publishMelodyToBridge();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      onPopInvokedWithResult: _onPopMaybeShare,
      child: Scaffold(
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
            // WS-T3 — 33 bindings and, until now, no way to discover any of
            // them: you either knew the FT2 conventions already or the whole
            // feature was invisible.
            IconButton(
              icon: const Icon(Icons.keyboard),
              tooltip: 'Keyboard',
              onPressed: () => showKeymapSheet(
                context,
                keymap: _keymap,
                supported: kTrackerIntents,
                service: _keymapService,
              ),
            ),
            // WS-T1 — following was hardcoded ON with no way to turn it off.
            // That mattered less when the view moved once per row; now that it
            // glides continuously, anyone editing while the song plays needs
            // the switch.
            IconButton(
              icon: Icon(
                _followPlay
                    ? Icons.center_focus_strong
                    : Icons.center_focus_weak,
              ),
              isSelected: _followPlay,
              tooltip: 'Follow the playhead',
              onPressed: () => setState(() => _followPlay = !_followPlay),
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
            // E4 — the shared "Open in…" action. Restricted to what this screen
            // can actually PUSH: offering a destination it has no route to
            // would convert the user's song and then drop it.
            OpenInMenu(
              from: AppMode.tracker,
              // WS-X1 — when this screen is editing a project track, say so:
              // a tracker target is LIVE (edits travel back), everything else
              // is a copy. Null when there is no project link, which keeps the
              // pre-project wording exactly as it was.
              liveKind: hasLiveProjectLink ? AppMode.tracker : null,
              targets: const [AppMode.tab, AppMode.score],
              documentBuilder: () => _song,
              onConverted: _openConvertedElsewhere,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                switch (v) {
                  case 'addMusic':
                    _addMusic();
                  case 'import':
                    _importModule();
                  case 'importScore':
                    _importScore();
                  case 'demo':
                    _loadDemo();
                  case 'starterBeat':
                    _applyStarterBeat();
                  case 'soundLibrary':
                    _showSoundLibrary();
                  case 'addToProject':
                    _addToProjectFromMenu();
                  case 'shareSong':
                    _shareSong();
                  case 'loadSong':
                    _loadSong();
                  case 'saveSong':
                    _saveToSongBook();
                  case 'exportDoor':
                    _exportDoor();
                  case 'daw':
                    sendToDaw();
                  case 'shareBeat':
                    shareBeat();
                  case 'loadBeat':
                    loadSharedBeat();
                  case 'shareMelody':
                    shareMelody();
                  case 'loadMelody':
                    loadSharedMelody();
                  case 'workshop':
                    _openInWorkshop();
                  case 'flowTimeline':
                    _showFlowTimeline();
                }
              },
              itemBuilder: (ctx) => [
                _menuSection(l10n.trackerMenuOpenLibrary),
                _menuRow(
                  'addMusic',
                  Icons.library_music_outlined,
                  l10n.musicPickerTitle,
                ),
                _menuRow('import', Icons.library_music, l10n.trackerImportMod),
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
                const PopupMenuDivider(),
                _menuSection(l10n.trackerMenuSaveExport),
                _menuRow(
                  'saveSong',
                  Icons.bookmark_add_outlined,
                  l10n.trackerSaveSong,
                ),
                _menuRow(
                  'addToProject',
                  Icons.playlist_add,
                  l10n.projectAddTrack,
                ),
                _menuRow('shareSong', Icons.ios_share, l10n.trackerShareSong),
                _menuRow(
                  'loadSong',
                  Icons.download_outlined,
                  l10n.trackerLoadSong,
                ),
                // WS-X6 — one export door. These were five sibling rows in a
                // flat menu, so the difference between "a sound file", "the
                // notes" and "a tracker module" was something you had to
                // already know. The door groups them by what you are trying to
                // do; nothing was removed.
                _menuRow('exportDoor', Icons.download, l10n.audioExportTitle),
                _menuRow('daw', Icons.library_add, l10n.dawSend),
                _menuSection(l10n.trackerMenuShareSend),
                _menuRow('shareBeat', Icons.upload, l10n.beatShare),
                _menuRow('loadBeat', Icons.download, l10n.beatLoadShared),
                _menuRow(
                  'shareMelody',
                  Icons.upload,
                  l10n.tuneShare,
                  enabled: _melodicIndex() >= 0,
                ),
                _menuRow(
                  'loadMelody',
                  Icons.download,
                  l10n.tuneLoadShared,
                  enabled: canLoadSharedMelody,
                ),
                const PopupMenuDivider(),
                _menuRow(
                  'flowTimeline',
                  Icons.timeline,
                  l10n.trackerFlowTimeline,
                ),
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
                  _commandBar(l10n),
                  const Divider(height: 1),
                  Expanded(child: _grid(context)),
                  const Divider(height: 1),
                  if (_showScope) _scopeStrip(context),
                  _pianoBar(l10n),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The classic block-editing menu (touch-friendly; the same ops have keyboard
  /// shortcuts on desktop — see the ⓘ legend). Mark begin/drag-select, select
  /// track/pattern, copy/cut/paste/paste-mix, transpose, clear, unmark.
  PopupMenuItem<String> _menuRow(
    String value,
    IconData icon,
    String label, {
    bool enabled = true,
  }) =>
      PopupMenuItem<String>(
        value: value,
        enabled: enabled,
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            // Expanded, not a bare Text: an unconstrained label overflowed this
            // popup by up to 368px (measured), which throws during layout and
            // clips the wording. German labels are the worst case — several are
            // half again as long as the English.
            Expanded(child: Text(label)),
          ],
        ),
      );

  PopupMenuItem<String> _menuSection(String label) => PopupMenuItem<String>(
        enabled: false,
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium,
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

  /// The single top command bar: transport + song tempo/length + pattern +
  /// settings, consolidating what used to be three separate rows (toolbar,
  /// arrangement, transport). Overflow scrolls horizontally on narrow screens.
  Widget _commandBar(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final playing = _clock.isRunning && !_paused;
    Widget sep() => Container(
          width: 1,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: scheme.outlineVariant,
        );
    // Play/Stop stay pinned left and Pattern/Settings pinned right, so the
    // primary controls are always reachable; the rest scrolls in the middle.
    return Container(
      color: scheme.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          IconButton.filledTonal(
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            tooltip: playing ? l10n.trackerPause : l10n.trackerPlay,
            onPressed: _togglePlay,
          ),
          IconButton(
            icon: const Icon(Icons.stop),
            tooltip: l10n.trackerStop,
            onPressed: _clock.isRunning || _paused ? _stop : null,
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  sep(),
                  IconButton(
                    icon: const Icon(Icons.fiber_manual_record),
                    color: _recording ? scheme.error : null,
                    tooltip: l10n.trackerRecordLive,
                    onPressed: () => _setRecording(!_recording),
                  ),
                  IconButton(
                    key: const ValueKey('tracker-pads'),
                    icon: const Icon(Icons.grid_view),
                    tooltip: l10n.trackerPads,
                    onPressed: _showPads,
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
                  sep(),
                  // Tempo (BPM).
                  Tooltip(
                    message: l10n.trackerTempo,
                    child: Row(
                      children: [
                        const Icon(Icons.speed, size: 16),
                        const SizedBox(width: 2),
                        DropdownButton<int>(
                          value: _kTempoOptions.contains(_song.timing.tempoBpm)
                              ? _song.timing.tempoBpm
                              : null,
                          hint: Text('${_song.timing.tempoBpm}'),
                          underline: const SizedBox.shrink(),
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
                      ],
                    ),
                  ),
                  sep(),
                  // Length (rows).
                  Tooltip(
                    message: l10n.trackerLength,
                    child: Row(
                      children: [
                        const Icon(Icons.straighten, size: 16),
                        const SizedBox(width: 2),
                        DropdownButton<int>(
                          value: _kLengthOptions.contains(_song.rows)
                              ? _song.rows
                              : -1,
                          underline: const SizedBox.shrink(),
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
                      ],
                    ),
                  ),
                  sep(),
                  // Position readout.
                  AnimatedBuilder(
                    animation: Listenable.merge([_row, _playingOrder]),
                    builder: (context, _) {
                      final row = _row.value;
                      final rowStr =
                          row < 0 ? '··' : row.toString().padLeft(2, '0');
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
          ),
          // Pattern / song arrangement → sheet (pinned right).
          ActionChip(
            avatar: const Icon(Icons.view_agenda_outlined, size: 16),
            label: Text('${_song.current.name} ▾'),
            tooltip: l10n.trackerPattern,
            onPressed: () => _showArrangementSheet(l10n),
          ),
          const SizedBox(width: 4),
          // Everything else → settings sheet (pinned right).
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsTitle,
            onPressed: () => _showTrackerSettingsSheet(l10n),
          ),
        ],
      ),
    );
  }

  /// Bottom sheet holding the song settings that used to sit on the toolbar:
  /// swing, edit-step, playback toggles, view, and the add-track / chord tools.
  void _showTrackerSettingsSheet(AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final scheme = Theme.of(ctx).colorScheme;
          void toggle(void Function() f) {
            setState(f);
            setSheet(() {});
          }

          Widget dropRow(String label, IconData icon, Widget dropdown) => Row(
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(label)),
                  dropdown,
                ],
              );
          Widget toggleChip(
            String label,
            IconData icon,
            bool on,
            void Function() onTap,
          ) =>
              FilterChip(
                avatar: Icon(icon, size: 18),
                label: Text(label),
                selected: on,
                onSelected: (_) => toggle(onTap),
              );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsTitle,
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    // Groove.
                    dropRow(
                      l10n.trackerSwing,
                      Icons.waves,
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
                            setSheet(() {});
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                    dropRow(
                      l10n.trackerEditStep,
                      Icons.south,
                      DropdownButton<int>(
                        value: _editStep,
                        items: [
                          for (final n in const [0, 1, 2, 4])
                            DropdownMenuItem(value: n, child: Text('$n')),
                        ],
                        onChanged: (v) => toggle(() => _editStep = v ?? 1),
                      ),
                    ),
                    const Divider(height: 20),
                    // Native module HEADER settings (S3M/IT/XM). Global volume
                    // and initial speed are carried from the imported header and
                    // now editable here; they round-trip through the S3M/IT
                    // writers. Tempo and per-channel pan are edited by the tempo
                    // control and the channel pan sliders; master volume,
                    // ultraClick, flags and createdWith are not retained by the
                    // editable model (documented import-loss in mod_pending.md).
                    Text(
                      l10n.trackerModuleHeader,
                      style: Theme.of(ctx).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.volume_up, size: 18),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 96,
                          child: Text(l10n.trackerGlobalVolume),
                        ),
                        Expanded(
                          child: Slider(
                            value: _song.globalVolume.clamp(0.0, 1.0),
                            label: '${(_song.globalVolume * 100).round()}%',
                            divisions: 128,
                            onChanged: (v) {
                              setState(() => _song.setGlobalVolume(v));
                              _syncPlayback();
                              setSheet(() {});
                            },
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text(
                            '${(_song.globalVolume * 100).round()}%',
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    dropRow(
                      l10n.trackerInitialSpeed,
                      Icons.speed,
                      DropdownButton<int>(
                        value: _song.initialSpeed.clamp(1, 31),
                        items: [
                          for (var n = 1; n <= 31; n++)
                            DropdownMenuItem(value: n, child: Text('$n')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _song.setInitialSpeed(v));
                          _syncPlayback();
                          setSheet(() {});
                        },
                      ),
                    ),
                    const Divider(height: 20),
                    // Playback toggles.
                    Text(
                      l10n.trackerPlay,
                      style: Theme.of(ctx).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        toggleChip(
                          l10n.trackerMetronome,
                          Icons.av_timer,
                          _metronome,
                          () => _metronome = !_metronome,
                        ),
                        toggleChip(
                          l10n.trackerQuantize,
                          Icons.grid_on,
                          _quantize,
                          () => _quantize = !_quantize,
                        ),
                        toggleChip(
                          l10n.trackerFollow,
                          Icons.my_location,
                          _followPlay,
                          () => _followPlay = !_followPlay,
                        ),
                        toggleChip(
                          l10n.trackerScope,
                          Icons.graphic_eq,
                          _showScope,
                          () => _showScope = !_showScope,
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    // View + tools.
                    Row(
                      children: [
                        Icon(
                          Icons.zoom_out_map,
                          size: 18,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(l10n.trackerZoomIn)),
                        IconButton(
                          icon: const Icon(Icons.zoom_out),
                          tooltip: l10n.trackerZoomOut,
                          onPressed: () => toggle(
                            () => _zoom = (_zoom - 0.15).clamp(0.75, 1.6),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.zoom_in),
                          tooltip: l10n.trackerZoomIn,
                          onPressed: () => toggle(
                            () => _zoom = (_zoom + 0.15).clamp(0.75, 1.6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        toggleChip(
                          l10n.trackerClassicSkin,
                          Icons.dark_mode,
                          _classic,
                          () => _classic = !_classic,
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 18),
                          label: Text(l10n.trackerAddTrack),
                          onPressed: () {
                            addTrack();
                            setSheet(() {});
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.queue_music, size: 18),
                          label: Text(l10n.trackerChord),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _showChordSheet();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Bottom sheet: the pattern selector + song-order editor (moved off the old
  /// always-on arrangement row). Patterns choose which grid you edit; the order
  /// list is the play sequence. Local [setSheet] keeps the chips live.
  void _showArrangementSheet(AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final scheme = Theme.of(ctx).colorScheme;
          void refresh() => setSheet(() {});
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.trackerPattern,
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < _song.patterns.length; i++)
                          GestureDetector(
                            onLongPress: () async {
                              await _promptRenamePattern(i);
                              refresh();
                            },
                            child: ChoiceChip(
                              label: Text(_song.patterns[i].name),
                              selected: i == _song.currentIndex,
                              onSelected: (_) {
                                selectPattern(i);
                                refresh();
                              },
                            ),
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 16),
                          label: Text(l10n.trackerPatternNew),
                          onPressed: () {
                            _addEmptyPattern();
                            refresh();
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.copy, size: 16),
                          label: Text(l10n.trackerPatternClone),
                          onPressed: () {
                            _clonePattern();
                            refresh();
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.edit_outlined, size: 16),
                          label: Text(l10n.trackerRenamePattern),
                          onPressed: () async {
                            await _promptRenamePattern(_song.currentIndex);
                            refresh();
                          },
                        ),
                        if (_song.patterns.length > 1)
                          ActionChip(
                            avatar: const Icon(Icons.delete_outline, size: 16),
                            label: Text(l10n.trackerRemoveTrack),
                            onPressed: () {
                              setState(
                                () => _song.removePattern(_song.currentIndex),
                              );
                              refresh();
                            },
                          ),
                      ],
                    ),
                    const Divider(height: 24),
                    Text(
                      l10n.trackerSong,
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<int>(
                      valueListenable: _playingOrder,
                      builder: (context, playing, _) => Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var i = 0; i < _song.order.length; i++)
                            InputChip(
                              label: Text(_song.patterns[_song.order[i]].name),
                              selected: playing >= 0
                                  ? i == playing
                                  : i == _orderCursor,
                              side: (playing < 0 && i == _orderCursor)
                                  ? BorderSide(
                                      color: scheme.primary,
                                      width: 1.5,
                                    )
                                  : null,
                              onPressed: () {
                                setState(() => _orderCursor = i);
                                selectPattern(_song.order[i]);
                                refresh();
                              },
                              onDeleted: () {
                                _orderDelete(i);
                                refresh();
                              },
                            ),
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: Text(_song.current.name),
                            onPressed: () {
                              addToOrder(_song.currentIndex);
                              refresh();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      children: [
                        // WS-T2 — the bird's-eye. At sixty-four patterns the
                        // chip strip beside this is a wall to scroll through.
                        IconButton(
                          icon: const Icon(Icons.grid_view, size: 18),
                          tooltip: 'Song overview',
                          onPressed: _showOrderOverview,
                        ),
                        // WS-T4 — the same channel, made legible.
                        IconButton(
                          icon: const Icon(Icons.piano, size: 18),
                          tooltip: 'Piano roll',
                          onPressed: _showPianoRoll,
                        ),
                        // WS-T6 — where the bar lines go. Previously not
                        // settable at all, and hardcoded to four beats.
                        IconButton(
                          icon: const Icon(Icons.straighten, size: 18),
                          tooltip: 'Beats and bars',
                          onPressed: _pickMeter,
                        ),
                        IconButton(
                          icon: const Icon(Icons.expand_more, size: 18),
                          tooltip: l10n.trackerOrderPrevPat,
                          onPressed: () {
                            _orderRetarget(-1);
                            refresh();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.expand_less, size: 18),
                          tooltip: l10n.trackerOrderNextPat,
                          onPressed: () {
                            _orderRetarget(1);
                            refresh();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 20),
                          tooltip: l10n.trackerOrderMoveLeft,
                          onPressed: () {
                            _orderMove(-1);
                            refresh();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 20),
                          tooltip: l10n.trackerOrderMoveRight,
                          onPressed: () {
                            _orderMove(1);
                            refresh();
                          },
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.control_point_duplicate,
                            size: 18,
                          ),
                          tooltip: l10n.trackerOrderInsert,
                          onPressed: () {
                            _orderInsert();
                            refresh();
                          },
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.skip_previous, size: 20),
                          tooltip: l10n.trackerBack,
                          onPressed: _song.patterns.length > 1 || _songMode
                              ? () {
                                  _step(-1);
                                  refresh();
                                }
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next, size: 20),
                          tooltip: l10n.trackerForward,
                          onPressed: _song.patterns.length > 1 || _songMode
                              ? () {
                                  _step(1);
                                  refresh();
                                }
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
      child: DragTarget<MusicDragPayload>(
        onWillAcceptWithDetails: (d) => _dropDecision(d.data).canDrop,
        onAcceptWithDetails: (d) => unawaited(_dropHere(d.data)),
        builder: (context, candidate, rejected) => Stack(
          children: [
            grid,
            if (_inspect && _hoverInfo != null)
              Positioned(top: 8, right: 8, child: _hoverInspectCard()),
            if (candidate.isNotEmpty && candidate.first != null)
              Positioned(
                left: 12,
                top: 8,
                child: Material(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    // Say what a release would do, while the finger is down.
                    child: Text(
                      dropSummary(_dropDecision(candidate.first!)),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
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

  /// WS-X2 — what dropping [payload] on the pattern grid would do.
  ///
  /// No `acceptsDirectly`: unlike the Audio Editor's timeline, this surface is a
  /// MODE, not a container — it has no cell type that holds a foreign document
  /// as-is, so every non-tracker kind must convert or be refused.
  DropDecision _dropDecision(MusicDragPayload payload) =>
      dropDecisionFor(payload, AppMode.tracker);

  /// Land a dragged document in the pattern on screen.
  ///
  /// ⚠️ **It lands in the CURRENT PATTERN, and does not replace the song — the
  /// opposite call to Loop Studio's, for a concrete reason.** A drop there could
  /// replace the whole band because every path goes through `_syncPlayback`, so
  /// it was one undoable edit. Here the equivalent path is `_replaceSong`, which
  /// calls `_clearUndo()`: a snapshot history cannot survive a change of
  /// channel/row shape. A drop that replaced the song would therefore be
  /// **unrecoverable**, and an unrecoverable drop is worse than a partial one.
  /// The cost of that choice is real and is stated below: a dropped song's own
  /// pattern list, order and tempo do not come with it. The menu's Import is
  /// still there for whoever wants the whole document.
  ///
  /// Everything that converts INTO tracker yields a `TrackerSong`
  /// (score/tab/loop → tracker) and same-kind carries one too, so unlike the
  /// Loop target there is exactly one document shape to handle here.
  Future<bool> _dropHere(MusicDragPayload payload) async {
    final plan = _dropPlan(payload);
    if (plan == null) return false;

    if (plan.decision.needsConfirmation || plan.warnings.isNotEmpty) {
      // Only a drop that COSTS something asks. Making people dismiss a dialog
      // on every drop is how they learn to dismiss the one that mattered.
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(ctx)!.trackerDropLossyTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final line in plan.warnings) Text(line)],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(AppLocalizations.of(ctx)!.trackerDropAnyway),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return false;
    }
    _commitDrop(plan.fitted);
    return true;
  }

  /// What a drop would do, and what it would cost — worked out before anything
  /// is committed or shown.
  ///
  /// Split out from the commit so the WARNINGS can be asserted without pumping a
  /// dialog: the dialog itself is the same shape Loop Studio's target already
  /// proved, but the list of what a particular drop loses is this surface's own
  /// arithmetic and is where a mistake would hide.
  ({DropDecision decision, FittedPattern fitted, List<String> warnings})?
      _dropPlan(MusicDragPayload payload) {
    final decision = _dropDecision(payload);
    final document = decision.document;
    if (!decision.canDrop || document is! TrackerSong) return null;

    // ⚠️ A loss the bridge's report CANNOT know about, because it happens after
    // the conversion: the pattern on screen has its own shape, and a wider or
    // longer grid has to be cut to land. The bridge answered honestly for the
    // conversion it did; the trim is ours, and hiding it would be exactly the
    // "lossy drop that did not ask" the protocol exists to prevent.
    final fitted = fitCellsToPattern(
      document.engine.exportCells(),
      channels: _song.channelCount,
      rows: _song.rows,
    );
    return (
      decision: decision,
      fitted: fitted,
      warnings: <String>[
        if (decision.report case final report?) ...[
          for (final lost in report.lost) '• $lost',
          for (final near in report.approximated) '~ $near',
        ],
        if (fitted.droppedNotes > 0)
          '• ${fitted.droppedNotes} notes do not fit this pattern '
              '(${_song.channelCount} channels × ${_song.rows} rows)',
        if (document.patterns.length > 1)
          '• only the current pattern lands — the other '
              '${document.patterns.length - 1} stay behind',
      ],
    );
  }

  /// Write a fitted grid in, as ONE undoable edit.
  ///
  /// Through the ordinary edit path deliberately: that is what makes overwriting
  /// the pattern an acceptable thing for a drop to do at all.
  void _commitDrop(FittedPattern fitted) {
    _pushUndo();
    setState(() {
      for (var channel = 0; channel < fitted.cells.length; channel++) {
        _song.engine.setChannelCells(channel, fitted.cells[channel]);
      }
    });
    _syncPlayback();
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
          _ChannelMeter(
            levels: _levels,
            channel: c,
            muted: muted,
            progress: _progress,
            pcm: _song.engine.getStem(c),
          ),
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
  void debugMarkBlock(int channel, int row) => setState(() {
        _anchorChannel = channel;
        _anchorRow = row;
      });
  @override
  double? debugCellVolume(int channel, int row) =>
      _song.engine.cellAt(channel, row).volume;
  @override
  void debugSetCellVolume(int channel, int row, double volume) =>
      setState(() => _song.engine.setCellVolume(channel, row, volume));
  @override
  int? debugCellMidi(int channel, int row) =>
      _song.engine.cellAt(channel, row).midi;
  @override
  void unmark() => _unmark();

  Widget _rowWidget(
    int row,
    int activeRow,
    int stepsPerBeat,
    ColorScheme scheme,
  ) {
    final isActive = row == activeRow;
    final meter = _meterFor(stepsPerBeat);
    // Bar before beat: every bar row is also a beat row.
    final isMeasure = meter.isBar(row);
    final isBeat = meter.isBeat(row);
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
    // A compact ± stepper (~2 keys wide) for the right rail.
    Widget stepper({
      required String tooltip,
      String? label,
      IconData? mid,
      required VoidCallback onMinus,
      required VoidCallback onPlus,
    }) {
      Widget tap(IconData i, VoidCallback f) => InkResponse(
            onTap: f,
            radius: 13,
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: Icon(i, size: 14),
            ),
          );
      return Tooltip(
        message: tooltip,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            tap(Icons.remove, onMinus),
            if (mid != null)
              Icon(mid, size: 13, color: scheme.onSurfaceVariant),
            if (label != null)
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            tap(Icons.add, onPlus),
          ],
        ),
      );
    }

    return Container(
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          // The sweepable multi-octave piano fills the width. Tap a key to enter
          // that absolute note at the cursor; keys light up as the song plays.
          Expanded(
            child: SizedBox(
              height: 72,
              child: Scrollbar(
                controller: _pianoScroll,
                child: SingleChildScrollView(
                  controller: _pianoScroll,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: _pianoWhiteKeys * _pianoKW,
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
          ),
          const SizedBox(width: 6),
          // Compact right rail (~2 keys wide): options · octave · zoom. The
          // options button opens a sheet with entry mode / field / show-keys /
          // clear / help; the pending-note badge shows mid-entry feedback.
          SizedBox(
            width: 66,
            height: 78,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Badge(
                  isLabelVisible: _pendingLabel.isNotEmpty,
                  label: Text(_pendingLabel),
                  child: IconButton(
                    icon: const Icon(Icons.keyboard_alt, size: 19),
                    tooltip: l10n.settingsTitle,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 24, minHeight: 22),
                    onPressed: () => _showPianoOptions(l10n),
                  ),
                ),
                stepper(
                  tooltip: l10n.trackerOctave,
                  label: '$_octave',
                  onMinus: () => _setOctave(_octave - 1),
                  onPlus: () => _setOctave(_octave + 1),
                ),
                stepper(
                  tooltip: l10n.trackerZoomIn,
                  mid: Icons.search,
                  onMinus: () => setState(
                    () => _pianoZoom = (_pianoZoom - 0.2).clamp(0.6, 2.2),
                  ),
                  onPlus: () => setState(
                    () => _pianoZoom = (_pianoZoom + 0.2).clamp(0.6, 2.2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The piano's option sheet (moved off the always-on strip to the right rail):
  /// note-entry mode, the edit field, show-keys, clear-cell, and the keyboard
  /// help. Tab still cycles the field; these are the touch equivalents.
  void _showPianoOptions(AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void refresh() => setSheet(() {});
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.keyboard, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SegmentedButton<_NoteEntry>(
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
                            onSelectionChanged: (s) {
                              setState(() {
                                _entryMode = s.first;
                                _pendingSemi = null;
                              });
                              refresh();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.trackerField,
                      style: Theme.of(ctx).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<_CellField>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: _CellField.note, label: Text('♪')),
                        ButtonSegment(
                          value: _CellField.volume,
                          label: Text('vol'),
                        ),
                        ButtonSegment(
                          value: _CellField.effect,
                          label: Text('fx'),
                        ),
                        ButtonSegment(
                          value: _CellField.instrument,
                          label: Text('ins'),
                        ),
                      ],
                      selected: {_field},
                      onSelectionChanged: (s) {
                        setState(() => _field = s.first);
                        refresh();
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.trackerShowKeys),
                      value: _showKeyHints,
                      onChanged: (v) {
                        setState(() => _showKeyHints = v);
                        refresh();
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.backspace_outlined),
                      title: Text(l10n.trackerClearCell),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _clearAtCursorAndAdvance();
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.info_outline),
                      title: Text(l10n.trackerKeyHelp),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _showKeyHelp(l10n);
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
    required this.progress,
    required this.pcm,
  });

  final ValueNotifier<List<double>> levels;
  final ValueNotifier<double> progress;
  final int channel;
  final bool muted;
  final Float64List pcm;

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
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Stack(
                children: [
                  // VU Meter Background
                  FractionallySizedBox(
                    widthFactor: level,
                    heightFactor: 1.0,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      color: Color.lerp(scheme.primary, scheme.error, level) ??
                          scheme.primary,
                    ),
                  ),
                  // Oscilloscope overlay
                  ValueListenableBuilder<double>(
                    valueListenable: progress,
                    builder: (context, prog, _) => OscilloscopeWidget(
                      pcm: pcm,
                      progress: prog,
                      waveColor: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ],
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
    kFxSetPan: '8xx  Set pan',
    kFxSampleOffset: '9xx  Sample offset',
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
    kFxRetrigVolSlide: 'Rxy  Retrigger + volume',
    kFxTempoSlide: 'Txy  Tempo slide',
    kFxTremor: 'Ixy  Tremor',
    kFxPanbrello: 'Yxy  Panbrello',
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

/// Edits the RAW native command a cell was imported with — its original
/// format effect byte/letter-command and param, plus the source-format tag that
/// gates same-format export. Independent of the normalized [_CommandEditor]
/// above: this is the provenance channel (`nativeEffect`/`nativeEffectParam`/
/// `nativeFormat`) that a same-format S3M/IT/XM/MOD export re-emits verbatim.
class _NativeCommandEditor extends StatefulWidget {
  const _NativeCommandEditor({
    required this.l10n,
    required this.initialFormat,
    required this.initialEffect,
    required this.initialParam,
    required this.initialVolpan,
    required this.onChanged,
    required this.onClear,
  });

  final AppLocalizations l10n;
  final String? initialFormat;
  final int initialEffect;
  final int initialParam;
  final int initialVolpan;
  final void Function(String format, int effect, int param) onChanged;
  final void Function() onClear;

  @override
  State<_NativeCommandEditor> createState() => _NativeCommandEditorState();
}

class _NativeCommandEditorState extends State<_NativeCommandEditor> {
  static const _formats = ['mod', 's3m', 'xm', 'it'];

  late String _format = widget.initialFormat ?? 's3m';
  late int _effect = widget.initialEffect < 0 ? 0 : widget.initialEffect;
  late int _param = widget.initialParam;

  void _emit() => widget.onChanged(_format, _effect, _param);

  @override
  Widget build(BuildContext context) {
    final decode = nativeEffectMnemonic(_format, _effect);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.l10n.trackerNativeCommand),
        const SizedBox(height: 2),
        Text(
          widget.l10n.trackerNativeCommandHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            // Source-format tag: only a matching export re-emits the command.
            DropdownButton<String>(
              value: _format,
              items: [
                for (final f in _formats)
                  DropdownMenuItem(value: f, child: Text(f.toUpperCase())),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _format = v);
                _emit();
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$decode  '
                '\$${_effect.toRadixString(16).toUpperCase().padLeft(2, '0')}'
                '${_param.toRadixString(16).toUpperCase().padLeft(2, '0')}',
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (widget.initialFormat != null)
              IconButton(
                icon: const Icon(Icons.backspace_outlined, size: 18),
                tooltip: widget.l10n.trackerClear,
                onPressed: widget.onClear,
              ),
          ],
        ),
        // Raw effect byte 00–FF (MOD nibble / S3M+IT letter-command / XM byte).
        Row(
          children: [
            SizedBox(width: 64, child: Text(widget.l10n.trackerNativeEffect)),
            Expanded(
              child: Slider(
                value: _effect.toDouble(),
                max: 255,
                divisions: 255,
                label: _effect.toRadixString(16).toUpperCase().padLeft(2, '0'),
                onChanged: (v) {
                  setState(() => _effect = v.round());
                  _emit();
                },
              ),
            ),
          ],
        ),
        // Raw param byte 00–FF.
        Row(
          children: [
            SizedBox(width: 64, child: Text(widget.l10n.trackerNativeParam)),
            Expanded(
              child: Slider(
                value: _param.toDouble(),
                max: 255,
                divisions: 255,
                label: _param.toRadixString(16).toUpperCase().padLeft(2, '0'),
                onChanged: (v) {
                  setState(() => _param = v.round());
                  _emit();
                },
              ),
            ),
          ],
        ),
        if (widget.initialVolpan >= 0)
          Text(
            'vol \$'
            '${widget.initialVolpan.toRadixString(16).toUpperCase().padLeft(2, '0')}',
            style: Theme.of(context).textTheme.bodySmall,
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
