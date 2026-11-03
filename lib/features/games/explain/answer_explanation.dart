// lib/features/games/explain/answer_explanation.dart
//
// The post-answer "Good to know" card: after a learner answers an item that
// compares or names musical TERMS, it explains them in one line each
// ("mf  mezzoforte = halblaut" + a short sentence) and, where a picture helps,
// draws a small visualization:
//
//  * dynamics      → a loudness ladder pp…ff (bars of rising height) with the
//                    terms in play highlighted, lighting up in step with a
//                    playing demo (see DynamicsDemo);
//  * cresc./dim.   → a hairpin over a rising / falling row of bars;
//  * tempo words   → a pulsing beat dot per term at its typical BPM;
//  * accel./rit.   → a row of beats whose spacing shrinks / grows;
//  * articulation  → four note-length bars (short + gap, joined, held, stressed).
//
// It never blocks the game: screens show it while the solved round waits for
// its (slightly longer, [kExplanationHold]) auto-advance and pass [onNext] so
// the learner can skip ahead; the close button hides it for the round.

import 'dart:math' as math;

import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/explain/music_terms.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/music_glyph.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// How long a solved round with an explanation stays up before the game moves
/// on by itself (the learner can always tap "Next" sooner). Long enough to
/// read one line and hear the example, short enough not to drag.
const kExplanationHold = Duration(milliseconds: 2800);

/// Whether the explanation card is switched on in Settings
/// ([SettingsService.answerExplanations]). True when no [SettingsService] is
/// provided, so a screen pumped on its own keeps the default behaviour.
bool answerExplanationsOn(BuildContext context, {bool listen = false}) {
  try {
    return Provider.of<SettingsService>(context, listen: listen)
        .answerExplanations;
  } on ProviderNotFoundException {
    return true;
  }
}

/// The solved-round hold for a screen that shows the explanation card:
/// [kExplanationHold] while the card is on, the ordinary [kRoundAdvanceDelay]
/// when the learner switched it off in Settings — the longer hold exists only
/// to read the card, so it goes with it.
Duration explanationHold(BuildContext context) =>
    answerExplanationsOn(context) ? kExplanationHold : kRoundAdvanceDelay;

/// The explanation card. Explains [terms] (in order). [highlight] picks which
/// rungs of a ladder visualization are lit (defaults to [terms]); [sounding]
/// lights the rung currently playing. A non-null [onNext] adds a "Next"
/// button.
class AnswerExplanation extends StatefulWidget {
  const AnswerExplanation({
    super.key,
    required this.terms,
    this.highlight,
    this.sounding,
    this.onNext,
    this.flexible = true,
  });

  /// Key of the card itself, for tests.
  static const panelKey = ValueKey('answer_explanation');

  final List<MusicTerm> terms;
  final Set<MusicTerm>? highlight;
  final ValueListenable<MusicTerm?>? sounding;
  final VoidCallback? onNext;

  /// Whether the card is a [Flexible] child of the screen's Column (the
  /// default — every game places it directly in its main Column): it then
  /// shares the leftover height with the game and scrolls inside if a small
  /// phone has less room than it would like. Pass false when it is NOT a
  /// direct child of a Flex.
  final bool flexible;

  @override
  State<AnswerExplanation> createState() => _AnswerExplanationState();
}

class _AnswerExplanationState extends State<AnswerExplanation> {
  bool _closed = false;

  @override
  void didUpdateWidget(AnswerExplanation old) {
    super.didUpdateWidget(old);
    // A different set of terms is a new explanation: show it again.
    if (!listEquals(old.terms, widget.terms)) _closed = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_closed ||
        widget.terms.isEmpty ||
        !answerExplanationsOn(context, listen: true)) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kind = widget.terms.first.kind;
    final highlight = widget.highlight ?? widget.terms.toSet();

    final card = Card(
      key: AnswerExplanation.panelKey,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        // Never more than ~a quarter of the screen, so it fits under the
        // game on a small phone (the content scrolls if it needs more).
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: math.min(260, MediaQuery.sizeOf(context).height * 0.28),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.explainTitle,
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: scheme.primary),
                    ),
                  ),
                  if (widget.onNext != null)
                    TextButton.icon(
                      key: const ValueKey('answer_explanation_next'),
                      onPressed: widget.onNext,
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: Text(l10n.explainNext),
                    ),
                  IconButton(
                    tooltip: l10n.explainClose,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _closed = true),
                  ),
                ],
              ),
              for (final t in widget.terms) _TermLine(term: t),
              const SizedBox(height: 8),
              Center(
                child: switch (kind) {
                  TermKind.dynamic => DynamicsLadder(
                      highlight: highlight,
                      sounding: widget.sounding,
                    ),
                  TermKind.dynamicChange =>
                    HairpinRamp(rising: widget.terms.first.rank > 0),
                  TermKind.tempo => Wrap(
                      spacing: 20,
                      runSpacing: 8,
                      children: [
                        for (final t in widget.terms)
                          if (t.kind == TermKind.tempo) TempoPulse(term: t),
                      ],
                    ),
                  TermKind.tempoChange =>
                    TempoChangeDots(faster: widget.terms.first.rank > 0),
                  TermKind.articulation => Wrap(
                      spacing: 20,
                      runSpacing: 8,
                      children: [
                        for (final t in widget.terms) ArticulationBars(term: t),
                      ],
                    ),
                },
              ),
            ],
          ),
        ),
      ),
    );
    return widget.flexible ? Flexible(child: card) : card;
  }
}

