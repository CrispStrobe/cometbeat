// lib/features/games/expression/crescendo_read_screen.dart
//
// "Crescendo or Diminuendo?" — a dynamics-reading drill and the staff-read twin
// of the "Getting Louder or Softer?" ear game. A short phrase is drawn under a
// real crisp_notation hairpin (an opening wedge = crescendo = getting louder; a
// closing wedge = diminuendo = getting softer), and the child reads the wedge's
// direction. A correct answer plays the phrase with a matching dynamic ramp — a
// small aural link between the symbol and the sound. Binary staff-read; no-fail.
//
// SRI: 'reading.hairpin.<cresc|dim>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/explain/answer_explanation.dart';
import 'package:comet_beat/features/games/explain/music_terms.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/features/games/widgets/reading_staff.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

const _quarter = NoteDuration(DurationBase.quarter);

class CrescendoReadScreen extends StatefulWidget {
  const CrescendoReadScreen({super.key});

  @override
  State<CrescendoReadScreen> createState() => _CrescendoReadScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class CrescendoReadTester {
  /// Whether the drawn hairpin is a crescendo (the correct answer).
  bool get answerCrescendo;
  bool get isFinished;
}

class _CrescendoReadScreenState extends State<CrescendoReadScreen>
    with QuizRoundMixin
    implements CrescendoReadTester {
  @override
  bool get answerCrescendo => _cresc;
  @override
  bool get isFinished => finished;

  final _random = Random();

  late List<Pitch> _phrase; // the 4-note line the hairpin spans
  late bool _cresc; // is the wedge opening (crescendo)?
  bool? _tapped; // the child's last choice (true = crescendo)
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'crescendo_read';

  // Feedback sound is the dynamic ramp below, not the generic ping.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  Duration get advanceDelay => kExplanationHold;

  @override
  void prepareRound() {
    // A gentle 4-note line on the treble staff (a small arch reads clearly under
    // the wedge). Positions 2..5 keep it inside the staff.
    final start = 2 + _random.nextInt(2); // 2..3
    _phrase = [for (var i = 0; i < 4; i++) Clef.treble.pitchAt(start + i)];
    _cresc = _random.nextBool();
    _tapped = null;
    _lastAnswer = null;
  }

  Score get _cardScore => Score(
        clef: Clef.treble,
        measures: [
          Measure([
            for (var i = 0; i < _phrase.length; i++)
              NoteElement.note(_phrase[i], _quarter, id: 'e$i'),
          ]),
        ],
        hairpins: [
          Hairpin(
            'e0',
            'e${_phrase.length - 1}',
            _cresc ? HairpinType.crescendo : HairpinType.diminuendo,
          ),
        ],
      );

  /// Plays the phrase with a matching dynamic ramp — rising gains for a
  /// crescendo, falling for a diminuendo — linking the wedge to its sound.
  Future<void> _playRamp(AudioService audio) async {
    final gains =
        _cresc ? const [0.25, 0.5, 0.75, 1.0] : const [1.0, 0.75, 0.5, 0.25];
    for (var i = 0; i < _phrase.length; i++) {
      await audio
          .playPhrase([_phrase[i].midiNumber], gain: gains[i], noteMs: 240);
    }
  }

  void _onAnswer(bool cresc) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = cresc == _cresc;
    final audio = context.read<AudioService>();

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'reading.hairpin.${_cresc ? 'cresc' : 'dim'}',
            correct,
          );
    }
    if (correct) {
      _playRamp(audio);
    } else {
      audio.playWrong();
    }

    setState(() {
      _tapped = cresc;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameCrescendoRead),
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
                      prompt: l10n.crescendoReadPrompt,
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
                            child: ReadingStaffView(
                              score: _cardScore,
                              staffSpace: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // After an answer: what the term means (the right one, or
                    // the one tapped if wrong), with a small picture of it.
                    if (_tapped != null) ...[
                      AnswerExplanation(
                        terms: [
                          _tapped! ? MusicTerm.crescendo : MusicTerm.diminuendo,
                        ],
                        onNext: advancePending ? advanceNow : null,
                      ),
                      const SizedBox(height: 8),
                    ],
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    AnswerRow(
                      children: [
                        for (final cresc in const [true, false])
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
                                      : cresc == _cresc && _tapped == _cresc
                                          ? Colors.green
                                          : cresc == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                icon: Icon(
                                  cresc
                                      ? Icons.trending_up
                                      : Icons.trending_down,
                                ),
                                onPressed: () => _onAnswer(cresc),
                                label: Text(
                                  cresc
                                      ? l10n.crescendoLouderLabel
                                      : l10n.crescendoSofterLabel,
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
