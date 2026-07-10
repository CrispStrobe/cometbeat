// lib/features/games/cello/cello_finger_quiz_screen.dart
//
// "Finger-Quiz" — a first-position note on the bass clef: which finger
// plays it (0 = open string, 1–4)? The string is shown as a hint, so the
// child practices the finger pattern, not string-finding (that's the
// Saiten-Quiz).
//
// SRI: 'cello.finger.<step><octave>'.

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

class CelloFingerQuizScreen extends StatefulWidget {
  const CelloFingerQuizScreen({super.key});

  @override
  State<CelloFingerQuizScreen> createState() =>
      _CelloFingerQuizScreenState();
}

class _CelloFingerQuizScreenState extends State<CelloFingerQuizScreen>
    with QuizRoundMixin {
  final _random = Random();

  late CelloNote _target;
  int? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  // The cello-register pitch is the audio feedback.
  @override
  bool get playFeedbackSounds => false;

  @override
  String get gameType => 'cello_finger_quiz';

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

  void _onAnswer(int finger) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = finger == _target.finger;
    final audio = context.read<AudioService>();

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'cello.finger.${_target.pitch.step.name}${_target.pitch.octave}',
            correct,
          );
    }

    if (correct) {
      audio.playMidiNote(_target.pitch.midiNumber, ms: 900);
    } else {
      audio.playWrong();
    }

    setState(() {
      _tapped = finger;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameCelloFingerQuiz)),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'cello_finger_quiz',
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
                      prompt: l10n.celloFingerPrompt(
                          _target.string.label(l10n)),
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
                    Row(
                      children: [
                        for (final finger in const [0, 1, 2, 3, 4])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4),
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 20),
                                  backgroundColor: _tapped == null
                                      ? null
                                      : finger == _target.finger &&
                                              _tapped == _target.finger
                                          ? Colors.green
                                          : finger == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                          fontWeight: FontWeight.bold),
                                ),
                                onPressed: () => _onAnswer(finger),
                                child: Text('$finger'),
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
