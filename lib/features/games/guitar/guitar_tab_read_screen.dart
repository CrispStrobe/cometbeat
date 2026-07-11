// lib/features/games/guitar/guitar_tab_read_screen.dart
//
// "Tabulatur lesen" — a fretted first-position note is shown on the tablature;
// the child names the note it sounds. The reading tier of the Gitarren-Ecke.
//
// SRI: 'guitar.fret.<step><octave>'.

import 'dart:math';

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/guitar/guitar_tab.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

class GuitarTabReadScreen extends StatefulWidget {
  const GuitarTabReadScreen({super.key});

  @override
  State<GuitarTabReadScreen> createState() => _GuitarTabReadScreenState();
}

class _GuitarTabReadScreenState extends State<GuitarTabReadScreen>
    with QuizRoundMixin {
  final _random = Random();

  late GuitarNote _target;
  late List<Step> _options;
  Step? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'guitar_tab_read';

  // The fretted pitch is the audio feedback.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    _target = kGuitarFrettedNotes[_random.nextInt(kGuitarFrettedNotes.length)];
    final distractors = [...Step.values]
      ..remove(_target.pitch.step)
      ..shuffle(_random);
    _options = [_target.pitch.step, ...distractors.take(3)]..shuffle(_random);
    _tapped = null;
    _lastAnswer = null;
  }

  void _onAnswer(Step choice) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = choice == _target.pitch.step;
    final audio = context.read<AudioService>();

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'guitar.fret.${_target.pitch.step.name}${_target.pitch.octave}',
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
      appBar: AppBar(title: Text(l10n.gameGuitarTabRead)),
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
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.guitarTabReadPrompt,
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
                              theme: PartituraTheme.kids,
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
                        for (final option in _options)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _buttonColor(option),
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
