// "Same or Different?" — the youngest ear-discrimination skill (Kodály): two
// notes play one after the other, and the child decides whether they are the
// same pitch or different. No staff — pure listening. A clear gap for beginners,
// subtler gaps (down to a semitone) at 2★. Big replay button, two answer
// buttons, no-fail loop.
//
// SRI: 'pitch.hear.<same|diff>'.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/widgets/game_app_bar.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

class SameDiffScreen extends StatefulWidget {
  const SameDiffScreen({super.key});

  @override
  State<SameDiffScreen> createState() => _SameDiffScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class SameDiffTester {
  /// Whether the two notes are the same pitch (the correct answer).
  bool get answerSame;
  bool get isFinished;
}

class _SameDiffScreenState extends State<SameDiffScreen>
    with QuizRoundMixin
    implements SameDiffTester {
  final _random = Random();

  bool _wide = false; // 2★ makes "different" subtler (down to a semitone)
  late int _first; // midi of the first note
  late int _second; // midi of the second note
  late bool _same; // are the two notes the same pitch?
  bool? _tapped; // the child's last choice (true = same)
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'same_diff';

  @override
  bool get answerSame => _same;

  @override
  bool get isFinished => finished;

  @override
  void initState() {
    super.initState();
    _wide = context.read<ProgressService>().starsFor(gameType) >= 2;
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playPair());
  }

  @override
  void prepareRound() {
    _first = 60 + _random.nextInt(12); // C4..B4
    _same = _random.nextBool();
    if (_same) {
      _second = _first;
    } else {
      // Beginners get a clear leap; 2★ narrows it toward a single semitone.
      final minGap = _wide ? 1 : 3;
      final maxGap = _wide ? 4 : 12;
      final interval = minGap + _random.nextInt(maxGap - minGap + 1);
      _second = _random.nextBool() ? _first + interval : _first - interval;
    }
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playPair();
  }

  void _playPair() {
    context.read<AudioService>().playPhrase([_first, _second], noteMs: 500);
  }

  void _onAnswer(bool same) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = same == _same;
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'pitch.hear.${_same ? 'same' : 'diff'}',
            correct,
          );
    }
    setState(() {
      _tapped = same;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: GameAppBar(title: l10n.gameSameDiff),
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
                      prompt: l10n.sameDiffPrompt,
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
                        for (final same in const [true, false])
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
                                      : same == _same && _tapped == _same
                                          ? Colors.green
                                          : same == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                icon: Icon(
                                  same
                                      ? Icons.horizontal_rule
                                      : Icons.compare_arrows,
                                ),
                                onPressed: () => _onAnswer(same),
                                label: Text(
                                  same ? l10n.sameLabel : l10n.differentLabel,
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
