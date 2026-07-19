// lib/features/games/guitar/capo_match_screen.dart
//
// "Capo Match" — a chord SHAPE plus a capo fret is shown; the child picks what
// it actually SOUNDS like. A capo raises every string, so a C shape at capo 2
// sounds D — the applied side of the Tab Workshop's capo. The "no change"
// answer (the shape's own name) is always among the choices as a trap.
//
// SRI: 'guitar.capo.<shape>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Open-chord shapes the game draws from: (name, root pitch-class, isMinor).
const List<(String, int, bool)> _kShapes = [
  ('C', 0, false),
  ('G', 7, false),
  ('D', 2, false),
  ('A', 9, false),
  ('E', 4, false),
  ('Am', 9, true),
  ('Em', 4, true),
  ('Dm', 2, true),
];

const List<String> _kRootNames = [
  'C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B', //
];

/// The chord [rootPc]/[minor] transposed up [capo] semitones, as a name.
String _chordName(int rootPc, bool minor, int capo) =>
    _kRootNames[(rootPc + capo) % 12] + (minor ? 'm' : '');

class CapoMatchScreen extends StatefulWidget {
  const CapoMatchScreen({super.key});

  @override
  State<CapoMatchScreen> createState() => _CapoMatchScreenState();
}

class _CapoMatchScreenState extends State<CapoMatchScreen> with QuizRoundMixin {
  final _random = Random();

  late (String, int, bool) _shape;
  late int _capo;
  late String _correct;
  late List<String> _options;
  String? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'capo_match';

  // The transposed chord is the audio feedback.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    _shape = _kShapes[_random.nextInt(_kShapes.length)];
    _capo = 1 + _random.nextInt(5); // 1..5
    final (_, rootPc, minor) = _shape;
    _correct = _chordName(rootPc, minor, _capo);
    // The correct answer + the "no change" trap (the shape's own name), then
    // fill to four with other transpositions of the same quality.
    final opts = <String>{_correct, _chordName(rootPc, minor, 0)};
    final offsets = [for (var i = 1; i < 12; i++) i]..shuffle(_random);
    for (final o in offsets) {
      if (opts.length >= 4) break;
      opts.add(_chordName(rootPc, minor, o));
    }
    _options = opts.toList()..shuffle(_random);
    _tapped = null;
    _lastAnswer = null;
  }

  void _onAnswer(String choice) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = choice == _correct;
    final audio = context.read<AudioService>();

    if (_tapped == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('guitar.capo.${_shape.$1}', correct);
    }
    if (correct) {
      final (_, rootPc, minor) = _shape;
      final root = 48 + (rootPc + _capo) % 12; // C3-based sounding root
      const majorTriad = [0, 4, 7], minorTriad = [0, 3, 7];
      audio.playMidiChord(
        [for (final i in minor ? minorTriad : majorTriad) root + i],
      );
    } else {
      audio.playWrong();
    }

    setState(() {
      _tapped = choice;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  Color? _buttonColor(String option) {
    if (_tapped == null) return null;
    if (option == _correct) return Colors.green; // reveal the answer
    if (option == _tapped) return Colors.redAccent; // the wrong tap
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameCapoMatch),
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
                      prompt: l10n.capoMatchPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _shape.$1,
                                style: theme.textTheme.displayMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.capoMatchShapeLabel,
                                style: theme.textTheme.labelMedium,
                              ),
                              const SizedBox(height: 20),
                              Chip(
                                avatar: const Icon(Icons.straighten, size: 18),
                                label: Text(
                                  l10n.capoMatchCapo(_capo),
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    AnswerGrid(
                      children: [
                        for (final option in _options)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _buttonColor(option),
                              textStyle: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _onAnswer(option),
                            child: Text(option),
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
