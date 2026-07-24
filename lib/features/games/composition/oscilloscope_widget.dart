import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// A real-time waveform and VU meter for a tracker channel.
class OscilloscopeWidget extends StatelessWidget {
  const OscilloscopeWidget({
    super.key,
    required this.pcm,
    required this.progress,
    required this.waveColor,
    required this.backgroundColor,
  });

  /// The raw PCM waveform of the channel.
  final Float64List pcm;

  /// Playback progress from 0.0 to 1.0. < 0 means stopped.
  final double progress;

  final Color waveColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _OscilloscopePainter(
        pcm: pcm,
        progress: progress,
        wave: waveColor,
        bg: backgroundColor,
      ),
    );
  }
}

class _OscilloscopePainter extends CustomPainter {
  _OscilloscopePainter({
    required this.pcm,
    required this.progress,
    required this.wave,
    required this.bg,
  });

  final Float64List pcm;
  final double progress;
  final Color wave;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    if (pcm.isEmpty) return;

    final mid = size.height / 2;
    final wavePaint = Paint()
      ..color = wave
      ..strokeWidth = 1;
    
    // Draw the waveform (peak-per-column)
    final cols = size.width.round().clamp(1, 4000);
    final n = pcm.length;
    for (var x = 0; x < cols; x++) {
      final i0 = (x * n / cols).floor();
      final i1 = ((x + 1) * n / cols).floor().clamp(i0 + 1, n);
      var peak = 0.0;
      for (var i = i0; i < i1; i++) {
        final a = pcm[i].abs();
        if (a > peak) peak = a;
      }
      final h = peak * mid;
      if (h > 0.5) {
        canvas.drawLine(
          Offset(x.toDouble(), mid - h),
          Offset(x.toDouble(), mid + h),
          wavePaint,
        );
      }
    }

    // Draw the playhead
    if (progress >= 0 && progress <= 1) {
      final px = progress * size.width;
      final headPaint = Paint()
        ..color = Colors.red
        ..strokeWidth = 2;
      canvas.drawLine(Offset(px, 0), Offset(px, size.height), headPaint);
    }
  }

  @override
  bool shouldRepaint(_OscilloscopePainter old) =>
      old.progress != progress ||
      !identical(old.pcm, pcm) ||
      old.bg != bg ||
      old.wave != wave;
}
