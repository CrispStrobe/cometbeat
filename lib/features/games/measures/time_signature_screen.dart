// lib/features/games/measures/time_signature_screen.dart
//
// "Time Signatures" — read a time signature and say how many beats are in a bar
// (docs/PLAN.md, built on crisp_notation's common/cut-time glyphs). Includes the C
// (common) and ¢ (cut) symbols nothing else in the app taught.
//
// Star-gated: 3/4, 4/4 and C for beginners; ¢, 6/8 and 2/4 added at 2★.
// SRI: 'measures.timesig.<id>'.

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

class _Sig {
  const _Sig(this.id, this.signature);
  final String id;
  final TimeSignature signature;
}

const _basic = <_Sig>[
  _Sig('3_4', TimeSignature.threeFour),
  _Sig('4_4', TimeSignature.fourFour),
  _Sig('common', TimeSignature.commonTime),
];
const _advanced = <_Sig>[
  _Sig('cut', TimeSignature.cutTime),
  _Sig('6_8', TimeSignature.sixEight),
  _Sig('2_4', TimeSignature.twoFour),
];

class TimeSignatureScreen extends StatefulWidget {
  const TimeSignatureScreen({super.key});

  @override
  State<TimeSignatureScreen> createState() => _TimeSignatureScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class TimeSignatureTester {
  /// Beats per bar for the current round (the correct answer).
  int get answerBeats;
}

class _TimeSignatureScreenState extends State<TimeSignatureScreen>
    with QuizRoundMixin
    implements TimeSignatureTester {
  final _random = Random();

  late _Sig _sig;
  int? _tapped;
  bool? _lastAnswer;
  bool _wide = false;

  @override
  int get answerBeats => _sig.signature.beats;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'time_signature';

  @override
  void initState() {
    super.initState();
    _wide = context.read<ProgressService>().starsFor(gameType) >= 2;
    prepareRound();
  }

  @override
  void prepareRound() {
    final pool = _wide ? [..._basic, ..._advanced] : _basic;
    _sig = pool[_random.nextInt(pool.length)];
    _tapped = null;
    _lastAnswer = null;
  }

  void _onAnswer(int beats) {
    if (_lastAnswer == true) return;
    final correct = beats == _sig.signature.beats;
    if (_tapped == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('measures.timesig.${_sig.id}', correct);
    }
    context
        .read<AudioService>()
        .playCountedNote(_sig.signature.beats, beatMs: 420);
    setState(() {
      _tapped = beats;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameTimeSignature),
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
                      prompt: l10n.timeSignaturePrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 44,
                              vertical: 16,
                            ),
                            child: StaffView(
                              score: Score(
                                clef: Clef.treble,
                                timeSignature: _sig.signature,
                                measures: const [Measure([])],
                              ),
                              staffSpace: 16,
                              theme: kidsScoreTheme,
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
                        for (final beats in const [2, 3, 4, 6])
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _tapped == null
                                  ? null
                                  : beats == _sig.signature.beats
                                      ? Colors.green
                                      : beats == _tapped
                                          ? Colors.redAccent
                                          : null,
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _onAnswer(beats),
                            child: Text(l10n.beatsCount(beats)),
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
