// lib/features/games/measures/strong_beat_screen.dart
//
// "Strong Beat?" — metric-accent training on crisp_notation-public's new
// `beatStrength`. A measure is shown with its beat numbers; one beat is
// highlighted and the child says whether it is a STRONG (accented) or WEAK beat.
// The answer isn't hard-coded — `TimeSignature.beatStrength(position)` grades it,
// so the game is correct for 4/4 (1 & 3 strong), 3/4 (only 1), 6/8 (1 & 4) and
// any meter the library models.
//
// SRI: 'measures.accent.<ts>_<beat>'.

import 'dart:async';
import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/note_colors.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class StrongBeatScreen extends StatefulWidget {
  const StrongBeatScreen({super.key});

  @override
  State<StrongBeatScreen> createState() => _StrongBeatScreenState();
}

/// Test handle onto the running game (the state class is private; the correct
/// answer varies per round).
@visibleForTesting
abstract interface class StrongBeatTester {
  /// True when the highlighted beat is metrically strong (the correct answer).
  bool get targetIsStrong;
  bool get isFinished;
}

class _StrongBeatScreenState extends State<StrongBeatScreen>
    with QuizRoundMixin
    implements StrongBeatTester {
  final _random = Random();

  // A beat counts as "strong" when it sits at or above the meter's secondary
  // accent level (downbeat 1.0, secondary strong beats 0.5).
  static const _strongThreshold = 0.5;

  static const _easyMeters = [TimeSignature.fourFour];
  static const _midMeters = [
    TimeSignature.fourFour,
    TimeSignature.threeFour,
    TimeSignature.twoFour,
  ];
  static const _allMeters = [
    TimeSignature.fourFour,
    TimeSignature.threeFour,
    TimeSignature.twoFour,
    TimeSignature.sixEight,
  ];

  int _stars = 0;
  late TimeSignature _ts;
  late int _beat; // 1-based highlighted beat
  late bool _strong;

  @override
  int get totalRounds => 10;

  @override
  bool get playFeedbackSounds => false; // the clicked measure is the feedback

  @override
  String get gameType => 'strong_beat';

  @override
  bool get targetIsStrong => _strong;
  @override
  bool get isFinished => finished;

  List<TimeSignature> get _meterPool => _stars >= 2
      ? _allMeters
      : _stars >= 1
          ? _midMeters
          : _easyMeters;

  @override
  void initState() {
    super.initState();
    _stars = context.read<ProgressService>().starsFor(gameType);
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playMeasure());
  }

  /// Position of 1-based [beat] within the measure, as a fraction of a whole
  /// note (what `beatStrength` expects).
  Fraction _positionOf(int beat) => Fraction(beat - 1, _ts.beatUnit);

  @override
  void prepareRound() {
    _ts = _meterPool[_random.nextInt(_meterPool.length)];
    _beat = 1 + _random.nextInt(_ts.beats);
    _strong = _ts.beatStrength(_positionOf(_beat)) >= _strongThreshold;
    _tapped = null;
    _lastAnswer = null;
  }

  /// One note per beat on the middle line — rhythm, not pitch, is the point.
  Score get _measureScore {
    final dur = NoteDuration(
      _ts.beatUnit == 8 ? DurationBase.eighth : DurationBase.quarter,
    );
    return Score(
      clef: Clef.treble,
      timeSignature: _ts,
      measures: [
        Measure([
          for (var i = 0; i < _ts.beats; i++)
            NoteElement.note(const Pitch(Step.b), dur, id: 'b$i'),
        ]),
      ],
    );
  }

  final List<Timer> _timers = [];

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  void _cancelTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  // Tracked so scheduled ticks never outlive the widget (trips the test binding).
  void _after(int ms, void Function() cb) =>
      _timers.add(Timer(Duration(milliseconds: ms), cb));

  void _playMeasure() {
    // Click the measure: a bright tick on strong beats, a soft one on weak.
    _cancelTimers();
    final audio = context.read<AudioService>();
    for (var i = 0; i < _ts.beats; i++) {
      final strong = _ts.beatStrength(_positionOf(i + 1)) >= _strongThreshold;
      _after(480 * i, () => mounted ? audio.playTick(accent: strong) : null);
    }
  }

  void _onAnswer(bool strong) {
    if (_lastAnswer == true) return; // round already won
    final correct = strong == _strong;

    // Record the first try per round (mirrors the other quizzes).
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'measures.accent.${_ts.beats}${_ts.beatUnit}_$_beat',
            correct,
          );
    }

    if (correct) {
      _playMeasure();
    } else {
      context.read<AudioService>().playWrong();
    }

    setState(() {
      _tapped = strong;
      _lastAnswer = correct;
    });
    final advanced = resolveAnswer(correct: correct);
    if (advanced && !finished) {
      _after(800, () => (mounted && !finished) ? _playMeasure() : null);
    }
  }

  bool? _tapped; // what the child tapped this round (null = untouched)
  bool? _lastAnswer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameStrongBeat),
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
                      prompt: l10n.strongBeatPrompt(_beat),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                child: StaffView(
                                  score: _measureScore,
                                  staffSpace: 15,
                                  showBeatNumbers: true,
                                  theme: kidsScoreTheme.copyWith(
                                    elementColors: {
                                      'b${_beat - 1}': pitchClassColor(Step.g),
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              IconButton.filledTonal(
                                onPressed: _playMeasure,
                                icon: const Icon(Icons.volume_up),
                                tooltip: l10n.strongBeatReplay,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 22),
                            ),
                            onPressed: () => _onAnswer(true),
                            icon: const Icon(Icons.volume_up),
                            label: Text(l10n.strongBeatStrong),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 22),
                            ),
                            onPressed: () => _onAnswer(false),
                            icon: const Icon(Icons.volume_mute),
                            label: Text(l10n.strongBeatWeak),
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
