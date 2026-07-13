// lib/features/games/composition/ending_detective_screen.dart
//
// "Schluss-Detektiv" — a short C-major melody plays (and shows); does it
// sound FINISHED? Closure perception: phrases that end on the tonic sound
// closed, endings on 2, 5 or the leading tone hang in the air. The first
// composition-craft skill.
//
// SRI: 'composition.closure.<tonic|open>'.

import 'dart:math';

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/widgets/game_app_bar.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/score_theme.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

class EndingDetectiveScreen extends StatefulWidget {
  const EndingDetectiveScreen({super.key});

  @override
  State<EndingDetectiveScreen> createState() => _EndingDetectiveScreenState();
}

class _EndingDetectiveScreenState extends State<EndingDetectiveScreen>
    with QuizRoundMixin {
  final _random = Random();

  late List<Pitch> _melody;
  late bool _finishedEnding; // ends on the tonic C
  bool? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'ending_detective';

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playMelody());
  }

  @override
  void prepareRound() {
    // Five in-key steps, then the ending: tonic C5 (closed) or one of
    // D5 / B4 / G4 (open).
    var position = 3 + _random.nextInt(3); // F4..A4 region
    final melody = <Pitch>[];
    for (var i = 0; i < 5; i++) {
      melody.add(Clef.treble.pitchAt(position));
      position = (position + [-1, 1, 1, 2][_random.nextInt(4)]).clamp(0, 8);
    }
    _finishedEnding = _random.nextBool();
    final endPosition = _finishedEnding ? 5 : [6, 4, 2][_random.nextInt(3)];
    melody.add(Clef.treble.pitchAt(endPosition)); // C5 or D5/B4/G4
    _melody = melody;
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playMelody();
  }

  void _playMelody() {
    context.read<AudioService>().playSequence([
      for (var i = 0; i < _melody.length; i++)
        (_melody[i].midiNumber, i == _melody.length - 1 ? 800 : 400),
    ]);
  }

  Score get _score => Score.simple(
        notes: _melody
            .asMap()
            .entries
            .map(
              (e) =>
                  '${e.value.step.name}${e.value.octave}${e.key == _melody.length - 1 ? ':h' : e.key == 0 ? ':q' : ''}',
            )
            .join(' '),
      );

  void _onAnswer(bool saysFinished) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = saysFinished == _finishedEnding;

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'composition.closure.${_finishedEnding ? "tonic" : "open"}',
            correct,
          );
    }

    setState(() {
      _tapped = saysFinished;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(
        title: l10n.gameEndingDetective,
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: l10n.listenAgain,
            onPressed: _playMelody,
          ),
        ],
      ),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'ending_detective',
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
                      prompt: l10n.endingDetectivePrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: StaffView(
                              score: _score,
                              staffSpace: 10,
                              theme: kidsScoreTheme,
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
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            child: FilledButton.icon(
                              style: _buttonStyle(context, true),
                              icon: const Icon(Icons.check_circle),
                              onPressed: () => _onAnswer(true),
                              label: Text(l10n.soundsFinished),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            child: FilledButton.icon(
                              style: _buttonStyle(context, false),
                              icon: const Icon(Icons.more_horiz),
                              onPressed: () => _onAnswer(false),
                              label: Text(l10n.soundsOpen),
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

  ButtonStyle _buttonStyle(BuildContext context, bool value) =>
      FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 20),
        backgroundColor: _tapped == null
            ? null
            : value == _finishedEnding && _tapped == _finishedEnding
                ? Colors.green
                : value == _tapped
                    ? Colors.redAccent
                    : null,
      );
}
