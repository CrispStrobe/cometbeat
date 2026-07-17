// lib/features/games/note_reading/duet_screen.dart
//
// "Duet" — score reading across a two-staff system (docs/PLAN.md, built on
// crisp_notation's StaffSystemView). Two parts are shown one above the other with one
// note highlighted; the child names the highlighted note — so they have to track
// the right line of a multi-staff score. At 2★ the lower part switches to the
// bass clef, like a real grand-staff duet.
//
// SRI: 'note_reading.<clef>.<step><octave>' on the highlighted note.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material also exports `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

const _wholeNote = NoteDuration(DurationBase.whole);

class DuetScreen extends StatefulWidget {
  const DuetScreen({super.key});

  @override
  State<DuetScreen> createState() => _DuetScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class DuetTester {
  /// The letter of the highlighted note (the correct answer).
  Step get answerStep;
}

class _DuetScreenState extends State<DuetScreen>
    with QuizRoundMixin
    implements DuetTester {
  final _random = Random();

  late Pitch _topPitch;
  late Pitch _bottomPitch;
  late Clef _bottomClef;
  late bool _targetIsTop;
  late List<Step> _options;
  Step? _tapped;
  bool? _lastAnswer;
  bool _wide = false;

  Pitch get _target => _targetIsTop ? _topPitch : _bottomPitch;
  Clef get _targetClef => _targetIsTop ? Clef.treble : _bottomClef;

  @override
  Step get answerStep => _target.step;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'duet';

  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    _wide = context.read<ProgressService>().starsFor(gameType) >= 2;
    prepareRound();
  }

  @override
  void prepareRound() {
    // Lower part is bass clef once the game has earned two stars.
    _bottomClef = _wide ? Clef.bass : Clef.treble;
    _topPitch = Clef.treble.pitchAt(1 + _random.nextInt(8)); // top staff
    _bottomPitch = _bottomClef.pitchAt(1 + _random.nextInt(8));
    _targetIsTop = _random.nextBool();

    final distractors = [...Step.values]
      ..remove(_target.step)
      ..shuffle(_random);
    _options = [_target.step, ...distractors.take(3)]..shuffle(_random);
    _tapped = null;
    _lastAnswer = null;
  }

  Score _staff(Pitch p, Clef clef, String id) => Score(
        clef: clef,
        measures: [
          Measure([NoteElement.note(p, _wholeNote, id: id)]),
        ],
      );

  String get _sriId =>
      'note_reading.${_targetClef.name}.${_target.step.name}${_target.octave}';

  void _onAnswer(Step choice) {
    if (_lastAnswer == true) return;
    final correct = choice == _target.step;
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(_sriId, correct);
    }
    if (correct) {
      context.read<AudioService>().playMidiNote(_target.midiNumber);
    } else {
      context.read<AudioService>().playWrong();
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
    final system = StaffSystem([
      _staff(_topPitch, Clef.treble, 'top'),
      _staff(_bottomPitch, _bottomClef, 'bottom'),
    ]);

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameDuet),
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
                      prompt: l10n.duetPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                            child: StaffSystemView(
                              system: system,
                              staffSpace: 12,
                              theme: kidsScoreTheme,
                              highlightedIds: {_targetIsTop ? 'top' : 'bottom'},
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 12),
                    AnswerGrid(
                      children: [
                        for (final option in _options)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _tapped == null
                                  ? null
                                  : option == _target.step
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
