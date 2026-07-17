// lib/features/games/chords/triad_seventh_screen.dart
//
// "Triad or Seventh?" — an ear game on the added seventh. A chord is played
// (arpeggio then block, synthesized, no staff): either a plain major triad
// (three notes) or a dominant-seventh (the same triad plus a minor 7th on top,
// four notes). The child decides which one they heard — training the ear to
// notice the extra, slightly tense top note. Big replay button.
//
// The dominant-7 is built app-side (major Triad pitches + root.transposeBy(a
// minor seventh)), so no 7th-chord model is needed from crisp_notation.
//
// SRI: 'chords.hear.<triad|seventh>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material also exports `Step` and `Interval` (a curve); crisp_notation's win.
import 'package:flutter/material.dart' hide Interval, Step;
import 'package:provider/provider.dart';

class TriadSeventhScreen extends StatefulWidget {
  const TriadSeventhScreen({super.key});

  @override
  State<TriadSeventhScreen> createState() => _TriadSeventhScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class TriadSeventhTester {
  /// Whether the chord is a dominant-seventh (else a plain triad).
  bool get answerSeventh;
  bool get isFinished;
}

class _TriadSeventhScreenState extends State<TriadSeventhScreen>
    with QuizRoundMixin
    implements TriadSeventhTester {
  final _random = Random();

  static const _roots = [Step.c, Step.d, Step.e, Step.f, Step.g, Step.a];

  late Step _root;
  late bool _seventh; // dominant-7 vs plain major triad
  bool? _tapped; // last choice (true = seventh)
  bool? _lastAnswer;

  @override
  bool get answerSeventh => _seventh;
  @override
  bool get isFinished => finished;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'triad_seventh';

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playChord());
  }

  @override
  void prepareRound() {
    _root = _roots[_random.nextInt(_roots.length)];
    _seventh = _random.nextBool();
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playChord();
  }

  List<int> _chordMidis() {
    final root = Pitch(_root);
    final triad = Triad(root, ChordQuality.major).pitches;
    return [
      for (final p in triad) p.midiNumber,
      // The dominant-7 adds a minor seventh above the root.
      if (_seventh) root.transposeBy(Interval.minorSeventh).midiNumber,
    ];
  }

  void _playChord() =>
      context.read<AudioService>().playArpeggioThenChord(_chordMidis());

  void _onAnswer(bool seventh) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = seventh == _seventh;

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'chords.hear.${_seventh ? 'seventh' : 'triad'}',
            correct,
          );
    }

    setState(() {
      _tapped = seventh;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameTriadSeventh),
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
                      prompt: l10n.triadSeventhPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: IconButton.filledTonal(
                          iconSize: 96,
                          padding: const EdgeInsets.all(32),
                          icon: const Icon(Icons.volume_up),
                          tooltip: l10n.listenAgain,
                          onPressed: _playChord,
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
                        for (final seventh in const [false, true])
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  backgroundColor: _tapped == null
                                      ? null
                                      : seventh == _seventh &&
                                              _tapped == _seventh
                                          ? Colors.green
                                          : seventh == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                onPressed: () => _onAnswer(seventh),
                                child: Text(
                                  seventh ? l10n.seventhLabel : l10n.triadLabel,
                                ),
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
