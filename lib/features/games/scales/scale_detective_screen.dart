// lib/features/games/scales/scale_detective_screen.dart
//
// "Tonleiter-Detektiv" — a major scale is rendered with one note altered by
// a semitone (visible as an accidental against the key signature); the child
// taps the note that doesn't belong. Element tap via partitura's StaffView.
//
// SRI: 'scales.spot.<tonic>_major'.

import 'dart:math';

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step, Key;
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

import '../../../core/services/sri_service.dart';
import '../../../l10n/app_localizations.dart';
import '../note_reading/note_names.dart';
import '../widgets/game_widgets.dart';

class ScaleDetectiveScreen extends StatefulWidget {
  const ScaleDetectiveScreen({super.key});

  @override
  State<ScaleDetectiveScreen> createState() => _ScaleDetectiveScreenState();
}

class _ScaleDetectiveScreenState extends State<ScaleDetectiveScreen>
    with QuizRoundMixin {
  final _random = Random();

  // Beginner keys; more via difficulty progression (see docs/PLAN.md).
  static const _tonics = [Step.c, Step.f, Step.g];

  late Step _tonic;
  late Key _key;
  late List<Pitch> _pitches; // with the wrong one substituted
  late int _wrongIndex;
  String? _tappedId;
  bool? _lastAnswer;

  @override
  int get totalRounds => 8;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    _tonic = _tonics[_random.nextInt(_tonics.length)];
    _key = Key.major(Pitch(_tonic));
    final scale = Scale(Pitch(_tonic), ScaleType.major).pitches;

    _wrongIndex = 1 + _random.nextInt(scale.length - 2); // not the tonics
    final original = _pitchesOf(scale)[_wrongIndex];
    // Shift by a semitone, away from any existing alteration so we stay
    // within a single sharp/flat (B♭ in F major becomes B natural).
    final shift = original.alter == 0
        ? (_random.nextBool() ? 1 : -1)
        : -original.alter;
    final wrong = Pitch(original.step,
        alter: original.alter + shift, octave: original.octave);

    _pitches = [..._pitchesOf(scale)];
    _pitches[_wrongIndex] = wrong;
    _tappedId = null;
    _lastAnswer = null;
  }

  List<Pitch> _pitchesOf(List<Pitch> scale) => scale;

  String _token(Pitch p) {
    final accidental = switch (p.alter) {
      1 => '#',
      -1 => 'b',
      // Explicit natural where the key signature says otherwise.
      0 when _key.signature.alterFor(p.step) != 0 => 'n',
      _ => '',
    };
    return '${p.step.name}$accidental${p.octave}';
  }

  Score get _score => Score.simple(
        keySignature: _key.signature,
        notes: _pitches.map(_token).join(' '),
      );

  void _onElementTap(String elementId) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = elementId == 'e$_wrongIndex';

    if (_lastAnswer == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('scales.spot.${_tonic.name}_major', correct);
    }

    setState(() {
      _tappedId = elementId;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = PartituraTheme.kids.copyWith(
      elementColors: {
        if (_tappedId != null)
          _tappedId!: _lastAnswer! ? Colors.green : Colors.redAccent,
      },
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameScaleDetective)),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'scale_detective',
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
                          .scaleDetectivePrompt(noteName(l10n, _tonic)),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            child: StaffView(
                              score: _score,
                              theme: theme,
                              onElementTap: _onElementTap,
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
