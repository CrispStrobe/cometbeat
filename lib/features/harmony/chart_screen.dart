// lib/features/harmony/chart_screen.dart
//
// BB-U1 / BB-U2 — the chart surface: read it, edit it, hear it.
//
// This is NOT the Score Workshop with chords bolted on, and the difference is
// not cosmetic. The Workshop engraves noteheads on staves and its whole document
// model is a stream of notes; a chart has bars and chord names and no notes at
// all, and it has to stay legible on a music stand across a room. Two surfaces,
// two jobs, one shared harmony engine underneath.
//
// Chord symbols drawn ABOVE A STAFF are a separate feature, and a working one —
// the readers parse them and the layout engraves them. That is for a score that
// happens to carry harmony. This is for harmony that has no score.
library;

import 'dart:async';

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_playback.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/harmony/chart_grid_view.dart';
import 'package:comet_beat/features/harmony/chord_keypad.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Something to look at on first open. An empty grid teaches nothing, and a
/// blues is the shortest form that shows sections, repeats and a turnaround.
const kStarterChartText = '''
title: Twelve-Bar Blues
key: C
tempo: 100

[A] x2
| C7 | F7 | C7 | C7 |
| F7 | F7 | C7 | C7 |
| G7 | F7 | C7 | G7 |
''';

