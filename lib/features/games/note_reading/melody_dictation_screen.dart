// lib/features/games/note_reading/melody_dictation_screen.dart
//
// "Melodie-Diktat" — the production sibling of Melody Echo: a short melody
// plays (audio only, nothing shown) and the child WRITES it down by tapping
// noteheads onto an interactive staff, left to right. Each placement sounds
// its pitch; an undo fixes mistakes. When the melody is complete it is checked
// against the target note-for-note. This is classic ear-training dictation,
// reusing partitura's InteractiveStaff (the same input the composing sandbox
// uses).
//
// SRI: 'note_reading.dictation.len<N>'.

import 'dart:math';

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

class MelodyDictationScreen extends StatefulWidget {
  const MelodyDictationScreen({super.key});

  static const melodyLength = 3;
  static const _clef = Clef.treble;

  @override
  State<MelodyDictationScreen> createState() => _MelodyDictationScreenState();
}

class _MelodyDictationScreenState extends State<MelodyDictationScreen>
    with QuizRoundMixin {
  final _random = Random();

  late List<int> _melody; // target staff positions
  final List<int> _placed = []; // the child's answer so far (index 0 = anchor)
  bool? _lastAnswer;
  bool _recorded = false; // SRI recorded for this round?

  @override
  int get totalRounds => 8;

  @override
  String get gameType => 'melody_dictation';

  // Placements play their own pitch; the melody is the real feedback.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playMelody());
  }

  List<int> _randomMelody() {
    // Stepwise-leaning walk over the staff (positions 1..7), same shape as
    // Melody Echo so the two games feel like a matched pair.
    var position = 2 + _random.nextInt(4);
    final melody = <int>[position];
    while (melody.length < MelodyDictationScreen.melodyLength) {
      final step = [-2, -1, -1, 1, 1, 2][_random.nextInt(6)];
      position = (position + step).clamp(1, 7);
      melody.add(position);
    }
    return melody;
  }

  @override
  void prepareRound() {
    _melody = _randomMelody();
    // The first note is given as an anchor — standard dictation practice, and
    // it makes the task achievable for a beginner.
    _placed
      ..clear()
      ..add(_melody.first);
    _lastAnswer = null;
    _recorded = false;
    if (round > 0) _playMelody();
  }

  Pitch _pitchAt(int position) => MelodyDictationScreen._clef.pitchAt(position);

  void _playMelody() {
    context.read<AudioService>().playSequence([
      for (final position in _melody) (_pitchAt(position).midiNumber, 450),
    ]);
  }

  static const _quarter = NoteDuration(DurationBase.quarter);
  static const _quarterRest = RestElement(_quarter);

  /// The staff the child taps on: placed notes (as quarters), remaining slots
  /// as quarter rests, padded to a full 4/4 bar so the width stays steady.
  Score get _score {
    final elements = <MusicElement>[];
    for (var i = 0; i < MelodyDictationScreen.melodyLength; i++) {
      if (i < _placed.length) {
        elements
            .add(NoteElement.note(_pitchAt(_placed[i]), _quarter, id: 'n$i'));
      } else {
        elements.add(_quarterRest);
      }
    }
    // Pad the remaining beats of the 4/4 bar with rests.
    for (var b = MelodyDictationScreen.melodyLength; b < 4; b++) {
      elements.add(_quarterRest);
    }
    return Score(
      clef: MelodyDictationScreen._clef,
      timeSignature: TimeSignature.fourFour,
      measures: [Measure(elements)],
    );
  }

  void _onStaffTap(StaffTarget target) {
    if (_lastAnswer == true) return; // already solved
    if (_placed.length >= MelodyDictationScreen.melodyLength) return;

    final pitch = target.pitchFor(MelodyDictationScreen._clef);
    final position = pitch.staffPosition(MelodyDictationScreen._clef);
    context.read<AudioService>().playMidiNote(pitch.midiNumber, ms: 400);

    setState(() => _placed.add(position));

    if (_placed.length == MelodyDictationScreen.melodyLength) _evaluate();
  }

  /// Remove the last note the child placed (never the given anchor). Clears any
  /// red marks so they can re-try that slot — this is the self-correction.
  void _undo() {
    if (_lastAnswer == true || _placed.length <= 1) return;
    setState(() {
      _placed.removeLast();
      _lastAnswer = null;
    });
  }

  void _evaluate() {
    var correct = true;
    for (var i = 0; i < _melody.length; i++) {
      if (_placed[i] != _melody[i]) {
        correct = false;
        break;
      }
    }

    // Record only the first full attempt of the round.
    if (!_recorded) {
      context.read<SriService>().recordResponse(
            'note_reading.dictation.len${_melody.length}',
            correct,
          );
      _recorded = true;
    }
    final audio = context.read<AudioService>();
    correct ? audio.playCorrect() : audio.playWrong();

    setState(() => _lastAnswer = correct);
    resolveAnswer(correct: correct);
    // On a miss we keep the notes on the staff (wrong ones marked red) so the
    // child can undo and fix them, rather than wiping the whole attempt.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // The given anchor (n0) is tinted so the child knows it's the starting
    // note; on evaluation, placed notes turn green if right, red if wrong.
    final theme = PartituraTheme.kids.copyWith(
      elementColors: {
        if (_lastAnswer == null)
          'n0': Theme.of(context).colorScheme.primary
        else
          for (var i = 0; i < _placed.length; i++)
            'n$i': (i < _melody.length && _placed[i] == _melody[i])
                ? Colors.green
                : Colors.redAccent,
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.gameMelodyDictation),
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: l10n.listenAgain,
            onPressed: _playMelody,
          ),
        ],
      ),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'melody_dictation',
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
                      prompt: l10n.melodyDictationPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: InteractiveStaff(
                              score: _score,
                              theme: theme,
                              staffSpace: 16,
                              onStaffTap: _onStaffTap,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Progress dots: how many notes placed of the target length.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0;
                            i < MelodyDictationScreen.melodyLength;
                            i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              i < _placed.length
                                  ? Icons.circle
                                  : Icons.circle_outlined,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        const SizedBox(width: 16),
                        TextButton.icon(
                          onPressed: _placed.length <= 1 || _lastAnswer == true
                              ? null
                              : _undo,
                          icon: const Icon(Icons.undo),
                          label: Text(l10n.dictationUndo),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FeedbackLine(correct: _lastAnswer),
                  ],
                ),
              ),
      ),
    );
  }
}
