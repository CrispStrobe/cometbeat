// lib/features/games/scales/count_notes_screen.dart
//
// "Count the Notes" — an ear-training game on aural attention: a short phrase of
// 2, 3 or 4 notes plays, and the child taps how many notes they heard. No staff
// is shown; it is pure listening (each note a distinct pitch so the onsets are
// easy to separate). Big replay button; three answer buttons. No-fail loop (a
// wrong answer just buzzes).
//
// SRI: 'pitch.hear.count<n>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CountNotesScreen extends StatefulWidget {
  const CountNotesScreen({super.key});

  @override
  State<CountNotesScreen> createState() => _CountNotesScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class CountNotesTester {
  /// How many notes the current phrase holds (the correct answer).
  int get answerCount;
  bool get isFinished;
}

class _CountNotesScreenState extends State<CountNotesScreen>
    with QuizRoundMixin
    implements CountNotesTester {
  @override
  int get answerCount => _count;
  @override
  bool get isFinished => finished;

  /// The counts the child chooses between.
  static const _options = [2, 3, 4];

  final _random = Random();

  late int _count; // how many notes in the phrase
  late List<int> _notes; // the phrase (distinct pitches)
  int? _tapped; // the child's last choice
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'count_notes';

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playPhrase());
  }

  @override
  void prepareRound() {
    _count = _options[_random.nextInt(_options.length)];
    // Build a phrase of distinct pitches (a small random walk) so each note is
    // a clearly separate onset — the child counts onsets, not pitch changes.
    final notes = <int>[];
    var midi = 60 + _random.nextInt(8); // C4..G4
    for (var i = 0; i < _count; i++) {
      notes.add(midi);
      var next =
          midi + (_random.nextBool() ? 1 : -1) * (1 + _random.nextInt(4));
      next = next.clamp(55, 79);
      if (next == midi) next += 2; // never repeat a pitch
      midi = next.clamp(55, 79);
    }
    _notes = notes;
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playPhrase();
  }

  void _playPhrase() {
    context.read<AudioService>().playPhrase(_notes, noteMs: 450);
  }

  void _onAnswer(int count) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = count == _count;

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'pitch.hear.count$_count',
            correct,
          );
    }

    setState(() {
      _tapped = count;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  Color? _buttonColor(int option) {
    if (_tapped == null) return null;
    if (option == _count) return Colors.green; // reveal the right count
    if (option == _tapped) return Colors.redAccent; // the wrong tap
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameCountNotes),
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
                      prompt: l10n.countNotesPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: IconButton.filledTonal(
                          iconSize: 96,
                          padding: const EdgeInsets.all(32),
                          icon: const Icon(Icons.volume_up),
                          tooltip: l10n.listenAgain,
                          onPressed: _playPhrase,
                        ),
                      ),
                    ),
                    Text(
                      l10n.listenAgain,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        for (final option in _options)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 24,
                                  ),
                                  backgroundColor: _buttonColor(option),
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                onPressed: () => _onAnswer(option),
                                child: Text('$option'),
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