class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key, this.initialChart});

  /// Opens on this chart instead of the starter one.
  final Chart? initialChart;

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  late Chart _chart;
  ChartBarRef? _selected;
  ChartBarRef? _playingBar;

  /// The transport clock. `playMixedTimedChords` renders a WAV and hands it to
  /// the player, so there is no position callback to follow — the highlight is
  /// driven by our own stopwatch started at the same moment.
  Timer? _ticker;
  Stopwatch? _clock;
  ChartPlayback? _playback;

  bool get _playing => _ticker != null;

  @override
  void initState() {
    super.initState();
    _chart = widget.initialChart ?? parseChartText(kStarterChartText).chart;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- transport

  Future<void> _play() async {
    final playback = resolveChartPlayback(_chart);
    if (playback.isEmpty) return;

    final audio = context.read<AudioService>();
    _playback = playback;
    _clock = Stopwatch()..start();
    // 60 Hz would be wasted: the highlight only changes on a bar boundary, and
    // at any sane tempo that is seconds apart.
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
    setState(() {});

    // Comp and bass as separate stems so the bass keeps its own level, plus a
    // click so the chart is playable-along rather than just audible.
    await audio.playMixedTimedChords(
      [playback.comp, playback.bass],
      gains: const [0.85, 0.7],
      clickBeatMs: playback.beatMs,
    );
  }

  void _tick() {
    final playback = _playback;
    final clock = _clock;
    if (playback == null || clock == null) return;

    final ms = clock.elapsedMilliseconds;
    if (ms >= playback.totalMs) {
      _stop();
      return;
    }
    final span = playback.barAt(ms);
    final ref =
        span == null ? null : _refForPlayedBar(span.sectionIndex, span.index);
    if (ref != _playingBar) setState(() => _playingBar = ref);
  }

  /// Maps a bar in PLAY order back to the document bar it came from.
  ///
  /// With repeats expanded several played bars share one document bar, so the
  /// highlight has to land on the document bar the user is looking at.
  ChartBarRef? _refForPlayedBar(int sectionIndex, int playedIndex) {
    var seen = 0;
    for (var s = 0; s < _chart.sections.length; s++) {
      final section = _chart.sections[s];
      final total = section.bars.length * section.passes;
      if (playedIndex < seen + total) {
        final within = (playedIndex - seen) % section.bars.length;
        return ChartBarRef(s, within);
      }
      seen += total;
    }
    return null;
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    _ticker = null;
    _clock = null;
    _playback = null;
    if (mounted) setState(() => _playingBar = null);
    await context.read<AudioService>().stop();
  }

  // ------------------------------------------------------------------ editing

  Future<void> _editBar(ChartBarRef ref) async {
    // Editing while the band plays is how you lose your place, and the card
    // asks for "no accidental edits while playing".
    if (_playing) return;

    setState(() => _selected = ref);
    final bar = _chart.sections[ref.sectionIndex].bars[ref.barIndex];
    final current =
        bar.chordsInOrder.isEmpty ? null : bar.chordsInOrder.first.chord;

    final result = await showChordKeypad(context, initial: current);
    if (!mounted || result == null) return;

    final chosen = switch (result) {
      ChordChosen(:final chord) => chord,
      ChordCleared() => null,
    };
    setState(() {
      _chart = _replaceBar(_chart, ref, barWithChord(bar, chosen));
      _selected = null;
    });
  }

  static Chart _replaceBar(Chart chart, ChartBarRef ref, ChartBar bar) {
    final sections = [
      for (var s = 0; s < chart.sections.length; s++)
        if (s != ref.sectionIndex)
          chart.sections[s]
        else
          ChartSection(
            label: chart.sections[s].label,
            repeatCount: chart.sections[s].repeatCount,
            feel: chart.sections[s].feel,
            tempoScale: chart.sections[s].tempoScale,
            intensity: chart.sections[s].intensity,
            extra: chart.sections[s].extra,
            bars: [
              for (var b = 0; b < chart.sections[s].bars.length; b++)
                if (b == ref.barIndex) bar else chart.sections[s].bars[b],
            ],
          ),
    ];
    return Chart(
      title: chart.title,
      composer: chart.composer,
      keyFifths: chart.keyFifths,
      minor: chart.minor,
      meter: chart.meter,
      tempoBpm: chart.tempoBpm,
      styleId: chart.styleId,
      sections: sections,
      pickupBeats: chart.pickupBeats,
      extra: chart.extra,
    );
  }

  Future<void> _editAsText() async {
    if (_playing) await _stop();
    if (!mounted) return;
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => _ChartTextDialog(initial: formatChartText(_chart)),
    );
    if (!mounted || edited == null) return;

    final result = parseChartText(edited, defaults: _chart);
    setState(() => _chart = result.chart);

    // An unreadable chord is kept, so the chart is never silently shortened —
    // but the user has to be told which one, or they will not find it.
    if (!result.isClean && mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.chartUnreadableChords(
              result.problems.length,
              result.problems.map((p) => p.text).take(3).join(', '),
            ),
          ),
        ),
      );
    }
  }

  void _setTempo(int bpm) => setState(() {
        _chart = _ChartHeader.withTempo(_chart, bpm.clamp(40, 300));
      });

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_chart.title.isEmpty ? l10n.gameChart : _chart.title),
        actions: [
          IconButton(
            tooltip: l10n.chartEditAsText,
            icon: const Icon(Icons.edit_note),
            onPressed: _editAsText,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: ChartGridView(
                chart: _chart,
                playingBar: _playingBar,
                selected: _selected,
                onTapBar: _editBar,
              ),
            ),
          ),
          _transport(context, l10n, theme),
        ],
      ),
    );
  }

  Widget _transport(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) =>
      Material(
        elevation: 8,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                FilledButton.icon(
                  key: const Key('chartPlayButton'),
                  onPressed: _playing ? _stop : _play,
                  icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
                  label: Text(_playing ? l10n.chartStop : l10n.chartPlay),
                ),
                const SizedBox(width: 16),
                Text('${_chart.tempoBpm}', style: theme.textTheme.titleMedium),
                Text(
                  ' ${l10n.chartBpm}',
                  style: theme.textTheme.bodySmall,
                ),
                Expanded(
                  child: Slider(
                    value: _chart.tempoBpm.toDouble().clamp(40, 300),
                    min: 40,
                    max: 300,
                    // Changing tempo mid-playback would desync the highlight
                    // from audio that is already rendered and playing.
                    onChanged: _playing ? null : (v) => _setTempo(v.round()),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Rebuilding a `Chart` with one field changed. The model is immutable and has
/// no `copyWith`, and hand-rolling the full constructor at each call site is
/// exactly how a field gets quietly dropped.
class _ChartHeader {
  static Chart withTempo(Chart chart, int bpm) => Chart(
        title: chart.title,
        composer: chart.composer,
        keyFifths: chart.keyFifths,
        minor: chart.minor,
        meter: chart.meter,
        tempoBpm: bpm,
        styleId: chart.styleId,
        sections: chart.sections,
        pickupBeats: chart.pickupBeats,
        extra: chart.extra,
      );
}

class _ChartTextDialog extends StatefulWidget {
  const _ChartTextDialog({required this.initial});
  final String initial;

  @override
  State<_ChartTextDialog> createState() => _ChartTextDialogState();
}

class _ChartTextDialogState extends State<_ChartTextDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.chartEditAsText),
      content: SizedBox(
        width: 520,
        child: TextField(
          key: const Key('chartTextField'),
          controller: _controller,
          maxLines: 16,
          minLines: 8,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            helperText: l10n.chartTextHelp,
            helperMaxLines: 3,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.chartCancel),
        ),
        FilledButton(
          key: const Key('chartTextApply'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.chartOk),
        ),
      ],
    );
  }
}
