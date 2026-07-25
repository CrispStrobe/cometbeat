// A DRAWABLE automation curve — drag the shape instead of typing numbers.
//
// The DAW already stored breakpoint automation (gain, pan, any FX parameter)
// and could already play it back; what was missing was a way to SEE and shape
// it. Typing "at 1200 ms, 0.4" into a list is not how anyone draws a fade.
//
// Drag a handle to move it in time and value · tap empty space to add a point
// there · long-press a handle to delete it. The numeric list stays alongside
// this for precise values and for anyone who can't drag.

import 'package:comet_beat/core/audio/daw_timeline.dart'
    show DawAutomationPoint, DawFadeCurve;
import 'package:flutter/material.dart';

class AutomationCurveEditor extends StatefulWidget {
  const AutomationCurveEditor({
    required this.points,
    required this.min,
    required this.max,
    required this.timeMax,
    required this.onChanged,
    this.height = 160,
    super.key,
  });

  /// Breakpoints, sorted by time.
  final List<DawAutomationPoint> points;

  /// Value axis bounds (e.g. 0…2 for a gain multiplier, −1…1 for pan).
  final double min;
  final double max;

  /// Time axis length in ms.
  final double timeMax;

  final ValueChanged<List<DawAutomationPoint>> onChanged;
  final double height;

  @override
  State<AutomationCurveEditor> createState() => _AutomationCurveEditorState();
}

class _AutomationCurveEditorState extends State<AutomationCurveEditor> {
  /// The handle being dragged, or -1.
  int _dragging = -1;

  /// How close (px) a touch has to be to grab a handle rather than add one.
  static const double _grabRadius = 24;

  Offset _toPixels(DawAutomationPoint p, Size size) {
    final span = widget.max - widget.min;
    final x = widget.timeMax <= 0 ? 0.0 : p.ms / widget.timeMax * size.width;
    final y = span <= 0
        ? size.height / 2
        : (1 - (p.value - widget.min) / span) * size.height;
    return Offset(x.clamp(0, size.width), y.clamp(0, size.height));
  }

  DawAutomationPoint _fromPixels(Offset at, Size size, DawFadeCurve curve) {
    final ms = size.width <= 0
        ? 0.0
        : (at.dx / size.width * widget.timeMax).clamp(0.0, widget.timeMax);
    final span = widget.max - widget.min;
    final value = size.height <= 0
        ? widget.min
        : (widget.min + (1 - at.dy / size.height) * span)
            .clamp(widget.min, widget.max);
    return DawAutomationPoint(ms: ms, value: value.toDouble(), curve: curve);
  }

  int _handleNear(Offset at, Size size) {
    var best = -1;
    var bestDistance = _grabRadius;
    for (var i = 0; i < widget.points.length; i++) {
      final d = (_toPixels(widget.points[i], size) - at).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  void _emit(List<DawAutomationPoint> next) {
    next.sort((a, b) => a.ms.compareTo(b.ms));
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, widget.height);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            // A tap on empty canvas adds a point there; on a handle it does
            // nothing (dragging is the verb for handles).
            if (_handleNear(d.localPosition, size) >= 0) return;
            final curve = widget.points.isEmpty
                ? DawFadeCurve.linear
                : widget.points.first.curve;
            _emit([
              ...widget.points,
              _fromPixels(d.localPosition, size, curve),
            ]);
          },
          onLongPressStart: (d) {
            final i = _handleNear(d.localPosition, size);
            // Keep at least two points — a curve needs somewhere to go.
            if (i < 0 || widget.points.length <= 2) return;
            _emit([...widget.points]..removeAt(i));
          },
          onPanStart: (d) => setState(
            () => _dragging = _handleNear(d.localPosition, size),
          ),
          onPanUpdate: (d) {
            if (_dragging < 0 || _dragging >= widget.points.length) return;
            final moved = [...widget.points];
            final old = moved[_dragging];
            final next = _fromPixels(d.localPosition, size, old.curve);
            moved[_dragging] = next;
            // Re-sorting can move this point's index; follow it so the drag
            // doesn't jump to a different handle mid-gesture.
            moved.sort((a, b) => a.ms.compareTo(b.ms));
            final at = moved.indexOf(next);
            if (at >= 0) _dragging = at;
            widget.onChanged(moved);
          },
          onPanEnd: (_) => setState(() => _dragging = -1),
          onPanCancel: () => setState(() => _dragging = -1),
          child: SizedBox(
            width: constraints.maxWidth,
            height: widget.height,
            child: CustomPaint(
              painter: _AutomationCurvePainter(
                points: widget.points,
                toPixels: _toPixels,
                dragging: _dragging,
                line: scheme.primary,
                handle: scheme.primary,
                active: scheme.tertiary,
                grid: scheme.outlineVariant,
                fill: scheme.primary.withValues(alpha: 0.12),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AutomationCurvePainter extends CustomPainter {
  const _AutomationCurvePainter({
    required this.points,
    required this.toPixels,
    required this.dragging,
    required this.line,
    required this.handle,
    required this.active,
    required this.grid,
    required this.fill,
  });

  final List<DawAutomationPoint> points;
  final Offset Function(DawAutomationPoint, Size) toPixels;
  final int dragging;
  final Color line;
  final Color handle;
  final Color active;
  final Color grid;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    // Quarter lines give the eye something to judge the shape against.
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (points.isEmpty) return;
    final pixels = [for (final p in points) toPixels(p, size)];

    // The area under the curve, so the shape reads at a glance.
    final area = Path()..moveTo(pixels.first.dx, size.height);
    for (final p in pixels) {
      area.lineTo(p.dx, p.dy);
    }
    area
      ..lineTo(pixels.last.dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);

    final path = Path()..moveTo(pixels.first.dx, pixels.first.dy);
    for (final p in pixels.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    for (var i = 0; i < pixels.length; i++) {
      canvas.drawCircle(
        pixels[i],
        i == dragging ? 8 : 6,
        Paint()..color = i == dragging ? active : handle,
      );
    }
  }

  @override
  bool shouldRepaint(_AutomationCurvePainter old) =>
      old.points != points || old.dragging != dragging;
}
