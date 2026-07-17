// lib/features/games/keyboard/key_name_screen.dart
//
// "Tasten-Quiz" — one key on the keyboard lights up: what's it called?
// Keyboard geography by the black-key groups (C sits left of the two
// black keys). No labels, of course — that's the point.
//
// SRI: 'keyboard.name.<letter>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:crisp_notation/crisp_notation.dart' show Pitch, Step;
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class KeyNameScreen extends StatefulWidget {
  const KeyNameScreen({super.key});

  @override
  State<KeyNameScreen> createState() => _KeyNameScreenState();
}

class _KeyNameScreenState extends State<KeyNameScreen> with QuizRoundMixin {
  final _random = Random();

  late Pitch _target; // a white key in C4..B4
  late List<Step> _options;
  Step? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'key_name';

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    final step = Step.values[_random.nextInt(Step.values.length)];
    _target = Pitch(step);
    final distractors = [...Step.values]
      ..remove(step)
      ..shuffle(_random);
    _options = ([step, ...distractors.take(3)]..shuffle(_random));
    _tapped = null;
    _lastAnswer = null;
  }

  void _onAnswer(Step choice) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = choice == _target.step;

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'keyboard.name.${_target.step.name}',
            correct,
          );
    }

    if (correct) {
      context.read<AudioService>().playMidiNote(_target.midiNumber);
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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameKeyName),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'key_name',
                score: score,
                onRestart: restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    RoundHeader(
                      correct: _lastAnswer,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.keyNamePrompt,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Center(
                        child: SizedBox(
                          height: 180,
                          child: PianoKeyboard(
                            keyColors: {
                              _target.midiNumber: _lastAnswer == null
                                  ? scheme.primaryContainer
                                  : _lastAnswer!
                                      ? Colors.green
                                      : scheme.primaryContainer,
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 8),
                    AnswerGrid(
                      children: [
                        for (final option in _options)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _tapped == null
                                  ? null
                                  : option == _target.step &&
                                          _tapped == _target.step
                                      ? Colors.green
                                      : option == _tapped
                                          ? Colors.redAccent
                                          : null,
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _onAnswer(option),
                            child: Text(noteNameFor(context, option)),
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
