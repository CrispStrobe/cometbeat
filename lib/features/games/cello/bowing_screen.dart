// lib/features/games/cello/bowing_screen.dart
//
// "Bowing" — read string bowing marks (docs/PLAN.md, built on crisp_notation's
// up-bow/down-bow articulations). A note is shown on the bass staff with a bow
// mark; the child names it: down-bow (⊓) or up-bow (∨). At 2★ the down-bow-on-
// the-downbeat convention is taught via a two-note bar.
//
// SRI: 'cello.bowing.<down|up>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material also exports `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class BowingScreen extends StatefulWidget {
  const BowingScreen({super.key});

  @override
  State<BowingScreen> createState() => _BowingScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class BowingTester {
  /// True when the current round's mark is a down-bow.
  bool get isDown;
}

class _BowingScreenState extends State<BowingScreen>
    with QuizRoundMixin
    implements BowingTester {
  static const _wholeNote = NoteDuration(DurationBase.whole);

  final _random = Random();

  late Pitch _pitch;
  late bool _down;
  bool? _tapped; // the answer chosen (true = down)
  bool? _lastAnswer;

  @override
  bool get isDown => _down;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'bowing';

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // A comfortable note on the bass staff (cello reads bass clef).
    _pitch = Clef.bass.pitchAt(1 + _random.nextInt(7));
    _down = _random.nextBool();
    _tapped = null;
    _lastAnswer = null;
  }

  void _onAnswer(bool down) {
    if (_lastAnswer == true) return;
    final correct = down == _down;
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'cello.bowing.${_down ? 'down' : 'up'}',
            correct,
          );
    }
    context.read<AudioService>().playMidiNote(_pitch.midiNumber);
    setState(() {
      _tapped = down;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  Score get _score => Score(
        clef: Clef.bass,
        measures: [
          Measure([
            NoteElement.note(
              _pitch,
              _wholeNote,
              id: 'n',
              articulations: {
                _down ? Articulation.downBow : Articulation.upBow,
              },
            ),
          ]),
        ],
      );

  Widget _bowButton(BuildContext context, {required bool down}) {
    final l10n = AppLocalizations.of(context)!;
    final selected = _tapped != null;
    return FilledButton(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 20),
        backgroundColor: !selected
            ? null
            : down == _down
                ? Colors.green
                : down == _tapped
                    ? Colors.redAccent
                    : null,
        textStyle: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
      onPressed: () => _onAnswer(down),
      child: Text(down ? '⊓  ${l10n.bowDown}' : '∨  ${l10n.bowUp}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameBowing),
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
                      prompt: l10n.bowingPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 16,
                            ),
                            child: StaffView(
                              score: _score,
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
                    Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: _bowButton(context, down: true),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: _bowButton(context, down: false),
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
