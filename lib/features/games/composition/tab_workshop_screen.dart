import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_sources.dart' show ScoreSource;
import 'package:comet_beat/core/audio/loop_engine.dart'
    show LoopTiming, PatternCell, kPatternSteps;
import 'package:comet_beat/core/audio/microphone_pitch_service.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/score_instrument_render.dart'
    show renderMultiPartWithInstrument;
import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:comet_beat/core/audio/transcription/engine_config.dart'
    show Backend, TranscriptionStep;
import 'package:comet_beat/core/audio/wav_io.dart'
    show readWavPcm16, wavToMonoFloat;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/melody_bridge.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/transcription_config_service.dart';
import 'package:comet_beat/features/games/composition/music_inspect.dart';
import 'package:comet_beat/features/games/composition/tab_arranger.dart';
import 'package:comet_beat/features/games/composition/tab_chords.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:comet_beat/features/games/composition/tab_labeler.dart';
import 'package:comet_beat/features/games/composition/tab_mic_capture.dart';
import 'package:comet_beat/features/games/composition/tab_patterns.dart';
import 'package:comet_beat/features/games/composition/tabcnn_to_document.dart'
    show audioToTabDocument;
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/sound_lab/my_instruments_sheet.dart'
    show showMyInstrumentsSheet;
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/daw/send_to_daw.dart';
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
    _ => throw FormatException('Unsupported file type: .$ext'),
  };
}

/// Test seam onto [TabWorkshopScreen]'s state — drives editing + file-open with
/// injected bytes, and reads back what's shown, without the platform picker.
abstract class TabWorkshopTester {
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

  /// 🔍 Desktop hover: drive the hover over a cell and read whether the corner
  /// card is showing (a fretted cell shows it; an empty column clears it).
  void debugHoverCell(int col, int string);
  bool get debugHoverCardShown;

  /// Send the whole tab band to the Multitrack (DAW) as a clip.
  void sendToDaw();
}

/// A guitar/bass **tablature editor** (B1) — the Tab Workshop. Author tab on a
/// string×step grid (tap a cell, type a fret) for any [Tuning] + capo, hear it,
/// and open GPIF / MusicXML / MIDI / ABC files as editable tab. The
/// engraved staff (with a synced standard staff) previews the [TabDocument];
/// the same model round-trips to the Score Workshop and Tracker.
class TabWorkshopScreen extends StatefulWidget {
  /// Optional score to open as editable tab (e.g. from the Workshop). When null
  /// a built-in demo riff is shown.
  final Score? initialScore;

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

  (int, List<TabColumn>) _captureState() =>
      (_active, [for (final c in _doc.columns) c.copy()]);

  /// Snapshot the active track before a mutation so [undo] can restore it. A
  /// fresh edit invalidates the redo history.
  void _snapshot() {
    _undoStack.add(_captureState());
    if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  /// Drop all history — the document or track indices changed (load / paste /
  /// track removal), so old snapshots are stale.
  void _clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
  }

  void _restore((int, List<TabColumn>) snap) {
    final (track, cols) = snap;
    _active = track.clamp(0, _tracks.length - 1);
    _tracks[_active].doc.columns
      ..clear()
      ..addAll(cols);
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

  int _capo = 0;
  bool _showStandard = true;
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
  bool _countingIn = false;
  int _playToken = 0; // bumped to cancel an in-flight count-in
  Set<String> _highlightedIds = const {};
  List<({int col, int start, int end, bool note})> _schedule = const [];
  int _totalMs = 0;

  @override
  void initState() {
    super.initState();
    final score = widget.initialScore ?? asciiTabToScore(_demoTab);
    _tracks = [
      TabTrack('Guitar', TabDocument.fromScore(score, Tuning.standardGuitar)),
    ];
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
    final pcm = renderMultiPartWithInstrument(
      _bandScore(),
      inst,
      quarterMs: quarterMs,
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
  Set<String> get highlightedIds => _highlightedIds;
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
      () => _doc.setChord(_selCol, name == null ? null : kGuitarChords[name]),
    );
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
      cells.add((midis: midi == null ? null : [midi!], steps: steps));
      filled += steps;
    }
    if (filled < kPatternSteps) {
      cells.add((midis: null, steps: kPatternSteps - filled));
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
      : scoreToMusicXml(_doc.toScore(capo: _capo));

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

  void _loadDemo() => setState(() {
        _tracks[_active].doc =
            TabDocument.fromScore(asciiTabToScore(_demoTab), _doc.tuning);
        _sourceName = null;
        _selCol = 0;
        _selString = 0;
      });

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
    final beatMs = (60000 / _bpm).round();
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
    // Audio: every track sounding together. Highlight: the ACTIVE track's own
    // column timeline (that's what the preview shows).
    final events = _doc.toPlaybackEvents(bpm: _bpm, capo: _capo);
    final band = mergePlaybackEvents(
      [
        for (final t in audibleTracks(_tracks))
          t.doc.toPlaybackEvents(bpm: _bpm, capo: _capo),
      ],
    );
    context.read<AudioService>().playTimedChords(band);
    final schedule = <({int col, int start, int end, bool note})>[];
    var t = 0;
    for (var c = 0; c < events.length; c++) {
      final (midis, ms) = events[c];
      schedule.add((col: c, start: t, end: t + ms, note: midis.isNotEmpty));
      t += ms;
    }
    if (_ticker.isActive) _ticker.stop();
    setState(() {
      _schedule = schedule;
      _totalMs = t;
      _playing = true;
      _highlightedIds = const {};
    });
    _ticker.start();
  }

  void _stopPlayback() {
    _playToken++; // cancels any in-flight count-in
    if (_ticker.isActive) _ticker.stop();
    setState(() {
      _playing = false;
      _countingIn = false;
      _highlightedIds = const {};
    });
  }

  void _onTick(Duration elapsed) {
    final ms = elapsed.inMilliseconds;
    if (ms >= _totalMs) {
      _stopPlayback();
      return;
    }
    Set<String> ids = const {};
    for (final e in _schedule) {
      if (e.note && ms >= e.start && ms < e.end) {
        ids = {'t${e.col}'};
        break;
      }
    }
    if (!setEquals(ids, _highlightedIds)) {
      setState(() => _highlightedIds = ids);
    }
  }

  // ── Export ───────────────────────────────────────────────────────────────
  Future<void> _export(String format) async {
    final score = _doc.toScore(capo: _capo);
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
        await _saveBytes(
          scoreToMidi(score),
          '$base.mid',
          'MIDI',
          const ['mid'],
        );
      case 'daw':
        sendToDaw();
    }
  }

