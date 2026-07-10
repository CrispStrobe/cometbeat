// lib/features/games/harmony/harmony_quiz_screen.dart
//
// "Funktions-Quiz" — a triad is rendered in a labeled key (with its key
// signature); the child decides: Tonika, Subdominante or Dominante?
// Built on partitura_core's Key.triadFor(HarmonicFunction).
//
// SRI: 'harmony.function.<tonic>_<function>'.

import 'dart:math';

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step, Key;
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

import '../../../core/services/sri_service.dart';
import '../../../l10n/app_localizations.dart';
import '../note_reading/note_names.dart';
import '../widgets/game_widgets.dart';

class HarmonyQuizScreen extends StatefulWidget {
  const HarmonyQuizScreen({super.key});

  @override
  State<HarmonyQuizScreen> createState() => _HarmonyQuizScreenState();
}

class _HarmonyQuizScreenState extends State<HarmonyQuizScreen>
    with QuizRoundMixin {
  final _random = Random();

  // Beginner keys; more via difficulty progression (see docs/PLAN.md).
  static const _tonics = [Step.c, Step.g, Step.f];

  late Step _tonic;
  late Key _key;
  late HarmonicFunction _function;
  HarmonicFunction? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    _tonic = _tonics[_random.nextInt(_tonics.length)];
    _key = Key.major(Pitch(_tonic));
    _function = HarmonicFunction
        .values[_random.nextInt(HarmonicFunction.values.length)];
    _tapped = null;
    _lastAnswer = null;
  }

  String _token(Pitch p) {
    // The key signature covers the triad's alterations; no explicit
    // accidentals needed for T/S/D primary triads in major.
    return '${p.step.name}${p.octave}';
  }

  Score get _score {
    final pitches = _key.triadFor(_function).pitches;
    return Score.simple(
      keySignature: _key.signature,
      notes: '${pitches.map(_token).join('+')}:w',
    );
  }

  String _functionLabel(AppLocalizations l10n, HarmonicFunction f) =>
      switch (f) {
        HarmonicFunction.tonic => l10n.harmonicTonic,
        HarmonicFunction.subdominant => l10n.harmonicSubdominant,
        HarmonicFunction.dominant => l10n.harmonicDominant,
      };

  void _onAnswer(HarmonicFunction choice) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = choice == _function;

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'harmony.function.${_tonic.name}_${_function.name}',
            correct,
          );
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
      appBar: AppBar(title: Text(l10n.gameHarmonyQuiz)),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'harmony_quiz',
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
                      prompt: l10n.harmonyPrompt(
                          l10n.keyMajorName(noteName(l10n, _tonic))),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 48),
                            child: StaffView(
                              score: _score,
                              staffSpace: 14,
                              theme: PartituraTheme.kids,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    Column(
                      children: [
                        for (final option in HarmonicFunction.values)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 4),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _tapped == null
                                      ? null
                                      : option == _function &&
                                              _tapped == _function
                                          ? Colors.green
                                          : option == _tapped
                                              ? Colors.redAccent
                                              : null,
                                ),
                                onPressed: () => _onAnswer(option),
                                child: Text(_functionLabel(l10n, option)),
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
