// lib/features/games/guitar/fretboard_find_screen.dart
//
// "Find the Note" — the INVERSE of Read the Tab (guitar_tab_read): the child is
// given a note and taps WHERE it sits on the fretboard (productive recall). Any
// position of the target counts — a note lives on several strings. A tappable
// 6-string × 0–4-fret grid; correct cells light up so the whole shape is learnt.
// Naturals for the first half of the game, then sharps join in (a difficulty
// ramp). The target is a pitch class, so ANY octave/spelling of it counts.
//
// SRI: 'guitar.fret.pc<0-11>'.

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
  const FretboardFindScreen({super.key, this.reviewItemIds});

  /// SRI ids (`guitar.fret.pc<n>`) to re-ask instead of the usual rotation.
  final List<String>? reviewItemIds;

  @override
  State<FretboardFindScreen> createState() => _FretboardFindScreenState();
}

class _FretboardFindScreenState extends State<FretboardFindScreen>
    with QuizRoundMixin {
  /// Answer targets are PITCH CLASSES (0 = C … 11 = B). The naturals come first
  /// (easier); accidentals join once past the halfway mark.
  static const List<int> _naturals = [0, 2, 4, 5, 7, 9, 11];
  static const List<int> _all = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];

  int _round = 0; // drives the deterministic (test-stable) target rotation.
  late int _target; // target pitch class
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

  /// The pitch classes behind [FretboardFindScreen.reviewItemIds], in a
  /// fixed order; null when not reviewing.
  late final List<int>? _reviewTargets = () {
    final pcs = {
      for (final id in widget.reviewItemIds ?? const <String>[])
        if (RegExp(r'^guitar\.fret\.pc(\d+)$').firstMatch(id) case final m?)
          if (int.parse(m.group(1)!) case final pc when pc < 12) pc,
    }.toList();
    return pcs.isEmpty ? null : pcs;
  }();

  @override
  void prepareRound() {
    final review = _reviewTargets;
    if (review != null) {
      _target = review[_round % review.length];
      _round++;
      _tapped = null;
      _lastAnswer = null;
      return;
    }
    // Naturals-only for the first half, then all twelve — a difficulty ramp.
    // Round 0 lands on C (pitch class 0), keeping the rotation test-stable.
    final firstHalf = _round < totalRounds ~/ 2;
    final pool = firstHalf ? _naturals : _all;
    _target = pool[(_round * (firstHalf ? 3 : 5)) % pool.length];
    _round++;
    _tapped = null;
    _lastAnswer = null;
  }

  int _midiAt(int string, int fret) =>
      kGuitarTuning.strings[string].midiNumber + fret;

  /// The target pitch class lives at this fret (any octave, any spelling).
  bool _isTarget(int string, int fret) => _midiAt(string, fret) % 12 == _target;

  /// The target's display name — a natural letter (honouring the note-name
  /// style) or that letter plus a sharp for the black notes.
  String _targetName(BuildContext context) {
    final p = Pitch.fromMidi(60 + _target);
    return noteNameFor(context, p.step) + (p.alter == 1 ? '♯' : '');
  }

  void _onTap(int string, int fret) {
    if (_lastAnswer == true) return; // round already solved
    final correct = _isTarget(string, fret);
    final audio = context.read<AudioService>();

    if (_tapped == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('guitar.fret.pc$_target', correct);
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
                      prompt: l10n.fretboardFindPrompt(_targetName(context)),
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
