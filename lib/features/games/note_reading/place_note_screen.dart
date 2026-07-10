// lib/features/games/note_reading/place_note_screen.dart
//
// "Setz die Note!" — the inverse of the reading quiz: the game names a note,
// the child taps the right line or space on an interactive staff (partitura
// InteractiveStaff with ghost-note preview). Both octaves of a letter count
// as correct — the skill is letter placement, not octave discrimination.
//
// SRI: 'note_reading.place_<clef>.<letter>'.

import 'dart:math';

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

import '../../../core/services/sri_service.dart';
import '../../../l10n/app_localizations.dart';
import '../widgets/game_widgets.dart';
import 'note_names.dart';

class PlaceNoteScreen extends StatefulWidget {
  final Clef clef;

  const PlaceNoteScreen({super.key, required this.clef});

  @override
  State<PlaceNoteScreen> createState() => _PlaceNoteScreenState();
}

class _PlaceNoteScreenState extends State<PlaceNoteScreen>
    with QuizRoundMixin {
  final _random = Random();

  late Step _targetStep;
  NoteElement? _placed;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    _targetStep = Step.values[_random.nextInt(Step.values.length)];
    _placed = null;
    _lastAnswer = null;
  }

  Score get _score => Score(
        clef: widget.clef,
        measures: [
          Measure([if (_placed != null) _placed!]),
        ],
      );

  void _onStaffTap(StaffTarget target) {
    if (_lastAnswer == true) return; // round already resolved
    final pitch = target.pitchFor(widget.clef);
    final correct = pitch.step == _targetStep;

    if (_lastAnswer == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'note_reading.place_${widget.clef.name}.${_targetStep.name}',
            correct,
          );
    }

    setState(() {
      _placed = NoteElement.note(
        pitch,
        const NoteDuration(DurationBase.whole),
        id: 'answer',
      );
      _lastAnswer = correct;
    });

    if (!correct) {
      // Let the child see the miss, then clear it for the retry.
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted || _lastAnswer == true) return;
        setState(() => _placed = null);
      });
    }
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = PartituraTheme.kids.copyWith(
      elementColors: {
        if (_lastAnswer != null)
          'answer': _lastAnswer! ? Colors.green : Colors.redAccent,
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.clef == Clef.treble
            ? l10n.gamePlaceNoteTreble
            : l10n.gamePlaceNoteBass),
      ),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'place_note',
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
                      prompt: l10n
                          .placeNotePrompt(noteName(l10n, _targetStep)),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 24),
                            child: InteractiveStaff(
                              score: _score,
                              theme: theme,
                              ghostDuration:
                                  const NoteDuration(DurationBase.whole),
                              onStaffTap: _onStaffTap,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                  ],
                ),
              ),
      ),
    );
  }
}
