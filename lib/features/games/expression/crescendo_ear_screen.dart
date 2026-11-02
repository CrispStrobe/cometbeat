// lib/features/games/expression/crescendo_ear_screen.dart
//
// "Getting Louder or Softer?" — an ear-training game on the *direction of
// dynamics*: a steady pulse plays on one pitch whose loudness ramps up
// (crescendo) or down (diminuendo), and the child decides which way it moved.
// No staff is shown; it is pure listening — the aural twin of reading a
// crescendo hairpin. Charades trains a *fixed* level (pp..ff); this trains the
// *change over time* that nothing else drills. Big replay button; two answer
// buttons. No-fail loop (a wrong answer just buzzes).
//
// The pulse is synthesized by rendering each note with a ramped `gain` and
// concatenating: `renderSegments` peak-normalizes each note to the same level
// (same pitch/timbre), then scales by gain, so the gain ramp *is* the dynamic.
//
// SRI: 'dynamics.hear.<cresc|dim>'.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/explain/answer_explanation.dart';
import 'package:comet_beat/features/games/explain/music_terms.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CrescendoEarScreen extends StatefulWidget {
  const CrescendoEarScreen({super.key});

  @override
  State<CrescendoEarScreen> createState() => _CrescendoEarScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class CrescendoEarTester {
  /// Whether the pulse gets louder (a crescendo — the correct answer).
  bool get answerCrescendo;
  bool get isFinished;
}

class _CrescendoEarScreenState extends State<CrescendoEarScreen>
    with QuizRoundMixin
    implements CrescendoEarTester {
  @override
  bool get answerCrescendo => _cresc;
  @override
  bool get isFinished => finished;

  final _random = Random();

  // A steady pulse: [_pulses] notes on one pitch, gains ramping between _lo and
  // _hi. A ~5× amplitude ratio (≈14 dB) reads unmistakably as a crescendo.
  static const _pulses = 8;
  static const _noteMs = 220;
  static const _lo = 0.18;
  static const _hi = 1.0;

  late int _pitch; // midi of the repeated note
  late bool _cresc; // does it get louder?
  bool? _tapped; // the child's last choice (true = crescendo)
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'crescendo_ear';

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
    // A comfortable mid-register pitch (A4..E5) so timbre stays even across it.
    _pitch = 69 + _random.nextInt(8); // 69..76
    _cresc = _random.nextBool();
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playPulse();
  }

  /// Renders the ramped pulse to one WAV and plays it. Each note is rendered
  /// separately with its own ramped gain, then the PCM is concatenated — the
  /// per-note decay envelope keeps the seams click-free.
  void _playPulse() {
    final audio = context.read<AudioService>();
    final timbre = timbreFor(audio.instrument);
    final pcm = <int>[];
    for (var i = 0; i < _pulses; i++) {
      final frac = i / (_pulses - 1); // 0..1
      final gain = _cresc ? _lo + (_hi - _lo) * frac : _hi - (_hi - _lo) * frac;
      final note = renderSegments(
        [
          (freqs: [midiToFrequency(_pitch)], ms: _noteMs),
        ],
        timbre: timbre,
        gain: gain,
      );
      pcm.addAll(note);
    }
    audio.playWavBytes(wavBytes(Int16List.fromList(pcm)));
  }

  void _onAnswer(bool cresc) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = cresc == _cresc;

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'dynamics.hear.${_cresc ? 'cresc' : 'dim'}',
            correct,
          );
    }

    setState(() {
      _tapped = cresc;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameCrescendoEar),
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
                      prompt: l10n.crescendoEarPrompt,
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
                          _tapped! ? MusicTerm.crescendo : MusicTerm.diminuendo,
                        ],
                        onNext: advancePending ? advanceNow : null,
                      ),
                      const SizedBox(height: 8),
                    ],
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    AnswerRow(
                      children: [
                        for (final cresc in const [true, false])
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
                                      : cresc == _cresc && _tapped == _cresc
                                          ? Colors.green
                                          : cresc == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                icon: Icon(
                                  cresc
                                      ? Icons.trending_up
                                      : Icons.trending_down,
                                ),
                                onPressed: () => _onAnswer(cresc),
                                label: Text(
                                  cresc
                                      ? l10n.crescendoLouderLabel
                                      : l10n.crescendoSofterLabel,
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
