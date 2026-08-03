// lib/features/harmony/gig_mode_screen.dart
//
// BB-U4b — gig mode: the set, on stage.
//
// This is a READING surface, not an editing one, and the difference is the
// whole design. On a stand at a gig you need one thing legible from a metre
// away, you need to get to the next tune without looking, and you must not be
// able to change the chart by brushing the screen.
//
// It composes `ChartGridView` rather than re-rendering anything:
//   · `onTapBar: null`      — edits are OFF, structurally, not by a flag a
//                             future caller could forget to pass.
//   · a large `minBarWidth` — fewer, bigger bars per row.
// Everything a player sees here is the chart AS THE SET ASKS FOR IT
// (`resolveEntry`), so a tune re-keyed for this gig reads in its gig key.
library;

import 'dart:async';

import 'package:comet_beat/core/harmony/band_playback.dart';
import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/setlist.dart';
import 'package:comet_beat/core/harmony/style_library.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/chart_store.dart';
import 'package:comet_beat/features/harmony/chart_grid_view.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the device awake while a set is on screen.
///
/// A seam rather than a direct call, for two reasons that both still hold now
/// that it is implemented: a widget test must be able to assert WHEN the screen
/// is asked to stay awake without a platform channel, and a host that does not
/// want the behaviour can pass [none].
abstract class KeepAwake {
  const KeepAwake();

  /// Does nothing. Kept for tests and for a host that wants gig mode without
  /// touching the device's screen policy.
  static const KeepAwake none = _NoKeepAwake();

  /// The real one — `wakelock_plus`.
  static const KeepAwake platform = _PlatformKeepAwake();

  Future<void> enable();
  Future<void> disable();
}

class _NoKeepAwake extends KeepAwake {
  const _NoKeepAwake();
  @override
  Future<void> enable() async {}
  @override
  Future<void> disable() async {}
}

class _PlatformKeepAwake extends KeepAwake {
  const _PlatformKeepAwake();

  /// ⚠️ Every call is guarded. A wake lock is a NICE-TO-HAVE — on a platform
  /// with no implementation, or in a test with no plugin registered, the
  /// channel throws, and a set that will not open because the screen could not
  /// be kept on is a far worse outcome than a screen that dims.
  @override
  Future<void> enable() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // The set still opens.
    }
  }

  @override
  Future<void> disable() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {
      // Nothing to release, or nothing that can release it.
    }
  }
}

/// What happens when a song reaches its end.
enum GigEnding {
  /// Stay put and stop the band.
  stop,

  /// Move to the next song and keep playing.
  advance,
}

/// The decision taken when the playhead runs out.
///
/// Pulled out of the widget so it can be tested exhaustively without a clock:
/// `testWidgets` runs in a FAKE-async zone while the playhead is a real
/// `Stopwatch`, so a widget test cannot drive a song to its end without
/// deadlocking — awaiting a faked delay that only advances when pumped.
///
/// It also states the rule that is easy to get wrong: at the END of the set it
/// STOPS rather than wrapping round, for the same reason `next` is a dead end
/// there. The set finished.
GigEnding gigEnding({
  required bool autoAdvance,
  required int index,
  required int lastIndex,
}) =>
    autoAdvance && index < lastIndex ? GigEnding.advance : GigEnding.stop;

/// One setlist, one song at a time, big.
class GigModeScreen extends StatefulWidget {
  const GigModeScreen({
    required this.setlist,
    required this.charts,
    this.startIndex = 0,
    this.keepAwake = KeepAwake.platform,
    this.audio,
    super.key,
  });

  final Setlist setlist;
  final ChartStore charts;
  final int startIndex;
  final KeepAwake keepAwake;

  /// Plays the band. Optional, and passed in rather than read from the provider
  /// tree ON PURPOSE: a screen that reads a service from context breaks every
  /// minimal host that does not supply one, which is a mistake this arc already
  /// made once. Absent ⇒ gig mode is the reading surface it has always been,
  /// with no transport and no auto-advance — degraded honestly, not crashed.
  final AudioService? audio;

  @override
  State<GigModeScreen> createState() => _GigModeScreenState();
}

class _GigModeScreenState extends State<GigModeScreen> {
  late int _index = widget.startIndex.clamp(
    0,
    widget.setlist.entries.isEmpty ? 0 : widget.setlist.entries.length - 1,
  );

  /// Auto-advance is OFF by default. A set that starts moving on its own is
  /// alarming the first time; a player who wants it will find the switch.
  var _autoAdvance = false;
  bool _playing = false;
  Timer? _ticker;
  Stopwatch? _clock;
  int _songMs = 0;

  @override
  void initState() {
    super.initState();
    widget.keepAwake.enable();
  }

