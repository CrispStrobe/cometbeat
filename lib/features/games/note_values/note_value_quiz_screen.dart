// lib/features/games/note_values/note_value_quiz_screen.dart
//
// "Wie heißt dieses Zeichen?" — a note/rest symbol is shown, the child picks
// its name from four options. Every first-try answer is recorded into the
// SRI database under 'note_values.symbol.<item>'.
//
// Doubles as the review runner: pass [reviewItemIds] (full SRI IDs) and the
// rounds are exactly those items instead of a random selection.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/sri_service.dart';
import '../../../core/tuning.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/music_glyph.dart';
import 'symbol_catalog.dart';

class NoteValueQuizScreen extends StatefulWidget {
  /// Review mode: full SRI item IDs (`note_values.symbol.<id>`) to drill.
  /// Null = normal game with [defaultRounds] random symbols.
  final List<String>? reviewItemIds;

  const NoteValueQuizScreen({super.key, this.reviewItemIds});

  static const defaultRounds = 10;
  static const pointsPerRound = 100;

  @override
  State<NoteValueQuizScreen> createState() => _NoteValueQuizScreenState();
}

class _NoteValueQuizScreenState extends State<NoteValueQuizScreen> {
  final _random = Random();

  late final List<NoteSymbol> _sequence;
  int _round = 0;
  int _score = 0;
  late List<NoteSymbol> _options;
  bool _answeredWrong = false;
  NoteSymbol? _tapped; // last tapped option, for feedback coloring
  bool _finished = false;

  bool get _isReview => widget.reviewItemIds != null;
  NoteSymbol get _target => _sequence[_round];

  @override
  void initState() {
    super.initState();
    final reviewSymbols = widget.reviewItemIds
        ?.map((id) => symbolById(id.split('.').last))
        .whereType<NoteSymbol>()
        .toList();
    _sequence = (reviewSymbols == null || reviewSymbols.isEmpty)
        ? List.generate(NoteValueQuizScreen.defaultRounds,
            (_) => kNoteSymbols[_random.nextInt(kNoteSymbols.length)])
        : reviewSymbols;
    _prepareRound();
  }

  void _prepareRound() {
    final distractors = [...kNoteSymbols]
      ..remove(_target)
      ..shuffle(_random);
    _options = ([_target, ...distractors.take(3)]..shuffle(_random));
    _answeredWrong = false;
    _tapped = null;
  }

  void _onAnswer(NoteSymbol choice) {
    if (_tapped == _target) return; // round already resolved
    final correct = choice == _target;

    // First tap decides the SRI outcome; retries don't count as new answers.
    if (_tapped == null || !_answeredWrong) {
      context.read<SriService>().recordResponse(_target.sriId, correct);
    }

    setState(() {
      _tapped = choice;
      if (correct) {
        if (!_answeredWrong) {
          _score += NoteValueQuizScreen.pointsPerRound;
        }
        if (_round + 1 >= _sequence.length) {
          _finished = true;
        }
      } else {
        _answeredWrong = true;
      }
    });

    if (correct && !_finished) {
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        setState(() {
          _round++;
          _prepareRound();
        });
      });
    }
  }

  void _restart() {
    setState(() {
      _round = 0;
      _score = 0;
      _finished = false;
      _prepareRound();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isReview ? l10n.reviewTitle : l10n.gameNoteValueQuiz),
      ),
      body: SafeArea(
        child: _finished
            ? _ResultView(
                score: _score,
                rounds: _sequence.length,
                showRestart: !_isReview,
                onRestart: _restart,
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      l10n.roundOf(_round + 1, _sequence.length),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.whatIsThisSymbol,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: MusicGlyph(_target.glyph, size: 96),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _FeedbackBanner(
                      answered: _tapped != null,
                      correct: _tapped == _target,
                      l10n: l10n,
                    ),
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
                              backgroundColor: _buttonColor(option),
                            ),
                            onPressed: () => _onAnswer(option),
                            child: Text(
                              option.label(l10n),
                              textAlign: TextAlign.center,
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

  Color? _buttonColor(NoteSymbol option) {
    if (_tapped == null) return null;
    if (option == _target && _tapped == _target) return Colors.green;
    if (option == _tapped && option != _target) return Colors.redAccent;
    return null;
  }
}

class _FeedbackBanner extends StatelessWidget {
  final bool answered;
  final bool correct;
  final AppLocalizations l10n;

  const _FeedbackBanner({
    required this.answered,
    required this.correct,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Text(
        !answered
            ? ''
            : correct
                ? l10n.feedbackCorrect
                : l10n.feedbackTryAgain,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: correct ? Colors.green : Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final int score;
  final int rounds;
  final bool showRestart;
  final VoidCallback onRestart;

  const _ResultView({
    required this.score,
    required this.rounds,
    required this.showRestart,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Normalize to a 10-round-equivalent score so the same star bracket
    // works for review sessions of any length.
    final normalized =
        rounds > 0 ? (score * NoteValueQuizScreen.defaultRounds / rounds) : 0;
    final stars = scoreToStars('note_value_quiz', normalized.round(), true);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Icon(
                  i < stars ? Icons.star : Icons.star_border,
                  size: 56,
                  color: Colors.amber,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            l10n.resultScore(score),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          if (showRestart)
            FilledButton.icon(
              onPressed: onRestart,
              icon: const Icon(Icons.replay),
              label: Text(l10n.playAgain),
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.backButton),
          ),
        ],
      ),
    );
  }
}
