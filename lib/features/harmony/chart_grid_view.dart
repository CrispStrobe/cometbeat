// lib/features/harmony/chart_grid_view.dart
//
// BB-U1 — the chart view. Readable at a music stand, at arm's length, in a dim
// room.
//
// This is deliberately NOT notation. There are no staves and no noteheads: a
// chart is a grid of bars with chord names in them, and the thing that makes it
// usable on a stand is that the chord type stays large. Everything here serves
// that — the bars-per-row count comes from the available width rather than being
// fixed, so a phone in portrait gets two big bars rather than four unreadable
// ones.
//
// Stateless on purpose. It renders a `Chart` and reports taps; the screen owns
// the chart, the transport and the editing. That keeps it testable without a
// player and without an audio service.
library;

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:flutter/material.dart';

/// Where a bar lives in the DOCUMENT, as opposed to in play order.
///
/// A tap has to edit the bar the user pointed at, and with repeats expanded
/// several played bars share one document bar. Play order alone cannot say
/// which one to edit, so taps report this instead of a flat index.
class ChartBarRef {
  const ChartBarRef(this.sectionIndex, this.barIndex);

  final int sectionIndex;
  final int barIndex;

  @override
  bool operator ==(Object other) =>
      other is ChartBarRef &&
      other.sectionIndex == sectionIndex &&
      other.barIndex == barIndex;

  @override
  int get hashCode => Object.hash(sectionIndex, barIndex);

  @override
  String toString() => 'ChartBarRef($sectionIndex, $barIndex)';
}

/// A chord chart as a grid of bars.
class ChartGridView extends StatefulWidget {
  const ChartGridView({
    super.key,
    required this.chart,
    this.playingBar,
    this.selected,
    this.onTapBar,
    this.style = ChordSymbolStyle.plain,
    this.minBarWidth = 132,
    this.autoScroll = true,
  });

  final Chart chart;

  /// The bar currently sounding, in DOCUMENT terms, or null when stopped.
  final ChartBarRef? playingBar;

  /// The bar being edited.
  final ChartBarRef? selected;

  final void Function(ChartBarRef ref)? onTapBar;

  /// How chord symbols are spelled (♭ vs b, ∆ vs maj7, H vs B).
  final ChordSymbolStyle style;

  /// The narrowest a bar may become before the row holds fewer of them. This is
  /// what keeps the chord type legible instead of letting four bars squeeze
  /// onto a phone.
  final double minBarWidth;

  /// Keep the playing bar on screen. Off for a static render (a test, a
  /// screenshot) and harmless when there is no enclosing scrollable.
  final bool autoScroll;

  @override
  State<ChartGridView> createState() => _ChartGridViewState();
}

class _ChartGridViewState extends State<ChartGridView> {
  /// One key per DOCUMENT bar, so `ensureVisible` can be handed the real box.
  /// Rebuilt lazily and pruned with the chart, since a chart is tens of bars.
  final _keys = <ChartBarRef, GlobalKey>{};

  GlobalKey _keyFor(ChartBarRef ref) => _keys.putIfAbsent(ref, GlobalKey.new);

  @override
  void didUpdateWidget(ChartGridView old) {
    super.didUpdateWidget(old);
    if (!identical(old.chart, widget.chart)) _keys.clear();
    if (widget.playingBar != old.playingBar) _followPlayhead();
  }

  /// Brings the playing bar into view.
  ///
  /// Fires only when the bar CHANGES, which is what "never scrolls during a
  /// bar" means: at any sane tempo that is seconds apart, so the page moves
  /// once per bar rather than continuously under the reader's eye. Centred,
  /// because a bar pinned to the top edge gives no sight of what is coming.
  void _followPlayhead() {
    if (!widget.autoScroll) return;
    final ref = widget.playingBar;
    if (ref == null) return;
    // After this frame: the bar may not be laid out yet on the first change.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _keys[ref]?.currentContext;
      if (context == null || !mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOut,
      );
    });
  }

  Chart get chart => widget.chart;
  ChartBarRef? get playingBar => widget.playingBar;
  ChartBarRef? get selected => widget.selected;
  void Function(ChartBarRef)? get onTapBar => widget.onTapBar;
  ChordSymbolStyle get style => widget.style;
  double get minBarWidth => widget.minBarWidth;

  @override
  Widget build(BuildContext context) {
    if (chart.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Conventional lead-sheet row is four bars; narrow screens step down to
        // two and then one rather than shrinking the type.
        final available = constraints.maxWidth;
        var perRow = 4;
        while (perRow > 1 && available / perRow < minBarWidth) {
          perRow = perRow == 4 ? 2 : 1;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var s = 0; s < chart.sections.length; s++)
              _section(context, s, chart.sections[s], perRow),
          ],
        );
      },
    );
  }

  Widget _section(
    BuildContext context,
    int sectionIndex,
    ChartSection section,
    int perRow,
  ) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < section.bars.length; i += perRow) {
      final end = (i + perRow).clamp(0, section.bars.length);
      rows.add(
        Row(
          children: [
            for (var b = i; b < end; b++)
              Expanded(
                child: _bar(
                  context,
                  ChartBarRef(sectionIndex, b),
                  section.bars[b],
                ),
              ),
            // Pads a short final row so its bars keep the width of the rows
            // above instead of stretching to fill.
            for (var b = end; b < i + perRow; b++)
              const Expanded(child: SizedBox.shrink()),
          ],
        ),
      );
    }

    final hasHeader = section.label.isNotEmpty || section.passes > 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasHeader)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                children: [
                  if (section.label.isNotEmpty)
                    Text(
                      section.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  if (section.passes > 1) ...[
                    const SizedBox(width: 8),
                    Text(
                      '×${section.passes}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ...rows,
        ],
      ),
    );
  }

  Widget _bar(BuildContext context, ChartBarRef ref, ChartBar bar) {
    final theme = Theme.of(context);
    final isPlaying = ref == playingBar;
    final isSelected = ref == selected;

    final Color background;
    if (isPlaying) {
      background = theme.colorScheme.primaryContainer;
    } else if (isSelected) {
      background = theme.colorScheme.secondaryContainer;
    } else {
      background = theme.colorScheme.surface;
    }

    return Semantics(
      key: _keyFor(ref),
      button: onTapBar != null,
      selected: isSelected,
      // The chord names are the label a screen reader should read; an empty bar
      // says so in words rather than reading out a percent sign.
      label: _semanticLabel(bar),
      child: InkWell(
        onTap: onTapBar == null ? null : () => onTapBar!(ref),
        child: Container(
          height: 64,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: background,
            border: Border.all(
              color: isPlaying
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: isPlaying ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: _barContent(context, bar),
        ),
      ),
    );
  }

  Widget _barContent(BuildContext context, ChartBar bar) {
    final theme = Theme.of(context);
    final chords = bar.chordsInOrder;

    if (chords.isEmpty) {
      // A held bar. The percent sign IS the notation for it, so it is shown
      // rather than an empty box, which would read as "not filled in yet".
      return Text(
        '%',
        style: theme.textTheme.headlineSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    // One chord fills the bar; several share it, which is what a split bar
    // looks like on paper.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final chord in chords)
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  chord.chord.format(style: style),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _semanticLabel(ChartBar bar) {
    final chords = bar.chordsInOrder;
    if (chords.isEmpty) return 'repeat previous bar';
    return chords.map((c) => c.chord.format(style: style)).join(', ');
  }
}
