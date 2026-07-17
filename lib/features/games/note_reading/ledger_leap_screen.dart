// lib/features/games/note_reading/ledger_leap_screen.dart
//
// "Hilfslinien zählen" / "Ledger Leap" — the ledger-line drill (docs/PLAN.md,
// original concepts). A note sits exactly on the Nth ledger line above or below
// the staff; the child taps how many ledger lines it uses (1, 2 or 3). This
// isolates the middle-C / high-A neighbourhood that the reading quizzes only
// brush — the counting strategy that makes ledger reading possible.
//
// Notes always sit ON a ledger line (never a ledger space), so the count is
// unambiguous. SRI: 'note_reading.ledger.<clef>.<below|above><n>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:comet_beat/shared/widgets/note_mascot.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class LedgerLeapScreen extends StatefulWidget {
  const LedgerLeapScreen({super.key});

  static const _totalRounds = 10;
  static const _options = [1, 2, 3];

  @override
  State<LedgerLeapScreen> createState() => _LedgerLeapScreenState();
}

/// Typed window into the game for widget tests (the state class is private).
@visibleForTesting
abstract interface class LedgerLeapTester {
  int get round;
  int get score;

  /// The right answer for the current note (its ledger-line count).
  int get correctLines;
}

class _LedgerLeapScreenState extends State<LedgerLeapScreen>
    with QuizRoundMixin
    implements LedgerLeapTester {
  final _random = Random();

  late Clef _clef;
  late bool _below;
  late int _lines; // 1..3 ledger lines
  late Pitch _target;
  int? _tapped;

  @override
  int get correctLines => _lines;

  @override
  int get totalRounds => LedgerLeapScreen._totalRounds;

  @override
  String get gameType => 'ledger_leap';

  // The sounding pitch is the reward on a correct count.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // Beginners: treble, below the staff (the middle-C region), 1–2 lines.
    // At two stars: both clefs, above or below, up to 3 lines.
    final wide = context.read<ProgressService>().starsFor('ledger_leap') >= 2;
    _clef = wide && _random.nextBool() ? Clef.bass : Clef.treble;
    _below = wide ? _random.nextBool() : true;
    _lines = wide ? 1 + _random.nextInt(3) : 1 + _random.nextInt(2);

    // Staff lines sit at positions 0..8; ledger lines at -2,-4,-6 below and
    // 10,12,14 above. A note ON the Nth ledger line lands on that position.
    final position = _below ? -2 * _lines : 8 + 2 * _lines;
    _target = _clef.pitchAt(position);
    _tapped = null;
  }

  String get _sriId => 'note_reading.ledger.${_clef.name}.'
      '${_below ? 'below' : 'above'}$_lines';

  void _onAnswer(int count) {
    if (_tapped == _lines) return; // round already solved
    final correct = count == _lines;

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(_sriId, correct);
    }
    if (correct) {
      context.read<AudioService>().playMidiNote(_target.midiNumber);
    } else {
      context.read<AudioService>().playWrong();
    }

    setState(() => _tapped = count);
    resolveAnswer(correct: correct);
  }

  NoteMascotMood get _mascotMood => _tapped == null
      ? NoteMascotMood.idle
      : _tapped == _lines
          ? NoteMascotMood.happy
          : NoteMascotMood.oops;

  static const _wholeNote = NoteDuration(DurationBase.whole);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameLedgerLeap),
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
                      correct: _tapped == null ? null : _tapped == _lines,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.ledgerLeapPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Stack(
                          children: [
                            Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                child: StaffView(
                                  score: Score(
                                    clef: _clef,
                                    measures: [
                                      Measure([
                                        NoteElement.note(_target, _wholeNote),
                                      ]),
                                    ],
                                  ),
                                  staffSpace: 14,
                                  theme: kidsScoreTheme,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              left: 8,
                              child: NoteMascot(mood: _mascotMood, size: 30),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FeedbackLine(
                      correct: _tapped == null ? null : _tapped == _lines,
                    ),
                    const SizedBox(height: 16),
                    AnswerGrid(
                      children: [
                        for (final option in LedgerLeapScreen._options)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _buttonColor(option),
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _onAnswer(option),
                            child: Text('$option'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Color? _buttonColor(int option) {
    if (_tapped == null) return null;
    if (option == _lines && _tapped == _lines) return Colors.green;
    if (option == _tapped && option != _lines) return Colors.redAccent;
    return null;
  }
}
