// Guitar chord diagrams for the Tab Workshop. crisp_notation ships the
// `ChordDiagram` model + uke/banjo/mandolin presets but NO standard-guitar
// presets and NO render widget, so both live here (app-side). Frets are in
// tuning order — index 0 is the top tab line (high E), matching `Tuning`;
// 0 = open, -1 = muted (×), n = fretted.

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart';

/// Common open-position guitar chords, keyed by name. Order: high-E → low-E.
const Map<String, ChordDiagram> kGuitarChords = {
  'C': ChordDiagram([0, 1, 0, 2, 3, -1], name: 'C'),
  'G': ChordDiagram([3, 0, 0, 0, 2, 3], name: 'G'),
  'D': ChordDiagram([2, 3, 2, 0, -1, -1], name: 'D'),
  'A': ChordDiagram([0, 2, 2, 2, 0, -1], name: 'A'),
  'E': ChordDiagram([0, 0, 1, 2, 2, 0], name: 'E'),
  'Am': ChordDiagram([0, 1, 2, 2, 0, -1], name: 'Am'),
  'Em': ChordDiagram([0, 0, 0, 2, 2, 0], name: 'Em'),
  'Dm': ChordDiagram([1, 3, 2, 0, -1, -1], name: 'Dm'),
  'F': ChordDiagram([1, 1, 2, 3, 3, 1], name: 'F', barreFret: 1),
  'A7': ChordDiagram([0, 2, 0, 2, 0, -1], name: 'A7'),
  'E7': ChordDiagram([0, 0, 1, 0, 2, 0], name: 'E7'),
  'D7': ChordDiagram([2, 1, 2, 0, -1, -1], name: 'D7'),
  'G7': ChordDiagram([1, 0, 0, 0, 2, 3], name: 'G7'),
  'C7': ChordDiagram([0, 1, 3, 2, 3, -1], name: 'C7'),
  'B7': ChordDiagram([2, 0, 2, 1, 2, -1], name: 'B7'),
};

/// Draws a [ChordDiagram] as a compact fretboard grid (name, nut, dots, and
/// o/× markers over open/muted strings). Sizes itself from the string count.
class ChordDiagramView extends StatelessWidget {
  final ChordDiagram diagram;
  final double stringGap;
  final double fretGap;

  const ChordDiagramView(
    this.diagram, {
    super.key,
    this.stringGap = 10,
    this.fretGap = 12,
  });

  @override
  Widget build(BuildContext context) {
    final n = diagram.frets.length;
    final width = (n - 1) * stringGap + 16;
    final height = diagram.fretSpan * fretGap + 24;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _ChordPainter(
          diagram,
          stringGap,
          fretGap,
          Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _ChordPainter extends CustomPainter {
  final ChordDiagram d;
  final double sGap;
  final double fGap;
  final Color color;

  _ChordPainter(this.d, this.sGap, this.fGap, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final n = d.frets.length;
    const left = 8.0;
    const top = 16.0;
    final gridW = (n - 1) * sGap;
    final line = Paint()
      ..color = color
      ..strokeWidth = 1;
    final dot = Paint()..color = color;

    // Name.
    if (d.name != null) {
      _text(
        canvas,
        d.name!,
        Offset(left + gridW / 2, 0),
        center: true,
        bold: true,
      );
    }

    // Fret rows (baseFret 1 draws a thick nut on top).
    for (var r = 0; r <= d.fretSpan; r++) {
      final y = top + r * fGap;
      final p = (r == 0 && d.baseFret == 1)
          ? (Paint()
            ..color = color
            ..strokeWidth = 3)
          : line;
      canvas.drawLine(Offset(left, y), Offset(left + gridW, y), p);
    }
    // String columns.
    for (var s = 0; s < n; s++) {
      final x = left + s * sGap;
      canvas.drawLine(Offset(x, top), Offset(x, top + d.fretSpan * fGap), line);
    }

    // Open / muted markers + fretted dots. String index 0 is drawn on the LEFT
    // (top tab line) to match the tab grid orientation.
    for (var s = 0; s < n; s++) {
      final x = left + s * sGap;
      final f = d.frets[s];
      if (f < 0) {
        _text(canvas, '×', Offset(x, 2), center: true);
      } else if (f == 0) {
        _text(canvas, 'o', Offset(x, 2), center: true);
      } else {
        final row = f - (d.baseFret - 1);
        final y = top + (row - 0.5) * fGap;
        canvas.drawCircle(Offset(x, y), 3.2, dot);
      }
    }
  }

  void _text(
    Canvas canvas,
    String s,
    Offset at, {
    bool center = false,
    bool bold = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at.translate(center ? -tp.width / 2 : 0, 0));
  }

  @override
  bool shouldRepaint(_ChordPainter old) => old.d != d || old.color != color;
}
