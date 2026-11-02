// lib/features/games/chords/major_minor_sort_screen.dart
//
// "Major or Minor?" — a drag-and-drop sorting game on triad QUALITY read off the
// staff. Each card shows a triad; the child drags it into the Major or Minor
// basket by reading the chord (the third is what decides it). The reading twin of
// the aural Dur-oder-Moll?, and the sort-into-buckets sibling of Sharp or Flat?.
// A card only drops into the correct basket; a wrong drop bounces back and buzzes
// (the no-fail loop).
//
// At 2★ a third basket — Diminished — joins (the lowered fifth), mirroring how
// Sharp or Flat? grows a Natural basket; below 2★ it stays the binary Dur/Moll.
//
// SRI: 'chords.quality.<major|minor|diminished>'.

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

// Roots whose triads sit comfortably low on the treble staff (root + a fifth
// above stays on/near the staff for every quality).
const _roots = <Step>[Step.c, Step.d, Step.e, Step.f, Step.g, Step.a];

class MajorMinorSortScreen extends StatefulWidget {
  const MajorMinorSortScreen({super.key});

  static const cardCount = 4;

  @override
  State<MajorMinorSortScreen> createState() => _MajorMinorSortScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class MajorMinorSortTester {
  /// The quality of the card at [index] — its correct basket.
  ChordQuality qualityOf(int index);
  int get cardCount;
  bool get isFinished;
}

class _MajorMinorSortScreenState extends State<MajorMinorSortScreen>
    with QuizRoundMixin
    implements MajorMinorSortTester {
  final _random = Random();

  late List<Triad> _cards; // one triad per card
  late List<ChordQuality> _buckets; // the baskets in play (2 or 3 qualities)
  late List<bool> _placed;
  late Map<ChordQuality, List<Triad>> _binned;
  final Set<int> _recorded = {};
  bool? _lastDropOk;

  @override
  int get totalRounds => 6;

  @override
  String get gameType => 'major_minor_sort';

  @override
  int get cardCount => MajorMinorSortScreen.cardCount;
  @override
  ChordQuality qualityOf(int index) => _cards[index].quality;
  @override
  bool get isFinished => finished;

  // Drops give their own feedback (the chord sounds on a correct drop, a buzz on
  // a miss); no generic blips.
  @override
  bool get playFeedbackSounds => false;

  String _qualityName(ChordQuality q) => q.name; // major / minor / diminished
  String _qualityGlyph(ChordQuality q) => switch (q) {
        ChordQuality.major => 'M',
        ChordQuality.minor => 'm',
        ChordQuality.diminished => '°',
        ChordQuality.augmented => '+',
      };
  String _qualityLabel(AppLocalizations l, ChordQuality q) => switch (q) {
        ChordQuality.major => l.majorLabel,
        ChordQuality.minor => l.minorLabel,
        ChordQuality.diminished => l.diminishedLabel,
        ChordQuality.augmented => l.diminishedLabel, // unused in this game
      };

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // At 2★ Diminished joins as a third basket. Guarantee at least one of each
    // active quality so every basket is always in play.
    final wide = context.read<ProgressService>().starsFor(gameType) >= 2;
    _buckets = wide
        ? const [
            ChordQuality.major,
            ChordQuality.minor,
            ChordQuality.diminished,
          ]
        : const [ChordQuality.major, ChordQuality.minor];

    final qualities = [..._buckets];
    while (qualities.length < MajorMinorSortScreen.cardCount) {
      qualities.add(_buckets[_random.nextInt(_buckets.length)]);
    }
    qualities.shuffle(_random);

    _cards = [
      for (final q in qualities)
        Triad(Pitch(_roots[_random.nextInt(_roots.length)]), q),
    ];
    _placed = List.filled(MajorMinorSortScreen.cardCount, false);
    _binned = {for (final b in _buckets) b: <Triad>[]};
    _recorded.clear();
    _lastDropOk = null;
  }

  List<int> _midis(Triad t) => [for (final p in t.pitches) p.midiNumber];

  void _onAccept(int cardIndex, ChordQuality quality) {
    // Only ever called for the correct basket (see onWillAccept).
    if (_recorded.add(cardIndex)) {
      context.read<SriService>().recordResponse(
            'chords.quality.${_qualityName(quality)}',
            true,
          );
    }
    context.read<AudioService>().playChordSequence([_midis(_cards[cardIndex])]);
    setState(() {
      _placed[cardIndex] = true;
      _binned[quality]!.add(_cards[cardIndex]);
      _lastDropOk = true;
    });
    if (_placed.every((p) => p)) resolveAnswer(correct: true);
  }

  void _onMiss(int cardIndex) {
    context.read<AudioService>().playWrong();
    if (_recorded.add(cardIndex)) {
      context.read<SriService>().recordResponse(
            'chords.quality.${_qualityName(_cards[cardIndex].quality)}',
            false,
          );
    }
    setState(() {
      answeredWrong = true;
      _lastDropOk = false;
    });
  }

  Score _score(Triad t) => Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement(pitches: t.pitches, duration: _whole, id: 'c'),
          ]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameMajorMinorSort),
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
                      prompt: l10n.majorMinorSortPrompt,
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
                                  feedback: _ChordCard(
                                    score: _score(_cards[i]),
                                    dragging: true,
                                  ),
                                  childWhenDragging: const SizedBox(
                                    width: 84,
                                    height: 104,
                                  ),
                                  child: _ChordCard(score: _score(_cards[i])),
                                ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final quality in _buckets)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: DragTarget<int>(
                                // Any drop on a basket is judged here; a release on no basket
// (a tap, or a drag dropped back) is NOT an answer.
                                onAcceptWithDetails: (d) =>
                                    _cards[d.data].quality == quality
                                        ? _onAccept(d.data, quality)
                                        : _onMiss(d.data),
                                builder: (context, candidate, __) => _Bucket(
                                  glyph: _qualityGlyph(quality),
                                  label: _qualityLabel(l10n, quality),
                                  hovering: candidate.isNotEmpty,
                                  contents: _binned[quality] ?? const [],
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

class _ChordCard extends StatelessWidget {
  final Score score;
  final bool dragging;

  const _ChordCard({required this.score, this.dragging = false});

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
  final String glyph;
  final String label;
  final bool hovering;
  final List<Triad> contents;
  final Score Function(Triad) scoreOf;

  const _Bucket({
    required this.glyph,
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
          Text(
            '$label  $glyph',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final t in contents)
                  SizedBox(
                    width: 64,
                    height: 70,
                    child: StaffView(
                      score: scoreOf(t),
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
