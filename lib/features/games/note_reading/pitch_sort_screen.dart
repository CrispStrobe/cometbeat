// lib/features/games/note_reading/pitch_sort_screen.dart
//
// "High or Low?" — a drag-and-drop sorting game on pitch *direction*: a note
// sits high or low on the treble staff, and the child drags it into the HIGH or
// LOW bucket. High = above the middle line (B4), low = below it; the middle line
// itself is never used, so every note reads clearly one way. A card only drops
// into the correct bucket; a wrong drop bounces back and buzzes (the no-fail
// loop). The sort-into-buckets format (like Sort the Beats), on the high/low
// dimension (docs/PLAN.md sort backlog).
//
// SRI: 'pitch.height.<high|low>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

const _whole = NoteDuration(DurationBase.whole);

/// The middle line of the treble staff (B4) is position 4; above = high.
const _middlePos = 4;

class PitchSortScreen extends StatefulWidget {
  const PitchSortScreen({super.key, this.clef = Clef.treble});

  /// Which clef the notes are read in (treble by default; a bass variant reuses
  /// the same screen — high/low is clef-independent, but bass gives bass-clef
  /// reading practice and its own pitches/progress).
  final Clef clef;

  static const cardCount = 4;
  static const _buckets = [true, false]; // true = high, false = low

  @override
  State<PitchSortScreen> createState() => _PitchSortScreenState();
}

class _PitchSortScreenState extends State<PitchSortScreen> with QuizRoundMixin {
  final _random = Random();

  late List<Pitch> _cards; // one note per card
  late List<bool> _high; // card index → is it above the middle line?
  late List<bool> _placed;
  final Map<bool, List<Pitch>> _binned = {true: [], false: []};
  final Set<int> _recorded = {};
  bool? _lastDropOk;

  @override
  int get totalRounds => 6;

  @override
  String get gameType => 'pitch_sort';

  // Treble keeps the original id (no progress migration); bass gets its own.
  @override
  String get progressId =>
      widget.clef == Clef.bass ? 'pitch_sort_bass' : 'pitch_sort';

  // Drops give their own feedback (the note sounds on a correct drop, a buzz on
  // a miss); no generic blips.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // Clearly-high (upper half) and clearly-low (lower half) staff positions,
    // never the middle line. Ledger notes join at two stars for more spread.
    final wide = context.read<ProgressService>().starsFor(progressId) >= 2;
    final lows = [for (var p = wide ? -3 : 0; p < _middlePos; p++) p];
    final highs = [
      for (var p = _middlePos + 1; p <= (wide ? 11 : 8); p++) p,
    ];

    // Guarantee at least one of each so both buckets are always in play.
    final positions = <int>[
      lows[_random.nextInt(lows.length)],
      highs[_random.nextInt(highs.length)],
    ];
    while (positions.length < PitchSortScreen.cardCount) {
      final pool = _random.nextBool() ? lows : highs;
      positions.add(pool[_random.nextInt(pool.length)]);
    }
    positions.shuffle(_random);

    _cards = [for (final p in positions) widget.clef.pitchAt(p)];
    _high = [for (final p in positions) p > _middlePos];
    _placed = List.filled(PitchSortScreen.cardCount, false);
    _binned
      ..[true]!.clear()
      ..[false]!.clear();
    _recorded.clear();
    _lastDropOk = null;
  }

  void _onAccept(int cardIndex, bool bucketHigh) {
    // Only ever called for the correct bucket (see onWillAccept).
    if (_recorded.add(cardIndex)) {
      context.read<SriService>().recordResponse(
            'pitch.height.${bucketHigh ? 'high' : 'low'}',
            true,
          );
    }
    context
        .read<AudioService>()
        .playMidiNote(_cards[cardIndex].midiNumber, ms: 400);
    setState(() {
      _placed[cardIndex] = true;
      _binned[bucketHigh]!.add(_cards[cardIndex]);
      _lastDropOk = true;
    });
    if (_placed.every((p) => p)) resolveAnswer(correct: true);
  }

  void _onMiss(int cardIndex) {
    context.read<AudioService>().playWrong();
    if (_recorded.add(cardIndex)) {
      context.read<SriService>().recordResponse(
            'pitch.height.${_high[cardIndex] ? 'high' : 'low'}',
            false,
          );
    }
    setState(() {
      answeredWrong = true;
      _lastDropOk = false;
    });
  }

  Score _score(Pitch p) => Score(
        clef: widget.clef,
        measures: [
          Measure([NoteElement.note(p, _whole, id: 'n')]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(
        title: widget.clef == Clef.bass
            ? l10n.gamePitchSortBass
            : l10n.gamePitchSort,
      ),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: gameType,
                score: score,
                onRestart: restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    RoundHeader(
                      correct: finished ? true : _lastDropOk,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.pitchSortPrompt,
                    ),
                    const SizedBox(height: 16),
                    // Card pool.
                    SizedBox(
                      height: 120,
                      child: Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          children: [
                            for (var i = 0; i < _cards.length; i++)
                              if (!_placed[i])
                                Draggable<int>(
                                  data: i,
                                  feedback: _NoteCard(
                                    score: _score(_cards[i]),
                                    dragging: true,
                                  ),
                                  childWhenDragging: const SizedBox(
                                    width: 84,
                                    height: 104,
                                  ),
                                  onDraggableCanceled: (_, __) => _onMiss(i),
                                  child: _NoteCard(score: _score(_cards[i])),
                                ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final high in PitchSortScreen._buckets)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: DragTarget<int>(
                                onWillAcceptWithDetails: (d) =>
                                    _high[d.data] == high,
                                onAcceptWithDetails: (d) =>
                                    _onAccept(d.data, high),
                                builder: (context, candidate, __) => _Bucket(
                                  high: high,
                                  label: high
                                      ? l10n.pitchHighLabel
                                      : l10n.pitchLowLabel,
                                  hovering: candidate.isNotEmpty,
                                  contents: _binned[high] ?? const [],
                                  scoreOf: _score,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FeedbackLine(correct: finished ? true : _lastDropOk),
                  ],
                ),
              ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Score score;
  final bool dragging;

  const _NoteCard({required this.score, this.dragging = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 84,
        height: 104,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: dragging
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: StaffView(score: score, staffSpace: 7, theme: kidsScoreTheme),
      ),
    );
  }
}

class _Bucket extends StatelessWidget {
  final bool high;
  final String label;
  final bool hovering;
  final List<Pitch> contents;
  final Score Function(Pitch) scoreOf;

  const _Bucket({
    required this.high,
    required this.label,
    required this.hovering,
    required this.contents,
    required this.scoreOf,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 184,
      decoration: BoxDecoration(
        color:
            hovering ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hovering ? scheme.primary : scheme.outlineVariant,
          width: hovering ? 3 : 2,
        ),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                high ? Icons.arrow_upward : Icons.arrow_downward,
                color: scheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final p in contents)
                  SizedBox(
                    width: 64,
                    height: 70,
                    child: StaffView(
                      score: scoreOf(p),
                      staffSpace: 6,
                      theme: kidsScoreTheme,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
