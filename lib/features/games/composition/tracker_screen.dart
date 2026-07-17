// lib/features/games/composition/tracker_screen.dart
//
// "Tracker" (Sandbox skin) — a touch-first pattern sequencer in the spirit of
// ModEdit / FastTracker 2 / Scream Tracker 3 / Impulse Tracker, but built for a
// 10-year-old: pick an instrument tab, then tap a pentatonic piano-roll (pitch
// rows × step columns) to build that channel's part. All channels layer into one
// looping groove. Scale-locked to C-pentatonic so any placement sounds good (the
// Colour Melody rule) — a creative sandbox, no stars, no wrong answers.
//
// It's the Loop Mixer with an EDITABLE grid: TrackerEngine mixes the channels
// offline into ONE looping WAV (sample-accurate sync) played on a dedicated
// LoopPlayerService; a Stopwatch owns the musical phase so an edit re-swaps the
// loop in place without the beat restarting; a Ticker (created in initState —
// never a lazy `late final`, see CLAUDE.md) drives the step playhead.
//
// Slice 1 ships the Sandbox skin over the additive engine. Studio depth (the
// full note·instrument·volume·fx cell, keyboard entry, sfxr/sampled instruments)
// hangs off the same TrackerEngine document later — see docs/TRACKER_HANDOVER.md.

import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart';
import 'package:comet_beat/core/audio/mod/mod.dart';
import 'package:comet_beat/core/audio/mod/mod_bridge.dart';
import 'package:comet_beat/core/audio/mod/module_convert.dart'
    show sniffModuleFormat;
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/module_instrument_bridge.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/voice_clip_recorder.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/gapless_loop_player.dart';
import 'package:comet_beat/features/games/composition/tracker_notation.dart';
import 'package:comet_beat/features/games/note_reading/note_colors.dart';
import 'package:comet_beat/features/games/songs/song_book.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

class TrackerScreen extends StatefulWidget {
  const TrackerScreen({super.key});

  /// One 4/4 bar of eighth-note steps.
  static const steps = 8;

  /// Tempo presets — all keep the step length integral (see TrackerTiming).
  static const tempos = [75, 100, 120];

  /// Pitch rows, top (high) → bottom (low): a C-major pentatonic, so any
  /// combination is consonant. Highest at the top matches staff intuition.
  static const rowSteps = [Step.a, Step.g, Step.e, Step.d, Step.c];

  /// The MIDI note for each row in octave 4 (C4 = 60).
  static const _rowMidiOct4 = [69, 67, 64, 62, 60]; // A G E D C

