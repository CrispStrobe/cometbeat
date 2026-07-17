// lib/features/games/keyboard/key_melody_screen.dart
//
// "Melodie spielen" — real sight-playing: a four-note melody on the staff,
// played note by note on the keyboard. Correctly played staff notes turn
// green as you go, so eye and finger move together.
//
// SRI: 'keyboard.melody.len4'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class KeyMelodyScreen extends StatefulWidget {
  const KeyMelodyScreen({super.key});

  static const melodyLength = 4;

  @override
  State<KeyMelodyScreen> createState() => _KeyMelodyScreenState();
}

class _KeyMelodyScreenState extends State<KeyMelodyScreen> with QuizRoundMixin {
  final _random = Random();

  late List<Pitch> _melody;
  int _playedCount = 0;
  int? _wrongMidi;
  bool _sriRecorded = false;

  @override
  int get totalRounds => 6;

  @override
  String get gameType => 'key_melody';

  // The played notes are the audio feedback.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // Stepwise-leaning walk over the staff naturals (positions 1..7).
    var position = 2 + _random.nextInt(4);
    final melody = <Pitch>[Clef.treble.pitchAt(position)];
    while (melody.length < KeyMelodyScreen.melodyLength) {
      final step = [-2, -1, -1, 1, 1, 2][_random.nextInt(6)];
      position = (position + step).clamp(1, 7);
      melody.add(Clef.treble.pitchAt(position));
    }
    _melody = melody;
    _playedCount = 0;
    _wrongMidi = null;
    _sriRecorded = false;
  }

  bool get _complete => _playedCount >= _melody.length;

  Score get _score => Score.simple(
        notes: _melody.map((p) => '${p.step.name}${p.octave}').join(' '),
      );

  void _record(bool correct) {
    if (_sriRecorded) return;
    _sriRecorded = true;
    context.read<SriService>().recordResponse('keyboard.melody.len4', correct);
  }

  void _onKeyTap(int midi) {
    if (_complete) return; // round already resolved
    final audio = context.read<AudioService>();
    audio.playMidiNote(midi, ms: 450);

    if (midi == _melody[_playedCount].midiNumber) {
      setState(() {
        _playedCount++;
        _wrongMidi = null;
      });
      if (_complete) {
        _record(!answeredWrong);
        resolveAnswer(correct: true);
      }
    } else {
      _record(false);
      setState(() => _wrongMidi = midi);
      resolveAnswer(correct: false);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted || _complete) return;
        setState(() => _wrongMidi = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Played staff notes turn green; the next one to play is highlighted.
    final theme = kidsScoreTheme.copyWith(
      elementColors: {
        for (var i = 0; i < _playedCount; i++) 'e$i': Colors.green,
        if (!_complete) 'e$_playedCount': Colors.blue,
      },
    );

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameKeyMelody),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'key_melody',
                score: score,
                onRestart: restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    RoundHeader(
                      correct: _wrongMidi != null
                          ? false
                          : _complete
                              ? true
                              : null,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.keyMelodyPrompt,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: StaffView(
                              score: _score,
                              staffSpace: 11,
                              theme: theme,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FeedbackLine(
                      correct: _wrongMidi != null
                          ? false
                          : _complete
                              ? true
                              : null,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 170,
                      child: PianoKeyboard(
                        showLabels: true,
                        onKeyTap: _onKeyTap,
                        keyColors: {
                          if (_wrongMidi != null) _wrongMidi!: Colors.redAccent,
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
