// lib/features/games/highway/highway_view.dart
//
// THE HIGHWAY ITSELF — one painter for every instrument, every skin and both
// projections.
//
// The view knows three things and nothing else: a lane map (where things sit,
// in unit space), a list of graded notes (what to draw and in what state), and
// the current beat. Everything visible is derived:
//
//   • the background grid is the lane map's own grid lines plus the chart's
//     bar/beat rules, so the geometry is *musical*, not decorative;
//   • the instrument rail at the hit line is drawn from the SAME lane geometry
//     as the falling blocks, which is why a block always lands exactly on its
//     key, at any width;
//   • taps are hit-tested through that same geometry, so what you touch is
//     what you saw.
//
// [HighwayProjection.perspective] is the arcade look: identical data, run
// through a perspective divide so lanes converge toward a vanishing point and
// equal beats occupy less height further away. It is a projection, not a
// second renderer — the flat view is the same code with the divide disabled.

import 'dart:math' as math;

import 'package:comet_beat/core/games/highway/highway_chart.dart';
import 'package:comet_beat/core/games/highway/highway_grading.dart';
import 'package:comet_beat/core/games/highway/highway_lanes.dart';
import 'package:comet_beat/features/games/highway/highway_theme.dart';
import 'package:flutter/material.dart';

/// Flat (top-down) or perspective (receding) geometry.
enum HighwayProjection { flat, perspective }

/// A short-lived hit burst at the rail.
class HighwayFlash {
  const HighwayFlash({
    required this.unitX,
    required this.beat,
    required this.perfect,
    this.missed = false,
  });

  final double unitX;
  final double beat;
  final bool perfect;
  final bool missed;
}

/// Projects unit-space (x ∈ 0..1, u = beats ahead ÷ lead) onto the canvas.
/// Shared by the painter and the hit test so they can never disagree.
class HighwayGeometry {
  HighwayGeometry({
    required this.size,
    required this.railHeight,
    required this.leadBeats,
    required this.projection,
    this.farScale = 0.4,
  });

  final Size size;
  final double railHeight;
  final double leadBeats;
  final HighwayProjection projection;

  /// How wide the far end of the highway is, as a fraction of the near end.
  final double farScale;

  double get hitY => size.height - railHeight;
  double get height => hitY;

  /// Perspective divide: 1 at the hit line, [farScale] at the far end.
  double scaleAt(double u) {
    if (projection == HighwayProjection.flat) return 1;
    final k = 1 / farScale;
    return 1 / (1 + u.clamp(0.0, 1.4) * (k - 1));
  }

  /// Screen y for a point [u] lead-fractions ahead of the hit line.
  double yFor(double u) {
    if (projection == HighwayProjection.flat) return hitY - height * u;
    final p = scaleAt(u);
    final pEnd = scaleAt(1);
    return hitY - height * (1 - p) / (1 - pEnd);
  }

  /// Screen x for unit [x] at depth [u].
  double xFor(double x, double u) {
    final s = scaleAt(u);
    return size.width * (0.5 + (x - 0.5) * s);
  }

  /// Pixel width of a unit-space width at depth [u].
  double widthFor(double w, double u) => size.width * w * scaleAt(u);
}

/// The falling-note view. The owner drives [beat] from a ticker.
class HighwayView extends StatefulWidget {
  const HighwayView({
    super.key,
    required this.chart,
    required this.laneMap,
    required this.notes,
    required this.beat,
    required this.rules,
    required this.palette,
    this.projection = HighwayProjection.flat,
    this.flashes = const [],
    this.litMidi = const {},
    this.litLanes = const {},
    this.onRailTap,
    this.showRail = true,
    this.noteNameOf,
    this.livePitch,
    this.energy = 0,
  });

  final HighwayChart chart;
  final HighwayLaneMap laneMap;
  final List<HighwayNote> notes;
  final double beat;
  final HighwayRules rules;
  final HighwayPalette palette;
  final HighwayProjection projection;
  final List<HighwayFlash> flashes;

  /// Pitches currently sounding — the rail lights them.
  final Set<int> litMidi;

  /// Lanes currently sounding (string/pad instruments).
  final Set<int> litLanes;

