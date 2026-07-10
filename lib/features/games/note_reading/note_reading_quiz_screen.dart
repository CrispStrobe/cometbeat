// lib/features/games/note_reading/note_reading_quiz_screen.dart
//
// "Wie heißt diese Note?" — a note is rendered on a real staff (partitura
// StaffView, kid theme) and the child picks its letter name. One screen
// serves both clefs; the game registry creates a treble and a bass entry.
//
// SRI: 'note_reading.<clef>.<step><octave>', e.g. 'note_reading.treble.g4'.

import 'dart:math';

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

import '../../../core/services/audio_service.dart';
import '../../../core/services/progress_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../core/tuning.dart';
import '../../../l10n/app_localizations.dart';
import 'note_names.dart';

class NoteReadingQuizScreen extends StatefulWidget {
  final Clef clef;

  /// Review mode: full SRI item IDs (`note_reading.<clef>.<pitch>`) to
  /// drill. Null = normal game with [totalRounds] random staff notes.
  final List<String>? reviewItemIds;

  const NoteReadingQuizScreen({
    super.key,
    required this.clef,
    this.reviewItemIds,
  });

  static const totalRounds = 10;
  static const pointsPerRound = 100;

  @override
  State<NoteReadingQuizScreen> createState() => _NoteReadingQuizScreenState();
}

class _NoteReadingQuizScreenState extends State<NoteReadingQuizScreen> {
  final _random = Random();

  List<Pitch>? _reviewSequence; // null = random rounds
  int _round = 0;
  int _score = 0;
  late Pitch _target;
  late List<Step> _options;
  bool _answeredWrong = false;
  Step? _tapped;
  bool _finished = false;

  bool get _isReview => _reviewSequence != null;
  int get _totalRounds =>
      _reviewSequence?.length ?? NoteReadingQuizScreen.totalRounds;

  @override
  void initState() {
    super.initState();
    final parsed = widget.reviewItemIds
        ?.map((id) {
          try {
            return Pitch.parse(id.split('.').last);
          } on FormatException {
            return null;
          }
        })
        .whereType<Pitch>()
        .toList();
    _reviewSequence = (parsed == null || parsed.isEmpty) ? null : parsed;
    _prepareRound();
  }

  void _prepareRound() {
    // Naturals on the staff (bottom line..top line), no ledger lines yet —
    // the right starting range for beginners in both clefs.
    // Star-driven difficulty: 2+ stars widen the range to the ledger
    // neighborhood (middle C below the treble staff, high A above).
    final stars = context
        .read<ProgressService>()
        .starsFor('note_reading_${widget.clef.name}');
    _target = _reviewSequence != null
        ? _reviewSequence![_round]
        : stars >= 2
            ? widget.clef.pitchAt(-2 + _random.nextInt(13)) // -2..10
            : widget.clef.pitchAt(_random.nextInt(9)); // 0..8

    final distractors = [...Step.values]
      ..remove(_target.step)
      ..shuffle(_random);
    _options = ([_target.step, ...distractors.take(3)]..shuffle(_random));
    _answeredWrong = false;
    _tapped = null;
  }

  String get _sriId =>
      'note_reading.${widget.clef.name}.${_target.step.name}${_target.octave}';

  void _onAnswer(Step choice) {
    if (_tapped == _target.step) return; // round already resolved
    final correct = choice == _target.step;
    if (correct) {
      context.read<AudioService>().playMidiNote(_target.midiNumber);
    } else {
      context.read<AudioService>().playWrong();
    }

    if (_tapped == null || !_answeredWrong) {
      context.read<SriService>().recordResponse(_sriId, correct);
    }

    setState(() {
      _tapped = choice;
      if (correct) {
        if (!_answeredWrong) {
          _score += NoteReadingQuizScreen.pointsPerRound;
        }
        if (_round + 1 >= _totalRounds) {
          _finished = true;
          if (!_isReview) {
            context.read<ProgressService>().recordResult(
                  'note_reading_${widget.clef.name}',
                  score: _score,
                  stars: scoreToStars('note_reading_quiz', _score, true),
                );
          }
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
    final title = _isReview
        ? l10n.reviewTitle
        : switch (widget.clef) {
            Clef.treble => l10n.gameNoteReadingTreble,
            Clef.bass => l10n.gameNoteReadingBass,
            Clef.tenor => l10n.gameNoteReadingTenor,
            Clef.alto => l10n.gameNoteReadingAlto,
          };

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: _finished
            ? _ResultView(
                score: _score,
                rounds: _totalRounds,
                onRestart: _isReview ? null : _restart,
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      l10n.roundOf(_round + 1, _totalRounds),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.whatIsThisNote,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 24),
                            child: StaffView(
                              score: Score.simple(
                                clef: widget.clef,
                                notes:
                                    '${_target.step.name}${_target.octave}:w',
                              ),
                              staffSpace: 14,
                              theme: PartituraTheme.kids,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 28,
                      child: Text(
                        _tapped == null
                            ? ''
                            : _tapped == _target.step
                                ? l10n.feedbackCorrect
                                : l10n.feedbackTryAgain,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: _tapped == _target.step
                                      ? Colors.green
                                      : Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
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
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _onAnswer(option),
                            child: Text(noteName(l10n, option)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Color? _buttonColor(Step option) {
    if (_tapped == null) return null;
    if (option == _target.step && _tapped == _target.step) {
      return Colors.green;
    }
    if (option == _tapped && option != _target.step) return Colors.redAccent;
    return null;
  }
}

class _ResultView extends StatelessWidget {
  final int score;
  final int rounds;
  final VoidCallback? onRestart;

  const _ResultView({
    required this.score,
    required this.rounds,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Normalize to a 10-round-equivalent score so the same star bracket
    // works for review sessions of any length.
    final normalized = rounds > 0
        ? (score * NoteReadingQuizScreen.totalRounds / rounds).round()
        : 0;
    final stars = scoreToStars('note_reading_quiz', normalized, true);

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
          if (onRestart != null)
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