  @override
  void dispose() {
    // Released on the way out, not left on: a phone that never sleeps again
    // after one gig is a bug the user blames on the app, correctly.
    widget.keepAwake.disable();
    _ticker?.cancel();
    widget.audio?.stop();
    super.dispose();
  }

  /// Renders the current song and plays it.
  Future<void> _play() async {
    final audio = widget.audio;
    final chart = _chart;
    if (audio == null || chart == null) return;

    final band = renderBand(chart, style: styleFor(chart.styleId));
    if (band == null) return;

    _stopClock();
    setState(() {
      _playing = true;
      _songMs = band.totalMs;
    });
    _clock = Stopwatch()..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    await audio.playWavBytes(band.wav);
  }

  void _stopClock() {
    _ticker?.cancel();
    _ticker = null;
    _clock = null;
  }

  Future<void> _stop() async {
    _stopClock();
    if (mounted) setState(() => _playing = false);
    await widget.audio?.stop();
  }

  void _tick() {
    final clock = _clock;
    if (clock == null) return;
    if (clock.elapsedMilliseconds < _songMs) return;

    // The song ended.
    _stopClock();
    final ending = gigEnding(
      autoAdvance: _autoAdvance,
      index: _index,
      lastIndex: widget.setlist.entries.length - 1,
    );
    switch (ending) {
      case GigEnding.advance:
        setState(() => _index++);
        unawaited(_play());
      case GigEnding.stop:
        setState(() => _playing = false);
    }
  }

  SetlistEntry? get _entry =>
      widget.setlist.entries.isEmpty ? null : widget.setlist.entries[_index];

  /// The chart for the current entry, resolved to this gig's key and tempo.
  /// Null when the chart is missing or unreadable — both of which the set
  /// shows rather than hides.
  Chart? get _chart {
    final entry = _entry;
    if (entry == null) return null;
    for (final saved in widget.charts.list()) {
      if (saved.name != entry.chartName) continue;
      final chart = saved.chart;
      return chart == null ? null : resolveEntry(chart, entry);
    }
    return null;
  }

  void _go(int delta) {
    final last = widget.setlist.entries.length - 1;
    final next = _index + delta;
    if (next < 0 || next > last) return;
    // Moving by hand stops the band. Leaving the previous song playing under
    // the new chart is the one behaviour nobody wants on a stand.
    unawaited(_stop());
    setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final entry = _entry;
    final chart = _chart;
    final total = widget.setlist.entries.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(entry?.chartName ?? widget.setlist.name),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                total == 0 ? '' : l10n.gigPosition(_index + 1, total),
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
        ],
      ),
      body: entry == null
          ? Center(child: Text(l10n.setlistNoSongs))
          : Column(
              children: [
                // The player's own cue for this song, if they left one. First
                // thing on the page, because "capo 3" is no use after the
                // count-in.
                if (entry.note != null && entry.note!.isNotEmpty)
                  Container(
                    width: double.infinity,
                    color: theme.colorScheme.secondaryContainer,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Text(
                      entry.note!,
                      key: const ValueKey('gigCue'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                Expanded(
                  child: chart == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              l10n.setlistMissingHint,
                              key: const ValueKey('gigMissing'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: ChartGridView(
                            chart: chart,
                            // Edits are off by construction: no callback means
                            // there is nothing to forget to disable.
                            minBarWidth: 150,
                          ),
                        ),
                ),
                if (widget.audio != null) _playbackRow(l10n),
                _transport(l10n, total),
              ],
            ),
    );
  }

  /// Play/stop and the auto-advance switch. Present only when a player was
  /// supplied — see [GigModeScreen.audio].
  Widget _playbackRow(AppLocalizations l10n) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                key: const ValueKey('gigPlay'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: _playing ? _stop : _play,
                icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
                label: Text(_playing ? l10n.gigPause : l10n.gigPlay),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SwitchListTile(
                key: const ValueKey('gigAutoAdvance'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  l10n.gigAutoAdvance,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                value: _autoAdvance,
                onChanged: (on) => setState(() => _autoAdvance = on),
              ),
            ),
          ],
        ),
      );

  Widget _transport(AppLocalizations l10n, int total) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const ValueKey('gigPrev'),
                  // Big targets: this is pressed without looking.
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(64),
                  ),
                  onPressed: _index > 0 ? () => _go(-1) : null,
                  icon: const Icon(Icons.skip_previous),
                  label: Text(l10n.gigPrev),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('gigNext'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(64),
                  ),
                  onPressed: _index < total - 1 ? () => _go(1) : null,
                  icon: const Icon(Icons.skip_next),
                  label: Text(
                    _index < total - 1 ? l10n.gigNext : l10n.gigEnd,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
