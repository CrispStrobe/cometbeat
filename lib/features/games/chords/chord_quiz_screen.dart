// lib/features/games/chords/chord_quiz_screen.dart
//
// "Akkord-Quiz" — a triad is rendered on the staff; the child names it.
// Level 1: major triads in root position, answer = root name.
//
// SRI: 'chords.triad.<root>_major'.

import 'dart:math';

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

import '../../../core/services/sri_service.dart';
import '../../../l10n/app_localizations.dart';
import '../note_reading/note_names.dart';
import '../widgets/game_widgets.dart';

class ChordQuizScreen extends StatefulWidget {
  const ChordQuizScreen({super.key});

  @override
  State<ChordQuizScreen> createState() => _ChordQuizScreenState();
}

class _ChordQuizScreenState extends State<ChordQuizScreen>
    with QuizRoundMixin {
  final _random = Random();

  // Roots whose major triads sit comfortably on the treble staff.
  static const _roots = [Step.c, Step.d, Step.e, Step.f, Step.g, Step.a];

  late Step _root;
  late List<Step> _options;
  Step? _tapped;
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
    _root = _roots[_random.nextInt(_roots.length)];
    final distractors = [..._roots]
      ..remove(_root)
      ..shuffle(_random);
    _options = ([_root, ...distractors.take(3)]..shuffle(_random));
    _tapped = null;
    _lastAnswer = null;
  }

  String _token(Pitch p) {
    final accidental = switch (p.alter) { 1 => '#', -1 => 'b', _ => '' };
    return '${p.step.name}$accidental${p.octave}';
  }

  Score get _score {
    final pitches = Triad(Pitch(_root), ChordQuality.major).pitches;
    return Score.simple(notes: '${pitches.map(_token).join('+')}:w');
  }

  void _onAnswer(Step choice) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = choice == _root;

    if (_tapped == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('chords.triad.${_root.name}_major', correct);
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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameChordQuiz)),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'chord_quiz',
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
                      prompt: l10n.chordQuizPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 48),
                            child: StaffView(
                              score: _score,
                              staffSpace: 14,
                              theme: PartituraTheme.kids,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 3.2,
                      children: [
                        for (final option in _options)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _tapped == null
                                  ? null
                                  : option == _root && _tapped == _root
                                      ? Colors.green
                                      : option == _tapped
                                          ? Colors.redAccent
                                          : null,
                            ),
                            onPressed: () => _onAnswer(option),
                            child: Text(
                                l10n.majorChordName(noteName(l10n, option))),
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
