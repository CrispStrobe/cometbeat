import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_sources.dart' show ScoreSource;
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/loop_engine.dart'
    show LoopTiming, PatternCell, kPatternSteps;
import 'package:comet_beat/core/audio/microphone_pitch_service.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:comet_beat/core/audio/tracker_song.dart' show TrackerSong;
import 'package:comet_beat/core/audio/transcription/engine_config.dart'
    show Backend, TranscriptionStep;
import 'package:comet_beat/core/audio/wav_io.dart'
    show readWavPcm16, wavToMonoFloat;
import 'package:comet_beat/core/interop/drag_payload.dart';
import 'package:comet_beat/core/interop/project_bridge.dart';
import 'package:comet_beat/core/notation/guitar_score_fingering.dart'
    show barresFor, fingerFrettings;
import 'package:comet_beat/core/project/project_link.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/melody_bridge.dart';
import 'package:comet_beat/core/services/project_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/transcription_config_service.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:comet_beat/features/games/composition/chord_db.dart';
import 'package:comet_beat/features/games/composition/music_inspect.dart';
import 'package:comet_beat/features/games/composition/tab_arranger.dart';
import 'package:comet_beat/features/games/composition/tab_chord_builder.dart';
import 'package:comet_beat/features/games/composition/tab_chords.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:comet_beat/features/games/composition/tab_fx.dart';
import 'package:comet_beat/features/games/composition/tab_labeler.dart';
import 'package:comet_beat/features/games/composition/tab_mic_capture.dart';
import 'package:comet_beat/features/games/composition/tab_patterns.dart';
import 'package:comet_beat/features/games/composition/tabcnn_to_document.dart'
    show audioToTabDocument;
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/sound_lab/my_instruments_sheet.dart'
    show showMyInstrumentsSheet;
import 'package:comet_beat/features/workshop/export/score_pdf.dart'
    show exportScoreToPdf;
import 'package:comet_beat/features/workshop/model/score_document.dart'
    show grandStaffFromScore;
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/daw/send_to_daw.dart';
import 'package:comet_beat/shared/widgets/fx_rack.dart';
import 'package:comet_beat/shared/widgets/open_in_menu.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// A small built-in ASCII-tab riff so the screen is never empty. Parsed with
/// [asciiTabToScore], then made editable via [TabDocument.fromScore].
const _demoTab = '''
e|---0-------3-----0-------|
B|-----1-------1-------1---|
G|-------0-------0-------0-|
D|-------------------------|
A|-------------------------|
E|-0-------3-------0-------|
''';

/// Tuning presets offered in the picker (label ← [Tuning.name]).
final List<Tuning> tabTuningPresets = <Tuning>[
  Tuning.standardGuitar,
  Tuning.dropDGuitar,
  Tuning.dadgadGuitar,
  Tuning.openGGuitar,
  Tuning.sevenStringGuitar,
  Tuning.eightStringGuitar,
  Tuning.standardBass,
  Tuning.fiveStringBass,
  Tuning.ukulele,
  Tuning.mandolin,
  Tuning.banjoOpenG,
];

/// Extensions the tab reader accepts. GPIF (`.gp`/`.gpx`) carry real
/// tab/fret data; the rest are read as pitches and placed on the fretboard by
/// lowest-fret when converted to a [TabDocument].
const List<String> tabImportExtensions = <String>[
  'gp',
  'gpx',
  'musicxml',
  'xml',
  'mxl',
  'mid',
  'midi',
  'abc',
  'ly',
];

/// Parses an opened file into a [Score] by its extension — the tab editor's own
/// import (kept separate from the Workshop's `importScore` so this screen stays
/// self-contained). Pure given the raw [bytes], so it is unit-testable without a
/// file picker. Throws a [FormatException] on an unknown extension.
Score parseTabFile(String fileName, Uint8List bytes) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  String text() => utf8.decode(bytes);
  return switch (ext) {
    'gp' => scoreFromGpif(readGpifFromGp(bytes)),
    'gpx' => scoreFromGpif(readGpifFromGpx(bytes)),
    'musicxml' || 'xml' => scoreFromMusicXml(text()),
    'mxl' => scoreFromMusicXml(readMusicXmlFromMxl(bytes)),
    'mid' || 'midi' => scoreFromMidi(bytes),
    'abc' => scoreFromAbc(text()),
    'ly' => scoreFromLilyPond(text()),
    _ => throw FormatException('Unsupported file type: .$ext'),
  };
}

/// Test seam onto [TabWorkshopScreen]'s state — drives editing + file-open with
/// injected bytes, and reads back what's shown, without the platform picker.
abstract class TabWorkshopTester {
  /// WS-X1 — put this tab in the project, re-open that track LIVE, and have
  /// edits land back in it.
  String? addToProject({String? name});
  bool openProjectTrack(String trackId);
  bool get hasLiveProjectLink;
  bool writeBackToProject();

  Future<void> openScoreFile({String? pickedName, Uint8List? pickedBytes});

  /// Transcribe a mono WAV recording into editable tab on the active track (via
  /// the TabCNN audio→tab model). [pickedBytes] injects the file in tests.
  Future<void> openAudioRecording({String? pickedName, Uint8List? pickedBytes});
  bool get isTranscribingAudio;
  String? get sourceName;
  Tuning get tuning;
  int get capo;
  int get columnCount;

  /// The fret on [string] at [col], or null if empty.
  int? fretAt(int col, int string);
  void selectCell(int col, int string);
  void enterFret(int fret);
  void deleteCell();
  void addColumn();
  void removeColumnAtCursor();

  /// Restores the active track to its state before/after the last undo.
  void undo();
  void redo();
  bool get canUndo;
  bool get canRedo;

  /// Copies the whole bar the cursor is in and inserts it right after; the
  /// cursor lands on the first column of the copy. Returns columns added.
  int duplicateBar();

  /// Transposes the whole tab by [semitones] (all-or-nothing; false = a note
  /// would fall off the fretboard, nothing changed).
  bool transposeBy(int semitones);
  void play();
  bool get isPlaying;

  /// Render+play the whole tab through [inst] (the picker minus the sheet).
  void debugPlayWithInstrument(TrackerInstrument inst);

  /// A one-bar metronome count-in before playback (opt-in).
  bool get countInOn;
  void setCountIn(bool on);
  bool get isCountingIn;
  Set<String> get highlightedIds;

  /// WS-X2 test seam: drop [payload] on the grid, skipping the confirmation
  /// (the dialog is the shape the other three targets already proved). Returns
  /// whether anything landed.
  bool debugDrop(MusicDragPayload payload);

  /// WS-X2 test seam: what a drop would warn about — empty when it costs
  /// nothing, which is when no dialog should appear.
  List<String> debugDropWarnings(MusicDragPayload payload);

  /// Set the tuning, as the settings sheet's picker does.
  ///
  /// A seam because the tuning decides what a fret SOUNDS, so it is part of
  /// several things worth testing: the derived-score cache key, the drop
  /// warnings, and the crash that used to happen when frets outlived their
  /// strings.
  void setTuning(Tuning tuning);

  /// Set the capo, as the settings sheet's stepper does.
  ///
  /// A seam because the capo is SCREEN state that changes what the score sounds,
  /// which makes it part of the derived-score cache key — and a key is only
  /// worth having if something proves it is complete.
  void debugSetCapo(int frets);

  /// How many times the engraved score has actually been DERIVED.
  ///
  /// The other half of the rebuild story: a build that reuses the cached score is
  /// far cheaper than one that re-derives it, and this is what proves the cache
  /// is working rather than quietly missing every time — the failure mode that
  /// looks exactly like success.
  int get debugScoreBuilds;

  /// How many times the SCREEN has rebuilt.
  ///
  /// A perf seam, not a feature: two of this screen's biggest costs were
  /// whole-screen rebuilds nothing visible needed (an FX slider drag at ~60 fps,
  /// and the playhead moving to the next column). Both are now narrowed, and a
  /// counter is the only way to keep them narrow — a wall-clock assertion on
  /// shared CI hardware is noise, but "this gesture must not rebuild the screen"
  /// is exact.
  int get debugBuildCount;
  void toggleTechnique(TabTechnique t);
  Set<TabTechnique> techniquesAt(int col);
  void setChordByName(String? name);
  String? chordNameAt(int col);

  /// Generative insert (after the cursor): voice a chord in a [ChordStyle],
  /// lay down a named progression (each chord in that style), or run a scale
  /// across the fretboard — each optionally [repeat]ed. The cursor lands on the
  /// last inserted column. All return the number of columns added.
  int insertChordStyle(String chordName, ChordStyle style, {int repeat});
  int insertProgression(String progressionName, ChordStyle style, {int repeat});
  int insertScale(
    int rootMidi,
    String scaleName, {
    int octaves,
    bool descending,
    int repeat,
    int? startFret,
  });
  void saveToSongBook(String title);
  int get bpm;
  int get trackCount;
  int get activeTrack;
  void selectTrack(int index);
  void addTrack();
  void removeTrack();
  void toggleMute();
  void toggleSolo();
  bool isMuted(int track);
  bool isSoloed(int track);

  /// Shared-tune bridge (MelodyBridge): publish the top voice of the tab out as
  /// a tune, and pull a shared tune in as fretted columns after the cursor.
  bool get canShareMelody;
  void shareMelody();
  bool get canLoadSharedMelody;
  void loadSharedMelody();

  /// Loads a Song-Book song (by MusicXML) into the active track as editable tab.
  void openSongMusicXml(String title, String musicXml);

  /// Replaces the active track with tab parsed from ASCII-tab [text].
  void pasteAsciiTab(String text);

  /// The multi-part score handed to the Score Workshop (one part per track).
  MultiPartScore debugWorkshopScore();
  bool get isListening;

  /// Feeds a reading straight into the mic-capture path, bypassing the plugin,
  /// so the wiring is testable without a microphone.
  void debugFeedReading(PitchReading reading);

  /// 🔍 Looking Glass: whether inspect mode is on, toggle it, and (for a test)
  /// the `(noteNames, columnChord)` the inspector reports for a cell (null = an
  /// empty column).
  bool get inspectMode;
  void toggleInspectMode();
  (String, String?)? debugInspectInfo(int col, int string);

  /// Practice tools (D4): whether looping / the speed trainer are on.
  bool get debugLoop;
  bool get debugLoopBar;
  bool get debugMetronome;
  bool get debugSpeedTrainer;

  /// 🔍 Desktop hover: drive the hover over a cell and read whether the corner
  /// card is showing (a fretted cell shows it; an empty column clears it).
  void debugHoverCell(int col, int string);
  bool get debugHoverCardShown;

  /// Send the whole tab band to the Multitrack (DAW) as a clip.
  void sendToDaw();

  /// Name the left-hand finger for every fretted note in the active track
  /// (B10, automatic), and read back the digits at a column.
  void addLeftFingerings();
  List<int>? leftFingersAt(int col);
}

/// A guitar/bass **tablature editor** (B1) — the Tab Workshop. Author tab on a
/// string×step grid (tap a cell, type a fret) for any [Tuning] + capo, hear it,
/// and open GPIF / MusicXML / MIDI / ABC files as editable tab. The
/// engraved staff (with a synced standard staff) previews the [TabDocument];
/// the same model round-trips to the Score Workshop and Tracker.
///
/// The standard-notation staff shown ABOVE the tab — independent of the tab, so
/// a user can have tab + notation together (not either/or). [off] hides it;
/// [standard] is a single clef; [grand] is a treble+bass grand staff (better for
/// the low strings, which sink far below a single staff).
enum _Notation { off, standard, grand }

class TabWorkshopScreen extends StatefulWidget {
  /// Optional single score to open as editable tab (e.g. from the Workshop).
  /// When null (and [initialParts] is null) a built-in demo riff is shown.
  final Score? initialScore;

  /// Optional MULTI-part score — one editable tab track per part, so an
  /// orchestral / band import opens every instrument (not just the first).
  /// Takes precedence over [initialScore]. Track names come from [initialNames]
  /// where given, else "Track N".
  final MultiPartScore? initialParts;

  /// Optional per-part track names, aligned with [initialParts].parts.
  final List<String>? initialNames;

  /// When set (opened to edit an Audio Editor music clip), "Send to Audio Editor"
  /// calls this with the edited band score and pops back — an IN-PLACE round-trip
  /// that updates the source clip instead of adding a new one.
  final void Function(MultiPartScore edited)? onReturnToDaw;

  /// Test seam: overrides the audio→tab transcription (default
  /// [audioToTabDocument], which downloads + runs the TabCNN model). Tests inject
  /// a fake so `openAudioRecording` is exercised without the model / network.
  final Future<TabDocument?> Function(
    Float64List mono,
    int sampleRate,
    Tuning tuning,
  )? debugAudioToTab;

  const TabWorkshopScreen({
    super.key,
    this.initialScore,
    this.initialParts,
    this.initialNames,
    this.onReturnToDaw,
    this.debugAudioToTab,
  });

