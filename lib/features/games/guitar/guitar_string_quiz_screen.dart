// lib/features/games/guitar/guitar_string_quiz_screen.dart
//
// "Welche Saite?" — an open string (fret 0) is shown on the tablature; the
// child names the note it plays (learning E–A–D–G–B–E). The first, easy tier
// of the Gitarren-Ecke, on crisp_notation's TabStaffView.
//
// SRI: 'guitar.string.s<number>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/guitar/guitar_tab.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class GuitarStringQuizScreen extends StatefulWidget {
  const GuitarStringQuizScreen({super.key});

  @override
  State<GuitarStringQuizScreen> createState() => _GuitarStringQuizScreenState();
}

class _GuitarStringQuizScreenState extends State<GuitarStringQuizScreen>
    with QuizRoundMixin {
  final _random = Random();

  /// The five distinct open-string letters (E A D G B), the answer choices.
  static final List<Step> _choices =
      kGuitarOpenStrings.map((s) => s.pitch.step).toSet().toList();

  late GuitarNote _target;
  Step? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'guitar_string_quiz';

  // The plucked open string is the audio feedback.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    _target = kGuitarOpenStrings[_random.nextInt(kGuitarOpenStrings.length)];
    _tapped = null;
    _lastAnswer = null;
  }

  void _onAnswer(Step choice) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = choice == _target.pitch.step;
    final audio = context.read<AudioService>();

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'guitar.string.s${_target.stringNumber}',
            correct,
          );
    }

    if (correct) {
      audio.playMidiNote(_target.pitch.midiNumber, ms: 900);
    } else {
      audio.playWrong();
    }

    setState(() {
      _tapped = choice;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  Color? _buttonColor(Step option) {
    if (_tapped == null) return null;
    if (option == _target.pitch.step && _tapped == _target.pitch.step) {
      return Colors.green;
    }
    if (option == _tapped && option != _target.pitch.step) {
      return Colors.redAccent;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameGuitarStringQuiz),
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
                      prompt: l10n.guitarStringPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: TabStaffView(
                              score: Score.simple(
                                notes:
                                    '${_target.pitch.step.name}${_target.pitch.octave}:w',
                              ),
                              tuning: kGuitarTuning,
                              staffSpace: 16,
                              theme: kidsScoreTheme,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final option in _choices)
                          SizedBox(
                            width: 92,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: _buttonColor(option),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 18),
                                textStyle: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              onPressed: () => _onAnswer(option),
                              child: Text(noteNameFor(context, option)),
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
