// lib/features/games/note_reading/step_skip_screen.dart
//
// "Step or Skip?" — a reading drill on melodic *motion*: two notes sit on the
// staff, and the child decides whether the second one is a STEP away (the very
// next line-or-space, a 2nd) or a SKIP (a bigger jump — a 3rd, 4th or 5th).
// Steps-vs-skips is one of the first things young readers learn to see; naming
// the exact interval comes later (Connect the Steps). No staff-height reference
// is needed — it is purely "are they neighbours or not?". Big staff card, two
// tap buttons, no-fail loop.
//
// SRI: 'reading.motion.<step|skip>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

const _half = NoteDuration(DurationBase.half);

/// The melodic motion between the two notes. From 2★ the game splits skips into
/// a skip (3rd/4th) and a leap (5th+) for a harder three-way tier.
enum _Motion { step, skip, leap }

class StepSkipScreen extends StatefulWidget {
  const StepSkipScreen({super.key, this.clef = Clef.treble});

  /// Which clef the notes are read in (treble by default; a bass variant reuses
  /// the same screen — the step/skip judgement is clef-independent, but bass
  /// gives bass-clef reading practice and its own pitches/progress).
  final Clef clef;

  @override
  State<StepSkipScreen> createState() => _StepSkipScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class StepSkipTester {
  /// Whether the two notes are a step apart (the correct answer).
  bool get answerStep;

  /// The correct motion name ('step' / 'skip' / 'leap').
  String get answerMotion;
  bool get isFinished;
}

class _StepSkipScreenState extends State<StepSkipScreen>
    with QuizRoundMixin
    implements StepSkipTester {
  @override
  bool get answerStep => _motion == _Motion.step;
  @override
  String get answerMotion => _motion.name;
  @override
  bool get isFinished => finished;

  final _random = Random();

  late Pitch _a; // first note
  late Pitch _b; // second note
  late _Motion _motion; // the correct motion this round
  bool _threeWay = false; // 2★+: offer Step / Skip / Leap
  _Motion? _tapped; // last choice
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'step_skip';

  // Treble keeps the original id (no progress migration); bass gets its own.
  @override
  String get progressId =>
      widget.clef == Clef.bass ? 'step_skip_bass' : 'step_skip';

  // A correct answer sounds the two notes; a miss buzzes. No generic blips.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // From 2★ the game becomes a three-way (Step / Skip / Leap).
    _threeWay = context.read<ProgressService>().starsFor(progressId) >= 2;
    final choices =
        _threeWay ? _Motion.values : const [_Motion.step, _Motion.skip];
    _motion = choices[_random.nextInt(choices.length)];

    // step = a 2nd; skip = 3rd/4th; leap = 5th+. In the binary tier a skip
    // stretches to a 5th (2..4) so the harder intervals still appear.
    final delta = switch (_motion) {
      _Motion.step => 1,
      _Motion.skip =>
        _threeWay ? 2 + _random.nextInt(2) : 2 + _random.nextInt(3),
      _Motion.leap => 4 + _random.nextInt(3), // 4..6
    };
    // Keep both notes comfortably on/around the staff [-1 .. 9].
    final low = -1 + _random.nextInt(9 - delta + 1); // low..low+delta ≤ 9
    final up = _random.nextBool();
    final aPos = up ? low : low + delta;
    final bPos = up ? low + delta : low;
    _a = widget.clef.pitchAt(aPos);
    _b = widget.clef.pitchAt(bPos);
    _tapped = null;
    _lastAnswer = null;
  }

  void _onAnswer(_Motion choice) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = choice == _motion;
    final audio = context.read<AudioService>();

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'reading.motion.${_motion.name}',
            correct,
          );
    }
    if (correct) {
      audio.playPhrase([_a.midiNumber, _b.midiNumber], noteMs: 380);
    } else {
      audio.playWrong();
    }

    setState(() {
      _tapped = choice;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  static IconData _iconFor(_Motion m) => switch (m) {
        _Motion.step => Icons.stairs,
        _Motion.skip => Icons.trending_up,
        _Motion.leap => Icons.rocket_launch,
      };

  String _labelFor(AppLocalizations l, _Motion m) => switch (m) {
        _Motion.step => l.stepLabel,
        _Motion.skip => l.skipLabel,
        _Motion.leap => l.leapLabel,
      };

  Score get _cardScore => Score(
        clef: widget.clef,
        measures: [
          Measure([
            NoteElement.note(_a, _half, id: 'a'),
            NoteElement.note(_b, _half, id: 'b'),
          ]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(
        title: widget.clef == Clef.bass
            ? l10n.gameStepSkipBass
            : l10n.gameStepSkip,
      ),
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
                      prompt: l10n.stepSkipPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: Card(
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            child: StaffView(
                              score: _cardScore,
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
                    Row(
                      children: [
                        for (final motion in _threeWay
                            ? _Motion.values
                            : const [_Motion.step, _Motion.skip])
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  backgroundColor: _tapped == null
                                      ? null
                                      : motion == _motion && _tapped == _motion
                                          ? Colors.green
                                          : motion == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                icon: Icon(_iconFor(motion)),
                                onPressed: () => _onAnswer(motion),
                                label: Text(_labelFor(l10n, motion)),
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