/// "mf  mezzoforte = halblaut" + the one-sentence explanation (+ the BPM for
/// a tempo word).
class _TermLine extends StatelessWidget {
  const _TermLine({required this.term});

  final MusicTerm term;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final glyph = term.glyph;
    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (glyph != null)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: MusicGlyph(
                String.fromCharCode(glyph),
                size: 26,
                color: scheme.onSurface,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: termName(l10n, term),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      TextSpan(text: ' = ${termMeaning(l10n, term)}'),
                    ],
                  ),
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  term.kind == TermKind.tempo
                      ? '${termInfo(l10n, term)} (${l10n.explainBpm(term.bpm)})'
                      : termInfo(l10n, term),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The six dynamic levels as bars of rising height, pp … ff, with [highlight]
/// lit and the [sounding] one glowing while a demo plays it.
class DynamicsLadder extends StatelessWidget {
  const DynamicsLadder({super.key, this.highlight = const {}, this.sounding});

  final Set<MusicTerm> highlight;
  final ValueListenable<MusicTerm?>? sounding;

  @override
  Widget build(BuildContext context) {
    final s = sounding;
    if (s == null) return _build(context, null);
    return ValueListenableBuilder<MusicTerm?>(
      valueListenable: s,
      builder: (context, now, _) => _build(context, now),
    );
  }

  Widget _build(BuildContext context, MusicTerm? now) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.labelSmall;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final t in MusicTerm.dynamicsLadder)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      key: ValueKey('ladder_bar_${t.name}'),
                      duration: const Duration(milliseconds: 180),
                      width: 22,
                      height: 8.0 + t.rank * 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: t == now
                            ? scheme.tertiary
                            : highlight.contains(t)
                                ? scheme.primary
                                : scheme.outlineVariant,
                        boxShadow: t == now
                            ? [
                                BoxShadow(
                                  color: scheme.tertiary.withValues(alpha: 0.6),
                                  blurRadius: 10,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Opacity(
                      opacity: highlight.contains(t) || t == now ? 1 : 0.45,
                      child: MusicGlyph(
                        String.fromCharCode(t.glyph!),
                        size: 20,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        _Axis(
          from: l10n.explainAxisSoft,
          to: l10n.explainAxisLoud,
          style: small,
        ),
      ],
    );
  }
}

/// "soft ──→ loud" under a ladder.
class _Axis extends StatelessWidget {
  const _Axis({required this.from, required this.to, this.style});

  final String from;
  final String to;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(from, style: style),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_right_alt, size: 18),
          ),
          Text(to, style: style),
        ],
      );
}

/// A hairpin (opening for a crescendo, closing for a diminuendo) over a row
/// of bars that grow or shrink with it.
class HairpinRamp extends StatelessWidget {
  const HairpinRamp({super.key, required this.rising});

