// A realistic VISUAL drum kit that lights up as it plays. A drawn kit
// (cymbals · toms · snare · kick · hi-hat · accents) whose pieces flash and
// glow the instant their [Drum] sounds — driven by the step sequencer during
// playback/recording, and by [DrumKitVisualController.flash] on a live pad tap.
//
// Self-contained: its own decay [Ticker] + [CustomPainter], no audio. Reads a
// `step` ValueListenable + a `hitAt(drum, step)` query (so it needs nothing of
// the screen's internals) and an optional controller for live hits.
//
// Flutter-only → widget-tested in test/drum_kit_visual_test.dart.

import 'dart:math';

import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Fires a one-shot flash for a [Drum] — used for LIVE feedback (a pad tap, a
/// classified beatbox hit) that doesn't come from the step clock.
class DrumKitVisualController extends ChangeNotifier {
  Drum? _last;
  int _seq = 0;

  Drum? get lastFlash => _last;

  /// The flash counter — bumped on every [flash] so repeated hits of the SAME
  /// drum still register (a plain value-equality listener would miss them).
  int get seq => _seq;

  void flash(Drum drum) {
    _last = drum;
    _seq++;
    notifyListeners();
  }
}

/// Test handle onto a running [DrumKitVisual] (the state class is private).
@visibleForTesting
abstract interface class DrumKitVisualTester {
  /// The current glow (0 = dark … 1 = just struck) of [drum].
  double glowOf(Drum drum);
}

/// The visual kit. [step] is the sequencer playhead (−1 = stopped); on each
/// advance, every drum with `hitAt(drum, step) == true` flashes. [drums] limits
/// which voices are drawn (defaults to the full kit).
class DrumKitVisual extends StatefulWidget {
  const DrumKitVisual({
    super.key,
    required this.step,
    required this.hitAt,
    this.controller,
    this.onHit,
    this.drums = Drum.values,
  });

  final ValueListenable<int> step;
  final bool Function(Drum drum, int step) hitAt;
  final DrumKitVisualController? controller;

  /// Tapping a drawn piece fires its [Drum] — the kit is playable, not just a
  /// readout. (The screen routes this to its pad handler, so a tap auditions the
  /// drum and, while recording, is captured onto the grid.)
  final ValueChanged<Drum>? onHit;
  final List<Drum> drums;

  @override
  State<DrumKitVisual> createState() => _DrumKitVisualState();
}

class _DrumKitVisualState extends State<DrumKitVisual>
    with SingleTickerProviderStateMixin
    implements DrumKitVisualTester {
  // Per-drum glow intensity (0 = dark, 1 = just struck), decayed each frame.
  final Map<Drum, double> _glow = {for (final d in Drum.values) d: 0.0};
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  int _lastStep = -1;
  int _lastFlashSeq = 0;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    widget.step.addListener(_onStep);
    widget.controller?.addListener(_onFlash);
    _ticker = createTicker(_onFrame)..start();
  }

  @override
  void didUpdateWidget(DrumKitVisual old) {
    super.didUpdateWidget(old);
    if (old.step != widget.step) {
      old.step.removeListener(_onStep);
      widget.step.addListener(_onStep);
    }
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onFlash);
      widget.controller?.addListener(_onFlash);
    }
  }

  @override
  void dispose() {
    widget.step.removeListener(_onStep);
    widget.controller?.removeListener(_onFlash);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  double glowOf(Drum drum) => _glow[drum] ?? 0.0;

  void _light(Drum drum) {
    _glow[drum] = 1.0;
    _active = true;
  }

  void _onStep() {
    final s = widget.step.value;
    if (s == _lastStep) return;
    _lastStep = s;
    if (s < 0) return;
    for (final d in widget.drums) {
      if (widget.hitAt(d, s)) _light(d);
    }
  }

  void _onFlash() {
    final c = widget.controller;
    if (c == null || c.seq == _lastFlashSeq) return;
    _lastFlashSeq = c.seq;
    final d = c.lastFlash;
    if (d != null) _light(d);
  }

  void _onFrame(Duration now) {
    if (!_active) {
      _lastTick = now;
      return;
    }
    final dt = (now - _lastTick).inMicroseconds / 1e6;
    _lastTick = now;
    // Exponential decay: a struck piece flares then fades over ~0.4 s.
    final k = exp(-dt * 6.0);
    var anyLit = false;
    for (final d in _glow.keys) {
      final g = _glow[d]! * k;
      _glow[d] = g < 1e-3 ? 0.0 : g;
      if (_glow[d]! > 0) anyLit = true;
    }
    _active = anyLit;
    _repaint.value++; // drive the CustomPainter without a full rebuild
  }

  void _onTapDown(TapDownDetails d) {
    final onHit = widget.onHit;
    if (onHit == null) return;
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    final drum = pieceAt(d.localPosition, box.size, widget.drums.toSet());
    if (drum != null) onHit(drum);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: GestureDetector(
        onTapDown: widget.onHit == null ? null : _onTapDown,
        child: CustomPaint(
          painter: _DrumKitPainter(
            glow: _glow,
            drums: widget.drums,
            dark: dark,
            repaint: _repaint,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// Which drawn piece (if any) sits under [p] on a canvas of [size], among the
/// [shown] drums. Front-most (last-painted) wins where pieces overlap; each
/// piece is an ellipse matched to how it's drawn, so taps feel accurate.
@visibleForTesting
Drum? pieceAt(Offset p, Size size, Set<Drum> shown) {
  final s = size.shortestSide;
  for (final piece in _kLayout.reversed) {
    if (!shown.contains(piece.drum)) continue;
    final c = Offset(piece.cx * size.width, piece.cy * size.height);
    final r = piece.r * s;
    final (hw, hh) = switch (piece.shape) {
      _Shape.cymbal || _Shape.hihat => (r * 1.05, r * 0.45),
      _Shape.tom || _Shape.snare => (r, r * 0.85), // head + a bit of the shell
      _Shape.kick => (r, r),
    };
    final dx = (p.dx - c.dx) / hw, dy = (p.dy - c.dy) / hh;
    if (dx * dx + dy * dy <= 1.0) return piece.drum;
  }
  return null;
}

// ── Layout ───────────────────────────────────────────────────────────────────

enum _Shape { cymbal, hihat, tom, kick, snare }

/// One drawn piece: where it sits (normalized 0..1), how big (fraction of the
/// canvas' shorter side), its shell/brass hue, how deep the shell is (a fraction
/// of the head radius — 0 for cymbals), and how to draw it.
class _Piece {
  const _Piece(
    this.drum,
    this.shape,
    this.cx,
    this.cy,
    this.r,
    this.color, {
    this.depth = 1.0,
  });
  final Drum drum;
  final _Shape shape;
  final double cx, cy, r, depth;
  final Color color;
}

// An acoustic kit seen from the front, painted back-to-front. Only the acoustic
// core is drawn (a photo-real acoustic kit); clap/rim/cowbell live in the pads/grid.
const _kBrass = Color(0xFFCBA23A); // cymbal gold
const _kRed = Color(0xFF9B2A2A); // glossy shell red
const _kSteel = Color(0xFFAAB2BC); // snare steel

const List<_Piece> _kLayout = [
  // Cymbals + hi-hat sit high, behind the drums.
  _Piece(Drum.ride, _Shape.cymbal, 0.80, 0.24, 0.185, _kBrass),
  _Piece(Drum.crash, _Shape.cymbal, 0.21, 0.25, 0.165, _kBrass),
  _Piece(Drum.openHat, _Shape.hihat, 0.095, 0.40, 0.11, _kBrass),
  _Piece(Drum.hat, _Shape.hihat, 0.095, 0.47, 0.11, _kBrass),
  // Rack toms mounted over the kick; floor tom to the right (deeper shell).
  _Piece(Drum.highTom, _Shape.tom, 0.40, 0.40, 0.115, _kRed, depth: 1.15),
  _Piece(Drum.tom, _Shape.tom, 0.57, 0.39, 0.125, _kRed, depth: 1.15),
  _Piece(Drum.lowTom, _Shape.tom, 0.86, 0.58, 0.155, _kRed, depth: 1.7),
  // Snare (steel, shallow) then the big front kick.
  _Piece(Drum.snare, _Shape.snare, 0.30, 0.62, 0.135, _kSteel, depth: 0.85),
  _Piece(Drum.kick, _Shape.kick, 0.53, 0.74, 0.225, _kRed),
];

class _DrumKitPainter extends CustomPainter {
  _DrumKitPainter({
    required this.glow,
    required this.drums,
    required this.dark,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Map<Drum, double> glow;
  final List<Drum> drums;
  final bool dark;

  static const _cream = Color(0xFFF3ECD9); // drum head
  static const _chrome = Color(0xFFE6EAEF);
  static const _chromeDark = Color(0xFF8A929C);

  @override
  void paint(Canvas canvas, Size size) {
    final shown = drums.toSet();
    final s = size.shortestSide;
    for (final p in _kLayout) {
      if (!shown.contains(p.drum)) continue;
      final c = Offset(p.cx * size.width, p.cy * size.height);
      final r = p.r * s;
      final g = (glow[p.drum] ?? 0).clamp(0.0, 1.0);
      switch (p.shape) {
        case _Shape.cymbal:
        case _Shape.hihat:
          _cymbal(canvas, c, r, g, hat: p.shape == _Shape.hihat);
        case _Shape.tom:
        case _Shape.snare:
          _drum(canvas, c, r, p.color, g, depth: r * p.depth);
        case _Shape.kick:
          _kick(canvas, c, r, p.color, g);
      }
    }
  }

  // A soft ground shadow under a piece.
  void _shadow(Canvas canvas, Offset c, double rx, double ry) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx + rx * 0.12, c.dy + ry * 0.9),
        width: rx * 2,
        height: ry * 1.1,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, ry * 0.6),
    );
  }

  // A cymbal / hi-hat: a stand, a gold disc with lathe grooves, a bell + shine.
  void _cymbal(
    Canvas canvas,
    Offset c,
    double r,
    double g, {
    required bool hat,
  }) {
    // Stand: a thin metal rod down to the kit floor.
    canvas.drawLine(
      c,
      Offset(c.dx, c.dy + r * (hat ? 1.6 : 2.5)),
      Paint()
        ..color = _chromeDark.withValues(alpha: 0.7)
        ..strokeWidth = max(1.5, r * 0.07),
    );
    final disc = Rect.fromCenter(center: c, width: r * 2, height: r * 0.62);
    _shadow(canvas, c, r * 0.9, r * 0.34);
    if (g > 0) _halo(canvas, c, r * 1.5, g);
    // The brass disc — a warm radial gradient, brightening when struck.
    canvas.drawOval(
      disc,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.1, -0.3),
          radius: 0.9,
          colors: [
            Color.lerp(const Color(0xFFF6E7B0), Colors.white, g)!,
            Color.lerp(_kBrass, Colors.white, 0.4 * g)!,
            Color.lerp(const Color(0xFF7A5E1C), Colors.white, 0.3 * g)!,
          ],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(disc),
    );
    // Concentric lathe grooves.
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.6, r * 0.015)
      ..color = const Color(0xFF6B521A).withValues(alpha: 0.35);
    for (var i = 1; i <= 5; i++) {
      final f = i / 6.0;
      canvas.drawOval(
        Rect.fromCenter(center: c, width: r * 2 * f, height: r * 0.62 * f),
        groove,
      );
    }
    // The bell (raised centre) + a bright specular streak.
    canvas.drawOval(
      Rect.fromCenter(center: c, width: r * 0.42, height: r * 0.18),
      Paint()..color = Color.lerp(const Color(0xFFEAD48A), Colors.white, g)!,
    );
    canvas.drawArc(
      Rect.fromCenter(center: c, width: r * 1.7, height: r * 0.5),
      pi * 1.05,
      pi * 0.5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, r * 0.04)
        ..color = Colors.white.withValues(alpha: 0.45),
    );
    // Rim edge.
    canvas.drawOval(
      disc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, r * 0.03)
        ..color = const Color(0xFF5A461A).withValues(alpha: 0.5),
    );
    if (hat) {
      // A thin lower plate makes the hi-hat read as a pair.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(c.dx, c.dy + r * 0.22),
          width: r * 1.92,
          height: r * 0.34,
        ),
        Paint()..color = const Color(0xFF9A7A2A),
      );
    }
  }

  // A drum seen at a slight angle: a cylindrical shell + a bright head, a chrome
  // rim with tension lugs. [depth] is the visible shell height in pixels.
  void _drum(
    Canvas canvas,
    Offset c,
    double r,
    Color shell,
    double g, {
    required double depth,
  }) {
    final rx = r, ry = r * 0.5;
    _shadow(canvas, Offset(c.dx, c.dy + depth), rx, ry);
    // Shell wall: a rectangle between the head plane and the bottom ellipse,
    // capped by that bottom ellipse — the cylinder silhouette.
    final wall = Rect.fromLTRB(c.dx - rx, c.dy, c.dx + rx, c.dy + depth);
    final bottom = Rect.fromCenter(
      center: Offset(c.dx, c.dy + depth),
      width: rx * 2,
      height: ry * 2,
    );
    canvas.drawOval(
      bottom,
      Paint()..color = Color.lerp(shell, Colors.black, 0.35)!,
    );
    canvas.drawRect(
      wall,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Color.lerp(shell, Colors.black, 0.35)!,
            Color.lerp(shell, Colors.white, 0.35)!,
            shell,
            Color.lerp(shell, Colors.black, 0.4)!,
          ],
          stops: const [0.0, 0.28, 0.55, 1.0],
        ).createShader(wall),
    );
    // A chrome hoop at the bottom edge of the shell.
    canvas.drawArc(
      bottom,
      0,
      pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.5, r * 0.06)
        ..color = _chrome.withValues(alpha: 0.7),
    );

    final head = Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);
    // Chrome counter-hoop (rim) just outside the head.
    final rim = Rect.fromCenter(
      center: c,
      width: rx * 2 * 1.06,
      height: ry * 2 * 1.06,
    );
    canvas.drawOval(
      rim,
      Paint()
        ..shader = const SweepGradient(
          colors: [_chromeDark, _chrome, _chromeDark, _chrome, _chromeDark],
          stops: [0.0, 0.25, 0.5, 0.75, 1.0],
        ).createShader(rim),
    );
    // Tension lugs around the rim.
    final lug = Paint()..color = _chrome;
    final lugEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.6, r * 0.02)
      ..color = _chromeDark;
    const lugs = 8;
    for (var i = 0; i < lugs; i++) {
      final a = (i / lugs) * 2 * pi;
      final lp = Offset(c.dx + cos(a) * rx * 1.02, c.dy + sin(a) * ry * 1.02);
      canvas.drawCircle(lp, r * 0.055, lug);
      canvas.drawCircle(lp, r * 0.055, lugEdge);
    }
    if (g > 0) _halo(canvas, c, r, g);
    // The head: a bright radial gradient, flaring white when struck.
    canvas.drawOval(
      head,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.35),
          radius: 1.0,
          colors: [
            Color.lerp(Colors.white, Colors.white, g)!,
            Color.lerp(_cream, Colors.white, g)!,
            Color.lerp(const Color(0xFFD8CFB8), Colors.white, 0.8 * g)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(head),
    );
    // Head rim line + a soft top highlight.
    canvas.drawOval(
      head,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, r * 0.03)
        ..color = const Color(0xFF9A9583).withValues(alpha: 0.6),
    );
  }

  // The kick: a big front-facing shell with a cream resonant head, chrome hoop,
  // lugs, and a small port hole.
  void _kick(Canvas canvas, Offset c, double r, Color shell, double g) {
    _shadow(canvas, c, r * 0.95, r * 0.85);
    if (g > 0) _halo(canvas, c, r * 0.9, g);
    // Outer shell ring (glossy).
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [
            Color.lerp(shell, Colors.white, 0.4)!,
            shell,
            Color.lerp(shell, Colors.black, 0.45)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Chrome counter-hoop.
    canvas.drawCircle(
      c,
      r * 0.82,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(2.0, r * 0.08)
        ..shader = const SweepGradient(
          colors: [_chromeDark, _chrome, _chromeDark, _chrome, _chromeDark],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.82)),
    );
    // Tension lugs around the hoop.
    const lugs = 10;
    for (var i = 0; i < lugs; i++) {
      final a = (i / lugs) * 2 * pi;
      final lp = Offset(c.dx + cos(a) * r * 0.9, c.dy + sin(a) * r * 0.9);
      canvas.drawCircle(lp, r * 0.045, Paint()..color = _chrome);
    }
    // The front head.
    canvas.drawCircle(
      c,
      r * 0.74,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.25, -0.3),
          colors: [
            Colors.white,
            Color.lerp(_cream, Colors.white, g)!,
            Color.lerp(const Color(0xFFD6CDB6), Colors.white, 0.8 * g)!,
          ],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.74)),
    );
    // A small bass-port hole, lower-right.
    canvas.drawCircle(
      Offset(c.dx + r * 0.32, c.dy + r * 0.28),
      r * 0.13,
      Paint()..color = const Color(0xFF2A2622).withValues(alpha: 0.85),
    );
  }

  // A warm additive halo behind a struck piece.
  void _halo(Canvas canvas, Offset c, double r, double g) {
    canvas.drawCircle(
      c,
      r * (1.1 + 0.3 * g),
      Paint()
        ..color = const Color(0xFFFFF0A0).withValues(alpha: 0.5 * g)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.55),
    );
  }

  @override
  bool shouldRepaint(_DrumKitPainter old) =>
      old.dark != dark || old.drums != drums;
}
