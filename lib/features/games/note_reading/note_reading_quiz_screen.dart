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
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/features/games/note_reading/reading_hint.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

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

  @override
  State<NoteReadingQuizScreen> createState() => _NoteReadingQuizScreenState();
}

class _NoteReadingQuizScreenState extends State<NoteReadingQuizScreen>
    with QuizRoundMixin<NoteReadingQuizScreen> {
  final _random = Random();

  List<Pitch>? _reviewSequence; // null = random rounds
  late Pitch _target;
  late List<Step> _options;
  Step? _tapped;

  bool get _isReview => _reviewSequence != null;

  @override
  int get totalRounds =>
      _reviewSequence?.length ?? NoteReadingQuizScreen.totalRounds;

  @override
  String get gameType => 'note_reading_quiz';

  @override
  String get progressId => 'note_reading_${widget.clef.name}';

  @override
  bool get isReviewSession => _isReview;

  // This game plays the actual sounding pitch as feedback, not a generic blip.
  @override
  bool get playFeedbackSounds => false;

  /// Normalize review sessions to a full-length-equivalent score so any length
  /// lands in the same star brackets.
  int get _starScore => totalRounds > 0
      ? (score * NoteReadingQuizScreen.totalRounds / totalRounds).round()
      : 0;

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
    prepareRound();
  }

  @override
  void prepareRound() {
    // Naturals on the staff (bottom line..top line), no ledger lines yet —
    // the right starting range for beginners in both clefs.
    // Star-driven difficulty: 2+ stars widen the range to the ledger
    // neighborhood (middle C below the treble staff, high A above).
    final stars = context
        .read<ProgressService>()
        .starsFor('note_reading_${widget.clef.name}');
    _target = _reviewSequence != null
        ? _reviewSequence![round]
        : stars >= 2
            ? widget.clef.pitchAt(-2 + _random.nextInt(13)) // -2..10
            : widget.clef.pitchAt(_random.nextInt(9)); // 0..8

    final distractors = [...Step.values]
      ..remove(_target.step)
      ..shuffle(_random);
    _options = [_target.step, ...distractors.take(3)]..shuffle(_random);
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

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(_sriId, correct);
    }

    setState(() => _tapped = choice);
    resolveAnswer(correct: correct);
  }

  /// Landmark reading hint, faded by mastery: shown always for beginners
  /// (< 2 stars), only after a wrong attempt at 2 stars (a nudge when stuck),
  /// and never at 3 stars or in a review test.
  bool get _showHint {
    if (_isReview) return false;
    final stars = context.read<ProgressService>().starsFor(progressId);
    if (stars >= 3) return false;
    if (stars >= 2) return answeredWrong;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = _isReview
        ? l10n.reviewTitle
        : switch (widget.clef) {
            Clef.treble ||
            Clef.treble8va ||
            Clef.treble8vb =>
              l10n.gameNoteReadingTreble,
            Clef.bass || Clef.bass8vb => l10n.gameNoteReadingBass,
            Clef.tenor => l10n.gameNoteReadingTenor,
            Clef.alto => l10n.gameNoteReadingAlto,
          };

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: gameType,
                score: score,
                starScore: _starScore,
                onRestart: _isReview ? null : restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    RoundHeader(
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
                    if (_showHint) ...[
                      const SizedBox(height: 12),
                      _ReadingHintChip(
                        text: readingHintText(context, widget.clef, _target),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FeedbackLine(
                      correct: _tapped == null ? null : _tapped == _target.step,
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

  Color? _buttonColor(Step option) {
    if (_tapped == null) return null;
    if (option == _target.step && _tapped == _target.step) {
      return Colors.green;
    }
    if (option == _tapped && option != _target.step) return Colors.redAccent;
    return null;
  }
}

/// A muted "reading strategy" chip: a lightbulb + the landmark/interval hint.
class _ReadingHintChip extends StatelessWidget {
  final String text;

  const _ReadingHintChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lightbulb_outline,
              size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
