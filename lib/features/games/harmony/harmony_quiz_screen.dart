// lib/features/games/harmony/harmony_quiz_screen.dart
//
// "Funktions-Quiz" — a triad is rendered in a labeled key (with its key
// signature); the child decides: Tonika, Subdominante or Dominante?
// Built on crisp_notation_core's Key.triadFor(HarmonicFunction).
//
// SRI: 'harmony.function.<tonic>_<function>'.

import 'dart:math';

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step, Key;
import 'package:provider/provider.dart';

class HarmonyQuizScreen extends StatefulWidget {
  /// Review mode: full SRI item IDs (`harmony.function.<tonic>_<function>`).
  final List<String>? reviewItemIds;

  const HarmonyQuizScreen({super.key, this.reviewItemIds});

  @override
  State<HarmonyQuizScreen> createState() => _HarmonyQuizScreenState();
}

class _HarmonyQuizScreenState extends State<HarmonyQuizScreen>
    with QuizRoundMixin {
  final _random = Random();

  // Beginner keys; more via difficulty progression (see docs/PLAN.md).
  static const _tonics = [Step.c, Step.g, Step.f];

  List<(Step, HarmonicFunction)>? _reviewItems;
  bool get _isReview => _reviewItems != null;

  late Step _tonic;
  late Key _key;
  late HarmonicFunction _function;
  HarmonicFunction? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => _reviewItems?.length ?? 10;

  @override
  bool get isReviewSession => _isReview;

  @override
  String get gameType => 'harmony_quiz';

  @override
  void initState() {
    super.initState();
    final parsed = widget.reviewItemIds
        ?.map((id) {
          final parts = id.split('.').last.split('_');
          if (parts.length != 2) return null;
          final tonic = Step.values.asNameMap()[parts[0]];
          final function = HarmonicFunction.values.asNameMap()[parts[1]];
          return (tonic == null || function == null) ? null : (tonic, function);
        })
        .whereType<(Step, HarmonicFunction)>()
        .toList();
    _reviewItems = (parsed == null || parsed.isEmpty) ? null : parsed;
    prepareRound();
  }

  @override
  void prepareRound() {
    if (_isReview) {
      final (tonic, function) = _reviewItems![round];
      _tonic = tonic;
      _function = function;
    } else {
      _tonic = _tonics[_random.nextInt(_tonics.length)];
      _function = HarmonicFunction
          .values[_random.nextInt(HarmonicFunction.values.length)];
    }
    _key = Key.major(Pitch(_tonic));
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
      appBar: GameAppBar(
        title: _isReview ? l10n.reviewTitle : l10n.gameHarmonyQuiz,
      ),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'harmony_quiz',
                score: score,
                onRestart: _isReview ? null : restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    RoundHeader(
                      correct: _lastAnswer,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.harmonyPrompt(
                        l10n.keyMajorName(noteNameFor(context, _tonic)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 48),
                            child: StaffView(
                              score: _score,
                              staffSpace: 14,
                              theme: kidsScoreTheme,
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
                            padding: const EdgeInsets.symmetric(vertical: 4),
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
