// lib/features/games/cello/cello_string_quiz_screen.dart
//
// "Saiten-Quiz" — a first-position note on the bass clef: which cello
// string is it played on? The four string buttons are drawn like strings
// (C thickest). Every answer plays the note in its true cello register.
//
// SRI: 'cello.string.<step><octave>'.

import 'dart:math';

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

import '../../../core/services/audio_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../l10n/app_localizations.dart';
import '../widgets/game_widgets.dart';
import 'cello_first_position.dart';

class CelloStringQuizScreen extends StatefulWidget {
  const CelloStringQuizScreen({super.key});

  @override
  State<CelloStringQuizScreen> createState() =>
      _CelloStringQuizScreenState();
}

class _CelloStringQuizScreenState extends State<CelloStringQuizScreen>
    with QuizRoundMixin {
  final _random = Random();

  late CelloNote _target;
  CelloString? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  // The cello-register pitch is the audio feedback.
  @override
  bool get playFeedbackSounds => false;

  @override
  String get gameType => 'cello_string_quiz';

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    _target =
        kCelloFirstPosition[_random.nextInt(kCelloFirstPosition.length)];
    _tapped = null;
    _lastAnswer = null;
  }

  void _onAnswer(CelloString choice) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = choice == _target.string;
    final audio = context.read<AudioService>();

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'cello.string.${_target.pitch.step.name}${_target.pitch.octave}',
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameCelloStringQuiz)),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'cello_string_quiz',
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
                      prompt: l10n.celloStringPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 32),
                            child: StaffView(
                              score: Score.simple(
                                clef: Clef.bass,
                                notes:
                                    '${_target.pitch.step.name}${_target.pitch.octave}:w',
                              ),
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
                    // Four "strings": C thickest, A thinnest.
                    Row(
                      children: [
                        for (final string in CelloString.values)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6),
                              child: _StringButton(
                                label: string.label(l10n),
                                thickness:
                                    6.0 - string.index * 1.2,
                                color: _tapped == null
                                    ? null
                                    : string == _target.string &&
                                            _tapped == _target.string
                                        ? Colors.green
                                        : string == _tapped
                                            ? Colors.redAccent
                                            : null,
                                onTap: () => _onAnswer(string),
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

class _StringButton extends StatelessWidget {
  final String label;
  final double thickness;
  final Color? color;
  final VoidCallback onTap;

  const _StringButton({
    required this.label,
    required this.thickness,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: color?.withValues(alpha: 0.2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 96,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The "string" itself.
              Container(
                width: 40,
                height: thickness,
                decoration: BoxDecoration(
                  color: color ?? scheme.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
