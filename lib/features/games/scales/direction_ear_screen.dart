// lib/features/games/scales/direction_ear_screen.dart
//
// "Higher or Lower?" — an ear-training game on melodic *direction*: two notes
// play one after the other, and the child decides whether the second is higher
// or lower than the first. No staff is shown; it is pure listening (the aural
// twin of the visual "High or Low?" sort). Big replay button for repeated
// listening; two answer buttons. No-fail loop (a wrong answer just buzzes).
//
// SRI: 'pitch.hear.<up|down>'.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

class DirectionEarScreen extends StatefulWidget {
  const DirectionEarScreen({super.key});

  @override
  State<DirectionEarScreen> createState() => _DirectionEarScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class DirectionEarTester {
  /// Whether the second note is higher than the first (the correct answer).
  bool get answerUp;
  bool get isFinished;
}

class _DirectionEarScreenState extends State<DirectionEarScreen>
    with QuizRoundMixin
    implements DirectionEarTester {
  @override
  bool get answerUp => _up;
  @override
  bool get isFinished => finished;

  final _random = Random();

  late int _first; // midi of the first note
  late int _second; // midi of the second note
  late bool _up; // is the second higher?
  bool? _tapped; // the child's last choice (true = up)
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'direction_ear';

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playPair());
  }

  @override
  void prepareRound() {
    _first = 60 + _random.nextInt(8); // C4..G4
    final interval = 2 + _random.nextInt(11); // 2..12 semitones (a clear leap)
    _up = _random.nextBool();
    _second = _up ? _first + interval : _first - interval;
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playPair();
  }

  void _playPair() {
    context.read<AudioService>().playPhrase([_first, _second], noteMs: 500);
  }

  void _onAnswer(bool up) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = up == _up;

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'pitch.hear.${_up ? 'up' : 'down'}',
            correct,
          );
    }

    setState(() {
      _tapped = up;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameDirectionEar)),
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
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.directionEarPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: IconButton.filledTonal(
                          iconSize: 96,
                          padding: const EdgeInsets.all(32),
                          icon: const Icon(Icons.volume_up),
                          tooltip: l10n.listenAgain,
                          onPressed: _playPair,
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
                        for (final up in const [true, false])
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
                                      : up == _up && _tapped == _up
                                          ? Colors.green
                                          : up == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                icon: Icon(
                                  up
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward,
                                ),
                                onPressed: () => _onAnswer(up),
                                label: Text(
                                  up
                                      ? l10n.directionUpLabel
                                      : l10n.directionDownLabel,
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