  final void Function(HighwayRailKey key)? onRailTap;
  final bool showRail;

  /// Localized note-name formatter (German B/H); null falls back to none.
  final String Function(int midi)? noteNameOf;

  /// Live microphone pitch, in fractional MIDI — drawn as a moving marker on
  /// the continuous-pitch map.
  final double? livePitch;

  /// 0…1 — how well the run is going right now (the streak multiplier). It
  /// only ever brightens the hit line: a clean run should FEEL different, and
  /// this is the cheapest honest way to say so without a HUD animation.
  final double energy;

  @override
  State<HighwayView> createState() => _HighwayViewState();
}

class _HighwayViewState extends State<HighwayView> {
  /// The key each live pointer is currently over. Input goes through raw
  /// pointers rather than a tap gesture for two reasons a music game cannot do
  /// without: several fingers must be able to answer a CHORD at the same
  /// instant (a tap gesture arbitrates to one), and dragging across the lanes
  /// must fire each lane it crosses — which is how a strum is actually played.
  final Map<int, int> _laneOfPointer = {};

  double _railHeight(Size size) {
    if (!widget.showRail) return 0;
    final isKeyboard = widget.laneMap is KeyboardLaneMap;
    return math.min(
      size.height * (isKeyboard ? 0.26 : 0.2),
      isKeyboard ? 132.0 : 96.0,
    );
  }

  void _pointer(int id, Offset local, Size size, HighwayGeometry geometry) {
    final onRailTap = widget.onRailTap;
    if (onRailTap == null) return;
    final x = (local.dx / size.width).clamp(0.0, 1.0);
    // Above the rail a touch means "that block", so a raised key wins when the
    // finger is inside one. On the rail the usual keyboard rule applies.
    final yFrac = local.dy < geometry.hitY
        ? 0.0
        : ((local.dy - geometry.hitY) / math.max(1.0, geometry.railHeight))
            .clamp(0.0, 1.0);
    final key = widget.laneMap.hitTest(x, yFrac);
    if (key == null) return;
    // A finger held still must not re-trigger; a finger that has slid onto a
    // new key must.
    final identity = key.midi ?? key.lane;
    if (_laneOfPointer[id] == identity) return;
    _laneOfPointer[id] = identity;
    onRailTap(key);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final geometry = HighwayGeometry(
            size: size,
            railHeight: _railHeight(size),
            leadBeats: widget.rules.leadBeats,
            projection: widget.projection,
          );
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) =>
                _pointer(e.pointer, e.localPosition, size, geometry),
            onPointerMove: (e) =>
                _pointer(e.pointer, e.localPosition, size, geometry),
            onPointerUp: (e) => _laneOfPointer.remove(e.pointer),
            onPointerCancel: (e) => _laneOfPointer.remove(e.pointer),
            child: CustomPaint(
              size: size,
              painter: _HighwayPainter(
                chart: widget.chart,
                laneMap: widget.laneMap,
                notes: widget.notes,
                beat: widget.beat,
                rules: widget.rules,
                palette: widget.palette,
                geometry: geometry,
                flashes: widget.flashes,
                litMidi: widget.litMidi,
                litLanes: widget.litLanes,
                showRail: widget.showRail,
                noteNameOf: widget.noteNameOf,
                livePitch: widget.livePitch,
                energy: widget.energy,
              ),
            ),
          );
        },
      );
}

class _HighwayPainter extends CustomPainter {
  _HighwayPainter({
    required this.chart,
    required this.laneMap,
    required this.notes,
    required this.beat,
    required this.rules,
    required this.palette,
    required this.geometry,
    required this.flashes,
    required this.litMidi,
    required this.litLanes,
    required this.showRail,
    required this.noteNameOf,
    required this.livePitch,
    required this.energy,
  });

  final HighwayChart chart;
  final HighwayLaneMap laneMap;
  final List<HighwayNote> notes;
  final double beat;
  final HighwayRules rules;
  final HighwayPalette palette;
  final HighwayGeometry geometry;
  final List<HighwayFlash> flashes;
  final Set<int> litMidi;
  final Set<int> litLanes;
  final bool showRail;
  final String Function(int midi)? noteNameOf;
  final double? livePitch;
  final double energy;