  @override
  void sendToDaw() => sendToMultitrack(context, ScoreSource(_bandScore()));

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
    final score = _doc.toScore(capo: _capo);
    final view = _showStandard
        ? NotationTabView(
            score: score,
            tuning: _doc.tuning,
            capo: _capo,
            showTuning: true,
            highlightedIds: _highlightedIds,
          )
        : TabStaffView(
            score: score,
            tuning: _doc.tuning,
            capo: _capo,
            showTuning: true,
            highlightedIds: _highlightedIds,
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
          IconButton(
            icon: const Icon(Icons.piano_outlined),
            tooltip: l10n.workshopPlayWithInstrument,
            onPressed: _playWithInstrument,
          ),
          IconButton(
            icon: const Icon(Icons.av_timer),
            color: _countIn ? Theme.of(context).colorScheme.primary : null,
            tooltip: l10n.tabCountIn,
            onPressed: () => setState(() => _countIn = !_countIn),
          ),
          IconButton(
            icon: Icon(_listening ? Icons.mic : Icons.mic_none),
            tooltip: l10n.tabMic,
            color: _listening ? Theme.of(context).colorScheme.error : null,
            onPressed: _toggleMic,
          ),
          IconButton(
            icon: Icon(_inspect ? Icons.search_off : Icons.search),
            isSelected: _inspect,
            tooltip: l10n.inspectMode,
            onPressed: () => setState(() => _inspect = !_inspect),
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: l10n.tabImport,
            onPressed: openScoreFile,
          ),
          IconButton(
            icon: _transcribing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.graphic_eq),
            tooltip: l10n.tabOpenRecording,
            onPressed: _transcribing ? null : openAudioRecording,
          ),
          IconButton(
            icon: const Icon(Icons.library_music_outlined),
            tooltip: l10n.tabOpenSongBook,
            onPressed: _openFromSongBook,
          ),
          IconButton(
            icon: const Icon(Icons.content_paste),
            tooltip: l10n.tabPasteAscii,
            onPressed: _promptPasteAscii,
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: l10n.tabSaveSongBook,
            onPressed: _promptSave,
          ),
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: l10n.tabOpenWorkshop,
            onPressed: _openInScoreWorkshop,
          ),
          // Shared-tune bridge: hand the tab's melody to the Loop Mixer /
          // Tracker / Score Editor, or pull a tune they shared in as tab.
          PopupMenuButton<String>(
            icon: const Icon(Icons.library_music_outlined),
            tooltip: l10n.tuneShare,
            enabled: canShareMelody || MelodyBridge.instance.hasMelody,
            onSelected: (v) =>
                v == 'share' ? shareMelody() : loadSharedMelody(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'share',
                enabled: canShareMelody,
                child: Text(l10n.tuneShare),
              ),
              PopupMenuItem(
                value: 'load',
                enabled: MelodyBridge.instance.hasMelody,
                child: Text(l10n.tuneLoadShared),
              ),
            ],
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
              PopupMenuItem(value: 'daw', child: Text(l10n.dawSend)),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.music_note),
            tooltip: l10n.tabDemo,
            onPressed: _loadDemo,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.tabClear,
            onPressed: _clearAll,
          ),
        ],
      ),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          children: [
            _trackStrip(l10n),
            const Divider(height: 1),
            _controls(l10n),
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
            _editorPanel(l10n),
          ],
        ),
      ),
    );
  }

  /// The band's track strip: pick the track you're editing, add or remove one.
  Widget _trackStrip(AppLocalizations l10n) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text(l10n.tabTracks),
          const SizedBox(width: 8),
          for (var i = 0; i < _tracks.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChoiceChip(
                    label: Text(
                      _tracks[i].name,
                      style: _tracks[i].muted
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough,
                            )
                          : null,
                    ),
                    selected: i == _active,
                    onSelected: (_) => selectTrack(i),
                  ),
                  if (i == _active) ...[
                    _msToggle('M', _tracks[i].muted, toggleMute),
                    _msToggle('S', _tracks[i].soloed, toggleSolo),
                  ],
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.library_add_outlined),
            tooltip: l10n.tabAddTrack,
            onPressed: addTrack,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: l10n.tabRemoveTrack,
            onPressed: _tracks.length > 1 ? removeTrack : null,
          ),
        ],
      ),
    );
  }

  /// A compact M/S toggle badge for the active track.
  Widget _msToggle(String letter, bool on, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            letter,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: on ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls(AppLocalizations l10n) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(l10n.tabTuning),
          const SizedBox(width: 8),
          DropdownButton<Tuning>(
            value: _doc.tuning,
            onChanged: (t) => setState(() {
              if (t != null) {
                _doc.tuning = t;
                _selString = _selString.clamp(0, t.stringCount - 1);
              }
            }),
            items: [
              for (final t in tabTuningPresets)
                DropdownMenuItem(value: t, child: Text(_tuningLabel(t))),
            ],
          ),
          const SizedBox(width: 20),
          Text(l10n.tabCapo),
          IconButton(
            icon: const Icon(Icons.remove),
            tooltip: l10n.tabCapo,
            onPressed: _capo > 0 ? () => setState(() => _capo--) : null,
          ),
          Text('$_capo'),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.tabCapo,
            onPressed: _capo < 12 ? () => setState(() => _capo++) : null,
          ),
          const SizedBox(width: 20),
          Text(l10n.tabTempo),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: l10n.tabTempo,
            onPressed: _bpm > 40 ? () => setState(() => _bpm -= 10) : null,
          ),
          Text('$_bpm'),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: l10n.tabTempo,
            onPressed: _bpm < 240 ? () => setState(() => _bpm += 10) : null,
          ),
          const SizedBox(width: 20),
          Text(l10n.tabShowStandard),
          Switch(
            value: _showStandard,
            onChanged: (v) => setState(() => _showStandard = v),
          ),
        ],
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
  Widget _grid() {
    final n = _doc.stringCount;
    final grid = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Chord-name header aligned above the columns.
          Row(
            children: [
              const SizedBox(width: 40),
              for (int c = 0; c < _doc.columns.length; c++)
                SizedBox(
                  width: 34,
                  child: Text(
                    _doc.columns[c].chord?.name ?? '',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          for (int s = 0; s < n; s++)
            Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    _doc.tuning.strings[s].toString().toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                for (int c = 0; c < _doc.columns.length; c++) _cell(c, s),
              ],
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
          grid,
          if (_inspect && _hoverInfo != null)
            Positioned(top: 8, right: 8, child: _hoverInspectCard()),
        ],
      ),
    );
  }

  Widget _cell(int col, int string) {
    final fret = _doc.columns[col].frets[string];
    final selected = col == _selCol && string == _selString;
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: _inspect ? (_) => _onCellHover(col, string) : null, // 🔍 desktop
      child: GestureDetector(
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
          child: Text(
            fret?.toString() ?? '·',
            style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              color: fret == null ? scheme.onSurfaceVariant : scheme.onSurface,
            ),
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
  Widget _editorPanel(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l10n.tabDuration),
              for (final (dur, steps) in kTabDurations)
                ChoiceChip(
                  label: Text(_durLabel(steps)),
                  selected: _dur == dur,
                  onSelected: (_) => setState(() {
                    _dur = dur;
                    _doc.setDuration(_selCol, dur);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
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
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.arrow_downward),
                tooltip: l10n.tabTransposeDown,
                onPressed: () => transposeBy(-1),
              ),
              Text(
                l10n.tabTranspose,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_upward),
                tooltip: l10n.tabTransposeUp,
                onPressed: () => transposeBy(1),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.grid_goldenratio, size: 18),
                label: Text(l10n.tabChord),
                onPressed: _pickChord,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(l10n.tabPattern),
                onPressed: _pickPattern,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l10n.tabTechnique),
              for (final t in TabTechnique.values)
                FilterChip(
                  label: Text(_techLabel(l10n, t)),
                  selected: _selCol < _doc.columns.length &&
                      _doc.columns[_selCol].techniques.contains(t),
                  onSelected: (_) => toggleTechnique(t),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// A bottom-sheet grid of guitar chord diagrams; picking one attaches it to
  /// the selected column (or clears it).
  Future<void> _pickChord() async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
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
                          onPressed: () =>
                              _previewColumns(strumColumns(entry.value, _dur)),
                        ),
                      ],
                    ),
                ],
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
    );
    if (picked == null) return;
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

  String _durLabel(int steps) => switch (steps) {
        8 => '𝅝',
        6 => '𝅗𝅥.',
        4 => '𝅗𝅥',
        3 => '♩.',
        2 => '♩',
        _ => '♪',
      };
}
