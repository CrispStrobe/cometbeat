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

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/foundation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/scheduler.dart';
import 'package:klang_universum/core/audio/crisp_dsp/voice_fx.dart';
import 'package:klang_universum/core/audio/tracker_engine.dart';
import 'package:klang_universum/core/audio/voice_clip_recorder.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/loop_player_service.dart';
import 'package:klang_universum/features/games/composition/tracker_notation.dart';
import 'package:klang_universum/features/games/note_reading/note_colors.dart';
import 'package:klang_universum/features/games/widgets/game_app_bar.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/score_theme.dart';
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
  final _loop = LoopPlayerService();
  final _recorder = VoiceClipRecorder();

  /// The groove's musical clock: playback phase derives from it, never from the
  /// player, so an edit re-enters the loop in phase.
  final _clock = Stopwatch();

  late final Ticker _ticker;
  final _step = ValueNotifier<int>(-1);

  int _selected = 0;
  bool _isRecording = false;
  bool _showNotation = false;

  int get _voiceIndex => _engine.channels.indexWhere((c) => c.id == 'voice');

  /// The selected channel's pattern as staff notation (the "score view").
  Score get _selectedScore {
    final ch = _engine.channels[_selected];
    return trackerChannelToScore(
      ch,
      _engine.timing,
      clef: ch.id == 'bass' ? Clef.bass : Clef.treble,
    );
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final t = _engine.timing;
      _step.value = _clock.isRunning
          ? (_clock.elapsedMilliseconds % t.totalMs) ~/ t.stepMs
          : -1;
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _step.dispose();
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
  int get pitchRows => TrackerScreen.rowSteps.length;
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
  void tapCell(int row, int step) => _onTap(row, step);
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

  /// The MIDI note a grid row maps to for the given channel.
  int _midiFor(int channel, int row) =>
      TrackerScreen._rowMidiOct4[row] +
      12 * (TrackerScreen._channelOctave[_engine.channels[channel].id] ?? 0);

  void _onTap(int row, int step) {
    final midi = _midiFor(_selected, row);
    final placed = _engine.toggleNote(_selected, step, midi);
    setState(() {});
    if (placed != null) {
      context.read<AudioService>().playMidiNote(midi, ms: 300);
    }
    _syncPlayback();
  }

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
  /// phase so the beat never resets on an edit.
  void _syncPlayback() {
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
    'voice': Icons.mic,
  };

  String _channelLabel(AppLocalizations l10n, String id) => switch (id) {
        'melody' => l10n.trackerChannelMelody,
        'sparkle' => l10n.trackerChannelSparkle,
        'zap' => l10n.trackerChannelZap,
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
    final rowColors = [
      for (final s in TrackerScreen.rowSteps) pitchClassColor(s),
    ];

    return Scaffold(
      appBar: GameAppBar(
        title: l10n.gameTracker,
        actions: [
          IconButton(
            icon: Icon(_showNotation ? Icons.grid_view : Icons.music_note),
            tooltip: l10n.trackerToggleNotation,
            onPressed: () => setState(() => _showNotation = !_showNotation),
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
              const SizedBox(height: 10),
              _Playhead(step: _step, steps: _engine.rows),
              const SizedBox(height: 8),
              // The pentatonic piano-roll for the selected channel.
              Expanded(
                child: Column(
                  children: [
                    for (var row = 0;
                        row < TrackerScreen.rowSteps.length;
                        row++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              for (var step = 0; step < _engine.rows; step++)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    child: _Cell(
                                      color: rowColors[row],
                                      active: _engine
                                              .cellAt(_selected, step)
                                              .midi ==
                                          _midiFor(_selected, row),
                                      onTap: () => _onTap(row, step),
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
              // The "score view": the selected channel's pattern as notation.
              if (_showNotation) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 92,
                  child: Card(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: StaffView(
                          score: _selectedScore,
                          staffSpace: 8,
                          theme: kidsScoreTheme,
                        ),
                      ),
                    ),
                  ),
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

class _Cell extends StatelessWidget {
  const _Cell({
    required this.color,
    required this.active,
    required this.onTap,
  });

  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: active ? color : color.withValues(alpha: 0.14),
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
