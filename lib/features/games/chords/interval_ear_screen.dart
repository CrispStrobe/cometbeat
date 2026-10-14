// lib/features/games/chords/interval_ear_screen.dart
//
// "Intervall-Detektiv" — two notes are played one after the other; the
// child names the interval. Level 1: second, third, fifth, octave (very
// distinct sounds). SRI: 'chords.interval.<name>'.

import 'dart:math';

import 'package:comet_beat/core/curriculum/interval_songs.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material also exports `Step` (Stepper) and `Interval` (animation curves);
// crisp_notation's win here.
import 'package:flutter/material.dart' hide Step, Interval;
import 'package:provider/provider.dart';

class IntervalEarScreen extends StatefulWidget {
  const IntervalEarScreen({super.key, this.reviewItemIds});

  /// SRI ids (`chords.interval.<second|third|fifth|octave>`) to re-ask instead
  /// of a random interval.
  final List<String>? reviewItemIds;

  @override
  State<IntervalEarScreen> createState() => _IntervalEarScreenState();
}

class _IntervalEarScreenState extends State<IntervalEarScreen>
    with QuizRoundMixin {
  final _random = Random();

  static const _intervals = [
    Interval.majorSecond,
    Interval.majorThird,
    Interval.perfectFifth,
    Interval.perfectOctave,
  ];

  static const _roots = [Step.c, Step.d, Step.e, Step.f, Step.g];

  late Interval _interval;
  late Pitch _root;
  Interval? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'interval_ear';

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playInterval());
  }

  /// The intervals behind [IntervalEarScreen.reviewItemIds]; null when not
  /// reviewing.
  late final List<Interval>? _reviewIntervals = () {
    final ids = {...?widget.reviewItemIds};
    final intervals = [
      for (final i in _intervals)
        if (ids.contains('chords.interval.${_skillName(i)}')) i,
    ];
    return intervals.isEmpty ? null : intervals;
  }();

  static String _skillName(Interval interval) => switch (interval.number) {
        2 => 'second',
        3 => 'third',
        5 => 'fifth',
        _ => 'octave',
      };

  @override
  void prepareRound() {
    final pool = _reviewIntervals ?? _intervals;
    _root = Pitch(_roots[_random.nextInt(_roots.length)]);
    _interval = pool[_random.nextInt(pool.length)];
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playInterval();
  }

  void _playInterval() {
    final top = _root.transposeBy(_interval);
    context.read<AudioService>().playSequence([
      (_root.midiNumber, 650),
      (top.midiNumber, 900),
    ]);
  }

  String _intervalLabel(AppLocalizations l10n, Interval interval) =>
      switch (interval.number) {
        2 => l10n.intervalSecond,
        3 => l10n.intervalThird,
        5 => l10n.intervalFifth,
        _ => l10n.intervalOctave,
      };

  void _onAnswer(Interval choice) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = choice == _interval;

    if (_tapped == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('chords.interval.${_skillName(_interval)}', correct);
    }

    setState(() {
      _tapped = choice;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameIntervalEar),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'interval_ear',
                score: score,
                onRestart: restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    RoundHeader(
                      correct: _lastAnswer,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.listenIntervalPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: IconButton.filledTonal(
                          iconSize: 96,
                          padding: const EdgeInsets.all(32),
                          icon: const Icon(Icons.volume_up),
                          tooltip: l10n.listenAgain,
                          onPressed: _playInterval,
                        ),
                      ),
                    ),
                    Text(
                      l10n.listenAgain,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                    // Once answered, name the interval by a tune the child knows
                    // (locale-neutral: the folk-song name + a ♪). See
                    // core/curriculum/interval_songs.dart.
                    if (intervalSongFor(_interval.semitones) case final s?
                        when _lastAnswer != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Chip(
                          avatar: const Text('♪'),
                          label: Text(s.song),
                        ),
                      ),
                    const SizedBox(height: 16),
                    AnswerGrid(
                      children: [
                        for (final option in _intervals)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _tapped == null
                                  ? null
                                  : option == _interval && _tapped == _interval
                                      ? Colors.green
                                      : option == _tapped
                                          ? Colors.redAccent
                                          : null,
                            ),
                            onPressed: () => _onAnswer(option),
                            child: Text(_intervalLabel(l10n, option)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
