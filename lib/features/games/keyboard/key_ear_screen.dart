// lib/features/games/keyboard/key_ear_screen.dart
//
// "Echo-Tasten" — relative pitch on the keyboard: first you hear C (the
// anchor, its key blinks), then the mystery note; tap the key you heard.
// Every tapped key sounds, so searching is allowed and instructive.
//
// SRI: 'keyboard.ear.<step><octave>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:crisp_notation/crisp_notation.dart' show Clef, Pitch;
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class KeyEarScreen extends StatefulWidget {
  const KeyEarScreen({super.key});

  static const anchorMidi = 60; // C4

  @override
  State<KeyEarScreen> createState() => _KeyEarScreenState();
}

class _KeyEarScreenState extends State<KeyEarScreen> with QuizRoundMixin {
  final _random = Random();

  late Pitch _target; // natural, C4..C5
  int? _tappedMidi;
  bool? _lastAnswer;

  @override
  int get totalRounds => 8;

  @override
  String get gameType => 'key_ear';

  // Tapped keys sound on their own.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playRiddle());
  }

  @override
  void prepareRound() {
    // Naturals C4..C5: treble staff positions -2..5, anchored to C4.
    _target = Clef.treble.pitchAt(-2 + _random.nextInt(8));
    _tappedMidi = null;
    _lastAnswer = null;
    if (round > 0) _playRiddle();
  }

  void _playRiddle() {
    context.read<AudioService>().playSequence([
      (KeyEarScreen.anchorMidi, 600),
      (_target.midiNumber, 800),
    ]);
  }

  void _onKeyTap(int midi) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = midi == _target.midiNumber;
    context.read<AudioService>().playMidiNote(midi, ms: 550);

    if (_tappedMidi == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'keyboard.ear.${_target.step.name}${_target.octave}',
            correct,
          );
    }

    setState(() {
      _tappedMidi = midi;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);

    if (!correct) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted || _lastAnswer == true) return;
        setState(() => _tappedMidi = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: GameAppBar(
        title: l10n.gameKeyEar,
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: l10n.listenAgain,
            onPressed: _playRiddle,
          ),
        ],
      ),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'key_ear',
                score: score,
                onRestart: restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    RoundHeader(
                      correct: _lastAnswer,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.keyEarPrompt,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Center(
                        child: IconButton.filledTonal(
                          iconSize: 72,
                          padding: const EdgeInsets.all(24),
                          icon: const Icon(Icons.volume_up),
                          tooltip: l10n.listenAgain,
                          onPressed: _playRiddle,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 170,
                      child: PianoKeyboard(
                        onKeyTap: _onKeyTap,
                        keyColors: {
                          // The anchor C is always marked.
                          KeyEarScreen.anchorMidi: scheme.primaryContainer,
                          if (_tappedMidi != null)
                            _tappedMidi!:
                                _lastAnswer! ? Colors.green : Colors.redAccent,
                        },
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
