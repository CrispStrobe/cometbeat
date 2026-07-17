// lib/features/games/note_reading/which_voice_screen.dart
//
// "Which Voice?" — the inverse of Read the Voice: a note in a multi-voice chord
// is highlighted and the child picks which voice it is (Soprano / Alto / Tenor /
// Bass). Trains voice-position and range awareness (where each voice lives on
// the grand staff) rather than pitch naming. Shares the SATB voicing/rendering.
//
// Difficulty grows 2 voices (Soprano + Alto) → full SATB (four voices).
//
// SRI: 'note_reading.voice.<voice>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/satb_voicing.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material also exports `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class WhichVoiceScreen extends StatefulWidget {
  const WhichVoiceScreen({super.key});

  @override
  State<WhichVoiceScreen> createState() => _WhichVoiceScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class WhichVoiceTester {
  /// The highlighted note's voice (the correct answer).
  SatbVoice get answerVoice;
  bool get isFinished;
}

class _WhichVoiceScreenState extends State<WhichVoiceScreen>
    with QuizRoundMixin
    implements WhichVoiceTester {
  final _random = Random();

  int _stars = 0;
  late List<SatbPart> _parts;
  late SatbPart _target;
  SatbVoice? _tapped;
  bool? _lastAnswer;

  bool get _satb => _stars >= 1;

  @override
  SatbVoice get answerVoice => _target.voice;
  @override
  bool get isFinished => finished;

  @override
  int get totalRounds => 10;
  @override
  bool get playFeedbackSounds => false;
  @override
  String get gameType => 'which_voice';

  @override
  void initState() {
    super.initState();
    _stars = context.read<ProgressService>().starsFor(gameType);
    prepareRound();
  }

  @override
  void prepareRound() {
    _parts = voiceRandomChord(_random, satb: _satb, wide: _stars >= 2);
    _target = _parts[_random.nextInt(_parts.length)];
    _tapped = null;
    _lastAnswer = null;
  }

  void _hearVoice() =>
      context.read<AudioService>().playMidiNote(_target.pitch.midiNumber);

  void _onAnswer(SatbVoice choice) {
    if (_lastAnswer == true) return;
    final correct = choice == _target.voice;
    if (_tapped == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('note_reading.voice.${_target.voice.name}', correct);
    }
    if (correct) {
      _hearVoice();
    } else {
      context.read<AudioService>().playWrong();
    }
    setState(() {
      _tapped = choice;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final voices = _parts.map((p) => p.voice).toList();

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameWhichVoice),
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
                      prompt: l10n.whichVoicePrompt,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Center(
                        child: Card(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 16,
                                ),
                                child: StaffSystemView(
                                  system: satbSystem(_parts),
                                  staffSpace: 13,
                                  theme: kidsScoreTheme,
                                  highlightedIds: {_target.id},
                                ),
                              ),
                              IconButton.filledTonal(
                                onPressed: _hearVoice,
                                icon: const Icon(Icons.volume_up),
                                tooltip: l10n.readVoiceHear,
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 12),
                    AnswerGrid(
                      children: [
                        for (final voice in voices)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _tapped == null
                                  ? null
                                  : voice == _target.voice
                                      ? Colors.green
                                      : voice == _tapped
                                          ? Colors.redAccent
                                          : null,
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _onAnswer(voice),
                            child: Text(voice.label(l10n)),
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
