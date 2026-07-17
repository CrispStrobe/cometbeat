// lib/features/games/note_reading/beam_flag_screen.dart
//
// "Beam or Flag?" — a reading drill on the two ways short notes (eighths) are
// written. When eighths sit together on one beat they are joined by a BEAM (a
// thick bar across their stems); when they stand apart they each keep their own
// FLAG (a little tail). Same rhythm, two looks. The child reads the figure and
// decides which one it is. Big staff card, two tap buttons, no-fail loop.
//
// The engraver beams eighths that share a beat and flags eighths separated by a
// rest — so the "beamed" card is two eighths on beat 1, and the "flagged" card
// is two eighths each followed by an eighth rest (verified in crisp_notation:
// same-beat eighths → 1 beam, eighth-rest between → 0 beams).
//
// SRI: 'reading.beam.<beamed|flagged>'.

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

const _eighth = NoteDuration(DurationBase.eighth);
const _quarter = NoteDuration(DurationBase.quarter);
const _half = NoteDuration(DurationBase.half);

class BeamFlagScreen extends StatefulWidget {
  const BeamFlagScreen({super.key});

  @override
  State<BeamFlagScreen> createState() => _BeamFlagScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class BeamFlagTester {
  /// Whether the figure is beamed (the correct answer).
  bool get answerBeamed;
  bool get isFinished;
}

class _BeamFlagScreenState extends State<BeamFlagScreen>
    with QuizRoundMixin
    implements BeamFlagTester {
  @override
  bool get answerBeamed => _beamed;
  @override
  bool get isFinished => finished;

  final _random = Random();

  late Pitch _a; // first eighth
  late Pitch _b; // second eighth
  late bool _beamed; // beamed (joined) vs flagged (apart)
  bool? _tapped; // last choice (true = beamed)
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'beam_flag';

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
    _beamed = _random.nextBool();
    // Two comfortable positions on the treble staff [0 .. 8], a small step
    // apart so the beam/flags read cleanly.
    final aPos = 1 + _random.nextInt(6); // 1..6
    final step = (1 + _random.nextInt(2)) * (_random.nextBool() ? 1 : -1);
    _a = Clef.treble.pitchAt(aPos);
    _b = Clef.treble.pitchAt((aPos + step).clamp(0, 8));
    _tapped = null;
    _lastAnswer = null;
  }

  void _onAnswer(bool beamed) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = beamed == _beamed;
    final audio = context.read<AudioService>();

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'reading.beam.${_beamed ? 'beamed' : 'flagged'}',
            correct,
          );
    }
    if (correct) {
      audio.playPhrase([_a.midiNumber, _b.midiNumber], noteMs: 300);
    } else {
      audio.playWrong();
    }

    setState(() {
      _tapped = beamed;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  // Beamed: two eighths on beat 1 (the engraver joins them with a beam).
  // Flagged: two eighths each followed by an eighth rest, so neither beams and
  // both keep their flag.
  Score get _cardScore => Score(
        clef: Clef.treble,
        measures: [
          Measure(
            _beamed
                ? [
                    NoteElement.note(_a, _eighth, id: 'a'),
                    NoteElement.note(_b, _eighth, id: 'b'),
                    const RestElement(_quarter),
                    const RestElement(_half),
                  ]
                : [
                    NoteElement.note(_a, _eighth, id: 'a'),
                    const RestElement(_eighth),
                    NoteElement.note(_b, _eighth, id: 'b'),
                    const RestElement(_eighth),
                    const RestElement(_half),
                  ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameBeamFlag),
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
                      prompt: l10n.beamFlagPrompt,
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
                        for (final beamed in const [true, false])
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
                                      : beamed == _beamed && _tapped == _beamed
                                          ? Colors.green
                                          : beamed == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                icon: Icon(
                                  beamed ? Icons.horizontal_rule : Icons.flag,
                                ),
                                onPressed: () => _onAnswer(beamed),
                                label: Text(
                                  beamed ? l10n.beamLabel : l10n.flagLabel,
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
