// lib/features/games/cello/cello_finger_quiz_screen.dart
//
// "Finger-Quiz" — a note on the bass clef: which finger plays it (0 = open
// string, 1–4)? The string is shown as a hint, so the child practices the finger
// pattern, not string-finding (that's the Saiten-Quiz).
//
// Positions 1–4: the pool comes from `celloNotesInPosition`, derived from the
// arranger's hand model, so the same finger pattern can be drilled anywhere on
// the neck instead of only at the nut. Opens in first position.
//
// SRI: 'cello.finger.<step><octave>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/cello/cello_first_position.dart';
import 'package:comet_beat/features/games/cello/cello_positions.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class CelloFingerQuizScreen extends StatefulWidget {
  const CelloFingerQuizScreen({super.key});

  @override
  State<CelloFingerQuizScreen> createState() => _CelloFingerQuizScreenState();
}

class _CelloFingerQuizScreenState extends State<CelloFingerQuizScreen>
    with QuizRoundMixin {
  final _random = Random();

  late CelloNote _target;
  int? _tapped;
  bool? _lastAnswer;

  /// Which neck position is being drilled. Changing it restarts the game — a
  /// score is per position, and mixing them mid-run would grade two skills as
  /// one.
  int _position = 1;
  List<CelloNote> get _pool => celloNotesInPosition(_position);

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
    final pool = _pool;
    _target = pool[_random.nextInt(pool.length)];
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
      appBar: GameAppBar(title: l10n.gameCelloFingerQuiz),
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
                      correct: _lastAnswer,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.celloFingerPrompt(
                        _target.string.label(l10n),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _PositionPicker(
                      position: _position,
                      onChanged: (p) => setState(() {
                        _position = p;
                        restartGame();
                      }),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: StaffView(
                              score: Score.simple(
                                clef: Clef.bass,
                                notes:
                                    '${_target.pitch.step.name}${_target.pitch.octave}:w',
                              ),
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
                        for (final finger in const [0, 1, 2, 3, 4])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
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
                                      ?.copyWith(fontWeight: FontWeight.bold),
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

/// Chips 1–4 for the neck position being drilled. Roman-free on purpose: the
/// games say "1st position" in words elsewhere, and a bare digit row reads at a
/// glance for a child mid-round.
class _PositionPicker extends StatelessWidget {
  const _PositionPicker({required this.position, required this.onChanged});

  final int position;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Wrap (not Row) so the label + position chips flow to a second line on a
    // narrow phone instead of overflowing (the 1–4 positions overran 375px).
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.tabPatternPosition,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(width: 12),
        for (var p = 1; p <= kMaxGamePosition; p++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: ChoiceChip(
              label: Text(celloPositionLabel(p)),
              tooltip: celloPositionName(p).raised
                  ? l10n.celloPositionRaised(celloPositionName(p).number)
                  : null,
              selected: p == position,
              onSelected: (_) => onChanged(p),
            ),
          ),
      ],
    );
  }
}