  /// Per-channel octave shift, so bass sits low and sparkle sits high while
  /// every channel still plays the same consonant scale.
  static const _channelOctave = <String, int>{
    'melody': 0,
    'sparkle': 1,
    'zap': 0,
    'bass': -2,
    'voice': 0,
  };

  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class TrackerTester {
  List<String> get channelIds;
  int get selectedChannel;
  int get pitchRows;
  int get steps;
  bool get isPlaying;

  /// Total notes placed across all channels.
  int get noteCount;
  void selectChannel(int index);

  /// Tap the grid cell at ([row], [step]) of the selected channel.
  void tapCell(int row, int step);
  void clearAll();

  /// Whether the voice channel holds a recorded sample yet.
  bool get hasVoiceRecording;

  /// Test seam for the mic-less binding: assign [raw] (+ [fx]) to the voice
  /// channel as if it had just been recorded.
  void injectRecording(Float64List raw, VoiceEffect fx);

  bool get notationVisible;
  void toggleNotation();

  /// Imports the built-in demo tune into the melody channel (Score → Tracker).
  void importDemo();

  /// Imports a built-in song book tune (by id) into the melody channel.
  void importSong(String id);

  /// The id of the selected channel's current instrument.
  String get selectedInstrumentId;

  /// Re-voices the selected channel to the palette option with [optionId].
  void setInstrument(String optionId);

  // --- Arrangement (pattern slots + song) ---
  int get slotCount;
  int get currentSlot;
  void selectSlot(int index);

  /// Whether any slot (or the live pattern) has notes to play as a song.
  bool get songHasContent;
  void playSong();

  /// The editable order-list (slot indices in play order).
  List<int> get songOrder;
  void addToOrder(int slot);
  void clearOrder();

  /// Long-press equivalent: toggle the note at ([row], [step]) soft/normal.
  void toggleAccent(int row, int step);
  bool isSoft(int row, int step);

  /// Sets/reads the per-note effect at ([row], [step]) on the selected channel.
  void setNoteEffect(int row, int step, TrackerEffect effect);
  TrackerEffect effectAt(int step);

  /// Loads a parsed MOD module (the mic-less/file-less test path).
  void importModModule(ModModule mod);

  /// The current song serialized to MOD bytes.
  Uint8List exportModBytes();

  /// Loads a Score (as if from a MIDI file) into the channels.
  void importMidiScore(Score score);

  /// The current pattern serialized to Standard MIDI File bytes.
  Uint8List exportMidiBytes();
}

class _TrackerScreenState extends State<TrackerScreen>
    with SingleTickerProviderStateMixin
    implements TrackerTester {
  final _engine = TrackerEngine(
    timing: const TrackerTiming(
      rows: TrackerScreen.steps,
      stepsPerBeat: 2,
    ),
  );
  final _loop = GaplessLoopPlayer();
  final _recorder = VoiceClipRecorder();

  /// The groove's musical clock: playback phase derives from it, never from the
  /// player, so an edit re-enters the loop in phase.
  final _clock = Stopwatch();

  late final Ticker _ticker;
  final _step = ValueNotifier<int>(-1);

  int _selected = 0;
  bool _isRecording = false;
  bool _showNotation = false;

  /// Arrangement: four pattern slots (A–D). The engine edits the current slot's
  /// cells live; switching slots saves/loads snapshots. "Play song" chains the
  /// non-empty slots in order.
  static const _slotCount = 4;
  late final List<List<List<TrackerCell>>> _slots;
  int _currentSlot = 0;

  /// The song order-list: slot indices in play order (e.g. [0,0,1,0] = A A B A).
  /// Empty means "auto" — every non-empty slot A→D.
  final List<int> _order = [];
  bool _songMode = false;

  /// Which order entry is currently sounding (song mode), else -1.
  final _playingOrder = ValueNotifier<int>(-1);

  int get _voiceIndex => _engine.channels.indexWhere((c) => c.id == 'voice');

  /// The selected channel's pattern as staff notation (the "score view").
  Score get _selectedScore {
    final ch = _engine.channels[_selected];
    // Drums aren't pitched — show a rest bar rather than drum codes as pitches.
    final source = ch.instrument is PercussionInstrument
        ? TrackerChannel(
            id: ch.id,
            instrument: ch.instrument,
            rows: _engine.rows,
          )
        : ch;
    return trackerChannelToScore(
      source,
      _engine.timing,
      clef: ch.id == 'bass' ? Clef.bass : Clef.treble,
    );
  }

  @override
  void initState() {
    super.initState();
    _slots = List.generate(_slotCount, (_) => _engine.exportCells());
    _ticker = createTicker((_) {
      final t = _engine.timing;
      if (_songMode && _order.isNotEmpty && _clock.isRunning) {
        final songMs = _order.length * t.totalMs;
        final pos = _clock.elapsedMilliseconds % songMs;
        _playingOrder.value = pos ~/ t.totalMs;
        _step.value = (pos % t.totalMs) ~/ t.stepMs;
      } else {
        _playingOrder.value = -1;
        _step.value = _clock.isRunning
            ? (_clock.elapsedMilliseconds % t.totalMs) ~/ t.stepMs
            : -1;
      }
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _step.dispose();
    _playingOrder.dispose();
    _loop.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // --- TrackerTester ---
  @override
  List<String> get channelIds => [for (final c in _engine.channels) c.id];
  @override
  int get selectedChannel => _selected;
  @override
  int get pitchRows => _gridRows(_selected).length;
  @override
  int get steps => _engine.rows;
  @override
  bool get isPlaying => _clock.isRunning;
  @override
  int get noteCount => _engine.channels.fold(
        0,
        (n, c) => n + c.cells.where((cell) => !cell.isEmpty).length,
      );
  @override
  void selectChannel(int index) => setState(() => _selected = index);
  @override
  void tapCell(int row, int step) =>
      _onTapCode(_gridRows(_selected)[row].code, step);
  @override
  void clearAll() => _clearAll();
  @override
  bool get hasVoiceRecording {
    final v = _voiceIndex;
    final inst = v < 0 ? null : _engine.channels[v].instrument;
    return inst is SampleInstrument && inst.sample.isNotEmpty;
  }

  @override
  void injectRecording(Float64List raw, VoiceEffect fx) =>
      _assignVoice(raw, fx);
  @override
  bool get notationVisible => _showNotation;
  @override
  void toggleNotation() => setState(() => _showNotation = !_showNotation);
  @override
  void importDemo() => _importScore(kTrackerDemoTune);
  @override
  void importSong(String id) =>
      _importScore(kSongs.firstWhere((s) => s.id == id).score);
  @override
  String get selectedInstrumentId => _engine.channels[_selected].instrument.id;
  @override
  void setInstrument(String optionId) {
    final option = kTrackerInstruments.firstWhere((o) => o.id == optionId);
    _engine.setChannelInstrument(_selected, option.build());
    setState(() {});
    _syncPlayback();
  }

  @override
  int get slotCount => _slotCount;
  @override
  int get currentSlot => _currentSlot;
  @override
  void selectSlot(int index) => _selectSlot(index);
  @override
  bool get songHasContent =>
      !_engine.isEmpty ||
      [
        for (var i = 0; i < _slotCount; i++)
          if (i != _currentSlot) _slots[i],
      ].any((s) => !_slotEmpty(s));
  @override
  void playSong() => _playSong();
  @override
  List<int> get songOrder => List.unmodifiable(_order);
  @override
  void addToOrder(int slot) => _addToOrder(slot);
  @override
  void clearOrder() => setState(_order.clear);
  @override
  void toggleAccent(int row, int step) =>
      _toggleSoft(_gridRows(_selected)[row].code, step);
  @override
  bool isSoft(int row, int step) =>
      _engine.cellAt(_selected, step).volume != null &&
      _engine.cellAt(_selected, step).midi == _gridRows(_selected)[row].code;
  @override
  void setNoteEffect(int row, int step, TrackerEffect effect) =>
      _setCellEffect(step, effect);
  @override
  TrackerEffect effectAt(int step) => _engine.cellAt(_selected, step).effect;
  @override
  void importModModule(ModModule mod) => _loadMod(mod);
  @override
  Uint8List exportModBytes() => writeMod(_currentAsMod());
  @override
  void importMidiScore(Score score) => _loadMidi(score);
  @override
  Uint8List exportMidiBytes() => scoreToMidi(_trackerAsScore());

  bool _slotEmpty(List<List<TrackerCell>> snap) =>
      snap.every((ch) => ch.every((c) => c.isEmpty));

  /// Saves the live pattern into the current slot, then loads slot [index].
  void _selectSlot(int index) {
    if (index == _currentSlot) return;
    _slots[_currentSlot] = _engine.exportCells();
    _engine.importCells(_slots[index]);
    setState(() => _currentSlot = index);
    _syncPlayback();
  }

  /// Adds slot [index] to the end of the song order-list.
  void _addToOrder(int index) => setState(() => _order.add(index));

  /// Removes the order-list entry at [position].
  void _removeFromOrder(int position) =>
      setState(() => _order.removeAt(position));

  /// Renders the song (the [_order] list, or all non-empty slots A→D if the
  /// order is empty) into one long loop and plays it.
  void _playSong() {
    _slots[_currentSlot] = _engine.exportCells();
    final order = _order.isNotEmpty
        ? List<int>.of(_order)
        : [
            for (var i = 0; i < _slotCount; i++)
              if (!_slotEmpty(_slots[i])) i,
          ];
    if (order.isEmpty) return;
    if (!context.read<AudioService>().soundOn) return;
    final wav = renderSong(_engine, [for (final i in order) _slots[i]]);
    // Materialize the effective order so the strip + playhead reflect it.
    setState(() {
      _order
        ..clear()
        ..addAll(order);
      _songMode = true;
    });
    _clock
      ..reset()
      ..start();
    _loop.playLoop(wav);
  }

  /// Imports [score] onto the melody channel (index 0 — treble, so octave-4
  /// notes land on its grid) and switches to it. Partial: it quantizes to the
  /// grid and keeps only the first bar (see [scoreToTrackerCells]).
  void _importScore(Score score) {
    _engine.setChannelCells(
      0,
      scoreToTrackerCells(score, _engine.timing),
    );
    setState(() => _selected = 0);
    _syncPlayback();
  }

  // ── MOD import / export ────────────────────────────────────────────────────

  /// Loads a parsed [mod] into the tracker: re-voices channels from the module's
  /// samples and fills the pattern slots (partial — see mod_bridge.dart).
  void _loadMod(ModModule mod) {
    final imp = modToTracker(mod, rows: _engine.rows);
    final chN = _engine.channels.length;
    for (var c = 0; c < imp.channelCount && c < chN; c++) {
      _engine.setChannelInstrument(c, imp.channelInstruments[c]);
    }
    List<List<TrackerCell>> emptySnap() => [
          for (var c = 0; c < chN; c++)
            List<TrackerCell>.filled(
              _engine.rows,
              TrackerCell.empty,
              growable: true,
            ),
        ];
    List<List<TrackerCell>> fullSnap(List<List<TrackerCell>> p) => [
          for (var c = 0; c < chN; c++)
            c < p.length
                ? List<TrackerCell>.of(p[c])
                : List<TrackerCell>.filled(
                    _engine.rows,
                    TrackerCell.empty,
                    growable: true,
                  ),
        ];
    for (var s = 0; s < _slotCount; s++) {
      _slots[s] =
          s < imp.patterns.length ? fullSnap(imp.patterns[s]) : emptySnap();
    }
    _engine.importCells(_slots[0]);
    setState(() {
      _selected = 0;
      _currentSlot = 0;
      _order.clear();
    });
    _syncPlayback();
  }

  /// The current song as a MOD module: the non-empty slots become patterns; each
  /// channel's instrument becomes a sample (see trackerToMod).
  ModModule _currentAsMod() {
    _slots[_currentSlot] = _engine.exportCells();
    final patterns = [
      for (final s in _slots)
        if (!_slotEmpty(s)) s,
    ];
    return trackerToMod(
      patterns.isEmpty ? [_engine.exportCells()] : patterns,
      channelInstruments: [for (final c in _engine.channels) c.instrument],
      rows: _engine.rows,
    );
  }

  Future<void> _importMod() async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context)!.trackerModFailed;
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'MOD', extensions: ['mod']),
        ],
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      _loadMod(parseMod(bytes));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  /// "Borrow a sample from a module": pick a `.mod/.s3m/.xm/.it`, choose one of
  /// its samples, and make it the selected channel's instrument.
  Future<void> _borrowInstrument() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Module',
            extensions: ['mod', 's3m', 'xm', 'it'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (sniffModuleFormat(bytes) == null) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.trackerModFailed)));
        return;
      }
      final samples = borrowableSamples(bytes);
      if (samples.isEmpty) {
        messenger
            .showSnackBar(SnackBar(content: Text(l10n.trackerBorrowEmpty)));
        return;
      }
      if (!mounted) return;
      final picked = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(l10n.trackerBorrowSample),
          children: [
            for (final (index, sample) in samples)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, index),
                child: Text(_sampleLabel(index, sample)),
              ),
          ],
        ),
      );
      if (picked == null || !mounted) return;
      _engine.setChannelInstrument(
        _selected,
        sampleInstrumentFromModule('borrow', bytes, picked),
      );
      setState(() {});
      _syncPlayback();
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.trackerModFailed)));
    }
  }

  String _sampleLabel(int index, DocSample s) {
    final name = s.name.trim();
    final title = name.isEmpty ? 'Sample ${index + 1}' : name;
    return '${index + 1}. $title  (${s.pcm.length})';
  }

  Future<void> _exportMod() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = writeMod(_currentAsMod());
      final location = await getSaveLocation(
        suggestedName: 'tracker.mod',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'MOD', extensions: ['mod']),
        ],
      );
      if (location == null || !mounted) return;
      await XFile.fromData(bytes, name: 'tracker.mod').saveTo(location.path);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.workshopSavedTo(location.path))),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.trackerModFailed)));
    }
  }

  // ── MIDI import / export (via the Score bridge) ────────────────────────────

  /// The current pattern as a chord Score for MIDI export: each step becomes a
  /// chord of every pitched channel's note there (a block-chord reduction — the
  /// notes and their positions, one step each).
  Score _trackerAsScore() {
    final rows = _engine.rows;
    final one = NoteDuration(
      switch (_engine.timing.stepsPerBeat) {
        1 => DurationBase.quarter,
        4 => DurationBase.sixteenth,
        _ => DurationBase.eighth,
      },
    );
    final elements = <MusicElement>[];
    for (var s = 0; s < rows; s++) {
      final seen = <int>{};
      final pitches = <Pitch>[];
      for (final ch in _engine.channels) {
        if (ch.instrument is PercussionInstrument) continue;
        final m = ch.cells[s].midi;
        if (m != null && seen.add(m)) pitches.add(pitchFromMidi(m));
      }
      elements.add(
        pitches.isEmpty
            ? RestElement(one)
            : NoteElement(pitches: pitches, duration: one),
      );
    }
    final barSteps = _engine.timing.stepsPerBeat * 4;
    return Score(
      clef: Clef.treble,
      measures: [
        for (var i = 0; i < elements.length; i += barSteps)
          Measure(
            elements.sublist(i, (i + barSteps).clamp(0, elements.length)),
          ),
      ],
    );
  }

  /// Loads a MIDI-derived [score] into the pitched channels (chords split across
  /// channels via scoreToChannels); the channels keep their voices.
  void _loadMidi(Score score) {
    final chans = scoreToChannels(score, _engine.timing);
    for (var c = 0; c < chans.length && c < _engine.channels.length; c++) {
      _engine.setChannelCells(c, chans[c]);
    }
    setState(() => _selected = 0);
    _syncPlayback();
  }

  Future<void> _importMidi() async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context)!.trackerModFailed;
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'MIDI', extensions: ['mid', 'midi']),
        ],
      );
      if (file == null || !mounted) return;
      _loadMidi(scoreFromMidi(await file.readAsBytes()));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  Future<void> _exportMidi() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = scoreToMidi(_trackerAsScore());
      final location = await getSaveLocation(
        suggestedName: 'tracker.mid',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'MIDI', extensions: ['mid', 'midi']),
        ],
      );
      if (location == null || !mounted) return;
      await XFile.fromData(bytes, name: 'tracker.mid').saveTo(location.path);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.workshopSavedTo(location.path))),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.trackerModFailed)));
    }
  }

  /// The song picker — the Workshop ↔ Tracker bridge: the built-in song book
  /// (shared with the Workshop / Song Book) plus a simple demo tune. Importing a
  /// real tune drops its opening bar onto the grid to remix.
  void _showSongSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final l10n = AppLocalizations.of(sheetContext)!;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.trackerImportTune,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.music_note),
                title: Text(l10n.trackerDemoTune),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _importScore(kTrackerDemoTune);
                },
              ),
              for (final song in kSongs)
                ListTile(
                  leading: const Icon(Icons.library_music),
                  title: Text(song.title),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _importScore(song.score);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// Voices the recorded [raw] (+ [fx]) onto the voice channel and switches to
  /// it. Shared by the real mic path and the test seam.
  void _assignVoice(Float64List raw, VoiceEffect fx) {
    final v = _voiceIndex;
    if (v < 0) return;
    _engine.setChannelInstrument(
      v,
      SampleInstrument.recorded('voice', raw, fx),
    );
    setState(() => _selected = v);
    _syncPlayback();
  }

  Future<void> _recordVoice(VoiceEffect fx) async {
    if (_voiceIndex < 0) return;
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context)!.trackerRecordFailed;
    setState(() => _isRecording = true);
    try {
      final raw = await _recorder.record();
      if (!mounted) return;
      setState(() => _isRecording = false);
      _assignVoice(raw, fx);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isRecording = false);
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  bool _isPercussion(int channel) =>
      _engine.channels[channel].instrument is PercussionInstrument;

  /// The MIDI note a pitched grid row maps to for [channel].
  int _midiFor(int channel, int row) =>
      TrackerScreen._rowMidiOct4[row] +
      12 * (TrackerScreen._channelOctave[_engine.channels[channel].id] ?? 0);

  /// The grid rows for [channel]: drum rows for percussion, else the pentatonic
  /// pitch rows. `code` is what a placed cell holds — a Drum index, or a MIDI
  /// note (both round-trip through [TrackerCell.midi]).
  List<_GridRow> _gridRows(int channel) {
    if (_isPercussion(channel)) {
      return [
        for (final drum in PercussionInstrument.rows)
          _GridRow(_drumColor(drum), drum.index, icon: _drumIcon(drum)),
      ];
    }
    return [
      for (var r = 0; r < TrackerScreen.rowSteps.length; r++)
        _GridRow(
          pitchClassColor(TrackerScreen.rowSteps[r]),
          _midiFor(channel, r),
        ),
    ];
  }

  void _onTapCode(int code, int step) {
    final placed = _engine.toggleNote(_selected, step, code);
    setState(() {});
    if (placed != null && !_isPercussion(_selected)) {
      context.read<AudioService>().playMidiNote(code, ms: 300);
    }
    _syncPlayback();
  }

  static const _softVolume = 0.45;

  /// Toggles a note between normal and soft (a quiet "ghost" note) — dynamics.
  void _toggleSoft(int code, int step) {
    final cell = _engine.cellAt(_selected, step);
    if (cell.midi != code) return; // only the note that's actually there
    _engine.setCellVolume(
      _selected,
      step,
      cell.volume != null ? null : _softVolume,
    );
    setState(() {});
    _syncPlayback();
  }

  void _setCellEffect(int step, TrackerEffect effect) {
    _engine.setCellEffect(_selected, step, effect);
    setState(() {});
    _syncPlayback();
  }

  /// Long-press a placed note → a small menu for its dynamics + effect.
  void _onLongPressCode(int code, int step) {
    final cell = _engine.cellAt(_selected, step);
    if (cell.midi != code) return; // only opens on a placed note
    final additive =
        _engine.channels[_selected].instrument is AdditiveInstrument;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final l10n = AppLocalizations.of(sheetContext)!;
        final current = _engine.cellAt(_selected, step);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: Text(l10n.trackerSoftNote),
                  value: current.volume != null,
                  onChanged: (_) {
                    Navigator.pop(sheetContext);
                    _toggleSoft(code, step);
                  },
                ),
                if (additive) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.trackerEffect,
                    style: Theme.of(sheetContext).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final fx in TrackerEffect.values)
                        ChoiceChip(
                          label: Text(_effectLabel(l10n, fx)),
                          selected: current.effect == fx,
                          onSelected: (_) {
                            Navigator.pop(sheetContext);
                            _setCellEffect(step, fx);
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _effectLabel(AppLocalizations l10n, TrackerEffect fx) => switch (fx) {
        TrackerEffect.none => l10n.trackerEffectNone,
        TrackerEffect.arpeggio => l10n.trackerEffectArp,
        TrackerEffect.vibrato => l10n.trackerEffectVibrato,
        TrackerEffect.slideUp => l10n.trackerEffectSlideUp,
        TrackerEffect.slideDown => l10n.trackerEffectSlideDown,
      };

  static Color _drumColor(Drum d) => switch (d) {
        Drum.kick => const Color(0xFF4E342E),
        Drum.snare => const Color(0xFF6D4C41),
        Drum.hat => const Color(0xFF8D6E63),
      };

  static IconData _drumIcon(Drum d) => switch (d) {
        Drum.kick => Icons.circle,
        Drum.snare => Icons.radio_button_checked,
        Drum.hat => Icons.blur_on,
      };

  void _clearAll() {
    setState(_engine.clearAll);
    _syncPlayback();
  }

  void _setTempo(int bpm) {
    if (bpm == _engine.timing.tempoBpm) return;
    setState(() => _engine.timing = _engine.timing.copyWith(tempoBpm: bpm));
    // A new tempo is a new grid — restart the groove from the top.
    _clock
      ..stop()
      ..reset();
    _syncPlayback();
  }

  /// Swaps/stops the looping mix to match the pattern, keeping the musical
  /// phase so the beat never resets on an edit. Any single-pattern playback
  /// exits song mode (editing returns to the one-bar loop).
  void _syncPlayback() {
    _songMode = false;
    if (_engine.isEmpty) {
      _clock
        ..stop()
        ..reset();
      _loop.stop();
      return;
    }
    if (!context.read<AudioService>().soundOn) return; // master mute
    final wav = _engine.renderLoop();
    if (!_clock.isRunning) {
      _clock
        ..reset()
        ..start();
    }
    final position = Duration(
      milliseconds: _clock.elapsedMilliseconds % _engine.timing.totalMs,
    );
    _loop.playLoop(wav, position: position);
  }

  static const _channelIcons = <String, IconData>{
    'melody': Icons.music_note,
    'sparkle': Icons.auto_awesome,
    'zap': Icons.bolt,
    'bass': Icons.speaker,
    'drums': Icons.album,
    'voice': Icons.mic,
  };

  String _channelLabel(AppLocalizations l10n, String id) => switch (id) {
        'melody' => l10n.trackerChannelMelody,
        'sparkle' => l10n.trackerChannelSparkle,
        'zap' => l10n.trackerChannelZap,
        'drums' => l10n.trackerChannelDrums,
        'voice' => l10n.trackerChannelVoice,
        _ => l10n.trackerChannelBass,
      };

  static const _voiceEffectIcons = <VoiceEffect, IconData>{
    VoiceEffect.normal: Icons.person,
    VoiceEffect.chipmunk: Icons.pets,
    VoiceEffect.monster: Icons.sentiment_very_dissatisfied,
    VoiceEffect.deep: Icons.waves,
    VoiceEffect.robot: Icons.smart_toy,
  };

  String _voiceEffectLabel(AppLocalizations l10n, VoiceEffect fx) =>
      switch (fx) {
        VoiceEffect.normal => l10n.trackerVoiceNormal,
        VoiceEffect.chipmunk => l10n.trackerVoiceChipmunk,
        VoiceEffect.monster => l10n.trackerVoiceMonster,
        VoiceEffect.deep => l10n.trackerVoiceDeep,
        VoiceEffect.robot => l10n.trackerVoiceRobot,
      };

  String _instrumentLabel(AppLocalizations l10n, String id) => switch (id) {
        'piano' => l10n.instrumentPiano,
        'cello' => l10n.instrumentCello,
        'flute' => l10n.instrumentFlute,
        'musicBox' => l10n.instrumentMusicBox,
        'zap' => l10n.trackerSfxrZap,
        'blip' => l10n.trackerSfxrBlip,
        'laser' => l10n.trackerSfxrLaser,
        'coin' => l10n.trackerSfxrCoin,
        _ => l10n.trackerSfxrExplosion,
      };

  /// The per-channel instrument picker (additive voices + chiptune presets).
  void _showInstrumentSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final l10n = AppLocalizations.of(sheetContext)!;
        final currentId = _engine.channels[_selected].instrument.id;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.trackerChangeInstrument,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final option in kTrackerInstruments)
                      ChoiceChip(
                        label: Text(_instrumentLabel(l10n, option.id)),
                        selected: option.id == currentId,
                        onSelected: (_) {
                          Navigator.pop(sheetContext);
                          setInstrument(option.id);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The "pick a voice, then record" sheet.
  void _showRecordSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final l10n = AppLocalizations.of(sheetContext)!;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.trackerRecordPrompt,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final fx in VoiceEffect.values)
                      ActionChip(
                        avatar: Icon(_voiceEffectIcons[fx], size: 18),
                        label: Text(_voiceEffectLabel(l10n, fx)),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _recordVoice(fx);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _tempoLabel(AppLocalizations l10n, int bpm) => switch (bpm) {
        75 => l10n.loopMixerTempoChill,
        120 => l10n.loopMixerTempoFast,
        _ => l10n.loopMixerTempoGroove,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(
        title: l10n.gameTracker,
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_play),
            tooltip: l10n.trackerPlaySong,
            onPressed: songHasContent ? _playSong : null,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: l10n.trackerChangeInstrument,
            onPressed: _showInstrumentSheet,
          ),
          IconButton(
            icon: const Icon(Icons.library_music),
            tooltip: l10n.trackerImportTune,
            onPressed: _showSongSheet,
          ),
          IconButton(
            icon: Icon(_showNotation ? Icons.grid_view : Icons.music_note),
            tooltip: l10n.trackerToggleNotation,
            onPressed: () => setState(() => _showNotation = !_showNotation),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'importMod':
                  _importMod();
                case 'exportMod':
                  _exportMod();
                case 'importMid':
                  _importMidi();
                case 'exportMid':
                  _exportMidi();
                case 'borrow':
                  _borrowInstrument();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'importMod',
                child: Text(l10n.trackerImportMod),
              ),
              PopupMenuItem(
                value: 'exportMod',
                child: Text(l10n.trackerExportMod),
              ),
              PopupMenuItem(
                value: 'importMid',
                child: Text(l10n.trackerImportMidi),
              ),
              PopupMenuItem(
                value: 'exportMid',
                child: Text(l10n.trackerExportMidi),
              ),
              PopupMenuItem(
                value: 'borrow',
                child: Text(l10n.trackerBorrowSample),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                l10n.trackerPrompt,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              // Instrument tabs — pick the channel you're editing.
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (var i = 0; i < _engine.channels.length; i++)
                    _ChannelChip(
                      label: _channelLabel(l10n, _engine.channels[i].id),
                      icon: _channelIcons[_engine.channels[i].id]!,
                      selected: i == _selected,
                      hasNotes: _engine.channels[i].hasAnyNote,
                      onTap: () => setState(() => _selected = i),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Pattern slots (A–D) — build a few patterns, then Play song.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    l10n.trackerPattern,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(width: 8),
                  for (var i = 0; i < _slotCount; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ChoiceChip(
                        label: Text(String.fromCharCode(65 + i)), // A B C D
                        selected: i == _currentSlot,
                        onSelected: (_) => _selectSlot(i),
                        side: (i != _currentSlot && !_slotEmpty(_slots[i]))
                            ? BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 1.5,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
              // Song order-list: the play sequence; the sounding entry lights up.
              Row(
                children: [
                  Text(
                    l10n.trackerSong,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _playingOrder,
                      builder: (context, playing, _) => Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (var i = 0; i < _order.length; i++)
                            InputChip(
                              label: Text(String.fromCharCode(65 + _order[i])),
                              selected: i == playing,
                              onDeleted: () => _removeFromOrder(i),
                            ),
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: Text(String.fromCharCode(65 + _currentSlot)),
                            onPressed: () => _addToOrder(_currentSlot),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _Playhead(step: _step, steps: _engine.rows),
              const SizedBox(height: 8),
              // The selected channel's grid: pentatonic pitch rows, or drum rows.
              Expanded(
                child: Column(
                  children: [
                    for (final gridRow in _gridRows(_selected))
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              if (gridRow.icon != null)
                                SizedBox(
                                  width: 24,
                                  child: Icon(
                                    gridRow.icon,
                                    size: 16,
                                    color: gridRow.color,
                                  ),
                                ),
                              for (var step = 0; step < _engine.rows; step++)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    child: _Cell(
                                      color: gridRow.color,
                                      active: _engine
                                              .cellAt(_selected, step)
                                              .midi ==
                                          gridRow.code,
                                      soft: _engine
                                              .cellAt(_selected, step)
                                              .volume !=
                                          null,
                                      onTap: () =>
                                          _onTapCode(gridRow.code, step),
                                      onLongPress: () =>
                                          _onLongPressCode(gridRow.code, step),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // The "score view": ALL pitched channels as stacked staves (the
              // full multi-part notation), or a rest bar when nothing's placed.
              if (_showNotation) ...[
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final parts = trackerToScoreParts(
                      _engine.channels,
                      _engine.timing,
                    );
                    final scores = parts.isEmpty ? [_selectedScore] : parts;
                    return SizedBox(
                      height: scores.length > 1 ? 140 : 92,
                      child: Card(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final s in scores)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  child: StaffView(
                                    score: s,
                                    staffSpace: 7,
                                    theme: kidsScoreTheme,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final bpm in TrackerScreen.tempos)
                          ChoiceChip(
                            label: Text(_tempoLabel(l10n, bpm)),
                            selected: _engine.timing.tempoBpm == bpm,
                            onSelected: (_) => _setTempo(bpm),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _isRecording ? null : _showRecordSheet,
                    icon: Icon(_isRecording ? Icons.mic : Icons.mic_none),
                    label: Text(
                      _isRecording ? l10n.trackerRecording : l10n.trackerRecord,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _engine.isEmpty ? null : _clearAll,
                    icon: const Icon(Icons.clear),
                    label: Text(l10n.trackerClear),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An instrument tab. Shows a dot when that channel already holds notes so the
/// child can see which parts they've filled without switching to each.
class _ChannelChip extends StatelessWidget {
  const _ChannelChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.hasNotes,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool hasNotes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 18,
        color: selected ? scheme.onSecondaryContainer : scheme.primary,
      ),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      // A small filled dot marks channels that already have notes.
      onSelected: (_) => onTap(),
      side: hasNotes && !selected
          ? BorderSide(color: scheme.primary, width: 1.5)
          : null,
    );
  }
}

/// A row of step dots with the sounding step lit; beats (every 2 steps) are
/// spaced apart. Only this leaf listens to the ticker, so the per-frame update
/// never rebuilds the grid.
class _Playhead extends StatelessWidget {
  const _Playhead({required this.step, required this.steps});

  final ValueListenable<int> step;
  final int steps;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.primary;
    return ValueListenableBuilder<int>(
      valueListenable: step,
      builder: (context, current, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < steps; i++)
            Container(
              width: 10,
              height: 10,
              margin: EdgeInsets.only(left: i == 0 ? 0 : (i % 2 == 0 ? 10 : 4)),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == current
                    ? base
                    : base.withValues(alpha: i.isEven ? 0.25 : 0.12),
              ),
            ),
        ],
      ),
    );
  }
}

/// One grid row: its [color], the cell payload [code] (a MIDI note or a Drum
/// index), and an optional leading [icon] (drum rows).
class _GridRow {
  const _GridRow(this.color, this.code, {this.icon});

  final Color color;
  final int code;
  final IconData? icon;
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.color,
    required this.active,
    required this.onTap,
    required this.onLongPress,
    this.soft = false,
  });

  final Color color;
  final bool active;

  /// A soft/ghost note — drawn half-filled so dynamics are visible.
  final bool soft;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    // A placed note fills the cell; a soft note fills it only partway.
    final fillAlpha = active ? (soft ? 0.5 : 1.0) : 0.14;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: color.withValues(alpha: fillAlpha),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? color : color.withValues(alpha: 0.35),
            width: active ? 3 : 1.5,
          ),
        ),
      ),
    );
  }
}
