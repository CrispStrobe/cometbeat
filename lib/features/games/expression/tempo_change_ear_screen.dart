// lib/features/games/expression/tempo_change_ear_screen.dart
//
// "Speeding Up or Slowing Down?" — an ear-training game on the *direction of
// tempo*: a steady pulse plays on one pitch whose beats get closer together
// (accelerando) or further apart (ritardando), and the child decides which way
// it moved. No staff is shown; it is pure listening — the tempo twin of
// "Getting Louder or Softer?". Tempo_duel/charades train a *fixed* speed; this
// trains the *change over time*. Big replay button; two answer buttons. No-fail
// loop (a wrong answer just buzzes).
//
// The pulse is a same-pitch sequence whose per-note duration ramps between
// [_msSlow] and [_msFast] — shorter notes pack closer, so the ramp *is* the
// perceived tempo change.
//
// SRI: 'tempo.hear.<accel|ritard>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/explain/answer_explanation.dart';
import 'package:comet_beat/features/games/explain/music_terms.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TempoChangeEarScreen extends StatefulWidget {
  const TempoChangeEarScreen({super.key});

  @override
  State<TempoChangeEarScreen> createState() => _TempoChangeEarScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class TempoChangeEarTester {
  /// Whether the pulse speeds up (an accelerando — the correct answer).
  bool get answerAccelerando;
  bool get isFinished;
}

class _TempoChangeEarScreenState extends State<TempoChangeEarScreen>
    with QuizRoundMixin
    implements TempoChangeEarTester {
  @override
  bool get answerAccelerando => _accel;
  @override
  bool get isFinished => finished;

  final _random = Random();

  // A steady pulse: [_pulses] notes on one pitch, per-note duration ramping
  // between _msSlow and _msFast. A ~2.3× span reads clearly as a tempo change.
  static const _pulses = 8;
  static const _msSlow = 340;
  static const _msFast = 150;

  late int _pitch; // midi of the repeated note
  late bool _accel; // does it speed up?
  bool? _tapped; // the child's last choice (true = accelerando)
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'tempo_change_ear';

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playPulse());
  }

  @override
  Duration get advanceDelay => kExplanationHold;

  @override
  void prepareRound() {
    // A comfortable mid-register pitch (A4..E5) — loudness/pitch stay constant
    // so only the timing changes.
    _pitch = 69 + _random.nextInt(8); // 69..76
    _accel = _random.nextBool();
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playPulse();
  }

  /// Plays the same-pitch pulse with a ramping per-note duration: accelerando
  /// starts slow and ends fast (durations shrink), ritardando the reverse.
  void _playPulse() {
    final notes = <(int, int)>[];
    for (var i = 0; i < _pulses; i++) {
      final frac = i / (_pulses - 1); // 0..1
      final ms = _accel
          ? (_msSlow - (_msSlow - _msFast) * frac).round()
          : (_msFast + (_msSlow - _msFast) * frac).round();
      notes.add((_pitch, ms));
    }
    context.read<AudioService>().playSequence(notes);
  }

  void _onAnswer(bool accel) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = accel == _accel;

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'tempo.hear.${_accel ? 'accel' : 'ritard'}',
            correct,
          );
    }

    setState(() {
      _tapped = accel;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameTempoChangeEar),
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
                      prompt: l10n.tempoChangeEarPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: IconButton.filledTonal(
                          iconSize: 96,
                          padding: const EdgeInsets.all(32),
                          icon: const Icon(Icons.volume_up),
                          tooltip: l10n.listenAgain,
                          onPressed: _playPulse,
                        ),
                      ),
                    ),
                    Text(
                      l10n.listenAgain,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    // After an answer: what the term means (the right one, or
                    // the one tapped if wrong), with a small picture of it.
                    if (_tapped != null) ...[
                      AnswerExplanation(
                        terms: [
                          _tapped!
                              ? MusicTerm.accelerando
                              : MusicTerm.ritardando,
                        ],
                        onNext: advancePending ? advanceNow : null,
                      ),
                      const SizedBox(height: 8),
                    ],
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    AnswerRow(
                      children: [
                        for (final accel in const [true, false])
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  backgroundColor: _tapped == null
                                      ? null
                                      : accel == _accel && _tapped == _accel
                                          ? Colors.green
                                          : accel == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                icon: Icon(
                                  accel
                                      ? Icons.fast_forward
                                      : Icons.slow_motion_video,
                                ),
                                onPressed: () => _onAnswer(accel),
                                label: Text(
                                  accel
                                      ? l10n.tempoFasterLabel
                                      : l10n.tempoSlowerLabel,
                                ),
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
