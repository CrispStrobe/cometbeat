// lib/features/games/note_reading/hear_voice_screen.dart
//
// "Hear the Voice" — the aural SATB game (third of the scoped three). The full
// chord plays, then one voice alone; the child identifies which voice they heard
// (Soprano / Alto / Tenor / Bass). Pure ear-training: no notation is shown, so
// they must track a line by sound. At 2 voices it's really "higher or lower?";
// at full SATB the inner voices make it a real listening challenge.
//
// Difficulty grows 2 voices (Soprano + Alto) → full SATB. Shares satb_voicing.
//
// SRI: 'note_reading.ear_voice.<voice>'.

import 'dart:async';
import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/satb_voicing.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/note_mascot.dart';
// Material also exports `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class HearVoiceScreen extends StatefulWidget {
  const HearVoiceScreen({super.key});

  @override
  State<HearVoiceScreen> createState() => _HearVoiceScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class HearVoiceTester {
  /// The voice that plays alone (the correct answer).
  SatbVoice get answerVoice;
  bool get isFinished;
}

class _HearVoiceScreenState extends State<HearVoiceScreen>
    with QuizRoundMixin
    implements HearVoiceTester {
  final _random = Random();
  final List<Timer> _timers = [];

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
  String get gameType => 'hear_voice';

  @override
  void initState() {
    super.initState();
    _stars = context.read<ProgressService>().starsFor(gameType);
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playPrompt());
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  void prepareRound() {
    _parts = voiceRandomChord(_random, satb: _satb, wide: _stars >= 2);
    _target = _parts[_random.nextInt(_parts.length)];
    _tapped = null;
    _lastAnswer = null;
  }

  void _after(int ms, void Function() cb) =>
      _timers.add(Timer(Duration(milliseconds: ms), cb));

  /// Play the whole chord, then the target voice alone.
  void _playPrompt() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    final audio = context.read<AudioService>();
    audio.playMidiChord(_parts.map((p) => p.pitch.midiNumber).toList());
    _after(1300, () {
      if (mounted) audio.playMidiNote(_target.pitch.midiNumber, ms: 900);
    });
  }

  void _onAnswer(SatbVoice choice) {
    if (_lastAnswer == true) return;
    final correct = choice == _target.voice;
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'note_reading.ear_voice.${_target.voice.name}',
            correct,
          );
    }
    if (!correct) context.read<AudioService>().playWrong();
    setState(() {
      _tapped = choice;
      _lastAnswer = correct;
    });
    final advanced = resolveAnswer(correct: correct);
    if (advanced && !finished) {
      // Play the next round's prompt once the auto-advance has landed.
      _after(800, () {
        if (mounted && !finished) _playPrompt();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final voices = _parts.map((p) => p.voice).toList();

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameHearVoice),
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
                      prompt: l10n.hearVoicePrompt,
                    ),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            NoteMascot(
                              mood: _lastAnswer == null
                                  ? NoteMascotMood.idle
                                  : _lastAnswer!
                                      ? NoteMascotMood.happy
                                      : NoteMascotMood.oops,
                              size: 72,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.tonalIcon(
                              onPressed: _playPrompt,
                              icon: const Icon(Icons.replay),
                              label: Text(l10n.hearVoiceReplay),
                            ),
                          ],
                        ),
                      ),
                    ),
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
