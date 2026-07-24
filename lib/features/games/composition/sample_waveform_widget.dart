import 'dart:typed_data';

import 'package:flutter/material.dart';

/// The sample editor's waveform strip: a peak-per-column render of the recorded
/// clip with two draggable trim handles; the kept region is bright, the cropped
/// tails dim. Reports the new [start]/[end] fractions as the user drags.
class SampleWaveform extends StatefulWidget {
  const SampleWaveform({
    super.key,
    required this.pcm,
    required this.start,
    required this.end,
    required this.onChanged,
    required this.wave,
    required this.bg,
  });

  final Float64List pcm;
  final double start;
  final double end;
  final void Function(double start, double end) onChanged;
  final Color wave;
  final Color bg;

  @override
  State<SampleWaveform> createState() => _SampleWaveformState();
}

class _SampleWaveformState extends State<SampleWaveform> {
  int _handle = 0; // 0 = start, 1 = end — whichever the drag grabbed

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        double fracAt(double dx) => (dx / w).clamp(0.0, 1.0);
        void grab(double dx) {
          final f = fracAt(dx);
          _handle = (f - widget.start).abs() <= (f - widget.end).abs() ? 0 : 1;
        }

        void drag(double dx) {
          final f = fracAt(dx);
          if (_handle == 0) {
            widget.onChanged(f.clamp(0.0, widget.end - 0.02), widget.end);
          } else {
            widget.onChanged(widget.start, f.clamp(widget.start + 0.02, 1.0));
          }
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => grab(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => drag(d.localPosition.dx),
          onTapDown: (d) {
            grab(d.localPosition.dx);
            drag(d.localPosition.dx);
          },
          child: CustomPaint(
            size: Size(w, 64),
            painter: _WaveformPainter(
              pcm: widget.pcm,
              start: widget.start,
              end: widget.end,
              wave: widget.wave,
              bg: widget.bg,
            ),
          ),
        );
      },
    );
  }
}

/// Paints [pcm] (−1..1 floats) as a peak-per-column waveform, dimming the
/// cropped tails outside [start]..[end] and drawing a knob at each handle.
class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.pcm,
    required this.start,
    required this.end,
    required this.wave,
    required this.bg,
  });

  final Float64List pcm;
  final double start;
  final double end;
  final Color wave;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );
    canvas.drawRRect(r, Paint()..color = bg);
    canvas.save();
    canvas.clipRRect(r);
    final mid = size.height / 2;
    if (pcm.isNotEmpty) {
      final cols = size.width.round().clamp(1, 4000);
      final n = pcm.length;
      final keep = Paint()
        ..color = wave
        ..strokeWidth = 1;
      final drop = Paint()
        ..color = wave.withValues(alpha: 0.28)
        ..strokeWidth = 1;
      for (var x = 0; x < cols; x++) {
        final frac = x / cols;
        final i0 = (x * n / cols).floor();
        final i1 = ((x + 1) * n / cols).floor().clamp(i0 + 1, n);
        var peak = 0.0;
        for (var i = i0; i < i1; i++) {
          final a = pcm[i].abs();
          if (a > peak) peak = a;
        }
        final h = peak.clamp(0.0, 1.0) * mid;
        final xx = x * size.width / cols;
        canvas.drawLine(
          Offset(xx, mid - h),
          Offset(xx, mid + h),
          frac >= start && frac <= end ? keep : drop,
        );
      }
    }
    // Shade the cropped tails.
    final shade = Paint()..color = bg.withValues(alpha: 0.5);
    if (start > 0) {
      canvas.drawRect(
        Rect.fromLTRB(0, 0, start * size.width, size.height),
        shade,
      );
    }
    if (end < 1) {
      canvas.drawRect(
        Rect.fromLTRB(end * size.width, 0, size.width, size.height),
        shade,
      );
    }
    // Handles.
    final line = Paint()
      ..color = const Color(0xFFFF5252)
      ..strokeWidth = 2;
    for (final f in [start, end]) {
      final x = f * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      canvas.drawCircle(Offset(x, mid), 6, line..style = PaintingStyle.fill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.start != start ||
      old.end != end ||
      old.bg != bg ||
      old.wave != wave ||
      !identical(old.pcm, pcm);
}
