// lib/features/games/note_reading/read_voice_screen.dart
//
// "Read the Voice" — reading an individual line out of a multi-voice texture, on
// partitura's `Measure.voice2` (two voices per staff, stems up/down). A chord is
// shown with one voice highlighted; the child names the note THAT voice sings —
// so they must track the right line, not just any note. The 4-voice generalisation
// of Duet (which highlights one part of a two-staff system).
//
// Difficulty grows 2 voices (Soprano + Alto, one treble staff) → full SATB (four
// voices across a grand staff). Voicing/rendering shared via satb_voicing.dart.
//
// SRI: 'note_reading.<clef>.<step><octave>' on the highlighted note (shared pool).

import 'dart:math';

// Material also exports `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/features/games/note_reading/satb_voicing.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/score_theme.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

class ReadVoiceScreen extends StatefulWidget {
  const ReadVoiceScreen({super.key});

  @override
  State<ReadVoiceScreen> createState() => _ReadVoiceScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class ReadVoiceTester {
  /// Letter of the highlighted voice's note (the correct answer).
  Step get answerStep;
  bool get isFinished;
}

class _ReadVoiceScreenState extends State<ReadVoiceScreen>
    with QuizRoundMixin
    implements ReadVoiceTester {
  final _random = Random();

  int _stars = 0;
  late List<SatbPart> _parts;
  late SatbPart _target;
  late List<Step> _options;
  Step? _tapped;
  bool? _lastAnswer;

  bool get _satb => _stars >= 1; // 4 voices once past level 0

  @override
  Step get answerStep => _target.pitch.step;
  @override
  bool get isFinished => finished;

  @override
  int get totalRounds => 10;
  @override
  bool get playFeedbackSounds => false;
  @override
  String get gameType => 'read_voice';

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

    final distractors = [...Step.values]
      ..remove(_target.pitch.step)
      ..shuffle(_random);
    _options = [_target.pitch.step, ...distractors.take(3)]..shuffle(_random);
    _tapped = null;
    _lastAnswer = null;
  }

  String get _sriId =>
      'note_reading.${_target.voice.clef.name}.${_target.pitch.step.name}'
      '${_target.pitch.octave}';

  void _hearVoice() =>
      context.read<AudioService>().playMidiNote(_target.pitch.midiNumber);

  void _onAnswer(Step choice) {
    if (_lastAnswer == true) return;
    final correct = choice == _target.pitch.step;
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(_sriId, correct);
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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameReadVoice)),
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
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.readVoicePrompt(_target.voice.label(l10n)),
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
                        for (final option in _options)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _tapped == null
                                  ? null
                                  : option == _target.pitch.step
                                      ? Colors.green
                                      : option == _tapped
                                          ? Colors.redAccent
                                          : null,
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _onAnswer(option),
                            child: Text(noteNameFor(context, option)),
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
