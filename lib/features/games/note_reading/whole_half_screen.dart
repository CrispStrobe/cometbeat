// "Whole or Half Step?" — two neighbour notes (a 2nd) are shown; the child taps
// whether the gap is a whole step (tone) or a half step (semitone). The natural
// sequel to Step or Skip? and the foundation of scale-building — half steps hide
// at E–F and B–C, so a plain 2nd isn't enough; you must read the letters.
// Naturals only; treble at 1★, +bass clef at 2★. SRI `reading.tone.<whole|half>`.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

const _halfNote = NoteDuration(DurationBase.half);

class WholeHalfScreen extends StatefulWidget {
  const WholeHalfScreen({super.key});

  @override
  State<WholeHalfScreen> createState() => _WholeHalfScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class WholeHalfTester {
  /// Whether the shown gap is a half step (the correct answer).
  bool get answerHalf;
  bool get isFinished;
}

class _WholeHalfScreenState extends State<WholeHalfScreen>
    with QuizRoundMixin
    implements WholeHalfTester {
  final _random = Random();

  bool _wide = false; // 2★ adds the bass clef
  late Clef _clef;
  late Pitch _a;
  late Pitch _b;
  late bool _half; // true = half step (semitone), false = whole step (tone)
  bool? _tapped; // the last option tapped (true = "half step")
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'whole_half';

  @override
  bool get playFeedbackSounds => false; // sounds the interval itself

  @override
  bool get answerHalf => _half;

  @override
  bool get isFinished => finished;

  @override
  void initState() {
    super.initState();
    _wide = context.read<ProgressService>().starsFor(gameType) >= 2;
    prepareRound();
  }

  @override
  void prepareRound() {
    _clef = _wide && _random.nextBool() ? Clef.bass : Clef.treble;
    final wantHalf = _random.nextBool();
    // Every adjacent line/space pair in a comfortable range, split by tone vs
    // semitone; a half step only falls at E–F / B–C, so we pick from the wanted
    // bucket to keep the two answers balanced.
    final candidates = <(Pitch, Pitch)>[];
    for (var pos = -1; pos <= 7; pos++) {
      for (final dir in const [1, -1]) {
        final a = _clef.pitchAt(pos);
        final b = _clef.pitchAt(pos + dir);
        if (((b.midiNumber - a.midiNumber).abs() == 1) == wantHalf) {
          candidates.add((a, b));
        }
      }
    }
    final pick = candidates[_random.nextInt(candidates.length)];
    _a = pick.$1;
    _b = pick.$2;
    _half = wantHalf;
    _tapped = null;
    _lastAnswer = null;
  }

  void _onAnswer(bool half) {
    if (_lastAnswer == true) return; // round already cleared
    final correct = half == _half;
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'reading.tone.${_half ? 'half' : 'whole'}',
            correct,
          );
    }
    final audio = context.read<AudioService>();
    if (correct) {
      audio.playPhrase([_a.midiNumber, _b.midiNumber], noteMs: 380);
    } else {
      audio.playWrong();
    }
    setState(() {
      _tapped = half;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  Score get _cardScore => Score(
        clef: _clef,
        measures: [
          Measure([
            NoteElement.note(_a, _halfNote, id: 'a'),
            NoteElement.note(_b, _halfNote, id: 'b'),
          ]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: GameAppBar(title: l10n.gameWholeHalf),
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
                      prompt: l10n.wholeHalfPrompt,
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
                        for (final half in const [false, true])
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
                                      : half == _half
                                          ? Colors.green
                                          : half == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                icon: Icon(
                                  half ? Icons.compress : Icons.open_in_full,
                                ),
                                onPressed: () => _onAnswer(half),
                                label: Text(
                                  half
                                      ? l10n.halfStepLabel
                                      : l10n.wholeStepLabel,
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
