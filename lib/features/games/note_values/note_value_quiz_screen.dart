// lib/features/games/note_values/note_value_quiz_screen.dart
//
// "Wie heißt dieses Zeichen?" — a note/rest symbol is shown, the child picks
// its name from four options. Every first-try answer is recorded into the
// SRI database under 'note_values.symbol.<item>'.
//
// Doubles as the review runner: pass [reviewItemIds] (full SRI IDs) and the
// rounds are exactly those items instead of a random selection.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_values/symbol_catalog.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class NoteValueQuizScreen extends StatefulWidget {
  /// Review mode: full SRI item IDs (`note_values.symbol.<id>`) to drill.
  /// Null = normal game with [defaultRounds] random symbols.
  final List<String>? reviewItemIds;

  const NoteValueQuizScreen({super.key, this.reviewItemIds});

  static const defaultRounds = 10;

  @override
  State<NoteValueQuizScreen> createState() => _NoteValueQuizScreenState();
}

class _NoteValueQuizScreenState extends State<NoteValueQuizScreen>
    with QuizRoundMixin<NoteValueQuizScreen> {
  final _random = Random();

  late final List<NoteSymbol> _sequence;
  late List<NoteSymbol> _options;
  NoteSymbol? _tapped; // last tapped option, for feedback coloring

  bool get _isReview => widget.reviewItemIds != null;
  NoteSymbol get _target => _sequence[round];

  @override
  int get totalRounds => _sequence.length;

  @override
  String get gameType => 'note_value_quiz';

  @override
  bool get isReviewSession => _isReview;

  /// Normalize review sessions to a full-length-equivalent score so any length
  /// lands in the same star brackets.
  int get _starScore => totalRounds > 0
      ? (score * NoteValueQuizScreen.defaultRounds / totalRounds).round()
      : 0;

  @override
  void initState() {
    super.initState();
    final reviewSymbols = widget.reviewItemIds
        ?.map((id) => symbolById(id.split('.').last))
        .whereType<NoteSymbol>()
        .toList();
    _sequence = (reviewSymbols == null || reviewSymbols.isEmpty)
        ? List.generate(
            NoteValueQuizScreen.defaultRounds,
            (_) => kNoteSymbols[_random.nextInt(kNoteSymbols.length)],
          )
        : reviewSymbols;
    prepareRound();
  }

  @override
  void prepareRound() {
    final distractors = [...kNoteSymbols]
      ..remove(_target)
      ..shuffle(_random);
    _options = [_target, ...distractors.take(3)]..shuffle(_random);
    _tapped = null;
  }

  bool get _targetIsRest => _target.id.endsWith('_rest');

  static String _durationToken(double beats) {
    if (beats >= 1.0) return 'w';
    if (beats >= 0.5) return 'h';
    if (beats >= 0.25) return 'q';
    if (beats >= 0.125) return 'e';
    return 's';
  }

  /// The symbol on a real staff so rests (whole vs half hang from different
  /// lines) are actually identifiable — a bare glyph is ambiguous.
  Score get _symbolScore {
    final token = _durationToken(_target.beats);
    return Score.simple(notes: _targetIsRest ? 'r:$token' : 'b4:$token');
  }

  /// The symbol's length in 4/4 beats (whole = 4, quarter = 1, eighth = ½).
  double get _targetBeats => _target.beats * 4;

  String _lengthLabel(AppLocalizations l10n) {
    final beats = _targetBeats;
    if (beats == 0.5) return l10n.halfBeat;
    if (beats == 0.25) return l10n.quarterBeat;
    return l10n.beatsCount(beats.toInt());
  }

  void _playLength() {
    context
        .read<AudioService>()
        .playNoteLength(_targetBeats, isRest: _targetIsRest);
  }

  void _onAnswer(NoteSymbol choice) {
    if (_tapped == _target) return; // round already resolved
    final correct = choice == _target;

    // First tap decides the SRI outcome; retries don't count as new answers.
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(_target.sriId, correct);
    }

    setState(() => _tapped = choice);
    resolveAnswer(correct: correct);
    // On a miss the round stays put — explain the length (text + audio) so the
    // child learns what they got wrong before trying again.
    if (!correct) _playLength();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(
        title: _isReview ? l10n.reviewTitle : l10n.gameNoteValueQuiz,
      ),
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
                      correct: _tapped == null ? null : _tapped == _target,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.whatIsThisSymbol,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: StaffView(
                              score: _symbolScore,
                              staffSpace: 18,
                              theme: kidsScoreTheme,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(
                      correct: _tapped == null ? null : _tapped == _target,
                    ),
                    if (_tapped != null && _tapped != _target) ...[
                      const SizedBox(height: 8),
                      _LengthExplanation(
                        text: _targetIsRest
                            ? l10n.symbolLengthRest(
                                _target.label(l10n),
                                _lengthLabel(l10n),
                              )
                            : l10n.symbolLength(
                                _target.label(l10n),
                                _lengthLabel(l10n),
                              ),
                        onHear: _playLength,
                        hearLabel: l10n.hearLength,
                      ),
                    ],
                    const SizedBox(height: 16),
                    AnswerGrid(
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

/// A little "how long is this?" card: the length in beats plus a button to
/// hear it, shown after a wrong answer in the Symbol Quiz.
class _LengthExplanation extends StatelessWidget {
  final String text;
  final String hearLabel;
  final VoidCallback onHear;

  const _LengthExplanation({
    required this.text,
    required this.hearLabel,
    required this.onHear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: onHear,
            icon: const Icon(Icons.volume_up, size: 18),
            label: Text(hearLabel),
          ),
        ],
      ),
    );
  }
}
