// "Ascending or Descending?" — an ear-training game on the direction of a short
// run: three (four at 2★) notes play in a row, and the child decides whether the
// run climbs up or steps down. A step past Higher or Lower? (which compares only
// two notes) — here a whole little phrase moves one way. No staff; big replay
// button, two answer buttons, no-fail loop.
//
// SRI: 'pitch.hear.<asc|desc>'.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/widgets/game_app_bar.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

class RunDirectionScreen extends StatefulWidget {
  const RunDirectionScreen({super.key});

  @override
  State<RunDirectionScreen> createState() => _RunDirectionScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class RunDirectionTester {
  /// Whether the run ascends (the correct answer).
  bool get answerAsc;
  bool get isFinished;
}

class _RunDirectionScreenState extends State<RunDirectionScreen>
    with QuizRoundMixin
    implements RunDirectionTester {
  final _random = Random();

  bool _wide = false; // 2★ makes the run four notes long
  late List<int> _run; // midi of the run, in order
  late bool _asc; // does the run ascend?
  bool? _tapped; // the child's last choice (true = ascending)
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'run_direction';

  @override
  bool get answerAsc => _asc;

  @override
  bool get isFinished => finished;

  @override
  void initState() {
    super.initState();
    _wide = context.read<ProgressService>().starsFor(gameType) >= 2;
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playRun());
  }

  @override
  void prepareRound() {
    final length = _wide ? 4 : 3;
    _asc = _random.nextBool();
    final start = 60 + _random.nextInt(6); // C4..F4
    _run = [start];
    for (var i = 1; i < length; i++) {
      final step = 2 + _random.nextInt(3); // 2..4 semitones between notes
      _run.add(_run.last + (_asc ? step : -step));
    }
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playRun();
  }

  void _playRun() {
    context.read<AudioService>().playPhrase(_run, noteMs: 420);
  }

  void _onAnswer(bool asc) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = asc == _asc;
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'pitch.hear.${_asc ? 'asc' : 'desc'}',
            correct,
          );
    }
    setState(() {
      _tapped = asc;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: GameAppBar(title: l10n.gameRunDirection),
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
                      prompt: l10n.runDirectionPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: IconButton.filledTonal(
                          iconSize: 96,
                          padding: const EdgeInsets.all(32),
                          icon: const Icon(Icons.volume_up),
                          tooltip: l10n.listenAgain,
                          onPressed: _playRun,
                        ),
                      ),
                    ),
                    Text(
                      l10n.listenAgain,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        for (final asc in const [true, false])
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  backgroundColor: _tapped == null
                                      ? null
                                      : asc == _asc && _tapped == _asc
                                          ? Colors.green
                                          : asc == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                icon: Icon(
                                  asc ? Icons.trending_up : Icons.trending_down,
                                ),
                                onPressed: () => _onAnswer(asc),
                                label: Text(
                                  asc
                                      ? l10n.ascendingLabel
                                      : l10n.descendingLabel,
                                ),
                              ),
                            ),
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
