// lib/features/games/note_reading/place_note_screen.dart
//
// "Setz die Note!" — the inverse of the reading quiz: the game names a note,
// the child taps the right line or space on an interactive staff (crisp_notation
// InteractiveStaff with ghost-note preview). Both octaves of a letter count
// as correct — the skill is letter placement, not octave discrimination.
//
// SRI: 'note_reading.place_<clef>.<letter>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/note_colors.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class PlaceNoteScreen extends StatefulWidget {
  final Clef clef;

  const PlaceNoteScreen({super.key, required this.clef});

  @override
  State<PlaceNoteScreen> createState() => _PlaceNoteScreenState();
}

class _PlaceNoteScreenState extends State<PlaceNoteScreen> with QuizRoundMixin {
  final _random = Random();

  late Step _targetStep;
  NoteElement? _placed;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'place_note';

  @override
  String get progressId => 'place_note_${widget.clef.name}';

  // The tapped pitch itself is the audio feedback here.
  @override
  bool get playFeedbackSounds => false;

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

  // Whole rests keep the measures at normal width (empty measures collapse),
  // so the tappable staff stays wide — and it's correct notation anyway.
  static const _wholeRest = RestElement(NoteDuration(DurationBase.whole));

  Score get _score => Score(
        clef: widget.clef,
        measures: [
          Measure([_placed ?? _wholeRest]),
          const Measure([_wholeRest]),
          const Measure([_wholeRest]),
        ],
      );

  void _onStaffTap(StaffTarget target) {
    if (_lastAnswer == true) return; // round already resolved
    final pitch = target.pitchFor(widget.clef);
    final correct = pitch.step == _targetStep;
    // Hear every placement — immediate pitch feedback.
    context.read<AudioService>().playMidiNote(pitch.midiNumber, ms: 500);

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
    final colorScaffold = context.watch<SettingsService>().colorScaffold;
    final theme = kidsScoreTheme.copyWith(
      elementColors: {
        if (_lastAnswer != null)
          'answer': _lastAnswer! ? Colors.green : Colors.redAccent,
      },
    );

    return Scaffold(
      appBar: GameAppBar(
        title: widget.clef == Clef.treble
            ? l10n.gamePlaceNoteTreble
            : l10n.gamePlaceNoteBass,
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
                      correct: _lastAnswer,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n
                          .placeNotePrompt(noteNameFor(context, _targetStep)),
                    ),
                    if (colorScaffold) ...[
                      const SizedBox(height: 8),
                      _TargetColorSwatch(
                        color: pitchClassColor(_targetStep),
                        label: noteNameFor(context, _targetStep),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: InteractiveStaff(
                              score: _score,
                              theme: theme,
                              // Fixed scale: fit-to-width explodes on a
                              // near-empty score (clef + one note).
                              staffSpace: 16,
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

/// A colour chip for the pre-reader scaffold: the target letter and its colour.
class _TargetColorSwatch extends StatelessWidget {
  final Color color;
  final String label;

  const _TargetColorSwatch({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
