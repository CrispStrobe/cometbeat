// lib/features/games/keyboard/grand_staff_read_screen.dart
//
// "Klaviersystem lesen" — the real piano-reading skill: a note is shown on the
// grand staff (treble + bass joined by a brace, crisp_notation's GrandStaffView) and
// the child names it. Notes appear on whichever staff fits; 2★ widens the range
// into the middle-C ledger region between the staves, exactly where pianists
// need it.
//
// SRI: 'keyboard.grand.<step><octave>'.

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
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class GrandStaffReadScreen extends StatefulWidget {
  const GrandStaffReadScreen({super.key});

  @override
  State<GrandStaffReadScreen> createState() => _GrandStaffReadScreenState();
}

class _GrandStaffReadScreenState extends State<GrandStaffReadScreen>
    with QuizRoundMixin {
  final _random = Random();

  late Pitch _target;
  late Clef _clef; // which staff the note sits on (treble = upper)
  late List<Step> _options;
  Step? _tapped;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'grand_staff_read';

  // The named pitch is the audio feedback.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // 2+ stars widen each staff into the middle-C ledger region between them.
    final stars = context.read<ProgressService>().starsFor(progressId);
    _clef = _random.nextBool() ? Clef.treble : Clef.bass;
    // Within-staff (0..8) for beginners; ledger neighbourhood otherwise. The
    // treble reaches down toward middle C, the bass reaches up toward it.
    _target = stars >= 2
        ? _clef.pitchAt(-3 + _random.nextInt(13)) // -3..9
        : _clef.pitchAt(_random.nextInt(9)); // 0..8

    final distractors = [...Step.values]
      ..remove(_target.step)
      ..shuffle(_random);
    _options = [_target.step, ...distractors.take(3)]..shuffle(_random);
    _tapped = null;
  }

  static const _whole = NoteDuration(DurationBase.whole);
  static const _wholeRest = RestElement(_whole);

  /// The grand staff with the target note on its staff and a rest on the other.
  GrandStaff get _grandStaff {
    final note = NoteElement.note(_target, _whole, id: 'target');
    final onTreble = _clef == Clef.treble;
    return GrandStaff(
      upper: Score(
        clef: Clef.treble,
        measures: [
          Measure([onTreble ? note : _wholeRest]),
        ],
      ),
      lower: Score(
        clef: Clef.bass,
        measures: [
          Measure([onTreble ? _wholeRest : note]),
        ],
      ),
    );
  }

  void _onAnswer(Step choice) {
    if (_tapped == _target.step) return; // round already resolved
    final correct = choice == _target.step;
    final audio = context.read<AudioService>();

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'keyboard.grand.${_target.step.name}${_target.octave}',
            correct,
          );
    }

    if (correct) {
      audio.playMidiNote(_target.midiNumber);
    } else {
      audio.playWrong();
    }

    setState(() => _tapped = choice);
    resolveAnswer(correct: correct);
  }

  Color? _buttonColor(Step option) {
    if (_tapped == null) return null;
    if (option == _target.step && _tapped == _target.step) return Colors.green;
    if (option == _tapped && option != _target.step) return Colors.redAccent;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameGrandStaffRead),
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
                      correct: _tapped == null ? null : _tapped == _target.step,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.whatIsThisNote,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: GrandStaffView(
                              grandStaff: _grandStaff,
                              staffSpace: 12,
                              theme: kidsScoreTheme,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(
                      correct: _tapped == null ? null : _tapped == _target.step,
                    ),
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
