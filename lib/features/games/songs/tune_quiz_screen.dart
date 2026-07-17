// lib/features/games/songs/tune_quiz_screen.dart
//
// "Lieder-Quiz" — name that tune: the opening of one song plays; pick its
// title. Pure ear + memory, and it sends children back to the song book.
//
// SRI: 'songs.tune.<songId>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/songs/song_book.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TuneQuizScreen extends StatefulWidget {
  const TuneQuizScreen({super.key});

  static const openingNotes = 7;

  @override
  State<TuneQuizScreen> createState() => _TuneQuizScreenState();
}

class _TuneQuizScreenState extends State<TuneQuizScreen> with QuizRoundMixin {
  final _random = Random();

  late Song _target;
  Song? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 8;

  @override
  String get gameType => 'tune_quiz';

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playOpening());
  }

  @override
  void prepareRound() {
    _target = kSongs[_random.nextInt(kSongs.length)];
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playOpening();
  }

  void _playOpening() {
    context.read<AudioService>().playSequence([
      for (final (_, midi, ms)
          in _target.playback.take(TuneQuizScreen.openingNotes))
        (midi, ms),
    ]);
  }

  void _onAnswer(Song choice) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = choice.id == _target.id;

    if (_tapped == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('songs.tune.${_target.id}', correct);
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
      appBar: GameAppBar(title: l10n.gameTuneQuiz),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'tune_quiz',
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
                      prompt: l10n.tuneQuizPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: IconButton.filledTonal(
                          iconSize: 96,
                          padding: const EdgeInsets.all(32),
                          icon: const Icon(Icons.volume_up),
                          tooltip: l10n.listenAgain,
                          onPressed: _playOpening,
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
                    Column(
                      children: [
                        for (final song in kSongs)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _tapped == null
                                      ? null
                                      : song.id == _target.id &&
                                              _tapped?.id == _target.id
                                          ? Colors.green
                                          : song.id == _tapped?.id
                                              ? Colors.redAccent
                                              : null,
                                ),
                                onPressed: () => _onAnswer(song),
                                child: Text(song.title),
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
