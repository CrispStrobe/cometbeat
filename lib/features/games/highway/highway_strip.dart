// lib/features/games/highway/highway_strip.dart
//
// The READING STRIP above the highway — the part that keeps this a music
// lesson rather than a reaction test.
//
// The highway teaches position; the strip teaches notation. Showing both, of
// the same music, at the same moment, is the whole pedagogical argument for a
// falling-note view existing inside a notation app: the learner reads the
// blocks, and the symbols for what they are playing scroll past a hand's width
// above, until one day they read those instead.
//
// Two modes, both driven by the highway chart itself (no engraved score
// needed, so it works for the built-in library as well as an import):
//
//   tab   — string lines with fret numbers, for the fretted/bowed instruments
//   names — a single row of note-name chips, coloured by hand, for keys/pads
//
// It scrolls right-to-left past a fixed "now" line, the mirror image of the
// highway's top-to-bottom, so the two never look like the same widget twice.

import 'package:comet_beat/core/games/highway/highway_chart.dart';
import 'package:comet_beat/core/games/highway/highway_lanes.dart';
import 'package:comet_beat/features/games/highway/highway_theme.dart';
import 'package:flutter/material.dart';

/// What the strip shows.
enum HighwayStripMode { tab, names }

class HighwayReadingStrip extends StatelessWidget {
  const HighwayReadingStrip({
    super.key,
    required this.chart,
    required this.laneMap,
    required this.beat,
    required this.palette,
    required this.mode,
    this.noteNameOf,
    this.visibleBeats = 8,
    this.height = 76,
  });

  final HighwayChart chart;
  final HighwayLaneMap laneMap;
  final double beat;
  final HighwayPalette palette;
  final HighwayStripMode mode;
  final String Function(int midi)? noteNameOf;
  final double visibleBeats;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _StripPainter(
            chart: chart,
            laneMap: laneMap,
            beat: beat,
            palette: palette,
            mode: mode,
            noteNameOf: noteNameOf,
            visibleBeats: visibleBeats,
          ),
        ),
      );
}

class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.chart,
    required this.laneMap,
    required this.beat,
    required this.palette,
    required this.mode,
    required this.noteNameOf,
    required this.visibleBeats,
  });

  final HighwayChart chart;
  final HighwayLaneMap laneMap;
  final double beat;
  final HighwayPalette palette;
  final HighwayStripMode mode;
  final String Function(int midi)? noteNameOf;
  final double visibleBeats;

  /// Where "now" sits, as a fraction of the width — a quarter in, so there is
  /// a little history and a lot of future.
  static const double _nowFrac = 0.22;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = palette.backdropBottom.withValues(alpha: 0.55),
    );

    final pxPerBeat = size.width * (1 - _nowFrac) / visibleBeats;
    final nowX = size.width * _nowFrac;
    double xOf(double b) => nowX + (b - beat) * pxPerBeat;

    _paintBarLines(canvas, size, xOf);
    switch (mode) {
      case HighwayStripMode.tab:
        _paintTab(canvas, size, xOf);
      case HighwayStripMode.names:
        _paintNames(canvas, size, xOf);
    }

    // The "now" line last, so it sits on top of the music.
    canvas.drawLine(
      Offset(nowX, 0),
      Offset(nowX, size.height),
      Paint()
        ..color = palette.hitLine
        ..strokeWidth = 2,
    );
  }

  void _paintBarLines(Canvas canvas, Size size, double Function(double) xOf) {
    final beatsPerBar = chart.beatsPerBar <= 0 ? 4.0 : chart.beatsPerBar;
    final firstBar = ((beat - 2) / beatsPerBar).floorToDouble() * beatsPerBar;
    final paint = Paint()
      ..color = palette.gridMajor
      ..strokeWidth = 1;
    for (var b = firstBar;
        b < beat + visibleBeats + beatsPerBar;
        b += beatsPerBar) {
      final x = xOf(b);
      if (x < -4 || x > size.width + 4) continue;
      canvas.drawLine(Offset(x, 6), Offset(x, size.height - 6), paint);
    }
  }

  void _paintTab(Canvas canvas, Size size, double Function(double) xOf) {
    final lanes = laneMap.laneCount;
    if (lanes <= 0) return;
    const top = 12.0;
    final bottom = size.height - 12;
    final step = (bottom - top) / (lanes - 1).clamp(1, 99);
    final line = Paint()
      ..color = palette.grid
      ..strokeWidth = 1;

    // String 0 (highest) on the top line — tab convention.
    for (var i = 0; i < lanes; i++) {
      final y = top + i * step;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }

    for (final event in chart.events) {
      if (event.endBeat < beat - 2 || event.startBeat > beat + visibleBeats) {
        continue;
      }
      final lane = event.lane;
      final caption = event.caption;
      if (lane == null || caption == null) continue;
      final x = xOf(event.startBeat);
      if (x < -12 || x > size.width + 12) continue;
      final y = top + lane.clamp(0, lanes - 1) * step;
      final active = event.startBeat <= beat && beat < event.endBeat;
      final tp = TextPainter(
        text: TextSpan(
          text: caption,
          style: TextStyle(
            color: active ? palette.glow : palette.voiceColor(event.voice),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Clear the line behind the digit so it reads like printed tab.
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x, y),
          width: tp.width + 6,
          height: tp.height + 2,
        ),
        Paint()..color = palette.backdropBottom,
      );
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }
  }

  void _paintNames(Canvas canvas, Size size, double Function(double) xOf) {
    final centre = size.height / 2;
    for (final column in chart.columns()) {
      final start = column.first.startBeat;
      if (start < beat - 2 || start > beat + visibleBeats) continue;
      final x = xOf(start);
      if (x < -20 || x > size.width + 20) continue;
      // A chord stacks upward from the middle, highest pitch on top.
      final sorted = [...column]
        ..sort((a, b) => (b.midi ?? 0).compareTo(a.midi ?? 0));
      final active =
          column.first.startBeat <= beat && beat < column.first.endBeat;
      for (var i = 0; i < sorted.length && i < 4; i++) {
        final event = sorted[i];
        final midi = event.midi;
        if (midi == null) continue;
        final label = noteNameOf?.call(midi) ?? '$midi';
        final y = centre + (i - (sorted.length - 1) / 2) * 17;
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: palette.blockText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, y),
            width: tp.width + 10,
            height: 16,
          ),
          const Radius.circular(8),
        );
        final colour = palette.voiceColor(event.voice);
        canvas.drawRRect(
          rect,
          Paint()
            ..color = active
                ? Color.lerp(colour, palette.glow, 0.5)!
                : colour.withValues(alpha: 0.85),
        );
        tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) => true;
}
