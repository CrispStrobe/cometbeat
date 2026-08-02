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

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_codec.dart';
import 'package:comet_beat/core/harmony/setlist.dart';
import 'package:comet_beat/core/services/chart_store.dart';
import 'package:comet_beat/features/harmony/chart_grid_view.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Keeps the device awake while a set is on screen.
///
/// ⚠️ A SEAM, not an implementation. Keeping the screen on needs a platform
/// plugin, which means a `pubspec.yaml` change plus per-platform verification —
/// not something to add unilaterally mid-session. The default does nothing, so
/// gig mode works today and gains the behaviour when the plugin lands, without
/// this screen changing. Tests substitute a recorder to prove it is asked at
/// the right moments.
abstract class KeepAwake {
  const KeepAwake();

  /// The default: does nothing, and says so rather than pretending.
  static const KeepAwake none = _NoKeepAwake();

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

/// One setlist, one song at a time, big.
class GigModeScreen extends StatefulWidget {
  const GigModeScreen({
    required this.setlist,
    required this.charts,
    this.startIndex = 0,
    this.keepAwake = KeepAwake.none,
    super.key,
  });

  final Setlist setlist;
  final ChartStore charts;
  final int startIndex;
  final KeepAwake keepAwake;

  @override
  State<GigModeScreen> createState() => _GigModeScreenState();
}

class _GigModeScreenState extends State<GigModeScreen> {
  late int _index = widget.startIndex.clamp(
    0,
    widget.setlist.entries.isEmpty ? 0 : widget.setlist.entries.length - 1,
  );

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
    super.dispose();
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
      final chart = chartFromJsonString(saved.json);
      return chart == null ? null : resolveEntry(chart, entry);
    }
    return null;
  }

  void _go(int delta) {
    final last = widget.setlist.entries.length - 1;
    final next = _index + delta;
    if (next < 0 || next > last) return;
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
                _transport(l10n, total),
              ],
            ),
    );
  }

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