  final bool rising;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(180, 64),
          painter: _HairpinPainter(
            rising: rising,
            line: scheme.onSurface,
            bar: scheme.primary,
          ),
        ),
        _Axis(
          from: rising ? l10n.explainAxisSoft : l10n.explainAxisLoud,
          to: rising ? l10n.explainAxisLoud : l10n.explainAxisSoft,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _HairpinPainter extends CustomPainter {
  _HairpinPainter({
    required this.rising,
    required this.line,
    required this.bar,
  });

  final bool rising;
  final Color line;
  final Color bar;

  @override
  void paint(Canvas canvas, Size size) {
    // Wedge in the top 18 px.
    final pen = Paint()
      ..color = line
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const top = 2.0, h = 16.0;
    final narrowX = rising ? 0.0 : size.width;
    final wideX = rising ? size.width : 0.0;
    canvas
      ..drawLine(Offset(narrowX, top + h / 2), Offset(wideX, top), pen)
      ..drawLine(Offset(narrowX, top + h / 2), Offset(wideX, top + h), pen);
    // Bars below, height following the wedge.
    const n = 8;
    final fill = Paint()..color = bar;
    final slot = size.width / n;
    final maxH = size.height - top - h - 6;
    for (var i = 0; i < n; i++) {
      final frac = (rising ? i + 1 : n - i) / n;
      final bh = maxH * frac;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * slot + slot * 0.2,
            size.height - bh,
            slot * 0.6,
            bh,
          ),
          const Radius.circular(3),
        ),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(_HairpinPainter old) =>
      old.rising != rising || old.line != line || old.bar != bar;
}

/// A beat dot that pulses at the tempo word's typical BPM — a handful of
/// beats, then it rests (so it never keeps a ticker spinning).
class TempoPulse extends StatefulWidget {
  const TempoPulse({super.key, required this.term, this.beats = 8});

  final MusicTerm term;

  /// How many pulses to show before resting.
  final int beats;

  @override
  State<TempoPulse> createState() => _TempoPulseState();
}

class _TempoPulseState extends State<TempoPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _beat = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (60000 / widget.term.bpm).round()),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed &&
            ++_count < widget.beats &&
            mounted) {
          _beat.forward(from: 0);
        }
      });
    _beat.forward();
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: AnimatedBuilder(
            animation: _beat,
            builder: (context, _) {
              // Big on the beat, shrinking until the next one.
              final v = _beat.isAnimating ? 1 - _beat.value : 0.0;
              final d = 18 + 22 * Curves.easeOut.transform(v);
              return Center(
                child: Container(
                  width: d,
                  height: d,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(
                      scheme.primaryContainer,
                      scheme.primary,
                      v,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 2),
        Text(
          widget.term.mark,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

/// A row of beats whose spacing shrinks (accelerando) or grows (ritardando).
class TempoChangeDots extends StatelessWidget {
  const TempoChangeDots({super.key, required this.faster});

  final bool faster;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(200, 24),
          painter: _DotsPainter(faster: faster, color: scheme.primary),
        ),
        _Axis(
          from: faster ? l10n.explainAxisSlow : l10n.explainAxisFast,
          to: faster ? l10n.explainAxisFast : l10n.explainAxisSlow,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({required this.faster, required this.color});

  final bool faster;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 9;
    // Gaps form a geometric series: each one 0.8× (faster) or 1.25× (slower)
    // the previous, scaled to fill the width.
    final ratio = faster ? 0.8 : 1.25;
    final gaps = [
      for (var i = 0; i < n - 1; i++) math.pow(ratio, i).toDouble(),
    ];
    final total = gaps.reduce((a, b) => a + b);
    final usable = size.width - 12;
    final paint = Paint()..color = color;
    var x = 6.0;
    for (var i = 0; i < n; i++) {
      canvas.drawCircle(Offset(x, size.height / 2), 5, paint);
      if (i < n - 1) x += gaps[i] / total * usable;
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) =>
      old.faster != faster || old.color != color;
}

/// Four note-length bars showing how an articulation shapes the notes: short
/// with gaps (staccato), joined under a slur (legato), full length (tenuto),
/// or one note standing out taller (accent, marcato even more).
class ArticulationBars extends StatelessWidget {
  const ArticulationBars({super.key, required this.term});

  final MusicTerm term;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(140, 40),
          painter: _ArticulationPainter(term: term, color: scheme.primary),
        ),
        Text(
          termName(AppLocalizations.of(context)!, term),
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

class _ArticulationPainter extends CustomPainter {
  _ArticulationPainter({required this.term, required this.color});

  final MusicTerm term;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 4;
    final slot = size.width / n;
    final fill = Paint()..color = color;
    const barH = 10.0;
    final baseY = size.height - 4;
    for (var i = 0; i < n; i++) {
      final (len, h) = switch (term) {
        MusicTerm.staccato => (slot * 0.35, barH),
        MusicTerm.legato => (slot, barH),
        MusicTerm.tenuto => (slot * 0.92, barH),
        MusicTerm.accent => (slot * 0.8, i == 1 ? barH * 2 : barH),
        MusicTerm.marcato => (slot * 0.8, i == 1 ? barH * 2.8 : barH),
        _ => (slot * 0.8, barH),
      };
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * slot, baseY - h, len, h),
          const Radius.circular(3),
        ),
        fill,
      );
    }
    if (term == MusicTerm.legato) {
      // The slur over the joined notes.
      final pen = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      final path = Path()
        ..moveTo(4, baseY - barH - 4)
        ..quadraticBezierTo(
          size.width / 2,
          baseY - barH - 26,
          size.width - 4,
          baseY - barH - 4,
        );
      canvas.drawPath(path, pen);
    }
  }

  @override
  bool shouldRepaint(_ArticulationPainter old) =>
      old.term != term || old.color != color;
}
