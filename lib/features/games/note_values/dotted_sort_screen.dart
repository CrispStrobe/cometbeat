// "Dotted or Not?" — a drag-and-drop sorting game on the augmentation dot: each
// card shows a note (whole/half/quarter/eighth), some carrying a dot, and the
// child drags it into the "Dotted" or "Plain" basket. Reading the little dot —
// which makes a note half again as long — is the skill; the note value varies so
// the shape alone doesn't give it away. A card only drops into the correct
// basket; a wrong drop bounces back and buzzes (the no-fail loop). The
// sort-into-buckets format (like Sharp or Flat? / Sort the Beats).
//
// SRI: 'note_values.dot.<dotted|plain>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

// The note values that can carry a dot (a dotted whole is uncommon; skip it).
const _bases = [DurationBase.half, DurationBase.quarter, DurationBase.eighth];

class DottedSortScreen extends StatefulWidget {
  const DottedSortScreen({super.key});

  static const cardCount = 4;
  static const _buckets = [true, false]; // true = dotted, false = plain

  @override
  State<DottedSortScreen> createState() => _DottedSortScreenState();
}

class _DottedSortScreenState extends State<DottedSortScreen>
    with QuizRoundMixin {
  final _random = Random();

  // All cards sit on the same middle-line pitch so only value + dot vary.
  final Pitch _pitch = Clef.treble.pitchAt(4); // B4

  late List<DurationBase> _base; // card index → note value
  late List<bool> _dotted; // card index → carries a dot
  late List<bool> _placed;
  final Map<bool, List<int>> _binned = {true: [], false: []};
  final Set<int> _recorded = {};
  bool? _lastDropOk;

  @override
  int get totalRounds => 6;

  @override
  String get gameType => 'dotted_sort';

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
    // Guarantee at least one dotted and one plain so both baskets stay in play.
    final dots = <bool>[true, false];
    while (dots.length < DottedSortScreen.cardCount) {
      dots.add(_random.nextBool());
    }
    dots.shuffle(_random);
    _dotted = dots;
    _base = [
      for (var i = 0; i < DottedSortScreen.cardCount; i++)
        _bases[_random.nextInt(_bases.length)],
    ];
    _placed = List.filled(DottedSortScreen.cardCount, false);
    _binned
      ..[true]!.clear()
      ..[false]!.clear();
    _recorded.clear();
    _lastDropOk = null;
  }

  void _onAccept(int cardIndex, bool bucketDotted) {
    // Only ever called for the correct basket (see onWillAccept).
    if (_recorded.add(cardIndex)) {
      context.read<SriService>().recordResponse(
            'note_values.dot.${bucketDotted ? 'dotted' : 'plain'}',
            true,
          );
    }
    context.read<AudioService>().playMidiNote(_pitch.midiNumber, ms: 400);
    setState(() {
      _placed[cardIndex] = true;
      _binned[bucketDotted]!.add(cardIndex);
      _lastDropOk = true;
    });
    if (_placed.every((p) => p)) resolveAnswer(correct: true);
  }

  void _onMiss(int cardIndex) {
    context.read<AudioService>().playWrong();
    if (_recorded.add(cardIndex)) {
      context.read<SriService>().recordResponse(
            'note_values.dot.${_dotted[cardIndex] ? 'dotted' : 'plain'}',
            false,
          );
    }
    setState(() {
      answeredWrong = true;
      _lastDropOk = false;
    });
  }

  Score _scoreOf(int cardIndex) => Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement.note(
              _pitch,
              NoteDuration(_base[cardIndex], dots: _dotted[cardIndex] ? 1 : 0),
              id: 'n',
            ),
          ]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameDottedSort),
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
                      prompt: l10n.dottedSortPrompt,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 120,
                      child: Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          children: [
                            for (var i = 0; i < _base.length; i++)
                              if (!_placed[i])
                                Draggable<int>(
                                  data: i,
                                  feedback: _NoteCard(
                                    score: _scoreOf(i),
                                    dragging: true,
                                  ),
                                  childWhenDragging: const SizedBox(
                                    width: 84,
                                    height: 104,
                                  ),
                                  onDraggableCanceled: (_, __) => _onMiss(i),
                                  child: _NoteCard(score: _scoreOf(i)),
                                ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final dotted in DottedSortScreen._buckets)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: DragTarget<int>(
                                onWillAcceptWithDetails: (d) =>
                                    _dotted[d.data] == dotted,
                                onAcceptWithDetails: (d) =>
                                    _onAccept(d.data, dotted),
                                builder: (context, candidate, __) => _Bucket(
                                  dotted: dotted,
                                  label: dotted
                                      ? l10n.dottedLabel
                                      : l10n.plainLabel,
                                  hovering: candidate.isNotEmpty,
                                  contents: _binned[dotted] ?? const [],
                                  scoreOf: _scoreOf,
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
  final bool dotted;
  final String label;
  final bool hovering;
  final List<int> contents;
  final Score Function(int) scoreOf;

  const _Bucket({
    required this.dotted,
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
            // A quarter note, with a trailing dot for the dotted basket.
            '$label  ♩${dotted ? '.' : ''}',
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
                for (final i in contents)
                  SizedBox(
                    width: 64,
                    height: 70,
                    child: StaffView(
                      score: scoreOf(i),
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
