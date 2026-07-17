// lib/features/games/note_reading/tie_slur_screen.dart
//
// "Tie or Slur?" — a reading drill on the two curved marks that look alike but
// mean different things: a TIE joins two notes of the SAME pitch (hold them as
// one), a SLUR joins notes of DIFFERENT pitch (play them smoothly). The child
// reads the two-note figure and decides which curve it is. Big staff card, two
// tap buttons, no-fail loop.
//
// SRI: 'reading.curve.<tie|slur>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

const _half = NoteDuration(DurationBase.half);

class TieSlurScreen extends StatefulWidget {
  const TieSlurScreen({super.key});

  @override
  State<TieSlurScreen> createState() => _TieSlurScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class TieSlurTester {
  /// Whether the curve is a tie (same pitch) — the correct answer.
  bool get answerTie;
  bool get isFinished;
}

class _TieSlurScreenState extends State<TieSlurScreen>
    with QuizRoundMixin
    implements TieSlurTester {
  @override
  bool get answerTie => _tie;
  @override
  bool get isFinished => finished;

  final _random = Random();

  late Pitch _a; // first note
  late Pitch _b; // second note (same as _a for a tie)
  late bool _tie; // tie (same pitch) vs slur (different pitch)
  bool? _tapped; // last choice (true = tie)
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'tie_slur';

  // A correct answer sounds the two notes; a miss buzzes. No generic blips.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    _tie = _random.nextBool();
    // Comfortable positions on the treble staff [0 .. 8].
    final aPos = 1 + _random.nextInt(7); // 1..7
    _a = Clef.treble.pitchAt(aPos);
    if (_tie) {
      _b = _a; // a tie joins the SAME pitch
    } else {
      // A slur joins a DIFFERENT pitch: a 2nd/3rd away, kept on the staff.
      final step = (1 + _random.nextInt(2)) * (_random.nextBool() ? 1 : -1);
      _b = Clef.treble.pitchAt((aPos + step).clamp(0, 8));
      if (_b.midiNumber == _a.midiNumber) _b = Clef.treble.pitchAt(aPos + 1);
    }
    _tapped = null;
    _lastAnswer = null;
  }

  void _onAnswer(bool tie) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = tie == _tie;
    final audio = context.read<AudioService>();

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'reading.curve.${_tie ? 'tie' : 'slur'}',
            correct,
          );
    }
    if (correct) {
      audio.playPhrase([_a.midiNumber, _b.midiNumber], noteMs: 420);
    } else {
      audio.playWrong();
    }

    setState(() {
      _tapped = tie;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  Score get _cardScore => Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement.note(_a, _half, id: 'a', tieToNext: _tie),
            NoteElement.note(_b, _half, id: 'b'),
          ]),
        ],
        slurs: _tie ? const [] : const [Slur('a', 'b')],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameTieSlur),
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
                      prompt: l10n.tieSlurPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: Card(
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            child: StaffView(
                              score: _cardScore,
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
                    Row(
                      children: [
                        for (final tie in const [true, false])
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  backgroundColor: _tapped == null
                                      ? null
                                      : tie == _tie && _tapped == _tie
                                          ? Colors.green
                                          : tie == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                icon: Icon(
                                  tie ? Icons.link : Icons.gesture,
                                ),
                                onPressed: () => _onAnswer(tie),
                                label: Text(
                                  tie ? l10n.tieLabel : l10n.slurLabel,
                                ),
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