  // One TextPainter per distinct label, kept across frames: laying out text is
  // the single most expensive thing here, and a dense piece redraws the same
  // handful of strings sixty times a second.
  static final Map<String, TextPainter> _textCache = {};

  static TextPainter _text(
    String s,
    double size,
    Color color, {
    bool bold = true,
  }) {
    final key = '$s|${size.toStringAsFixed(1)}|${color.toARGB32()}|$bold';
    final hit = _textCache[key];
    if (hit != null) return hit;
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (_textCache.length > 240) _textCache.clear(); // bounded, not clever
    _textCache[key] = tp;
    return tp;
  }

  /// The rail is asked for twice a frame (tints + keys); a lane map may build
  /// it on demand, so it is resolved once per paint.
  late final List<HighwayRailKey> _railKeys = laneMap.railKeys();

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackdrop(canvas, size);
    _paintLaneTints(canvas, size);
    _paintBeatGrid(canvas, size);
    _paintLaneLines(canvas, size);
    _paintBlocks(canvas, size);
    _paintFarFade(canvas, size);
    _paintHitLine(canvas, size);
    _paintFlashes(canvas, size);
    if (showRail) _paintRail(canvas, size);
  }

  void _paintBackdrop(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.backdropTop, palette.backdropBottom],
        ).createShader(Offset.zero & size),
    );
  }

  /// The darker columns behind raised (black) keys — the single cue that makes
  /// a keyboard highway readable at a glance.
  void _paintLaneTints(Canvas canvas, Size size) {
    final paint = Paint()..color = palette.raisedLaneTint;
    for (final key in _railKeys) {
      if (!key.slot.raised) continue;
      canvas.drawPath(_lanePath(key.slot.left, key.slot.right), paint);
    }
  }

  /// A lane column from the far end down to the hit line, respecting the
  /// projection (a trapezoid in perspective, a rectangle when flat).
  Path _lanePath(double left, double right) {
    final g = geometry;
    return Path()
      ..moveTo(g.xFor(left, 1), g.yFor(1))
      ..lineTo(g.xFor(right, 1), g.yFor(1))
      ..lineTo(g.xFor(right, 0), g.yFor(0))
      ..lineTo(g.xFor(left, 0), g.yFor(0))
      ..close();
  }

  void _paintBeatGrid(Canvas canvas, Size size) {
    final g = geometry;
    final beatsPerBar = chart.beatsPerBar <= 0 ? 4.0 : chart.beatsPerBar;
    final first = beat.floorToDouble();
    final bar = Paint()
      ..color = palette.gridMajor
      ..strokeWidth = 1.4;
    final light = Paint()
      ..color = palette.grid
      ..strokeWidth = 1;

    for (var b = first; b <= beat + rules.leadBeats + 1; b += 1) {
      final u = (b - beat) / rules.leadBeats;
      if (u < -0.02 || u > 1) continue;
      final isBar = ((b - chart.pickupBeats) % beatsPerBar).abs() < 1e-6;
      if (!isBar && !rules.showBeatGrid) continue;
      final y = g.yFor(u);
      final s = g.scaleAt(u);
      final halfW = size.width * 0.5 * s;
      canvas.drawLine(
        Offset(size.width / 2 - halfW, y),
        Offset(size.width / 2 + halfW, y),
        isBar ? bar : light,
      );
    }
  }

  void _paintLaneLines(Canvas canvas, Size size) {
    final g = geometry;
    for (final line in laneMap.gridLines()) {
      final paint = Paint()
        ..color = line.major ? palette.gridMajor : palette.grid
        ..strokeWidth = line.major ? 1.4 : 1;
      canvas.drawLine(
        Offset(g.xFor(line.position, 1), g.yFor(1)),
        Offset(g.xFor(line.position, 0), g.yFor(0)),
        paint,
      );
      final label = line.label;
      if (label != null) {
        final tp = _text(label, 11, palette.label, bold: false);
        tp.paint(
          canvas,
          Offset(g.xFor(line.position, 0) + 3, g.hitY - tp.height - 3),
        );
      }
    }
  }

  void _paintBlocks(Canvas canvas, Size size) {
    final g = geometry;
    final lead = rules.leadBeats;
    for (final note in notes) {
      final event = note.event;
      // Cull: everything outside the visible beat window.
      if (event.endBeat < beat - 0.35 || event.startBeat > beat + lead) {
        continue;
      }
      final slot = laneMap.slotFor(event);
      if (slot == null) continue;

      // Inset the block inside its slot, so two neighbouring keys sounding at
      // once still read as two blocks.
      final fill = laneMap.blockFill;
      final left = slot.center - slot.width * fill / 2;
      final right = slot.center + slot.width * fill / 2;

      final uTop = ((event.endBeat - beat) / lead).clamp(0.0, 1.0);
      final uBottom = ((event.startBeat - beat) / lead).clamp(-0.35, 1.0);
      final yTop = g.yFor(uTop);
      final yBottom = g.yFor(uBottom);
      if (yBottom < -8 || yTop > g.hitY + 8) continue;

      final base = switch (note.state) {
        HighwayNoteState.missed => palette.missed,
        _ => palette.voiceColor(event.voice),
      };
      final hit = note.state == HighwayNoteState.hit;
      final paint = Paint()
        ..color = hit
            ? Color.lerp(base, palette.glow, 0.45)!.withValues(alpha: 0.95)
            : base.withValues(
                alpha: note.state == HighwayNoteState.missed ? 0.5 : 0.92,
              );

      // A block is a trapezoid in perspective (its near edge is wider) and a
      // rounded rectangle when flat.
      final path = Path();
      if (geometry.projection == HighwayProjection.flat) {
        path.addRRect(
          RRect.fromLTRBR(
            g.xFor(left, uTop),
            yTop,
            g.xFor(right, uTop),
            yBottom,
            const Radius.circular(4),
          ),
        );
      } else {
        path
          ..moveTo(g.xFor(left, uTop), yTop)
          ..lineTo(g.xFor(right, uTop), yTop)
          ..lineTo(g.xFor(right, uBottom), yBottom)
          ..lineTo(g.xFor(left, uBottom), yBottom)
          ..close();
      }

      if (palette.glowStrength > 0 && (hit || uBottom < 0.22)) {
        canvas.drawPath(
          path,
          Paint()
            ..color = base.withValues(alpha: 0.30 * palette.glowStrength)
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              6 * palette.glowStrength,
            ),
        );
      }
      canvas.drawPath(path, paint);
      // A bright leading edge reads as "this is the moment it starts".
      canvas.drawLine(
        Offset(g.xFor(left, uBottom) + 1, yBottom),
        Offset(g.xFor(right, uBottom) - 1, yBottom),
        Paint()
          ..color = Colors.white.withValues(alpha: palette.dark ? 0.55 : 0.35)
          ..strokeWidth = 2,
      );

      _paintCaption(canvas, event, slot, uTop, uBottom, yTop, yBottom);
    }
  }

  void _paintCaption(
    Canvas canvas,
    HighwayEvent event,
    HighwaySlot slot,
    double uTop,
    double uBottom,
    double yTop,
    double yBottom,
  ) {
    String? label;
    if (rules.showCaptions && event.caption != null) {
      label = event.caption;
    } else if (rules.showNoteNames && event.midi != null) {
      label = noteNameOf?.call(event.midi!);
    }
    if (label == null) return;

    final uMid = (uTop + uBottom) / 2;
    final w = geometry.widthFor(slot.width, uMid);
    final h = (yBottom - yTop).abs();
    final fontSize = math.min(w * 0.62, 15.0);
    if (fontSize < 7 || h < fontSize * 1.2) return; // no room — draw nothing
    final tp = _text(label, fontSize, palette.blockText);
    tp.paint(
      canvas,
      Offset(
        geometry.xFor(slot.center, uMid) - tp.width / 2,
        (yTop + yBottom) / 2 - tp.height / 2,
      ),
    );
  }

  /// Haze at the far end, so notes appear rather than pop in.
  void _paintFarFade(Canvas canvas, Size size) {
    final fadeHeight = geometry.hitY * 0.22;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, fadeHeight),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.backdropTop,
            palette.backdropTop.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, fadeHeight)),
    );
  }

  void _paintHitLine(Canvas canvas, Size size) {
    final y = geometry.hitY;
    if (palette.glowStrength > 0) {
      // The glow grows with the streak — the only place the run's state shows
      // up in the playfield itself.
      final lift = 1 + energy.clamp(0.0, 1.0) * 1.6;
      final h = 26 * lift;
      canvas.drawRect(
        Rect.fromLTWH(0, y - h, size.width, h),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              palette.glow.withValues(alpha: 0),
              palette.glow
                  .withValues(alpha: 0.16 * palette.glowStrength * lift),
            ],
          ).createShader(Rect.fromLTWH(0, y - h, size.width, h)),
      );
    }
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = palette.hitLine
        ..strokeWidth = 2.5,
    );

    // The live pitch marker, for the continuous-pitch map (voice, bowed).
    final live = livePitch;
    if (live != null && laneMap is PitchLaneMap) {
      final x = (laneMap as PitchLaneMap).xForPitch(live) * size.width;
      canvas.drawCircle(
        Offset(x, y),
        9,
        Paint()..color = palette.glow.withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        Offset(x, y),
        14,
        Paint()..color = palette.glow.withValues(alpha: 0.25),
      );
    }
  }

  void _paintFlashes(Canvas canvas, Size size) {
    for (final flash in flashes) {
      final age = beat - flash.beat;
      if (age < 0 || age > 0.9) continue;
      final t = age / 0.9;
      final x = geometry.xFor(flash.unitX, 0);
      final y = geometry.hitY;
      final color = flash.missed
          ? palette.missed
          : (flash.perfect ? palette.glow : palette.voiceColor(0));
      canvas.drawCircle(
        Offset(x, y),
        10 + 34 * t,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - t)
          ..color = color.withValues(alpha: (1 - t) * 0.8),
      );
      if (flash.perfect && palette.glowStrength > 0) {
        canvas.drawCircle(
          Offset(x, y),
          8 * (1 - t) + 4,
          Paint()..color = color.withValues(alpha: (1 - t) * 0.5),
        );
      }
    }
  }

  void _paintRail(Canvas canvas, Size size) {
    final top = geometry.hitY;
    final h = geometry.railHeight;
    if (h <= 0) return;
    final keys = _railKeys;
    final isKeyboard = laneMap is KeyboardLaneMap;

    canvas.drawRect(
      Rect.fromLTWH(0, top, size.width, h),
      Paint()
        ..color =
            palette.dark ? const Color(0xFF0A0E16) : const Color(0xFFE9E4DC),
    );

    for (final key in keys) {
      final left = key.slot.left * size.width;
      final width = key.slot.width * size.width;
      final lit = (key.midi != null && litMidi.contains(key.midi)) ||
          litLanes.contains(key.lane);
      final keyHeight =
          key.slot.raised ? h * KeyboardLaneMap.blackKeyHeightFraction : h;
      final rect = Rect.fromLTWH(left, top, width, keyHeight);
      final base = key.slot.raised
          ? palette.railBlack
          : (isKeyboard ? palette.railWhite : palette.railBlack);
      final fill = lit ? Color.lerp(base, palette.glow, 0.65)! : base;
      final rrect = RRect.fromRectAndCorners(
        rect.deflate(isKeyboard ? 0.5 : 3),
        bottomLeft: const Radius.circular(4),
        bottomRight: const Radius.circular(4),
      );
      canvas.drawRRect(rrect, Paint()..color = fill);
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = palette.railEdge,
      );

      final label = key.label;
      if (label != null && !key.slot.raised && width > 14) {
        final tp = _text(
          label,
          math.min(width * 0.42, 12),
          isKeyboard ? palette.railEdge : palette.label,
          bold: false,
        );
        tp.paint(
          canvas,
          Offset(
            left + width / 2 - tp.width / 2,
            top + keyHeight - tp.height - 5,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_HighwayPainter old) => true; // driven by a ticker
}
