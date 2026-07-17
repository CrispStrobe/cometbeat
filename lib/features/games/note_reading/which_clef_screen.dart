// "Which Clef?" — a bare clef is shown on an empty staff; the child taps which
// clef it is (Treble or Bass; Alto and Tenor join at 2★). The youngest
// clef-literacy drill — nothing else in the app teaches reading the clef sign
// itself. A binary tap game (AnswerGrid), no-fail. SRI `reading.clef.<name>`.

import 'dart:math';

import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class WhichClefScreen extends StatefulWidget {
  const WhichClefScreen({super.key});

  @override
  State<WhichClefScreen> createState() => _WhichClefScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class WhichClefTester {
  /// Lowercase name of the shown clef — the correct answer (`treble`/`bass`/…).
  String get answerClef;
  bool get isFinished;
}

class _WhichClefScreenState extends State<WhichClefScreen>
    with QuizRoundMixin
    implements WhichClefTester {
  final _random = Random();

  late List<Clef> _options; // the answer set (widens to 4 clefs at 2★)
  late Clef _clef; // the shown clef = the correct answer
  Clef? _tapped; // the last option tapped this round
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'which_clef';

  @override
  String get answerClef => _clefKey(_clef);

  @override
  bool get isFinished => finished;

  @override
  void initState() {
    super.initState();
    // 2★ widens Treble/Bass → all four common clefs.
    final wide = context.read<ProgressService>().starsFor(gameType) >= 2;
    _options = wide
        ? const [Clef.treble, Clef.bass, Clef.alto, Clef.tenor]
        : const [Clef.treble, Clef.bass];
    prepareRound();
  }

  @override
  void prepareRound() {
    _clef = _options[_random.nextInt(_options.length)];
    _tapped = null;
    _lastAnswer = null;
  }

  void _onAnswer(Clef choice) {
    if (_lastAnswer == true) return; // round already cleared
    final correct = choice == _clef;
    // Record only the first attempt of the round (retries aren't re-counted).
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'reading.clef.${_clefKey(_clef)}',
            correct,
          );
    }
    setState(() {
      _tapped = choice;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  Score get _cardScore =>
      Score(clef: _clef, measures: const [Measure([])]); // clef only, no notes

  static String _clefKey(Clef c) => switch (c) {
        Clef.bass => 'bass',
        Clef.alto => 'alto',
        Clef.tenor => 'tenor',
        _ => 'treble',
      };

  static String _clefLabel(AppLocalizations l, Clef c) => switch (c) {
        Clef.bass => l.bassClefLabel,
        Clef.alto => l.altoClefLabel,
        Clef.tenor => l.tenorClefLabel,
        _ => l.trebleClefLabel,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: GameAppBar(title: l10n.gameWhichClef),
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
                      prompt: l10n.whichClefPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: Card(
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 16,
                            ),
                            child: StaffView(
                              score: _cardScore,
                              staffSpace: 18,
                              theme: kidsScoreTheme,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    AnswerGrid(
                      children: [
                        for (final c in _options)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              backgroundColor: _tapped == null
                                  ? null
                                  : c == _clef
                                      ? Colors.green
                                      : c == _tapped
                                          ? Colors.redAccent
                                          : null,
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _onAnswer(c),
                            child: Text(_clefLabel(l10n, c)),
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
