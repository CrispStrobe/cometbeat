// lib/features/games/measures/meter_detective_screen.dart
//
// "Takt-Detektiv" — two bars of beats are played with an accented downbeat
// (low drum-like tone on ONE, lighter tone on the others); the child feels
// whether it's a march (2/4), a waltz (3/4) or common time (4/4).
//
// SRI: 'measures.meter.<beats>_4'.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/audio_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../l10n/app_localizations.dart';
import '../widgets/game_widgets.dart';

class MeterDetectiveScreen extends StatefulWidget {
  const MeterDetectiveScreen({super.key});

  static const beatMs = 480;

  @override
  State<MeterDetectiveScreen> createState() => _MeterDetectiveScreenState();
}

class _MeterDetectiveScreenState extends State<MeterDetectiveScreen>
    with QuizRoundMixin {
  final _random = Random();

  static const _meters = [2, 3, 4]; // x/4

  late int _beats;
  int? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 8;

  @override
  String get gameType => 'meter_detective';

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playMeter());
  }

  @override
  void prepareRound() {
    _beats = _meters[_random.nextInt(_meters.length)];
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playMeter();
  }

  void _playMeter() {
    // Three bars: the downbeat is a low, weighty tone (C3), the other
    // beats a light high one (C5) — DUM-da-da makes the meter feel-able.
    context.read<AudioService>().playSequence([
      for (var bar = 0; bar < 3; bar++)
        for (var beat = 0; beat < _beats; beat++)
          (beat == 0 ? 48 : 72, MeterDetectiveScreen.beatMs),
    ]);
  }

  void _onAnswer(int beats) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = beats == _beats;

    if (_tapped == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('measures.meter.${_beats}_4', correct);
    }

    setState(() {
      _tapped = beats;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameMeterDetective)),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'meter_detective',
                score: score,
                onRestart: restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    RoundHeader(
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.meterDetectivePrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: IconButton.filledTonal(
                          iconSize: 96,
                          padding: const EdgeInsets.all(32),
                          icon: const Icon(Icons.volume_up),
                          tooltip: l10n.listenAgain,
                          onPressed: _playMeter,
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
                    Row(
                      children: [
                        for (final beats in _meters)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6),
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 20),
                                  backgroundColor: _tapped == null
                                      ? null
                                      : beats == _beats &&
                                              _tapped == _beats
                                          ? Colors.green
                                          : beats == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                          fontWeight: FontWeight.bold),
                                ),
                                onPressed: () => _onAnswer(beats),
                                child: Text('$beats/4'),
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
