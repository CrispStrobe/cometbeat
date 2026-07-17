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
// Slice 1 shipped the grid + endless length/tracks + Play/Stop. Slice 2 (this)
// adds the edit cursor, keyboard + on-screen piano entry, per-track instruments
// and per-cell volume/effect. Multi-pattern songs + order list and the full
// transport (pause/prev/next/loop) land in later slices — all over this
// same document.

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/gapless_loop_player.dart';
import 'package:comet_beat/features/games/composition/tracker_screen.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
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

/// Selectable pattern lengths (rows). "Endless" in practice — the grid handles
/// any of these, well past the Beginner grid's single bar.
const _kLengthOptions = [16, 32, 48, 64, 96, 128];

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
  int get cursorChannel;
  int get cursorRow;
  int get octave;

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
}

class _AdvancedTrackerScreenState extends State<AdvancedTrackerScreen>
    with SingleTickerProviderStateMixin
    implements AdvancedTrackerTester {
  final _song = TrackerSong();
  final _loop = GaplessLoopPlayer();
  final _focus = FocusNode();

  /// The musical clock — playback phase derives from it, never the player, so an
  /// edit re-enters the loop in phase.
  final _clock = Stopwatch();
  late final Ticker _ticker;

  /// The sounding row (0-based), or -1 when stopped. Drives the playhead without
  /// a full rebuild.
  final _row = ValueNotifier<int>(-1);

  /// The edit cursor — keyboard and on-screen piano enter notes here.
  int _cursorChannel = 0;
  int _cursorRow = 0;

  /// Keyboard/piano entry state.
  int _octave = 4;
  int _editStep = 1;

  final _vScroll = ScrollController();
  int _lastFollowedRow = -1;

  static const _rowNumWidth = 44.0;
  static const _cellWidth = 74.0;
  static const _rowHeight = 30.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (!_clock.isRunning) {
        if (_row.value != -1) _row.value = -1;
        return;
      }
      final t = _song.timing;
      final step = (_clock.elapsedMilliseconds % t.totalMs) ~/ t.stepMs;
      if (step != _row.value) {
        _row.value = step;
        _followPlayhead(step);
      }
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _row.dispose();
    _vScroll.dispose();
    _focus.dispose();
    _loop.dispose();
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
    setState(() {
      _song.setRows(rows);
      if (_cursorRow >= rows) _cursorRow = rows - 1;
    });
    _syncPlayback();
  }

  @override
  void addTrack() {
    setState(_song.addChannel);
    _syncPlayback();
  }

  @override
  void removeTrack(int channel) {
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
  void moveCursor(int channel, int row) => setState(() {
        _cursorChannel = channel.clamp(0, _song.channelCount - 1);
        _cursorRow = row.clamp(0, _song.rows - 1);
      });
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

  // --- Editing ---

  void _setCell(int channel, int row, TrackerCell cell) {
    setState(() => _song.engine.setCell(channel, row, cell));
    _syncPlayback();
  }

  void _clearAll() {
    setState(_song.engine.clearAll);
    _syncPlayback();
  }

  /// Enters [midi] at the cursor and advances by the edit-step (wrapping).
  void _enterNoteAtCursor(int midi) {
    _song.engine.setCell(_cursorChannel, _cursorRow, TrackerCell(midi: midi));
    setState(() => _cursorRow = (_cursorRow + _editStep) % _song.rows);
    _syncPlayback();
  }

  void _clearAtCursorAndAdvance() {
    _song.engine.clearCell(_cursorChannel, _cursorRow);
    setState(() => _cursorRow = (_cursorRow + _editStep) % _song.rows);
    _syncPlayback();
  }

  // --- Keyboard ---

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // Navigation / editing keys first.
    if (key == LogicalKeyboardKey.arrowDown) {
      moveCursor(_cursorChannel, (_cursorRow + 1) % _song.rows);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      moveCursor(
        _cursorChannel,
        (_cursorRow - 1 + _song.rows) % _song.rows,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      moveCursor((_cursorChannel + 1) % _song.channelCount, _cursorRow);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      moveCursor(
        (_cursorChannel - 1 + _song.channelCount) % _song.channelCount,
        _cursorRow,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _clearAtCursorAndAdvance();
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

    // Otherwise a piano-map character.
    final ch = event.character?.toLowerCase();
    if (ch != null && _typeKey(ch)) return KeyEventResult.handled;
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

  // --- Playback (mirrors tracker_screen.dart's phase-preserving loop swap) ---

  void _togglePlay() {
    if (_clock.isRunning) {
      _clock
        ..stop()
        ..reset();
      _loop.stop();
      _row.value = -1;
      setState(() {});
    } else {
      _clock
        ..reset()
        ..start();
      _syncPlayback();
      setState(() {});
    }
  }

  /// Swaps/stops the looping mix to match the current pattern, keeping the
  /// musical phase so an edit never resets the beat.
  void _syncPlayback() {
    if (!_clock.isRunning) return;
    if (_song.current.hasAnyNote == false &&
        !_song.engine.channels.any(
          (c) => c.hasAnyNote,
        )) {
      _loop.stop();
      return;
    }
    if (!context.read<AudioService>().soundOn) return; // master mute
    final wav = _song.renderCurrentPatternWav();
    final position = Duration(
      milliseconds: _clock.elapsedMilliseconds % _song.timing.totalMs,
    );
    _loop.playLoop(wav, position: position);
  }

  void _followPlayhead(int step) {
    if (!_vScroll.hasClients || step == _lastFollowedRow) return;
    _lastFollowedRow = step;
    final target = (step * _rowHeight) - 120;
    final max = _vScroll.position.maxScrollExtent;
    _vScroll.jumpTo(target.clamp(0.0, max));
  }

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

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: GameAppBar(
        title: l10n.trackerAdvancedTitle,
        actions: [
          IconButton(
            icon: const Icon(Icons.child_care),
            tooltip: l10n.trackerModeToBeginner,
            onPressed: _toBeginner,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: l10n.trackerClear,
            onPressed: _clearAll,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.large(
        onPressed: _togglePlay,
        tooltip: _clock.isRunning ? l10n.trackerStop : l10n.trackerPlay,
        child: Icon(_clock.isRunning ? Icons.stop : Icons.play_arrow),
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
                const Divider(height: 1),
                Expanded(child: _grid(context)),
                const Divider(height: 1),
                _pianoBar(l10n),
              ],
            ),
          ),
        ),
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
            Text('${l10n.trackerLength}: '),
            DropdownButton<int>(
              value: _kLengthOptions.contains(_song.rows) ? _song.rows : null,
              hint: Text('${_song.rows}'),
              items: [
                for (final n in _kLengthOptions)
                  DropdownMenuItem(value: n, child: Text('$n')),
              ],
              onChanged: (v) {
                if (v != null) setRows(v);
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
            // Edit-step: rows the cursor advances after each note.
            Text('${l10n.trackerEditStep}: '),
            DropdownButton<int>(
              value: _editStep,
              items: [
                for (final n in const [0, 1, 2, 4])
                  DropdownMenuItem(value: n, child: Text('$n')),
              ],
              onChanged: (v) => setState(() => _editStep = v ?? 1),
            ),
            const SizedBox(width: 12),
            Text(
              '${_song.channelCount} × ${_song.rows}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
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

  Widget _headerRow(ColorScheme scheme) {
    return Container(
      height: _rowHeight,
      color: scheme.surfaceContainerHigh,
      child: Row(
        children: [
          const SizedBox(width: _rowNumWidth),
          for (var c = 0; c < _song.channelCount; c++)
            SizedBox(
              width: _cellWidth,
              child: InkWell(
                onTap: () => _pickInstrument(c),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        _song.channels[c].instrument.id,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_song.channelCount > 1)
                      InkWell(
                        onTap: () => removeTrack(c),
                        child: const Icon(Icons.close, size: 13),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rowWidget(
    int row,
    int activeRow,
    int stepsPerBeat,
    ColorScheme scheme,
  ) {
    final isActive = row == activeRow;
    final isBeat = row % stepsPerBeat == 0;
    final rowBg = isActive
        ? scheme.primaryContainer
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
    // note + volume + effect sub-columns (classic tracker cell).
    final note = hasNote ? trackerNoteName(cell.midi!) : '···';
    final vol = hasNote && cell.volume != null && cell.volume != 1.0
        ? (cell.volume! * 99).round().toString().padLeft(2, '0')
        : '··';
    final fx = hasNote && cell.effect != TrackerEffect.none
        ? _effectCode(cell.effect)
        : '·';
    return GestureDetector(
      onTap: () {
        moveCursor(channel, row);
        _focus.requestFocus();
      },
      onLongPress: () => _cellMenu(channel, row),
      child: Container(
        width: _cellWidth,
        alignment: Alignment.center,
        decoration: BoxDecoration(
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
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$vol$fx',
                style: TextStyle(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontSize: 10,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
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
              const Spacer(),
              // Clear-at-cursor (the "===" key on a real tracker).
              OutlinedButton(
                onPressed: _clearAtCursorAndAdvance,
                child: const Text('···'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(height: 64, child: _MiniPiano(onNote: _pianoNote)),
        ],
      ),
    );
  }

  void _pianoNote(int semitone) {
    _enterNoteAtCursor(((_octave + 1) * 12 + semitone).clamp(0, 127));
    _focus.requestFocus();
  }
}

/// A one-octave on-screen piano (touch note entry). [onNote] gets the semitone
/// offset 0..11 (C..B); the screen adds the current base octave.
class _MiniPiano extends StatelessWidget {
  const _MiniPiano({required this.onNote});

  final void Function(int semitone) onNote;

  static const _whiteSemitones = [0, 2, 4, 5, 7, 9, 11]; // C D E F G A B
  // A black key sits after white indices 0,1,3,4,5 (C#,D#,F#,G#,A#); 2 and 6
  // have no black key.
  static const _blackAfterWhite = <int, int>{0: 1, 1: 3, 3: 6, 4: 8, 5: 10};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth / 7;
        return Stack(
          children: [
            Row(
              children: [
                for (final semi in _whiteSemitones)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(1),
                      child: Material(
                        color: scheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                          side: BorderSide(color: scheme.outline),
                        ),
                        child: InkWell(
                          onTap: () => onNote(semi),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                _kNoteNames[semi],
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            for (final entry in _blackAfterWhite.entries)
              Positioned(
                left: (entry.key + 1) * w - w * 0.3,
                width: w * 0.6,
                top: 0,
                height: 40,
                child: Material(
                  color: scheme.inverseSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: InkWell(onTap: () => onNote(entry.value)),
                ),
              ),
          ],
        );
      },
    );
  }
}
