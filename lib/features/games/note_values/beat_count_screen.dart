// lib/features/games/note_values/beat_count_screen.dart
//
// "Schläge zählen" — a note (possibly dotted, possibly TIED to a second
// note — crisp_notation v0.3 ties) is shown and played; the child counts how
// many quarter-note beats it lasts. Duration arithmetic made audible:
// a tie means "add them up".
//
// SRI: 'note_values.beats.<exprId>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart' show Score, StaffView;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class _BeatExpr {
  final String id; // SRI detail
  final String dsl; // on a fixed pitch, may contain a tie
  final int beats; // in quarters

  const _BeatExpr(this.id, this.dsl, this.beats);
}

const _expressions = <_BeatExpr>[
  _BeatExpr('q', 'g4:q', 1),
  _BeatExpr('h', 'g4:h', 2),
  _BeatExpr('h_dot', 'g4:h.', 3),
  _BeatExpr('w', 'g4:w', 4),
  _BeatExpr('q_q_tied', 'g4:q~ g4:q', 2),
  _BeatExpr('h_q_tied', 'g4:h~ g4:q', 3),
  _BeatExpr('h_h_tied', 'g4:h~ g4:h', 4),
  _BeatExpr('h_dot_q_tied', 'g4:h.~ g4:q', 4),
];

class BeatCountScreen extends StatefulWidget {
  const BeatCountScreen({super.key});

  @override
  State<BeatCountScreen> createState() => _BeatCountScreenState();
}

class _BeatCountScreenState extends State<BeatCountScreen> with QuizRoundMixin {
  final _random = Random();

  late _BeatExpr _expr;
  int? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'beat_count';

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playExpr());
  }

  @override
  void prepareRound() {
    _expr = _expressions[_random.nextInt(_expressions.length)];
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playExpr();
  }

  void _playExpr() {
    // One sustained tone for the summed duration — that's what a tie means.
    context.read<AudioService>().playMidiNote(67, ms: _expr.beats * 550);
  }

  void _playCounted() {
    // The same note with an audible beat, so the child can count along.
    context.read<AudioService>().playCountedNote(_expr.beats);
  }

  void _onAnswer(int beats) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = beats == _expr.beats;

    if (_tapped == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('note_values.beats.${_expr.id}', correct);
    }

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
      appBar: GameAppBar(
        title: l10n.gameBeatCount,
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: l10n.listenAgain,
            onPressed: _playExpr,
          ),
          IconButton(
            icon: const Icon(Icons.timer),
            tooltip: l10n.countAlong,
            onPressed: _playCounted,
          ),
        ],
      ),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'beat_count',
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
                      prompt: l10n.beatCountPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: StaffView(
                              score: Score.simple(notes: _expr.dsl),
                              staffSpace: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        for (final beats in const [1, 2, 3, 4])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  backgroundColor: _tapped == null
                                      ? null
                                      : beats == _expr.beats &&
                                              _tapped == _expr.beats
                                          ? Colors.green
                                          : beats == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                onPressed: () => _onAnswer(beats),
                                child: Text('$beats'),
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