  @override
  State<TabWorkshopScreen> createState() => _TabWorkshopScreenState();
}

class _TabWorkshopScreenState extends State<TabWorkshopScreen>
    with SingleTickerProviderStateMixin
    implements TabWorkshopTester {
  late List<TabTrack> _tracks;
  int _active = 0;

  /// Undo/redo history: `(trackIndex, deep-copied columns)` snapshots, newest
  /// last, capped so they never grow without bound.
  final List<(int, List<TabColumn>)> _undoStack = [];
  final List<(int, List<TabColumn>)> _redoStack = [];
  static const _maxUndo = 50;

  /// ⚠️ PERF: a SHALLOW list copy, not a deep one.
  ///
  /// This used to `copy()` every column, so a single fret keystroke deep-copied
  /// the whole document — three collections and up to four lists per column,
  /// through a 30-parameter `copyWith` — and fifty of those were retained.
  /// `TabColumn` is immutable and every edit goes through `copyWith`, so an
  /// unchanged column can be SHARED with the history instead of duplicated: the
  /// snapshot needs the list to stop changing, not the columns. Structural
  /// sharing, and it is only sound because of that immutability — if a column
  /// ever gains an in-place mutator this has to go back to a deep copy.
  (int, List<TabColumn>) _captureState() => (_active, List.of(_doc.columns));

  /// Snapshot the active track before a mutation so [undo] can restore it. A
  /// fresh edit invalidates the redo history.
  void _snapshot() {
    _undoStack.add(_captureState());
    if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  /// Name the left-hand FINGER for every fretted note in the active track.
  ///
  /// ⚠ This does NOT re-fret anything. The frets here are the ones the player
  /// typed, and `arrangeTab` would happily replace them with its own choice —
  /// so `fingerFrettings` is handed the shapes exactly as they stand and only
  /// adds the digit. Fingering a tab must never move a note.
  ///
  /// One undo step, like every other edit.
  @override
  void addLeftFingerings() {
    final cols = _doc.columns;
    if (cols.every((c) => c.frets.isEmpty)) return;
    final shapes = [for (final c in cols) c.frets];
    final fingers = fingerFrettings(shapes);
    // A barre is not a second decision — it is what the index is already doing
    // when the digits come out 1,1,1 at one fret. Naming it is the difference
    // between "three fingers there" and what a player actually reads.
    final barres = barresFor(shapes);
    setState(() {
      _snapshot();
      for (var i = 0; i < cols.length && i < fingers.length; i++) {
        cols[i] = cols[i].copyWith(
          leftFingers: fingers[i].isEmpty ? null : fingers[i],
          // ⚠ Never overwrite a barre the FILE stated. An imported Guitar Pro
          // barre is the engraver's, and a suggestion must not silently replace
          // a fact.
          barreFret: cols[i].barreFret ?? barres[i],
        );
      }
    });
  }

  @override
  List<int>? leftFingersAt(int col) =>
      col < _doc.columns.length ? _doc.columns[col].leftFingers : null;

  /// Drop all history — the document or track indices changed (load / paste /
  /// track removal), so old snapshots are stale.
  void _clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
  }

  void _restore((int, List<TabColumn>) snap) {
    final (track, cols) = snap;
    _active = track.clamp(0, _tracks.length - 1);
    // Through the document, so `revision` moves and the engraved score is
    // re-derived: an undo that only fixed the GRID left the notation and tab
    // panes showing the edit it had just taken back.
    _tracks[_active].doc.replaceColumns(cols);
    _selCol = _selCol.clamp(0, _doc.columns.length - 1);
  }

  @override
  bool get canUndo => _undoStack.isNotEmpty;
  @override
  bool get canRedo => _redoStack.isNotEmpty;

  @override
  void undo() {
    if (_undoStack.isEmpty) return;
    final prev = _undoStack.removeLast();
    setState(() {
      _redoStack.add(_captureState()); // so redo can come back here
      _restore(prev);
    });
  }

  @override
  void redo() {
    if (_redoStack.isEmpty) return;
    final next = _redoStack.removeLast();
    setState(() {
      _undoStack.add(_captureState());
      _restore(next);
    });
  }

  /// The document being edited — the active track's.
  TabDocument get _doc => _tracks[_active].doc;

  // --- WS-X1 live project links ---------------------------------------------

  /// The project track this screen is editing live, if any.
  ProjectLink? _projectLink;
  ProjectService? _projects;

  ProjectLinker? get _linker {
    final projects = _projects;
    return projects == null ? null : ProjectLinker(projects);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _projects = Provider.of<ProjectService>(context, listen: false);
    } on ProviderNotFoundException {
      _projects = null;
    }
  }

  @override
  String? addToProject({String? name}) {
    final linker = _linker;
    if (linker == null) return null;
    final doc = _doc;
    final id =
        linker.add(kind: AppMode.tab, document: doc, name: name ?? 'Tab');
    _projectLink = ProjectLink(document: doc, trackId: id, live: true);
    return id;
  }

  /// Opens a project track here. A TAB track opens live — no conversion, no
  /// copy; anything else is refused rather than silently converted, because a
  /// conversion belongs behind the "Open in…" menu where its cost is shown.
  @override
  bool openProjectTrack(String trackId) {
    final linker = _linker;
    if (linker == null) return false;
    final link = linker.open(trackId, AppMode.tab);
    final doc = link.document;
    if (doc is! TabDocument) return false;
    setState(() {
      _tracks[_active].doc = doc;
      _projectLink = link;
    });
    return true;
  }

  @override
  bool get hasLiveProjectLink => _projectLink?.live ?? false;

  @override
  bool writeBackToProject() {
    final linker = _linker;
    final link = _projectLink;
    if (linker == null || link == null) return false;
    return linker.writeBack(link, _doc);
  }

  int _capo = 0;
  bool _showTab = true;
  _Notation _notation = _Notation.standard;
  NoteDuration _dur = NoteDuration.quarter;
  int _selCol = 0;
  int _selString = 0;
  int _bpm = 120;
  bool _inspect = false; // 🔍 Looking Glass: tap a cell to see its note + chord
  InspectInfo? _hoverInfo; // 🔍 desktop hover: the cell under the mouse's card
  String? _sourceName;
  final _focus = FocusNode();

  // Mic capture: play a note, it lands on the fretboard at the cursor.
  final MicrophonePitchService _mic = MicrophonePitchService();
  StreamSubscription<PitchReading>? _micSub;
  TabMicCapture? _capture;
  bool _listening = false;

  // Playback highlight: a Ticker lights the sounding column's note id in time.
  late final Ticker _ticker;
  bool _playing = false;
  bool _countIn = false; // opt-in one-bar metronome before playback
  // Opt-in: render playback through the tracker replayer so a column's playing
  // techniques (slide/vibrato/bend) are HEARD, not just drawn. Off = the dry
  // Score voice, unchanged.
  bool _articulate = false;
  bool _countingIn = false;
  int _playToken = 0; // bumped to cancel an in-flight count-in
  /// The sounding column, as a notifier rather than plain state.
  ///
  /// ⚠️ PERF: this used to be a field set through `setState`, so every time the
  /// playhead moved to the next column the WHOLE screen rebuilt — a full
  /// `toScore`, a full tab layout and every grid cell, twice a second at 120 bpm,
  /// to move one highlight. The three views already repaint without relayout
  /// when only `highlightedIds` changes (`RenderStaffView`), so the narrow path
  /// existed in the renderer and the screen was throwing it away.
  final _highlighted = ValueNotifier<Set<String>>(const {});

  /// Where the last tick found the playhead in [_schedule].
  ///
  /// ⚠️ PERF: the tick used to scan the whole schedule EVERY frame to find the
  /// sounding column. The schedule is sorted and time only moves forward within
  /// a pass, so a cursor makes it O(1) amortised — the same fix the note-highway
  /// card describes for its per-frame grader scan. Reset whenever playback
  /// restarts, including on a loop wrap.
  int _scheduleCursor = 0;
  List<({int col, int start, int end, bool note})> _schedule = const [];
  int _totalMs = 0;
  // Practice tools (D4): loop the piece, and a speed trainer that ramps the
  // tempo one step per loop up to the authored [_bpm].
  bool _loop = false;
  bool _loopBar = false; // loop only the cursor's bar (implies looping)
  bool _speedTrainer = false;
  bool _metronome = false; // an in-play click, baked into the mix
  int _playBpm = 120; // the tempo currently sounding (trainer may ramp it)
  List<int> _trainerTempos = const [];
  int _loopIndex = 0;

  @override
  void initState() {
    super.initState();
    final parts = widget.initialParts?.parts;
    if (parts != null && parts.isNotEmpty) {
      // Multi-instrument import: one editable tab track per part.
      final names = widget.initialNames;
      _tracks = [
        for (var i = 0; i < parts.length; i++)
          TabTrack(
            (names != null && i < names.length && names[i].trim().isNotEmpty)
                ? names[i]
                : 'Track ${i + 1}',
            TabDocument.fromScore(parts[i], Tuning.standardGuitar),
          ),
      ];
    } else {
      final score = widget.initialScore ?? asciiTabToScore(_demoTab);
      _tracks = [
        TabTrack('Guitar', TabDocument.fromScore(score, Tuning.standardGuitar)),
      ];
    }
    _ticker = createTicker(_onTick);
    // Smart-fingering opt-in (Settings, on by default): load the symbolic labeler
    // once (background) so every score→tab path (imports, the MelodyBridge pull)
    // fingers like the human model via the TabArranger global. When the user has
    // turned it off, force the pure heuristic — no model download, no ONNX.
    bool smart;
    try {
      smart = context.read<SettingsService>().smartTabFingering;
    } on ProviderNotFoundException {
      smart = true;
    }
    if (!smart) {
      TabArranger.shared = null;
    } else if (TabArranger.shared == null) {
      TabLabeler.load().then((m) {
        if (m != null) TabArranger.shared = m;
      });
    }
  }

  @override
  void dispose() {
    _micSub?.cancel();
    _mic.dispose();
    _ticker.dispose();
    _focus.dispose();
    _highlighted.dispose();
    super.dispose();
  }

  // ── Tester seam ──────────────────────────────────────────────────────────
  @override
  String? get sourceName => _sourceName;
  @override
  Tuning get tuning => _doc.tuning;
  @override
  int get capo => _capo;
  @override
  int get columnCount => _doc.columns.length;
  @override
  int? fretAt(int col, int string) =>
      col < _doc.columns.length ? _doc.columns[col].frets[string] : null;
  @override
  void selectCell(int col, int string) => setState(() {
        _selCol = col.clamp(0, _doc.columns.length - 1);
        _selString = string.clamp(0, _doc.stringCount - 1);
      });

  /// The sounding pitch of ([string], [fret]) on this tuning, including the
  /// capo transpose so the inspector reports what is actually heard.
  Pitch _pitchAt(int string, int fret) =>
      Pitch.fromMidi(_doc.tuning.strings[string].midiNumber + fret + _capo);

  /// 🔍 Describe cell ([col], [string]): the fretted note, the chord the whole
  /// column sounds, and the string/fret (+ any attached chord name). Null when
  /// the column is empty (nothing to inspect).
  InspectInfo? _inspectInfoFor(int col, int string) {
    final column = _doc.columns[col];
    final colPitches = <Pitch>[
      for (var s = 0; s < _doc.stringCount; s++)
        if (column.frets[s] case final int f) _pitchAt(s, f),
    ];
    if (colPitches.isEmpty) return null;
    final fret = column.frets[string];
    final names = fret != null
        ? _pitchAt(string, fret).toString()
        : colPitches.map((p) => p.toString()).join(' ');
    final where = fret != null
        ? 'string ${string + 1} · fret $fret'
        : 'string ${string + 1}';
    final chordName = column.chord?.name;
    return InspectInfo(
      noteNames: names,
      chordSymbol: chordSymbolFor(colPitches),
      detail: chordName != null ? '$where · $chordName' : where,
    );
  }

  /// A cell tap: inspect it in Looking-Glass mode, else select it for editing.
  void _onCellTap(int col, int string) {
    if (_inspect) {
      selectCell(col, string); // show which cell, then describe it
      final info = _inspectInfoFor(col, string);
      if (info != null) showInspect(context, info);
      return;
    }
    selectCell(col, string);
  }

  @override
  void enterFret(int fret) {
    _snapshot();
    setState(() {
      _doc.setDuration(_selCol, _dur);
      _doc.setFret(_selCol, _selString, fret);
    });
  }

  @override
  void deleteCell() {
    _snapshot();
    setState(() => _doc.clearCell(_selCol, _selString));
  }

  @override
  void addColumn() {
    _snapshot();
    setState(() {
      _doc.insertColumn(_selCol + 1);
      _selCol = (_selCol + 1).clamp(0, _doc.columns.length - 1);
    });
  }

  @override
  void removeColumnAtCursor() {
    _snapshot();
    setState(() {
      _doc.removeColumn(_selCol);
      _selCol = _selCol.clamp(0, _doc.columns.length - 1);
    });
  }

  @override
  int duplicateBar() {
    _snapshot();
    final (_, end) = _doc.barBoundsAt(_selCol);
    final n = _doc.duplicateBar(_selCol);
    if (n > 0) {
      // Park the cursor on the first column of the fresh copy.
      setState(() => _selCol = end.clamp(0, _doc.columns.length - 1));
    } else {
      _undoStack.removeLast(); // nothing changed — drop the snapshot
    }
    return n;
  }

  @override
  bool transposeBy(int semitones) {
    _snapshot();
    final ok = _doc.transposeBy(semitones);
    if (ok) {
      setState(() {});
    } else {
      _undoStack.removeLast(); // nothing changed — drop the snapshot
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.tabTransposeLimit)),
        );
      }
    }
    return ok;
  }

  @override
  void play() => _play();
  @override
  bool get isPlaying => _playing;

  @override
  void debugPlayWithInstrument(TrackerInstrument inst) =>
      _renderAndPlayWith(inst);

  /// Pick a saved "My Instruments" voice and hear the whole tab through it — a
  /// preview, separate from the highlighting transport.
  Future<void> _playWithInstrument() async {
    final saved = await showMyInstrumentsSheet(context, includeBuiltIns: true);
    if (saved == null || !mounted) return;
    final inst = saved.instrument;
    if (inst != null) {
      _renderAndPlayWith(inst);
    }
  }

  void _renderAndPlayWith(TrackerInstrument inst) {
    final quarterMs = (60000 / (_bpm <= 0 ? 120 : _bpm)).round();
    // A6: renders per track and applies each track's own FX chain. With no
    // chains anywhere it takes the same single-pass path as before, so an
    // effect-free tab still sounds byte-identical.
    //
    // "Articulate" opts into the tracker replayer instead, so a column's playing
    // techniques (slide → 3xx, vibrato → 4xy, bend → 1xx) actually sound; the FX
    // chains still apply. Off keeps the dry Score voice.
    final pcm = _articulate
        ? renderTabBandThroughTracker(
            _tracks,
            inst,
            quarterMs: quarterMs,
            capo: _capo,
          )
        : renderTabBandWithFx(
            _tracks,
            inst,
            quarterMs: quarterMs,
            capo: _capo,
          );
    if (pcm.isEmpty) return;
    var peak = 0.0;
    for (final s in pcm) {
      if (s.abs() > peak) peak = s.abs();
    }
    final g = peak > 0.9 ? 0.9 / peak : 1.0;
    final i16 = Int16List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      i16[i] = (pcm[i] * g * 32767).round().clamp(-32768, 32767);
    }
    unawaited(context.read<AudioService>().playWavBytes(wavBytes(i16)));
  }

  @override
  bool get countInOn => _countIn;
  @override
  void setCountIn(bool on) => setState(() => _countIn = on);
  @override
  bool get isCountingIn => _countingIn;
  @override
  Set<String> get highlightedIds => _highlighted.value;
  @override
  int get debugBuildCount => _buildCount;
  @override
  int get debugScoreBuilds => _scoreBuilds;
  @override
  void setTuning(Tuning tuning) => setState(() => _doc.tuning = tuning);
  @override
  bool debugDrop(MusicDragPayload payload) {
    final plan = _dropPlan(payload);
    if (plan == null) return false;
    _commitDrop(plan.columns);
    return true;
  }

  @override
  List<String> debugDropWarnings(MusicDragPayload payload) =>
      _dropPlan(payload)?.warnings ?? const [];
  @override
  void debugSetCapo(int frets) => setState(() => _capo = frets.clamp(0, 12));
  @override
  void toggleTechnique(TabTechnique t) {
    _snapshot();
    setState(() => _doc.toggleTechnique(_selCol, t));
  }

  @override
  Set<TabTechnique> techniquesAt(int col) =>
      col < _doc.columns.length ? _doc.columns[col].techniques : const {};
  @override
  void setChordByName(String? name) {
    _snapshot();
    setState(
      () => _doc.setChordVoicing(
        _selCol,
        name == null ? null : kGuitarChords[name],
      ),
    );
  }

  /// Attach an arbitrary [diagram] (e.g. one the chord builder voiced from a
  /// root + quality) to the selected column, voicing its playable frets.
  void _setChordDiagram(ChordDiagram? diagram) {
    _snapshot();
    setState(() => _doc.setChordVoicing(_selCol, diagram));
  }

  /// The bundled chords-db voicings for the current tuning — `guitar`/`ukulele`
  /// when it's a standard tuning, else null (the chord builder then voices
  /// algorithmically). Loaded + cached lazily.
  Future<ChordDb?> _loadChordDb() {
    final pitches = _doc.tuning.strings.map((p) => p.midiNumber).toList();
    bool isTuning(Tuning t) {
      final other = t.strings.map((p) => p.midiNumber).toList();
      if (other.length != pitches.length) return false;
      for (var i = 0; i < pitches.length; i++) {
        if (pitches[i] != other[i]) return false;
      }
      return true;
    }

    if (isTuning(Tuning.standardGuitar)) return ChordDb.load('guitar');
    if (isTuning(Tuning.ukulele)) return ChordDb.load('ukulele');
    return Future<ChordDb?>.value();
  }

  @override
  String? chordNameAt(int col) =>
      col < _doc.columns.length ? _doc.columns[col].chord?.name : null;

  /// Plays [cols] once through the shared transport so a pattern/progression/
  /// scale can be heard before it's inserted. Reuses the capo-correct playback
  /// timeline; does not touch the document.
  void _previewColumns(List<TabColumn> cols) {
    if (cols.isEmpty) return;
    final events = TabDocument(tuning: _doc.tuning, columns: cols)
        .toPlaybackEvents(bpm: _bpm, capo: _capo);
    context.read<AudioService>().playTimedChords(events);
  }

  /// Drops [cols] in after the cursor and parks the cursor on the last of them.
  int _insertRun(List<TabColumn> cols) {
    if (cols.isEmpty) return 0;
    _snapshot();
    setState(() {
      final at = _selCol + 1;
      _doc.insertColumnsAt(at, cols);
      _selCol = (at + cols.length - 1).clamp(0, _doc.columns.length - 1);
    });
    return cols.length;
  }

  // ── Shared-tune bridge (MelodyBridge) ──────────────────────────────────────
  // Tab⇄tune is the easy direction: a fret already knows its exact pitch, so
  // publishing walks the columns reading the TOP sounding note of each (the
  // melody voice), and loading runs the shared line through [arrangeTab] (the
  // Viterbi arranger) so it stays in one hand position instead of bouncing to
  // the lowest fret per note. Polyphonic score→tab uses the same arranger via
  // TabDocument.fromScore.

  @override
  bool get canShareMelody => _doc.columns.any((c) => c.frets.isNotEmpty);

  @override
  void shareMelody() {
    final cells = <PatternCell>[];
    var filled = 0;
    for (final col in _doc.columns) {
      if (filled >= kPatternSteps) break;
      final (num, den) = col.duration.fraction;
      var steps = (num * LoopTiming.stepsPerBar / den).round();
      if (steps < 1) steps = 1;
      if (filled + steps > kPatternSteps) steps = kPatternSteps - filled;
      // The melody note is the highest sounding pitch in the column (top voice).
      int? midi;
      col.frets.forEach((string, fret) {
        final m = _doc.tuning.strings[string].midiNumber + fret + _capo;
        if (midi == null || m > midi!) midi = m;
      });
      cells
          .add(PatternCell(midis: midi == null ? null : [midi!], steps: steps));
      filled += steps;
    }
    if (filled < kPatternSteps) {
      cells.add(PatternCell(steps: kPatternSteps - filled));
    }
    if (cells.every((c) => c.midis == null)) return; // nothing but rests
    MelodyBridge.instance.publish(
      SharedMelody(cells: cells, tempoBpm: _bpm, source: 'tab'),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.tuneShared)),
    );
  }

  /// Decomposes [steps] eighth-steps into the fewest tab note values, largest
  /// first (the tab's own [kTabDurations] set — whole … eighth).
  List<NoteDuration> _tabDurationsFor(int steps) {
    final out = <NoteDuration>[];
    var rem = steps;
    while (rem > 0) {
      final pick = kTabDurations.firstWhere(
        (d) => d.$2 <= rem,
        orElse: () => kTabDurations.last, // an eighth (1 step) always fits
      );
      out.add(pick.$1);
      rem -= pick.$2;
    }
    return out;
  }

  @override
  bool get canLoadSharedMelody => MelodyBridge.instance.hasMelody;

  @override
  void loadSharedMelody() {
    final shared = MelodyBridge.instance.current;
    if (shared == null || shared.isEmpty) return;
    // Split each cell into notatable durations, one output column each (a note
    // held across pieces keeps its MIDI so the arranger parks it on one fret).
    final midiCols = <List<int>>[];
    final durs = <NoteDuration>[];
    for (final c in shared.cells) {
      final midis = c.midis;
      for (final d in _tabDurationsFor(c.steps)) {
        midiCols.add(
          midis == null || midis.isEmpty
              ? const []
              : [midis.first + shared.key],
        );
        durs.add(d);
      }
    }
    if (midiCols.isEmpty) return;
    final frettings = arrangeTab(midiCols, _doc.tuning, capo: _capo);
    final cols = [
      for (var i = 0; i < frettings.length; i++)
        TabColumn(frets: frettings[i], duration: durs[i]),
    ];
    if (_insertRun(cols) == 0) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.tuneLoaded)),
    );
  }

  @override
  int insertChordStyle(String chordName, ChordStyle style, {int repeat = 1}) {
    final c = kGuitarChords[chordName];
    if (c == null) return 0;
    // Regenerate per repeat so every column is a fresh instance (later edits
    // mutate a column's fret map in place — shared instances would corrupt).
    return _insertRun([
      for (var i = 0; i < repeat; i++) ...chordStyleColumns(c, style, _dur),
    ]);
  }

  @override
  int insertProgression(
    String progressionName,
    ChordStyle style, {
    int repeat = 1,
  }) {
    final chords = kProgressions[progressionName];
    if (chords == null) return 0;
    return _insertRun(
      progressionColumns(chords, kGuitarChords, style, _dur, repeat: repeat),
    );
  }

  @override
  int insertScale(
    int rootMidi,
    String scaleName, {
    int octaves = 1,
    bool descending = false,
    int repeat = 1,
    int? startFret,
  }) {
    final intervals = kScales[scaleName];
    if (intervals == null) return 0;
    return _insertRun([
      for (var i = 0; i < repeat; i++)
        ...scaleColumns(
          _doc.tuning,
          rootMidi,
          intervals,
          _dur,
          octaves: octaves,
          descending: descending,
          startFret: startFret,
        ),
    ]);
  }

  @override
  int get bpm => _bpm;
  @override
  bool get isListening => _listening;

  @override
  void debugFeedReading(PitchReading reading) => _onReading(reading);

  @override
  bool get inspectMode => _inspect;
  @override
  void toggleInspectMode() => setState(() => _inspect = !_inspect);
  @override
  bool get debugLoop => _loop;
  @override
  bool get debugLoopBar => _loopBar;
  @override
  bool get debugMetronome => _metronome;
  @override
  bool get debugSpeedTrainer => _speedTrainer;
  @override
  (String, String?)? debugInspectInfo(int col, int string) {
    final info = _inspectInfoFor(col, string);
    return info == null ? null : (info.noteNames, info.chordSymbol);
  }

  @override
  void debugHoverCell(int col, int string) => _onCellHover(col, string);
  @override
  bool get debugHoverCardShown => _inspect && _hoverInfo != null;

  /// A committed note from the mic lands at the cursor, then the cursor steps
  /// on — so playing a phrase writes it across the grid.
  void _onReading(PitchReading reading) {
    final placement = (_capture ??= TabMicCapture(_doc.tuning)).accept(reading);
    if (placement == null) return;
    setState(() {
      _doc.setDuration(_selCol, _dur);
      _doc.setFret(_selCol, placement.$1, placement.$2);
      _selCol++; // setFret grows the document as needed
      _selString = placement.$1;
    });
  }

  Future<void> _toggleMic() async {
    final l10n = AppLocalizations.of(context)!;
    if (_listening) {
      await _micSub?.cancel();
      _micSub = null;
      await _mic.stop();
      if (!mounted) return;
      setState(() => _listening = false);
      return;
    }
    try {
      if (!await _mic.hasPermission()) {
        if (!mounted) return;
        _snack(l10n.tabMicDenied);
        return;
      }
      _capture = TabMicCapture(_doc.tuning);
      _micSub = _mic.readings.listen(_onReading);
      await _mic.start();
      if (!mounted) return;
      setState(() => _listening = true);
    } catch (_) {
      await _micSub?.cancel();
      _micSub = null;
      if (!mounted) return;
      _snack(l10n.tabMicFailed);
    }
  }

  @override
  int get trackCount => _tracks.length;
  @override
  int get activeTrack => _active;

  @override
  void selectTrack(int index) => setState(() {
        _active = index.clamp(0, _tracks.length - 1);
        _selCol = _selCol.clamp(0, _doc.columns.length - 1);
        _selString = _selString.clamp(0, _doc.stringCount - 1);
      });

  @override
  void addTrack() => setState(() {
        _tracks.add(
          TabTrack(
            'Track ${_tracks.length + 1}',
            TabDocument.blank(Tuning.standardGuitar),
          ),
        );
        _active = _tracks.length - 1;
        _selCol = 0;
        _selString = 0;
      });

  @override
  void removeTrack() => setState(() {
        if (_tracks.length <= 1) return; // always keep one track
        _tracks.removeAt(_active);
        _active = _active.clamp(0, _tracks.length - 1);
        _selCol = _selCol.clamp(0, _doc.columns.length - 1);
        _selString = _selString.clamp(0, _doc.stringCount - 1);
        _clearHistory();
      });

  @override
  void toggleMute() =>
      setState(() => _tracks[_active].muted = !_tracks[_active].muted);
  @override
  void toggleSolo() =>
      setState(() => _tracks[_active].soloed = !_tracks[_active].soloed);
  @override
  bool isMuted(int track) => _tracks[track].muted;
  @override
  bool isSoloed(int track) => _tracks[track].soloed;

  /// The whole band as a [MultiPartScore] (one part per track), transposed by
  /// the capo so exports and hand-offs match what the editor plays.
  MultiPartScore _bandScore() =>
      MultiPartScore([for (final t in _tracks) t.doc.toScore(capo: _capo)]);

  @override
  MultiPartScore debugWorkshopScore() => _bandScore();

  /// Opens the current tab in the full Score Workshop (reuses its public
  /// `initialScore` param — no edit to that screen).
  /// E4 — pushes whichever screen [target] means, with the already-converted
  /// document. The bridge did the conversion (and warned about any loss); this
  /// only has to know the route.
  void _openConvertedElsewhere(AppMode target, ConversionResult result) {
    final document = result.document;
    if (document == null) return;
    switch (target) {
      case AppMode.tracker:
        if (document is! TrackerSong) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AdvancedTrackerScreen(initialSong: document),
          ),
        );
      case AppMode.score:
        if (document is! MultiPartScore) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CompositionWorkshopScreen(
              initialScore: document,
              initialNames: [_tracks[_active].name],
            ),
          ),
        );
      case AppMode.tab:
      case AppMode.loop:
      case AppMode.audio:
        // Not offered — see the `targets` list on the menu.
        break;
    }
  }

  void _openInScoreWorkshop() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CompositionWorkshopScreen(
          initialScore: _bandScore(),
          initialNames: [for (final t in _tracks) t.name],
        ),
      ),
    );
  }

  /// MusicXML for the whole band — multi-part when there is more than one
  /// track, else the single active track.
  String _bandMusicXml() => _tracks.length > 1
      ? multiPartToMusicXml(
          MultiPartScore([for (final t in _tracks) t.doc.toScore(capo: _capo)]),
        )
      : scoreToMusicXml(_score());

  @override
  void saveToSongBook(String title) {
    final name = title.trim().isEmpty ? 'Tab' : title.trim();
    final xml = _bandMusicXml();
    context.read<UserSongsService>().addSong(
          ImportedSong(
            id: 'tab_${name}_${_doc.columns.length}',
            title: name,
            musicXml: xml,
          ),
        );
    _snack(AppLocalizations.of(context)!.tabSaved(name));
  }

  // ── Actions ──────────────────────────────────────────────────────────────
  @override
  Future<void> openScoreFile({
    String? pickedName,
    Uint8List? pickedBytes,
  }) async {
    String name;
    Uint8List bytes;
    if (pickedBytes != null && pickedName != null) {
      name = pickedName;
      bytes = pickedBytes;
    } else {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Scores & tabs', extensions: tabImportExtensions),
        ],
      );
      if (file == null) return;
      name = file.name;
      bytes = await file.readAsBytes();
    }
    try {
      final score = parseTabFile(name, bytes);
      if (!mounted) return;
      setState(() {
        _tracks[_active].doc = TabDocument.fromScore(score, _doc.tuning);
        _sourceName = name;
        _selCol = 0;
        _selString = 0;
        _clearHistory();
      });
    } catch (_) {
      if (!mounted) return;
      _snack(AppLocalizations.of(context)!.tabImportFailed);
    }
  }

  bool _transcribing = false;
  @override
  bool get isTranscribingAudio => _transcribing;

  @override
  Future<void> openAudioRecording({
    String? pickedName,
    Uint8List? pickedBytes,
  }) async {
    if (_transcribing) return;
    // Capture context-bound objects before any await (picker / model I/O).
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    // The Settings backend choice for the audio→tab step (auto by default;
    // absent-provider in tests → auto).
    Backend prefer;
    try {
      prefer = context
          .read<TranscriptionConfigService>()
          .config
          .backendFor(TranscriptionStep.tab);
    } on ProviderNotFoundException {
      prefer = Backend.auto;
    }
    Uint8List bytes;
    String name;
    if (pickedBytes != null && pickedName != null) {
      bytes = pickedBytes;
      name = pickedName;
    } else {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Audio (WAV)', extensions: ['wav']),
        ],
      );
      if (file == null) return;
      bytes = await file.readAsBytes();
      name = file.name;
    }
    setState(() => _transcribing = true);
    TabDocument? doc;
    try {
      final wav = readWavPcm16(bytes);
      final mono = wavToMonoFloat(wav);
      final tuning = _doc.tuning;
      doc = await (widget.debugAudioToTab ??
          (m, sr, t) => audioToTabDocument(m, sr, tuning: t, prefer: prefer))(
        mono,
        wav.sampleRate,
        tuning,
      );
    } catch (_) {
      doc = null;
    }
    if (!mounted) return;
    setState(() {
      _transcribing = false;
      if (doc != null) {
        _tracks[_active].doc = doc;
        _sourceName = name;
        _selCol = 0;
        _selString = 0;
        _clearHistory();
      }
    });
    messenger.showSnackBar(
      SnackBar(
        content:
            Text(doc != null ? l10n.tabRecordingLoaded : l10n.tabNoAudioModel),
      ),
    );
  }

  @override
  void openSongMusicXml(String title, String musicXml) {
    try {
      final score = scoreFromMusicXml(musicXml);
      setState(() {
        _tracks[_active].doc = TabDocument.fromScore(score, _doc.tuning);
        _sourceName = title;
        _selCol = 0;
        _selString = 0;
        _clearHistory();
      });
    } catch (_) {
      if (mounted) _snack(AppLocalizations.of(context)!.tabImportFailed);
    }
  }

  @override
  void pasteAsciiTab(String text) {
    if (text.trim().isEmpty) return;
    try {
      final score = asciiTabToScore(text, tuning: _doc.tuning);
      setState(() {
        _tracks[_active].doc = TabDocument.fromScore(score, _doc.tuning);
        _selCol = 0;
        _selString = 0;
        _clearHistory();
      });
    } catch (_) {
      if (mounted) _snack(AppLocalizations.of(context)!.tabImportFailed);
    }
  }

  /// Dialog to paste ASCII tab (`e|--0--3--|` …) into the active track.
  Future<void> _promptPasteAscii() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tabPasteAscii),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 8,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: InputDecoration(
            hintText: l10n.tabPasteAsciiHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
    if (text != null) pasteAsciiTab(text);
  }

  /// Bottom-sheet list of Song-Book songs; pick one to load as editable tab.
  Future<void> _openFromSongBook() async {
    final l10n = AppLocalizations.of(context)!;
    final songs = context.read<UserSongsService>().songs;
    if (songs.isEmpty) {
      _snack(l10n.tabSongBookEmpty);
      return;
    }
    final picked = await showModalBottomSheet<ImportedSong>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.tabOpenSongBook,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final s in songs)
              ListTile(
                leading: const Icon(Icons.music_note),
                title: Text(s.title),
                subtitle: s.attribution == null ? null : Text(s.attribution!),
                onTap: () => Navigator.of(ctx).pop(s),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    openSongMusicXml(picked.title, picked.musicXml);
  }

  void _clearAll() => setState(() {
        _tracks[_active].doc = TabDocument.blank(_doc.tuning);
        _sourceName = null;
        _selCol = 0;
        _selString = 0;
      });

  void _play() {
    if (_playing || _countingIn) {
      _stopPlayback();
      return;
    }
    // Practice state resets at the START of a run (not on each loop): the speed
    // trainer's ramp begins at its first step; a plain run plays at [_bpm].
    _loopIndex = 0;
    _playBpm = _bpm;
    if (_speedTrainer) {
      _trainerTempos = speedTrainerTempos(baseBpm: _bpm);
      if (_trainerTempos.isNotEmpty) _playBpm = _trainerTempos.first;
    }
    if (_countIn) {
      unawaited(_runCountIn());
    } else {
      _startPlayback();
    }
  }

  /// A one-bar (4-beat) metronome count-in, then playback — so a learner can
  /// catch the pulse before playing along. Sequential with the audio (they
  /// share one player), and cancellable via [_stopPlayback].
  Future<void> _runCountIn() async {
    final token = ++_playToken;
    setState(() => _countingIn = true);
    final beatMs = (60000 / _playBpm).round();
    final audio = context.read<AudioService>();
    for (var i = 0; i < 4; i++) {
      if (!mounted || token != _playToken) return;
      unawaited(audio.playTick(accent: i == 0));
      await Future<void>.delayed(Duration(milliseconds: beatMs));
    }
    if (!mounted || token != _playToken) return;
    setState(() => _countingIn = false);
    _startPlayback();
  }

  void _startPlayback() {
    _scheduleCursor = 0; // a new pass starts at the beginning of the schedule
    // Audio: every track sounding together. Highlight: the ACTIVE track's own
    // column timeline (that's what the preview shows). [_playBpm] is the authored
    // [_bpm] normally, or the speed trainer's current ramp step.
    // "Loop bar" restricts playback to the cursor's bar (re-read each pass, so
    // moving the cursor moves the loop); otherwise the whole piece plays.
    final (from, to) =
        _loopBar ? _doc.barBoundsAt(_selCol) : (0, _doc.columns.length);
    final events =
        _doc.toPlaybackEvents(bpm: _playBpm, capo: _capo, from: from, to: to);
    // Mix each audible track as its own stem, scaled by its mixer volume (D2),
    // so per-track balance is audible instead of a flat merge.
    final audible = audibleTracks(_tracks).toList();
    context.read<AudioService>().playMixedTimedChords(
      [
        for (final t in audible)
          t.doc.toPlaybackEvents(
            bpm: _playBpm,
            capo: _capo,
            from: from,
            to: to,
          ),
      ],
      gains: [for (final t in audible) t.volume],
      pans: [for (final t in audible) t.pan],
      clickBeatMs: _metronome ? (60000 / _playBpm).round() : null,
    );
    final schedule = <({int col, int start, int end, bool note})>[];
    var t = 0;
    for (var c = 0; c < events.length; c++) {
      final (midis, ms) = events[c];
      // The schedule keeps ABSOLUTE column ids so the right column lights up
      // even when only a slice is playing.
      schedule
          .add((col: from + c, start: t, end: t + ms, note: midis.isNotEmpty));
      t += ms;
    }
    if (_ticker.isActive) _ticker.stop();
    setState(() {
      _schedule = schedule;
      _totalMs = t;
      _playing = true;
      _highlighted.value = const {};
    });
    _ticker.start();
  }

  void _stopPlayback() {
    _playToken++; // cancels any in-flight count-in
    if (_ticker.isActive) _ticker.stop();
    setState(() {
      _playing = false;
      _countingIn = false;
      _highlighted.value = const {};
    });
  }

  void _onTick(Duration elapsed) {
    final ms = elapsed.inMilliseconds;
    if (ms >= _totalMs) {
      if ((_loop || _loopBar) && _playing) {
        // Speed trainer: step the tempo up one rung per loop, holding at target.
        if (_speedTrainer && _trainerTempos.isNotEmpty) {
          _loopIndex++;
          final i = _loopIndex.clamp(0, _trainerTempos.length - 1);
          _playBpm = _trainerTempos[i];
        }
        _startPlayback(); // restarts the audio + ticker for the next pass
        return;
      }
      _stopPlayback();
      return;
    }
    // Walk forward from where the last tick stopped rather than scanning the
    // whole schedule: entries are in time order and `ms` only grows within a
    // pass, so anything before the cursor can no longer be sounding.
    while (_scheduleCursor < _schedule.length &&
        _schedule[_scheduleCursor].end <= ms) {
      _scheduleCursor++;
    }
    Set<String> ids = const {};
    for (var i = _scheduleCursor; i < _schedule.length; i++) {
      final e = _schedule[i];
      if (e.start > ms) break; // not started yet — nor is anything after it
      if (e.note && ms < e.end) {
        ids = {'t${e.col}'};
        break;
      }
    }
    if (!setEquals(ids, _highlighted.value)) {
      // No `setState`: only the three views read this, and they repaint without
      // relayout.
      _highlighted.value = ids;
    }
  }

  // ── Export ───────────────────────────────────────────────────────────────
  Future<void> _export(String format) async {
    final score = _score();
    final base = (_sourceName ?? 'tab').replaceAll(RegExp(r'\.[^.]*$'), '');
    switch (format) {
      case 'gp':
        // A band exports one GP Track per tab track (each with its own
        // tuning); techniques ride along as GPIF note properties.
        final gpif = _tracks.length > 1
            ? multiPartToGpif(
                MultiPartScore(
                  [for (final t in _tracks) t.doc.toScore(capo: _capo)],
                ),
                tunings: [for (final t in _tracks) t.doc.tuning],
                names: [for (final t in _tracks) t.name],
              )
            : scoreToGpif(score, tuning: _doc.tuning);
        await _saveBytes(
          writeGpFromGpif(gpif),
          '$base.gp',
          'GP tab',
          const ['gp'],
        );
      case 'musicxml':
        await _saveBytes(
          Uint8List.fromList(utf8.encode(_bandMusicXml())),
          '$base.musicxml',
          'MusicXML',
          const ['musicxml'],
        );
      case 'midi':
        // D1 — carry the active track's GM instrument into the exported MIDI so
        // it plays with that voice, not the default piano.
        await _saveBytes(
          scoreToMidi(
            _doc.toScore(capo: _capo, program: _tracks[_active].instrument),
          ),
          '$base.mid',
          'MIDI',
          const ['mid'],
        );
      case 'pdf':
        // E2 — print-ready PDF of the (standard-notation) tab score, reusing
        // the Score Workshop's paginated renderer.
        final pdf = await exportScoreToPdf(score, title: base);
        if (!mounted) return;
        await _saveBytes(pdf, '$base.pdf', 'PDF', const ['pdf']);
      case 'daw':
        sendToDaw();
    }
  }

  @override
  void sendToDaw() {
    final mp = _bandScore();
    // In-place round-trip: update the source Audio Editor clip and go back.
    if (widget.onReturnToDaw != null) {
      widget.onReturnToDaw!(mp);
      Navigator.of(context).pop();
    } else {
      sendToMultitrack(context, ScoreSource(mp));
    }
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
        SnackBar(content: Text(l10n.tabSavedTo(location.path))),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.tabExportFailed)));
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  String _tuningLabel(Tuning t) => t.name ?? '${t.stringCount}-string';

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      selectCell(_selCol - 1, _selString);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      selectCell(_selCol + 1, _selString);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      selectCell(_selCol, _selString - 1);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      selectCell(_selCol, _selString + 1);
    } else if (k == LogicalKeyboardKey.backspace ||
        k == LogicalKeyboardKey.delete) {
      deleteCell();
    } else {
      final digit = int.tryParse(event.character ?? '');
      if (digit != null) {
        enterFret(digit);
      } else {
        return KeyEventResult.ignored;
      }
    }
    return KeyEventResult.handled;
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    _buildCount++;
    // Cleared per build rather than invalidated per edit: the document is
    // mutable in place, so "this build's answers" is the only claim that is
    // certainly true.
    _fingerCache.clear();
    final score = _score();
    // Tab and notation are independent, stacked panes (notation on top).
    // Each pane rebuilds when the PLAYHEAD moves, and only that pane — the rest
    // of the screen (and `toScore` above) is untouched.
    final panes = <Widget>[
      if (_notation == _Notation.standard)
        ValueListenableBuilder<Set<String>>(
          valueListenable: _highlighted,
          builder: (context, ids, _) =>
              StaffView(score: score, highlightedIds: ids),
        ),
      if (_notation == _Notation.grand)
        ValueListenableBuilder<Set<String>>(
          valueListenable: _highlighted,
          // The grand-staff split is derived per build, so it is computed here
          // rather than inside the builder: the playhead does not change it.
          builder: (grandContext, ids, child) => GrandStaffView(
            grandStaff: grandStaffFromScore(score),
            highlightedIds: ids,
          ),
        ),
      if (_showTab)
        ValueListenableBuilder<Set<String>>(
          valueListenable: _highlighted,
          builder: (context, ids, _) => TabStaffView(
            score: score,
            tuning: _doc.tuning,
            capo: _capo,
            showTuning: true,
            highlightedIds: ids,
          ),
        ),
    ];
    final Widget view = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < panes.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          panes[i],
        ],
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_sourceName ?? l10n.tabWorkshopTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: l10n.tabUndo,
            onPressed: canUndo ? undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: l10n.tabRedo,
            onPressed: canRedo ? redo : null,
          ),
          IconButton(
            icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
            tooltip: l10n.tabPlay,
            onPressed: _play,
          ),
          // Settings belong in the top bar (they're settings, not editing tools).
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: l10n.settingsTitle,
            onPressed: () => _showTabSettings(l10n),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share),
            tooltip: l10n.tabExport,
            onSelected: _export,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'gp', child: Text(l10n.tabExportGp)),
              PopupMenuItem(
                value: 'musicxml',
                child: Text(l10n.tabExportMusicXml),
              ),
              PopupMenuItem(value: 'midi', child: Text(l10n.tabExportMidi)),
              PopupMenuItem(value: 'pdf', child: Text(l10n.tabExportPdf)),
              PopupMenuItem(value: 'daw', child: Text(l10n.dawSend)),
            ],
          ),
          // Everything else — the many one-off / less-frequent actions.
          // E4 — the shared "Open in…" action. Restricted to the two modes this
          // screen can actually PUSH: converting to a destination it cannot
          // open would convert the user's work and then drop it.
          OpenInMenu(
            from: AppMode.tab,
            // WS-X1 — when this screen holds a live project track, every other
            // target is honestly a copy, and the menu now says so.
            liveKind: hasLiveProjectLink ? AppMode.tab : null,
            targets: const [AppMode.tracker, AppMode.score],
            tuning: _doc.tuning,
            capo: _capo,
            documentBuilder: () => _doc,
            onConverted: _openConvertedElsewhere,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: l10n.tabMenu,
            onSelected: (v) {
              switch (v) {
                case 'playInstrument':
                  _playWithInstrument();
                case 'countIn':
                  setState(() => _countIn = !_countIn);
                case 'articulate':
                  setState(() => _articulate = !_articulate);
                case 'loop':
                  setState(() => _loop = !_loop);
                case 'loopBar':
                  setState(() => _loopBar = !_loopBar);
                case 'metronome':
                  setState(() => _metronome = !_metronome);
                case 'speedTrainer':
                  setState(() => _speedTrainer = !_speedTrainer);
                case 'mic':
                  _toggleMic();
                case 'import':
                  openScoreFile();
                case 'audio':
                  openAudioRecording();
                case 'songbook':
                  _openFromSongBook();
                case 'shareTune':
                  shareMelody();
                case 'loadTune':
                  loadSharedMelody();
                case 'fingerings':
                  addLeftFingerings();
                case 'inspect':
                  setState(() => _inspect = !_inspect);
                case 'paste':
                  _promptPasteAscii();
                case 'save':
                  _promptSave();
                case 'rig':
                  _showRigSheet();
                case 'mixer':
                  _showMixer();
                case 'workshop':
                  _openInScoreWorkshop();
                case 'clear':
                  _clearAll();
              }
            },
            itemBuilder: (_) => [
              _menuItem(
                'playInstrument',
                Icons.piano_outlined,
                l10n.workshopPlayWithInstrument,
              ),
              _menuItem('rig', Icons.graphic_eq, l10n.tabRig),
              _menuItem('mixer', Icons.tune, 'Mixer'),
              CheckedPopupMenuItem(
                value: 'countIn',
                checked: _countIn,
                child: Text(l10n.tabCountIn),
              ),
              CheckedPopupMenuItem(
                value: 'articulate',
                checked: _articulate,
                child: const Text('Articulate techniques'),
              ),
              CheckedPopupMenuItem(
                value: 'loop',
                checked: _loop,
                child: const Text('Loop'),
              ),
              CheckedPopupMenuItem(
                value: 'loopBar',
                checked: _loopBar,
                child: const Text('Loop bar'),
              ),
              CheckedPopupMenuItem(
                value: 'metronome',
                checked: _metronome,
                child: const Text('Metronome'),
              ),
              CheckedPopupMenuItem(
                value: 'speedTrainer',
                checked: _speedTrainer,
                child: const Text('Speed trainer'),
              ),
              CheckedPopupMenuItem(
                value: 'mic',
                checked: _listening,
                child: Text(l10n.tabMic),
              ),
              const PopupMenuDivider(),
              _menuItem('import', Icons.folder_open, l10n.tabImport),
              _menuItem('audio', Icons.graphic_eq, l10n.tabOpenRecording),
              _menuItem(
                'songbook',
                Icons.library_music_outlined,
                l10n.tabOpenSongBook,
              ),
              _menuItem(
                'save',
                Icons.bookmark_add_outlined,
                l10n.tabSaveSongBook,
              ),
              _menuItem('paste', Icons.content_paste, l10n.tabPasteAscii),
              const PopupMenuDivider(),
              _menuItem(
                'shareTune',
                Icons.upload,
                l10n.tuneShare,
                enabled: canShareMelody,
              ),
              _menuItem(
                'loadTune',
                Icons.download,
                l10n.tuneLoadShared,
                enabled: MelodyBridge.instance.hasMelody,
              ),
              _menuItem('workshop', Icons.edit_note, l10n.tabOpenWorkshop),
              const PopupMenuDivider(),
              _menuItem(
                'fingerings',
                Icons.back_hand_outlined,
                l10n.tabAddFingerings,
              ),
              CheckedPopupMenuItem(
                value: 'inspect',
                checked: _inspect,
                child: Text(l10n.inspectMode),
              ),
              _menuItem('clear', Icons.delete_sweep_outlined, l10n.tabClear),
            ],
          ),
        ],
      ),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          children: [
            _toolbar(l10n),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: view,
                      ),
                    ),
                    const Divider(height: 1),
                    _grid(),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _keypad(l10n),
          ],
        ),
      ),
    );
  }

  /// The single control bar: active track · note duration (inline on wide
  /// screens, a dropdown when cramped) · Tab & Notation view toggles · the Insert
  /// (pattern) and Chord tools. Everything that is a genuine *setting* (tuning,
  /// capo, tempo, transpose, techniques, track management) lives in the app-bar
  /// Settings sheet, not here.
  /// An icon+label overflow-menu row.
  /// E2 — the per-track guitar rig: a preset picker plus the shared FX rack
  /// over [TabTrack.fxChain]. Tab was the one mode with no effects at all.
  void _showRigSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final l10n = AppLocalizations.of(sheetContext)!;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                final track = _tracks[_active];
                // ⚠️ PERF: no screen `setState` here. `FxRack`'s sliders call
                // `onChanged` per drag FRAME, and this screen's `build` does a
                // full `toScore` + a whole non-lazy grid + a tab layout — so
                // dragging one knob used to rebuild the entire Workshop at
                // ~60 fps, behind a sheet that covers it. Nothing in `build`
                // reads `fxChain`: it is used when rendering audio, which
                // happens on a later, explicit action. The sheet still rebuilds,
                // because the rack is what has to redraw.
                void apply(List<FxSpec> chain) {
                  track.fxChain = chain;
                  setSheetState(() {});
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.tabRig,
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.tabRigHint,
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final preset in GuitarFxPreset.values)
                          ActionChip(
                            key: ValueKey('tab-rig-${preset.name}'),
                            label: Text(
                              preset == GuitarFxPreset.clean
                                  ? l10n.tabRigNone
                                  : tabRigLabel(preset),
                            ),
                            onPressed: () => apply(tabRigChain(preset)),
                          ),
                      ],
                    ),
                    const Divider(height: 24),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight:
                            MediaQuery.of(sheetContext).size.height * 0.45,
                      ),
                      child: SingleChildScrollView(
                        child: FxRack(
                          chain: track.fxChain,
                          dense: true,
                          onChanged: apply,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  PopupMenuItem<String> _menuItem(
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
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );

  Widget _toolbar(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 560;
    Widget sep() => Container(
          width: 1,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          color: scheme.outlineVariant,
        );

    Widget durChip(NoteDuration dur, int steps) {
      final sel = dur == _dur;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: InkWell(
          onTap: () => setState(() {
            _dur = dur;
            _doc.setDuration(_selCol, dur);
          }),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel ? scheme.primaryContainer : null,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: sel ? scheme.primary : scheme.outlineVariant,
              ),
            ),
            child: Text(_durLabel(steps), style: const TextStyle(fontSize: 15)),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          // Active track (name only — no decorative icon).
          DropdownButton<int>(
            value: _active,
            underline: const SizedBox.shrink(),
            items: [
              for (var i = 0; i < _tracks.length; i++)
                DropdownMenuItem(value: i, child: Text(_tracks[i].name)),
            ],
            onChanged: (i) {
              if (i != null) selectTrack(i);
            },
          ),
          sep(),
          // Note length — inline palette when there's room, else a dropdown.
          if (wide)
            for (final (dur, steps) in kTabDurations) durChip(dur, steps)
          else
            DropdownButton<NoteDuration>(
              value: kTabDurations.any((e) => e.$1 == _dur) ? _dur : null,
              underline: const SizedBox.shrink(),
              hint: Text(l10n.tabDuration),
              items: [
                for (final (dur, steps) in kTabDurations)
                  DropdownMenuItem(value: dur, child: Text(_durLabel(steps))),
              ],
              onChanged: (d) {
                if (d != null) {
                  setState(() {
                    _dur = d;
                    _doc.setDuration(_selCol, d);
                  });
                }
              },
            ),
          sep(),
          // Tab and Notation are independent — you can show both together.
          FilterChip(
            label: Text(l10n.tabTuning),
            avatar: const Icon(Icons.grid_on, size: 18),
            selected: _showTab,
            onSelected: (v) => setState(() => _showTab = v),
          ),
          const SizedBox(width: 6),
          SegmentedButton<_Notation>(
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(
                value: _Notation.off,
                icon: Icon(Icons.not_interested, size: 18),
                tooltip: 'No staff',
              ),
              ButtonSegment(
                value: _Notation.standard,
                icon: const Icon(Icons.music_note, size: 18),
                tooltip: l10n.tabShowStandard,
              ),
              const ButtonSegment(
                value: _Notation.grand,
                icon: Icon(Icons.piano, size: 18),
                tooltip: 'Grand staff',
              ),
            ],
            selected: {_notation},
            onSelectionChanged: (s) => setState(() => _notation = s.first),
          ),
          sep(),
          // The two most-used insert tools, directly reachable.
          OutlinedButton.icon(
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: Text(l10n.tabPattern),
            onPressed: _pickPattern,
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            icon: const Icon(Icons.grid_goldenratio, size: 18),
            label: Text(l10n.tabChord),
            onPressed: _pickChord,
          ),
        ],
      ),
    );
  }

  /// The mixer (D2): a volume slider + mute/solo per track. Volume scales that
  /// track's stem in playback ([AudioService.playMixedTimedChords] gains).
  void _showMixer() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final scheme = Theme.of(ctx).colorScheme;
          // ⚠️ PERF: same as the rig sheet — the volume and pan sliders fire
          // per drag frame, and neither value is read by this screen's `build`
          // (they are mix parameters, applied when audio is rendered). Only the
          // sheet needs to redraw.
          void bump(VoidCallback f) {
            f();
            setSheet(() {});
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mixer', style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  for (var i = 0; i < _tracks.length; i++) ...[
                    Row(
                      children: [
                        SizedBox(
                          width: 84,
                          child: Text(
                            _tracks[i].name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: _tracks[i].volume.clamp(0.0, 1.0),
                            onChanged: (v) => bump(() => _tracks[i].volume = v),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Mute',
                          icon: Icon(
                            _tracks[i].muted
                                ? Icons.volume_off
                                : Icons.volume_up,
                            color: _tracks[i].muted ? scheme.error : null,
                          ),
                          onPressed: () =>
                              bump(() => _tracks[i].muted = !_tracks[i].muted),
                        ),
                        IconButton(
                          tooltip: 'Solo',
                          icon: Icon(
                            Icons.headphones,
                            color: _tracks[i].soloed ? scheme.primary : null,
                          ),
                          onPressed: () => bump(
                            () => _tracks[i].soloed = !_tracks[i].soloed,
                          ),
                        ),
                      ],
                    ),
                    // Pan: L … centre … R (double-tap the label to re-centre).
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => bump(() => _tracks[i].pan = 0),
                          child: const SizedBox(
                            width: 84,
                            child: Text('Pan', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: _tracks[i].pan.clamp(-1.0, 1.0),
                            min: -1,
                            onChanged: (v) => bump(() => _tracks[i].pan = v),
                          ),
                        ),
                        const SizedBox(width: 96), // align with the icons above
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Settings sheet: tuning · capo · tempo · transpose · techniques · chord /
  /// pattern helpers · track management — everything that used to crowd the
  /// controls row and the editor panel.
  void _showTabSettings(AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void refresh() => setSheet(() {});
          final labelStyle = Theme.of(ctx).textTheme.labelMedium;
          Widget stepRow(
            String label,
            IconData icon,
            String value,
            VoidCallback? onMinus,
            VoidCallback? onPlus,
          ) =>
              Row(
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(label)),
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: onMinus == null
                        ? null
                        : () {
                            onMinus();
                            refresh();
                          },
                  ),
                  Text(value),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: onPlus == null
                        ? null
                        : () {
                            onPlus();
                            refresh();
                          },
                  ),
                ],
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
                    Row(
                      children: [
                        const Icon(Icons.tune, size: 18),
                        const SizedBox(width: 6),
                        Expanded(child: Text(l10n.tabTuning)),
                        DropdownButton<Tuning>(
                          value: _doc.tuning,
                          onChanged: (t) {
                            setState(() {
                              if (t != null) {
                                _doc.tuning = t;
                                _selString =
                                    _selString.clamp(0, t.stringCount - 1);
                              }
                            });
                            refresh();
                          },
                          items: [
                            for (final t in tabTuningPresets)
                              DropdownMenuItem(
                                value: t,
                                child: Text(_tuningLabel(t)),
                              ),
                          ],
                        ),
                      ],
                    ),
                    // Instrument (D1): the GM voice this track exports/plays as.
                    Row(
                      children: [
                        const Icon(Icons.piano, size: 18),
                        const SizedBox(width: 6),
                        const Expanded(child: Text('Instrument')),
                        DropdownButton<int?>(
                          value: _tracks[_active].instrument,
                          hint: const Text('Default'),
                          onChanged: (p) {
                            setState(() => _tracks[_active].instrument = p);
                            refresh();
                          },
                          items: [
                            const DropdownMenuItem(child: Text('Default')),
                            for (final (program, name) in kTabInstruments)
                              DropdownMenuItem(
                                value: program,
                                child: Text(name),
                              ),
                          ],
                        ),
                      ],
                    ),
                    // Meter (time signature): columns tile into bars by it.
                    Builder(
                      builder: (_) {
                        final cur = '${_doc.timeSignature.beats}'
                            '/${_doc.timeSignature.beatUnit}';
                        final meters = <String>{
                          '4/4', '3/4', '2/4', '6/8', '5/4',
                          '7/8', '12/8', '2/2', '3/8', '9/8', cur, //
                        }.toList()
                          ..sort();
                        return Row(
                          children: [
                            const Icon(Icons.straighten, size: 18),
                            const SizedBox(width: 6),
                            const Expanded(child: Text('Meter')),
                            DropdownButton<String>(
                              value: cur,
                              items: [
                                for (final m in meters)
                                  DropdownMenuItem(value: m, child: Text(m)),
                              ],
                              onChanged: (m) {
                                if (m == null) return;
                                final p = m.split('/');
                                setState(
                                  () => _doc.timeSignature = TimeSignature(
                                    int.parse(p[0]),
                                    int.parse(p[1]),
                                  ),
                                );
                                refresh();
                              },
                            ),
                          ],
                        );
                      },
                    ),
                    // Key signature (circle of fifths, −7..+7).
                    Row(
                      children: [
                        const Icon(Icons.vpn_key_outlined, size: 18),
                        const SizedBox(width: 6),
                        const Expanded(child: Text('Key')),
                        DropdownButton<int>(
                          value: _doc.keySignature.fifths.clamp(-7, 7),
                          items: [
                            for (var f = -7; f <= 7; f++)
                              DropdownMenuItem(
                                value: f,
                                child: Text(_keyLabel(f)),
                              ),
                          ],
                          onChanged: (f) {
                            if (f == null) return;
                            setState(() => _doc.keySignature = KeySignature(f));
                            refresh();
                          },
                        ),
                      ],
                    ),
                    stepRow(
                      l10n.tabCapo,
                      Icons.linear_scale,
                      '$_capo',
                      _capo > 0 ? () => setState(() => _capo--) : null,
                      _capo < 12 ? () => setState(() => _capo++) : null,
                    ),
                    stepRow(
                      l10n.tabTempo,
                      Icons.speed,
                      '$_bpm',
                      _bpm > 40 ? () => setState(() => _bpm -= 10) : null,
                      _bpm < 240 ? () => setState(() => _bpm += 10) : null,
                    ),
                    Row(
                      children: [
                        const Icon(Icons.swap_vert, size: 18),
                        const SizedBox(width: 6),
                        Expanded(child: Text(l10n.tabTranspose)),
                        IconButton(
                          icon: const Icon(Icons.arrow_downward),
                          onPressed: () {
                            transposeBy(-1);
                            refresh();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: () {
                            transposeBy(1);
                            refresh();
                          },
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Text(l10n.tabTechnique, style: labelStyle),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final t in TabTechnique.values)
                          FilterChip(
                            label: Text(_techLabel(l10n, t)),
                            selected: _selCol < _doc.columns.length &&
                                _doc.columns[_selCol].techniques.contains(t),
                            onSelected: (_) {
                              toggleTechnique(t);
                              refresh();
                            },
                          ),
                        // Tie: this note sustains into the next column.
                        FilterChip(
                          avatar: const Icon(Icons.link, size: 18),
                          label: const Text('Tie'),
                          selected: _selCol < _doc.columns.length &&
                              _doc.columns[_selCol].tieToNext,
                          onSelected: (v) {
                            setState(() => _doc.setTie(_selCol, v));
                            refresh();
                          },
                        ),
                        // Triplet: mark this note as a 3:2 tuplet member.
                        FilterChip(
                          avatar: const Icon(Icons.more_horiz, size: 18),
                          label: const Text('Triplet'),
                          selected: _selCol < _doc.columns.length &&
                              _doc.columns[_selCol].tuplet == (3, 2),
                          onSelected: (v) {
                            setState(
                              () => _doc.setTuplet(_selCol, v ? (3, 2) : null),
                            );
                            refresh();
                          },
                        ),
                        // Repeat barlines on the CURRENT bar.
                        FilterChip(
                          avatar: const Icon(Icons.repeat, size: 18),
                          label: const Text('Repeat ‖:'),
                          selected: _selCol < _doc.columns.length &&
                              _doc.columns[_doc.barBoundsAt(_selCol).$1]
                                  .startRepeat,
                          onSelected: (v) {
                            setState(
                              () => _doc.setBarRepeat(_selCol, start: v),
                            );
                            refresh();
                          },
                        ),
                        FilterChip(
                          avatar: const Icon(Icons.repeat, size: 18),
                          label: const Text(':‖'),
                          selected: _selCol < _doc.columns.length &&
                              _doc.columns[_doc.barBoundsAt(_selCol).$1]
                                  .endRepeat,
                          onSelected: (v) {
                            setState(() => _doc.setBarRepeat(_selCol, end: v));
                            refresh();
                          },
                        ),
                        // Alternate ending (volta) number for the current bar.
                        Builder(
                          builder: (_) {
                            final cur = _selCol < _doc.columns.length
                                ? _doc
                                    .columns[_doc.barBoundsAt(_selCol).$1].volta
                                : null;
                            return InputChip(
                              avatar: const Icon(Icons.call_split, size: 18),
                              label: Text(
                                cur == null ? 'Ending' : 'Ending $cur',
                              ),
                              selected: cur != null,
                              onPressed: () {
                                // Cycle none → 1 → 2 → 3 → none.
                                final next = cur == null
                                    ? 1
                                    : (cur >= 3 ? null : cur + 1);
                                setState(() => _doc.setBarVolta(_selCol, next));
                                refresh();
                              },
                            );
                          },
                        ),
                      ],
                    ),
                    // (Chord + Insert-pattern live directly in the toolbar now.)
                    const Divider(height: 20),
                    Text(l10n.tabTracks, style: labelStyle),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < _tracks.length; i++)
                          InputChip(
                            label: Text(
                              _tracks[i].name,
                              style: _tracks[i].muted
                                  ? const TextStyle(
                                      decoration: TextDecoration.lineThrough,
                                    )
                                  : null,
                            ),
                            selected: i == _active,
                            onPressed: () {
                              selectTrack(i);
                              refresh();
                            },
                            onDeleted: _tracks.length > 1 && i == _active
                                ? () {
                                    removeTrack();
                                    refresh();
                                  }
                                : null,
                          ),
                        ActionChip(
                          avatar: const Icon(
                            Icons.library_add_outlined,
                            size: 16,
                          ),
                          label: Text(l10n.tabAddTrack),
                          onPressed: () {
                            addTrack();
                            refresh();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          avatar: const Icon(Icons.volume_off, size: 16),
                          label: const Text('M'),
                          selected: _tracks[_active].muted,
                          onSelected: (_) {
                            toggleMute();
                            refresh();
                          },
                        ),
                        FilterChip(
                          avatar: const Icon(Icons.hearing, size: 16),
                          label: const Text('S'),
                          selected: _tracks[_active].soloed,
                          onSelected: (_) {
                            toggleSolo();
                            refresh();
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

  Future<void> _promptSave() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: _sourceName ?? 'My Tab');
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tabSaveSongBook),
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
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
    if (title == null || !mounted) return;
    saveToSongBook(title);
  }

  /// The editable string×step grid.
  ///
  /// ⚠️ **PERF: laid out COLUMN-major and built LAZILY, and both halves of that
  /// matter.**
  ///
  /// It used to be row-major — one `Row` per string, every cell of every column
  /// inside it — in a plain `SingleChildScrollView`. Nothing was lazy, so a
  /// 512-column six-string import materialised ~3000 cells (≈15–20k widgets)
  /// on **every** rebuild, including a single arrow-key press.
  ///
  /// Row-major cannot be made lazy without linked scrolling: six independent
  /// horizontal lists would need one shared offset, and a shared
  /// `ScrollController` across several scrollables is exactly what Flutter
  /// refuses. Turned on its side there is **one** scrollable — a horizontal
  /// `ListView` whose items are COLUMNS — so alignment is by construction and
  /// only the visible columns exist. The fixed `itemExtent` keeps scrolling O(1)
  /// (the list never measures the items it has not built).
  ///
  /// The cost of the shape: the heights are now explicit ([_kBarreRowHeight] and
  /// friends) because the gutter and the columns have to agree without a `Row`
  /// to align them.
  Widget _grid() {
    final n = _doc.stringCount;
    final scheme = Theme.of(context).colorScheme;
    // One scan for the whole grid rather than one per column.
    final anyBarre = _doc.columns.any((c) => c.barreFret != null);
    final height =
        (anyBarre ? _kBarreRowHeight : 0) + _kChordRowHeight + n * _kCellHeight;

    final grid = Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The fixed gutter: string letters, aligned with the cell rows.
            SizedBox(
              width: 40,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (anyBarre) const SizedBox(height: _kBarreRowHeight),
                  const SizedBox(height: _kChordRowHeight),
                  for (int s = 0; s < n; s++)
                    SizedBox(
                      height: _kCellHeight,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _doc.tuning.strings[s].toString().toUpperCase(),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemExtent: _kColumnWidth,
                itemCount: _doc.columns.length,
                itemBuilder: (context, c) =>
                    _columnWidget(c, n, scheme, anyBarre: anyBarre),
              ),
            ),
          ],
        ),
      ),
    );
    // WS-X2 — the fourth and last drop target. A dragged document lands in the
    // pattern on screen; see [_dropHere] for why it lands rather than replaces.
    final droppable = DragTarget<MusicDragPayload>(
      onWillAcceptWithDetails: (d) => _dropDecision(d.data).canDrop,
      onAcceptWithDetails: (d) => unawaited(_dropHere(d.data)),
      builder: (context, candidate, rejected) => Stack(
        children: [
          grid,
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
    );

    // 🔍 On desktop, the corner card shows the hovered cell's note + column
    // chord; leaving the grid clears it. No-op on touch.
    return MouseRegion(
      onExit: _inspect
          ? (_) {
              if (_hoverInfo != null) setState(() => _hoverInfo = null);
            }
          : null,
      child: Stack(
        children: [
          droppable,
          if (_inspect && _hoverInfo != null)
            Positioned(top: 8, right: 8, child: _hoverInspectCard()),
        ],
      ),
    );
  }

  /// The left-hand finger printed for [string] in [col], or null.
  ///
  /// `leftFingers` is stored in PITCH order (low → high) to match
  /// `NoteElement.fingerings`, while the grid is indexed by string, where 0 is
  /// the highest-sounding string. So the mapping is by descending string index —
  /// not by position in the map, which would silently mis-attribute every digit
  /// in a chord.
  int? _fingerAt(int col, int string) {
    final column = _doc.columns[col];
    final fingers = column.leftFingers;
    if (fingers == null || !column.frets.containsKey(string)) return null;
    // ⚠️ PERF: this is called once per CELL, and it used to allocate a list,
    // sort it and linear-search it every time — so a 6-string grid did six
    // sorts per column, per build, for a value that is the same for the whole
    // column. Now the column's string→finger map is built once and reused;
    // `_fingerCache` is cleared at the top of `build`, so it can never outlive
    // an edit.
    final byString = _fingerCache[col] ??= () {
      final strings = column.frets.keys.toList()
        ..sort((a, b) => b.compareTo(a));
      return <int, int>{
        for (var i = 0; i < strings.length && i < fingers.length; i++)
          strings[i]: fingers[i],
      };
    }();
    return byString[string];
  }

  /// The engraved score, derived once per CHANGE rather than once per build.
  ///
  /// ⚠️ PERF, and the single biggest win in this screen: `toScore` walks every
  /// column and allocates a `NoteElement` plus ~22 span lists, and it used to run
  /// on every build — including the many builds that change nothing about the
  /// music (a selection move, a toolbar toggle, a window resize, a keyboard
  /// animation frame). Worse, the result was a NEW `Score` each time, so
  /// `StaffView`'s `==` gate had to deep-compare the whole document to discover
  /// nothing had changed, and `TabStaffView` re-engraved unconditionally.
  ///
  /// Keyed on `TabDocument.revision` + the capo (which is screen state, not
  /// document state, and changes what the score sounds). The document bumps its
  /// revision on every mutation, and `tab_document_revision_test.dart` walks
  /// every mutator to keep that true — because the failure mode here is not a
  /// slow screen but a screen showing music that is no longer there.
  /// ⚠️ Keyed on the DOCUMENT too, not just its revision. `_doc` is
  /// `_tracks[_active].doc`, so switching tracks swaps the document underneath —
  /// and two documents can easily be sitting on the same revision number, which
  /// would serve one track's music while the other is selected. Identity is what
  /// makes the key unique; the revision is what makes it fresh.
  Score _score() {
    final doc = _doc;
    final revision = doc.revision;
    if (_cachedScore case final cached?
        when identical(_cachedDoc, doc) &&
            _cachedFor == revision &&
            _cachedCapo == _capo) {
      return cached;
    }
    final score = doc.toScore(capo: _capo);
    _scoreBuilds++;
    _cachedScore = score;
    _cachedDoc = doc;
    _cachedFor = revision;
    _cachedCapo = _capo;
    return score;
  }

  int _scoreBuilds = 0;
  Score? _cachedScore;
  TabDocument? _cachedDoc;
  int? _cachedFor;
  int? _cachedCapo;

  /// Grid geometry, explicit because the gutter and the lazily-built columns
  /// have to agree without a `Row` to align them (see [_grid]).
  static const double _kCellHeight = 32; // 30 + 1px margin top and bottom
  static const double _kColumnWidth = 34; // 32 + 1px margin each side
  static const double _kChordRowHeight = 22;
  static const double _kBarreRowHeight = 16;

  /// Rebuild count, for the perf guard (see `TabWorkshopTester.debugBuildCount`).
  int _buildCount = 0;

  /// Per-column string→finger maps, valid for ONE build (see [_fingerAt]).
  final _fingerCache = <int, Map<int, int>>{};

  /// WS-X2 — what dropping [payload] on the tab grid would do.
  ///
  /// No `acceptsDirectly`: this surface is a MODE, not a container — it has no
  /// cell type that holds a foreign document as-is.
  DropDecision _dropDecision(MusicDragPayload payload) =>
      dropDecisionFor(payload, AppMode.tab);

  /// Land a dragged document in the tab on screen.
  ///
  /// ⚠️ **It lands in the CURRENT document rather than replacing it** — the same
  /// call as the Tracker's, and for the same reason: this screen's adopt path
  /// (`_tracks[_active].doc = …`) calls `_clearHistory()`, so a replacing drop
  /// would be **unrecoverable**. Landing the columns through `replaceColumns`
  /// makes it one undoable edit. What that costs is stated in the dialog rather
  /// than hidden.
  ///
  /// Everything converting INTO tab yields a `TabDocument` (score/tracker/loop →
  /// tab) and same-kind carries one too, so there is exactly one document shape
  /// here — no switch-on-type, unlike Loop Studio's target.
  Future<bool> _dropHere(MusicDragPayload payload) async {
    final plan = _dropPlan(payload);
    if (plan == null) return false;
    if (plan.decision.needsConfirmation || plan.warnings.isNotEmpty) {
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
    _commitDrop(plan.columns);
    return true;
  }

  /// What a drop would do and what it would cost, before anything is committed.
  ///
  /// Split from the commit so the WARNINGS can be asserted without pumping a
  /// dialog: what a particular drop loses is this surface's own arithmetic, and
  /// that is where a mistake would hide.
  ({DropDecision decision, List<TabColumn> columns, List<String> warnings})?
      _dropPlan(MusicDragPayload payload) {
    final decision = _dropDecision(payload);
    final document = decision.document;
    if (!decision.canDrop || document is! TabDocument) return null;

    // ⚠️ Losses the bridge's report CANNOT know about, because they are about
    // the instrument this tab is FOR, not about the conversion:
    //   * frets land on OUR strings. A six-string part dropped on a bass keeps
    //     its frets (nothing is deleted) but the top two strings cannot sound
    //     here — "you will not hear this" rather than "this is gone", because
    //     the two have different remedies;
    //   * a fret number only means a pitch together with a tuning, so a document
    //     tuned differently sounds different here even when every string exists;
    //   * a second voice and the dropped meter stay behind, because only the
    //     columns land.
    final silent = fretsOutsideTuning(document.columns, _doc.stringCount);
    return (
      decision: decision,
      columns: document.columns,
      warnings: <String>[
        if (decision.report case final report?) ...[
          for (final lost in report.lost) '• $lost',
          for (final near in report.approximated) '~ $near',
        ],
        if (silent > 0)
          '• $silent frets sit on strings this instrument does not have — '
              'they are kept, but you will not hear them',
        if (document.tuning != _doc.tuning)
          '~ the frets will sound against YOUR tuning, not the one they '
              'were written for',
        if (document.voice2.isNotEmpty)
          '• the second voice stays behind — only the columns land',
        if (document.timeSignature != _doc.timeSignature)
          '~ your time signature is kept (${_doc.timeSignature.beats}/'
              '${_doc.timeSignature.beatUnit})',
      ],
    );
  }

  /// Write dropped columns in, as ONE undoable edit.
  void _commitDrop(List<TabColumn> columns) {
    _snapshot();
    setState(() {
      _doc.replaceColumns([for (final c in columns) c.copy()]);
      _selCol = 0;
      _selString = 0;
    });
  }

  /// One grid column: its barre numeral, its chord name, then a cell per string.
  ///
  /// Built on demand by the grid's `ListView`, so a long piece costs only the
  /// columns you can see.
  Widget _columnWidget(
    int c,
    int strings,
    ColorScheme scheme, {
    required bool anyBarre,
  }) {
    final column = _doc.columns[c];
    return Column(
      children: [
        if (anyBarre)
          SizedBox(
            height: _kBarreRowHeight,
            child: Text(
              // The SAME printed form the engraver uses — TabBarre owns it, so
              // the grid and the staff can never disagree.
              column.barreFret == null
                  ? ''
                  : 'C${TabBarre('', column.barreFret!).roman}',
              key: ValueKey<String>('tab-barre-$c'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.tertiary,
              ),
            ),
          ),
        SizedBox(
          height: _kChordRowHeight,
          child: Text(
            column.chord?.name ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: scheme.primary,
            ),
          ),
        ),
        for (int s = 0; s < strings; s++) _cell(c, s),
      ],
    );
  }

  Widget _cell(int col, int string) {
    final fret = _doc.columns[col].frets[string];
    final selected = col == _selCol && string == _selString;
    final scheme = Theme.of(context).colorScheme;
    // The finger digit, small and in the corner: the FRET is what the grid is
    // for, and a fingering must not compete with it for the eye. An open string
    // (finger 0) is left blank — a "0" beside a "0" fret says nothing a player
    // does not already know, and reads as a second fret number.
    final finger = _fingerAt(col, string);
    return MouseRegion(
      onEnter: _inspect ? (_) => _onCellHover(col, string) : null, // 🔍 desktop
      child: GestureDetector(
        // Keyed so a test can count what actually got BUILT — the only way to
        // prove the grid is lazy, since a lazy grid and an eager one look
        // identical on screen.
        key: ValueKey<String>('tab-cell-$col-$string'),
        onTap: () => _onCellTap(col, string),
        child: Container(
          width: 32,
          height: 30,
          margin: const EdgeInsets.all(1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                fret?.toString() ?? '·',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color:
                      fret == null ? scheme.onSurfaceVariant : scheme.onSurface,
                ),
              ),
              if (finger != null && finger > 0)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Text(
                    '$finger',
                    key: ValueKey<String>('tab-finger-$col-$string'),
                    style: TextStyle(
                      fontSize: 9,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 🔍 Desktop hover over a cell (Inspect on): show its card in the corner.
  void _onCellHover(int col, int string) {
    if (!_inspect) return;
    final info = _inspectInfoFor(col, string);
    if (info != _hoverInfo) setState(() => _hoverInfo = info);
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

  /// Duration palette + fret keypad + column add/remove.
  /// The fret keypad — the primary note-entry surface — plus column add /
  /// remove / duplicate. Duration moved to the toolbar; techniques, transpose
  /// and chord/pattern helpers moved to the settings sheet.
  Widget _keypad(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (int f = 0; f <= 12; f++)
            SizedBox(
              width: 40,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(40, 36),
                ),
                onPressed: () => enterFret(f),
                child: Text('$f'),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.backspace_outlined),
            tooltip: l10n.tabClearCell,
            onPressed: deleteCell,
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            icon: const Icon(Icons.playlist_add),
            tooltip: l10n.tabAddColumn,
            onPressed: addColumn,
          ),
          IconButton.filledTonal(
            icon: const Icon(Icons.playlist_remove),
            tooltip: l10n.tabRemoveColumn,
            onPressed: removeColumnAtCursor,
          ),
          IconButton.filledTonal(
            icon: const Icon(Icons.control_point_duplicate),
            tooltip: l10n.tabDuplicateBar,
            onPressed: duplicateBar,
          ),
        ],
      ),
    );
  }

  /// A bottom-sheet grid of guitar chord diagrams; picking one attaches it to
  /// the selected column (or clears it).
  Future<void> _pickChord() async {
    final l10n = AppLocalizations.of(context)!;
    // Chord-builder selection (root pitch class + quality index).
    var buildRoot = 0;
    var buildQuality = 0;
    // Curated multi-position voicings (chords-db) load lazily INSIDE the sheet
    // (below) so the picker opens immediately; the future is cached once.
    Future<ChordDb?>? dbFuture;
    ChordDiagram builtDiagram() {
      final (label, intervals) = kChordQualities[buildQuality];
      return chordVoicing(
        _doc.tuning,
        buildRoot,
        intervals,
        name: chordName(buildRoot, label),
      );
    }

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.tabChordPick,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final entry in kGuitarChords.entries)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Tap the diagram to attach it…
                          InkWell(
                            onTap: () => Navigator.of(ctx).pop(entry.key),
                            child: ChordDiagramView(entry.value),
                          ),
                          // …or hear it first, without closing the picker.
                          TextButton.icon(
                            icon: const Icon(Icons.play_arrow, size: 16),
                            label: Text(l10n.tabPatternPreview),
                            onPressed: () => _previewColumns(
                              strumColumns(entry.value, _dur),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const Divider(height: 24),
                // Build ANY chord: root + quality → a voicing on this tuning.
                Text(
                  'Build a chord',
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    DropdownButton<int>(
                      value: buildRoot,
                      onChanged: (v) => setSheet(() => buildRoot = v ?? 0),
                      items: [
                        for (var i = 0; i < kChordRoots.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(kChordRoots[i]),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: buildQuality,
                      onChanged: (v) => setSheet(() => buildQuality = v ?? 0),
                      items: [
                        for (var i = 0; i < kChordQualities.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(kChordQualities[i].$1),
                          ),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: l10n.tabPatternPreview,
                      icon: const Icon(Icons.play_arrow),
                      onPressed: () =>
                          _previewColumns(strumColumns(builtDiagram(), _dur)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Prefer the curated chords-db voicings (tap a shape to add it);
                // fall back to one algorithmically-voiced diagram + Add while
                // the DB loads or when it doesn't carry this chord/tuning.
                FutureBuilder<ChordDb?>(
                  future: dbFuture ??= _loadChordDb(),
                  builder: (_, snap) {
                    final voicings = snap.data?.voicings(
                          buildRoot,
                          kChordQualities[buildQuality].$1,
                        ) ??
                        const <ChordDiagram>[];
                    if (voicings.isEmpty) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ChordDiagramView(builtDiagram()),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            icon: const Icon(Icons.add),
                            label: Text(
                              chordName(
                                buildRoot,
                                kChordQualities[buildQuality].$1,
                              ),
                            ),
                            onPressed: () {
                              _setChordDiagram(builtDiagram());
                              Navigator.of(ctx).pop(); // applied already
                            },
                          ),
                        ],
                      );
                    }
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final v in voicings)
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () {
                                  _setChordDiagram(v);
                                  Navigator.of(ctx).pop();
                                },
                                child: ChordDiagramView(v),
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.play_arrow, size: 16),
                                label: Text(l10n.tabPatternPreview),
                                onPressed: () =>
                                    _previewColumns(strumColumns(v, _dur)),
                              ),
                            ],
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(Icons.clear),
                  label: Text(l10n.tabChordNone),
                  onPressed: () => Navigator.of(ctx).pop(''),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked == null) return; // builder applied inline, or dismissed
    setChordByName(picked.isEmpty ? null : picked);
  }

  static const List<String> _rootNames = [
    'C',
    'C♯',
    'D',
    'D♯',
    'E',
    'F',
    'F♯',
    'G',
    'G♯',
    'A',
    'A♯',
    'B',
  ];

  /// A bottom sheet that generates a run of columns — a chord voiced as a
  /// strum/arpeggio/pattern, a named progression in that voicing, or a scale
  /// (root + type + octaves + direction), optionally repeated — inserting it
  /// after the cursor at the current note length.
  Future<void> _pickPattern() async {
    final l10n = AppLocalizations.of(context)!;
    var mode = 0; // 0 = chord · 1 = progression · 2 = scale
    var chord = kGuitarChords.keys.first;
    var progName = kProgressions.keys.first;
    var styleIdx = 0; // index into [styles] (shared by chord + progression)
    var rootPc = 0; // 0 = C
    var scaleName = kScales.keys.first;
    var octaves = 1;
    var descending = false;
    int? startFret; // null = open (lowest fret); else a hand-position box
    var repeat = 1;

    // The chord voicings, in chip order — labels paired with their [ChordStyle].
    final styles = <(String, ChordStyle)>[
      (l10n.tabPatternStrum, ChordStyle.strum),
      (l10n.tabPatternUp, ChordStyle.up),
      (l10n.tabPatternDown, ChordStyle.down),
      (l10n.tabPatternUpDown, ChordStyle.upDown),
      (l10n.tabPatternDownUp, ChordStyle.downUp),
      (l10n.tabPatternTravis, ChordStyle.travis),
      (l10n.tabPatternBoomChuck, ChordStyle.boomChuck),
      (l10n.tabPatternStrumEighths, ChordStyle.strumEighths),
      (l10n.tabPatternIsland, ChordStyle.island),
    ];

    final inserted = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget seg(String label, bool on, VoidCallback onTap) => ChoiceChip(
                label: Text(label),
                selected: on,
                onSelected: (_) => setSheet(onTap),
              );
          Widget heading(String t) => Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Text(t, style: Theme.of(ctx).textTheme.labelLarge),
              );
          Widget modeTab(String label, int m) => Expanded(
                child: seg(label, mode == m, () => mode = m),
              );
          // The strum/arp/pattern chips, shared by chord + progression modes.
          Widget styleChips() => Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < styles.length; i++)
                    seg(styles[i].$1, styleIdx == i, () => styleIdx = i),
                ],
              );
          final children = <Widget>[
            Row(
              children: [
                modeTab(l10n.tabPatternChord, 0),
                const SizedBox(width: 6),
                modeTab(l10n.tabPatternProgression, 1),
                const SizedBox(width: 6),
                modeTab(l10n.tabPatternScale, 2),
              ],
            ),
          ];
          switch (mode) {
            case 0:
              children.addAll([
                heading(l10n.tabChordPick),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final name in kGuitarChords.keys)
                      ChoiceChip(
                        label: Text(name),
                        selected: chord == name,
                        onSelected: (_) => setSheet(() => chord = name),
                      ),
                  ],
                ),
                heading(l10n.tabPatternStyle),
                styleChips(),
              ]);
            case 1:
              children.addAll([
                heading(l10n.tabPatternProgression),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final name in kProgressions.keys)
                      ChoiceChip(
                        label: Text(name),
                        selected: progName == name,
                        onSelected: (_) => setSheet(() => progName = name),
                      ),
                  ],
                ),
                heading(l10n.tabPatternStyle),
                styleChips(),
              ]);
            default:
              children.addAll([
                heading(l10n.tabPatternRoot),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var pc = 0; pc < 12; pc++)
                      ChoiceChip(
                        label: Text(_rootNames[pc]),
                        selected: rootPc == pc,
                        onSelected: (_) => setSheet(() => rootPc = pc),
                      ),
                  ],
                ),
                heading(l10n.tabPatternScaleType),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final name in kScales.keys)
                      ChoiceChip(
                        label: Text(name),
                        selected: scaleName == name,
                        onSelected: (_) => setSheet(() => scaleName = name),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(l10n.tabPatternOctaves),
                    const SizedBox(width: 8),
                    for (final o in [1, 2])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: seg('$o', octaves == o, () => octaves = o),
                      ),
                    const SizedBox(width: 16),
                    seg(
                      l10n.tabPatternUp,
                      !descending,
                      () => descending = false,
                    ),
                    const SizedBox(width: 6),
                    seg(
                      l10n.tabPatternDown,
                      descending,
                      () => descending = true,
                    ),
                  ],
                ),
                heading(l10n.tabPatternPosition),
                Wrap(
                  spacing: 6,
                  children: [
                    seg(
                      l10n.tabPatternPositionOpen,
                      startFret == null,
                      () => startFret = null,
                    ),
                    for (final f in [3, 5, 7, 9, 12])
                      seg('$f', startFret == f, () => startFret = f),
                  ],
                ),
              ]);
          }
          children.addAll([
            heading(l10n.tabPatternRepeat),
            Wrap(
              spacing: 6,
              children: [
                for (final n in [1, 2, 4])
                  seg('×$n', repeat == n, () => repeat = n),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.tabPatternPreview),
                  // Hear one pass of the current selection without inserting.
                  onPressed: () {
                    final style = styles[styleIdx].$2;
                    _previewColumns(
                      switch (mode) {
                        0 =>
                          chordStyleColumns(kGuitarChords[chord]!, style, _dur),
                        1 => progressionColumns(
                            kProgressions[progName]!,
                            kGuitarChords,
                            style,
                            _dur,
                          ),
                        _ => scaleColumns(
                            _doc.tuning,
                            48 + rootPc,
                            kScales[scaleName]!,
                            _dur,
                            octaves: octaves,
                            descending: descending,
                            startFret: startFret,
                          ),
                      },
                    );
                  },
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(l10n.tabPatternInsert),
                  onPressed: () {
                    final style = styles[styleIdx].$2;
                    final n = switch (mode) {
                      0 => insertChordStyle(chord, style, repeat: repeat),
                      1 => insertProgression(progName, style, repeat: repeat),
                      _ => insertScale(
                          48 + rootPc,
                          scaleName,
                          octaves: octaves,
                          descending: descending,
                          repeat: repeat,
                          startFret: startFret,
                        ),
                    };
                    Navigator.of(ctx).pop(n);
                  },
                ),
              ],
            ),
          ]);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
          );
        },
      ),
    );
    if (inserted != null && inserted > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tabPatternAdded(inserted))),
      );
    }
  }

  String _techLabel(AppLocalizations l10n, TabTechnique t) => switch (t) {
        TabTechnique.hammer => l10n.tabTechHammer,
        TabTechnique.slide => l10n.tabTechSlide,
        TabTechnique.bend => l10n.tabTechBend,
        TabTechnique.vibrato => l10n.tabTechVibrato,
        TabTechnique.dead => l10n.tabTechDead,
        TabTechnique.ghost => l10n.tabTechGhost,
        TabTechnique.harmonic => l10n.tabTechHarmonic,
      };

  // Labels for the 32nd-note step grid (a whole note = 32 steps).
  String _durLabel(int steps) => switch (steps) {
        32 => '𝅝', // whole
        24 => '𝅗𝅥.', // dotted half
        16 => '𝅗𝅥', // half
        12 => '♩.', // dotted quarter
        8 => '♩', // quarter
        6 => '♪.', // dotted eighth
        4 => '♪', // eighth
        3 => '𝅘𝅥𝅯.', // dotted sixteenth
        2 => '𝅘𝅥𝅯', // sixteenth
        _ => '𝅘𝅥𝅰', // thirty-second
      };

  // Major-key name for a circle-of-fifths count.
  String _keyLabel(int fifths) => switch (fifths) {
        -7 => 'C♭',
        -6 => 'G♭',
        -5 => 'D♭',
        -4 => 'A♭',
        -3 => 'E♭',
        -2 => 'B♭',
        -1 => 'F',
        1 => 'G',
        2 => 'D',
        3 => 'A',
        4 => 'E',
        5 => 'B',
        6 => 'F♯',
        7 => 'C♯',
        _ => 'C',
      };
}
