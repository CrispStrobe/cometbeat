// lib/features/games/chords/chord_quiz_screen.dart
//
// "Akkord-Quiz" — a triad is rendered on the staff; the child names it.
// Level 1: major triads in root position, answer = root name.
//
// SRI: 'chords.triad.<root>_major'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
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

class ChordQuizScreen extends StatefulWidget {
  /// Review mode: full SRI item IDs (`chords.triad.<root>_major`) to drill.
  final List<String>? reviewItemIds;

  const ChordQuizScreen({super.key, this.reviewItemIds});

  @override
  State<ChordQuizScreen> createState() => _ChordQuizScreenState();
}

class _ChordQuizScreenState extends State<ChordQuizScreen> with QuizRoundMixin {
  final _random = Random();

  // Roots whose major triads sit comfortably on the treble staff.
  static const _roots = [Step.c, Step.d, Step.e, Step.f, Step.g, Step.a];

  List<Step>? _reviewRoots;
  bool get _isReview => _reviewRoots != null;

  late Step _root;
  late List<Step> _options;
  Step? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => _reviewRoots?.length ?? 10;

  @override
  bool get isReviewSession => _isReview;

  @override
  String get gameType => 'chord_quiz';

  // The chord itself plays on a correct answer.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    final parsed = widget.reviewItemIds
        ?.map((id) {
          final root = id.split('.').last.split('_').first;
          return Step.values.asNameMap()[root];
        })
        .whereType<Step>()
        .toList();
    _reviewRoots = (parsed == null || parsed.isEmpty) ? null : parsed;
    prepareRound();
  }

  @override
  void prepareRound() {
    _root = _isReview
        ? _reviewRoots![round]
        : _roots[_random.nextInt(_roots.length)];
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

  void _playChord() {
    final midis = Triad(Pitch(_root), ChordQuality.major)
        .pitches
        .map((p) => p.midiNumber)
        .toList();
    context.read<AudioService>().playMidiChord(midis);
  }

  void _onAnswer(Step choice) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = choice == _root;
    if (correct) _playChord();

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
      appBar: GameAppBar(
        title: _isReview ? l10n.reviewTitle : l10n.gameChordQuiz,
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: l10n.listenAgain,
            onPressed: _playChord,
          ),
        ],
      ),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'chord_quiz',
                score: score,
                onRestart: _isReview ? null : restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    RoundHeader(
                      correct: _lastAnswer,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.chordQuizPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 48),
                            child: StaffView(
                              score: _score,
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
                    AnswerGrid(
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
                              l10n.majorChordName(noteNameFor(context, option)),
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
