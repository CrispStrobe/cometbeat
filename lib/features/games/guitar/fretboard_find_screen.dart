// lib/features/games/guitar/fretboard_find_screen.dart
//
// "Find the Note" — the INVERSE of Read the Tab (guitar_tab_read): the child is
// given a note and taps WHERE it sits on the fretboard (productive recall). Any
// position of the target counts — a note lives on several strings. A tappable
// 6-string × 0–4-fret grid; correct cells light up so the whole shape is learnt.
//
// SRI: 'guitar.fret.<note>'.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/guitar/guitar_tab.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

/// The highest fret shown; frets 0..[_maxFret] across the six strings cover
/// every natural note (a small, kid-friendly window).
const int _maxFret = 4;

class FretboardFindScreen extends StatefulWidget {
  const FretboardFindScreen({super.key});

  @override
  State<FretboardFindScreen> createState() => _FretboardFindScreenState();
}

class _FretboardFindScreenState extends State<FretboardFindScreen>
    with QuizRoundMixin {
  /// The natural notes are the answer targets — the [Step] enum is exactly
  /// C D E F G A B.
  static const List<Step> _targets = Step.values;

  int _round = 0; // drives the deterministic (test-stable) target rotation.
  late Step _target;
  (int, int)? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'fretboard_find';

  // The correct fret plays the note; wrong plays the buzzer.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // Rotate through the naturals (stable order → testable, still varied).
    _target = _targets[(_round * 3) % _targets.length];
    _round++;
    _tapped = null;
    _lastAnswer = null;
  }

  int _midiAt(int string, int fret) =>
      kGuitarTuning.strings[string].midiNumber + fret;

  /// The natural target lives here iff this fret spells that exact letter
  /// (a sharp position has `alter == 1`, so it never matches a natural).
  bool _isTarget(int string, int fret) {
    final p = Pitch.fromMidi(_midiAt(string, fret));
    return p.alter == 0 && p.step == _target;
  }

  void _onTap(int string, int fret) {
    if (_lastAnswer == true) return; // round already solved
    final correct = _isTarget(string, fret);
    final audio = context.read<AudioService>();

    if (_tapped == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('guitar.fret.${_target.name}', correct);
    }
    if (correct) {
      audio.playMidiNote(_midiAt(string, fret), ms: 900);
    } else {
      audio.playWrong();
    }
    setState(() {
      _tapped = (string, fret);
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  Color? _cellColor(int string, int fret) {
    if (_tapped == null) return null;
    if (_isTarget(string, fret)) return Colors.green; // reveal every position
    if (_tapped == (string, fret)) return Colors.redAccent; // the wrong tap
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final strings = kGuitarTuning.strings;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameFretboardFind),
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
                      prompt: l10n.fretboardFindPrompt(
                        noteNameFor(context, _target),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              // Fret-number header.
                              Row(
                                children: [
                                  const SizedBox(width: 36),
                                  for (var f = 0; f <= _maxFret; f++)
                                    Expanded(
                                      child: Center(
                                        child: Text(
                                          '$f',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              for (var s = 0; s < strings.length; s++)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 3),
                                  child: Row(
                                    children: [
                                      // Open-string label.
                                      SizedBox(
                                        width: 36,
                                        child: Text(
                                          noteNameFor(context, strings[s].step),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge,
                                        ),
                                      ),
                                      for (var f = 0; f <= _maxFret; f++)
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 3,
                                            ),
                                            child: OutlinedButton(
                                              style: OutlinedButton.styleFrom(
                                                backgroundColor:
                                                    _cellColor(s, f),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  vertical: 12,
                                                ),
                                                minimumSize: const Size(0, 40),
                                              ),
                                              onPressed: () => _onTap(s, f),
                                              child: const Text(''),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                  ],
                ),
              ),
      ),
    );
  }
}
