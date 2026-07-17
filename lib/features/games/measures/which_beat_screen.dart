// lib/features/games/measures/which_beat_screen.dart
//
// "Which Beat?" — rhythmic placement (docs/PLAN.md, built on crisp_notation's
// beat-number teaching overlay). A 4/4 bar of notes is shown with one note
// highlighted; the child taps the beat it starts on (1–4). crisp_notation draws the
// "1 2 3 4" counting under the staff as a scaffold that fades: on for beginners,
// off at 2★ so the child must count the durations themselves.
//
// SRI: 'measures.beat.<n>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A bar pattern: note durations (in beats) that sum to 4, all on integer beats.
const _patterns = <List<int>>[
  [1, 1, 1, 1],
  [2, 1, 1],
  [1, 2, 1],
  [1, 1, 2],
  [2, 2],
];

class WhichBeatScreen extends StatefulWidget {
  const WhichBeatScreen({super.key});

  @override
  State<WhichBeatScreen> createState() => _WhichBeatScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class WhichBeatTester {
  /// The beat (1–4) the highlighted note starts on.
  int get answerBeat;
}

class _WhichBeatScreenState extends State<WhichBeatScreen>
    with QuizRoundMixin
    implements WhichBeatTester {
  final _random = Random();

  late List<int> _durations;
  late int _targetIndex; // which note is highlighted
  late int _answerBeat;
  bool _scaffold = true;
  int? _tapped;
  bool? _lastAnswer;

  @override
  int get answerBeat => _answerBeat;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'which_beat';

  @override
  void initState() {
    super.initState();
    _scaffold = context.read<ProgressService>().starsFor(gameType) < 2;
    prepareRound();
  }

  @override
  void prepareRound() {
    _durations = _patterns[_random.nextInt(_patterns.length)];
    _targetIndex = _random.nextInt(_durations.length);
    // The target's start beat = 1 + sum of durations before it.
    _answerBeat =
        1 + _durations.take(_targetIndex).fold<int>(0, (a, b) => a + b);
    _tapped = null;
    _lastAnswer = null;
  }

  // A repeated pitch keeps the focus on rhythm; ':h' for halves, ':q' quarters.
  Score get _score {
    final tokens = [
      for (final d in _durations) d == 2 ? 'b4:h' : 'b4:q',
    ].join(' ');
    return Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: tokens,
    );
  }

  void _onAnswer(int beat) {
    if (_lastAnswer == true) return;
    final correct = beat == _answerBeat;
    if (_tapped == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('measures.beat.$_answerBeat', correct);
    }
    if (correct) {
      context.read<AudioService>().playCorrect();
    } else {
      context.read<AudioService>().playWrong();
    }
    setState(() {
      _tapped = beat;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final theme = kidsScoreTheme.copyWith(
      elementColors: {'e$_targetIndex': scheme.primary},
    );

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameWhichBeat),
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
                      correct: _lastAnswer,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.whichBeatPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            child: StaffView(
                              score: _score,
                              staffSpace: 14,
                              showBeatNumbers: _scaffold,
                              theme: theme,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 12),
                    AnswerGrid(
                      children: [
                        for (var beat = 1; beat <= 4; beat++)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _tapped == null
                                  ? null
                                  : beat == _answerBeat
                                      ? Colors.green
                                      : beat == _tapped
                                          ? Colors.redAccent
                                          : null,
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _onAnswer(beat),
                            child: Text('$beat'),
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
