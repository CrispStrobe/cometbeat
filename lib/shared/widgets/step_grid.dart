// lib/shared/widgets/step_grid.dart
//
// The app's shared step-grid / mini piano-roll — one widget that SHOWS a
// pattern (so a kid sees what a layer/track plays) and, when given [onToggle],
// lets them TAP a cell to change it. It backs both the Live Looper's per-layer
// rolls and the Loop Mixer's beat/tune editors, so there is one editor to
// maintain.
//
// Two row modes:
//   • percussive: 3 drum lanes (0 hat · 1 snare · 2 kick).
//   • melodic:    a fixed [melodyRows] pitch grid (ascending MIDI); each cell's
//                 pitch snaps to its nearest row, and taps only land on those
//                 rows (so a diatonic grid keeps everything consonant).

import 'dart:math';

import 'package:flutter/material.dart';

/// One placed event on the grid: [row] is a MIDI pitch (melodic) or a drum lane
/// (percussive), [step] is a 16th column, [len] the length in steps.
class StepCell {
  const StepCell(this.row, this.step, {this.len = 1});
  final int row;
  final int step;
  final int len;
}

class StepGridView extends StatelessWidget {
  const StepGridView({
    super.key,
    required this.cells,
    required this.steps,
    this.percussive = false,
    this.melodyRows = const [],
    this.playStep,
    this.onToggle,
    this.height,
  });

  final List<StepCell> cells;
  final int steps;
  final bool percussive;

  /// The melodic pitch grid (ascending MIDI); ignored when [percussive].
  final List<int> melodyRows;

  /// The step the transport is on (a translucent playhead column), or null.
  final int? playStep;

  /// Tap-to-toggle. The callback gets the STORED row value (a drum lane for
  /// beats, a MIDI pitch for melodies) and the step. Null = read-only.
  final void Function(int row, int step)? onToggle;

  /// Optional fixed height; defaults to 36 (percussive) / 78 (melodic).
  final double? height;

  int get _rowCount =>
      percussive ? 3 : (melodyRows.isEmpty ? 1 : melodyRows.length);
  double get _h => height ?? (percussive ? 36 : 78);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paint = CustomPaint(
      painter: _StepGridPainter(
        cells: cells,
        percussive: percussive,
        steps: steps,
        playStep: playStep,
        melodyRows: melodyRows,
        fill: scheme.primary,
        grid: scheme.outlineVariant,
        bar: scheme.outline,
        bg: scheme.surfaceContainerHighest,
        play: scheme.tertiary,
      ),
    );
    final editable = onToggle != null && steps > 0 && _rowCount > 0;
    return SizedBox(
      height: _h,
      width: double.infinity,
      child: editable
          ? LayoutBuilder(
              builder: (context, c) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) {
                  final step = (d.localPosition.dx / c.maxWidth * steps)
                      .floor()
                      .clamp(0, steps - 1);
                  final yRow = (d.localPosition.dy / _h * _rowCount)
                      .floor()
                      .clamp(0, _rowCount - 1);
                  final int stored;
                  if (percussive) {
                    stored = yRow; // 0 hat · 1 snare · 2 kick
                  } else {
                    stored =
                        melodyRows[(_rowCount - 1) - yRow]; // top = highest
                  }
                  onToggle!(stored, step);
                },
                child: paint,
              ),
            )
          : paint,
    );
  }
}

class _StepGridPainter extends CustomPainter {
  _StepGridPainter({
    required this.cells,
    required this.percussive,
    required this.steps,
    required this.playStep,
    required this.melodyRows,
    required this.fill,
    required this.grid,
    required this.bar,
    required this.bg,
    required this.play,
  });
  final List<StepCell> cells;
  final bool percussive;
  final int steps;
  final int? playStep;
  final List<int> melodyRows;
  final Color fill;
  final Color grid;
  final Color bar;
  final Color bg;
  final Color play;

  @override
  void paint(Canvas canvas, Size size) {
    if (steps <= 0) return;
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(4),
    );
    canvas.drawRRect(r, Paint()..color = bg);
    canvas.save();
    canvas.clipRRect(r);

    final stepW = size.width / steps;

    // The playhead column, under the notes.
    final ps = playStep;
    if (ps != null && ps >= 0 && ps < steps) {
      canvas.drawRect(
        Rect.fromLTWH(ps * stepW, 0, stepW, size.height),
        Paint()..color = play.withValues(alpha: 0.35),
      );
    }
    // Beat lines every 4 steps; heavier bar lines every 16.
    for (var s = 4; s < steps; s += 4) {
      final x = s * stepW;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = s % 16 == 0 ? bar : grid
          ..strokeWidth = s % 16 == 0 ? 1.2 : 0.6,
      );
    }

    // Rows: 3 drum lanes, or the melodic pitch grid (nearest degree).
    final int rows;
    int Function(StepCell) rowOf = (_) => 0;
    if (percussive) {
      rows = 3;
      rowOf = (c) => c.row.clamp(0, 2);
    } else if (melodyRows.isNotEmpty) {
      rows = melodyRows.length;
      rowOf = (c) {
        var best = 0;
        var bd = 1 << 30;
        for (var i = 0; i < melodyRows.length; i++) {
          final d = (melodyRows[i] - c.row).abs();
          if (d < bd) {
            bd = d;
            best = i;
          }
        }
        return (rows - 1) - best; // higher pitch → top
      };
    } else if (cells.isEmpty) {
      rows = 1;
    } else {
      final lo = cells.map((c) => c.row).reduce(min);
      final hi = cells.map((c) => c.row).reduce(max);
      rows = (hi - lo + 1).clamp(1, 24);
      rowOf = (c) => (hi - c.row).clamp(0, rows - 1);
    }

    // Faint row separators for the melody grid (readability).
    if (!percussive && rows > 1) {
      for (var i = 1; i < rows; i++) {
        final y = i * size.height / rows;
        canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          Paint()
            ..color = grid
            ..strokeWidth = 0.4,
        );
      }
    }

    final rowH = size.height / rows;
    final cellPaint = Paint()..color = fill;
    for (final c in cells) {
      final x = c.step * stepW;
      final w = max(stepW * c.len - 1, 2.0);
      final y = rowOf(c) * rowH;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 0.5, y + 1, w, max(rowH - 2, 2)),
          const Radius.circular(2),
        ),
        cellPaint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StepGridPainter old) =>
      old.cells != cells ||
      old.steps != steps ||
      old.percussive != percussive ||
      old.playStep != playStep ||
      old.melodyRows != melodyRows ||
      old.fill != fill;
}
