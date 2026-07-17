// lib/features/games/scales/major_minor_ear_screen.dart
//
// "Dur oder Moll?" — the first ear-training game: a triad is played as an
// arpeggio then a block chord (synthesized, no staff shown); the child
// decides major or minor. Big replay button for repeated listening.
//
// SRI: 'scales.hear.<root>_<quality>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class MajorMinorEarScreen extends StatefulWidget {
  const MajorMinorEarScreen({super.key});

  @override
  State<MajorMinorEarScreen> createState() => _MajorMinorEarScreenState();
}

class _MajorMinorEarScreenState extends State<MajorMinorEarScreen>
    with QuizRoundMixin {
  final _random = Random();

  static const _roots = [Step.c, Step.d, Step.e, Step.f, Step.g, Step.a];

  // From 2★ the game widens from major/minor to all four triad qualities.
  static const _binaryQualities = [ChordQuality.major, ChordQuality.minor];
  static const _allQualities = [
    ChordQuality.major,
    ChordQuality.minor,
    ChordQuality.diminished,
    ChordQuality.augmented,
  ];

  late Step _root;
  late ChordQuality _quality;
  bool _wide = false;
  ChordQuality? _tapped;
  bool? _lastAnswer;

  List<ChordQuality> get _qualities => _wide ? _allQualities : _binaryQualities;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'major_minor_ear';

  @override
  void initState() {
    super.initState();
    prepareRound();
    // Play the first round's chord once the tree is up.
    WidgetsBinding.instance.addPostFrameCallback((_) => _playChord());
  }

  @override
  void prepareRound() {
    _wide = context.read<ProgressService>().starsFor(gameType) >= 2;
    _root = _roots[_random.nextInt(_roots.length)];
    _quality = _qualities[_random.nextInt(_qualities.length)];
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playChord();
  }

  String _labelFor(AppLocalizations l, ChordQuality q) => switch (q) {
        ChordQuality.major => l.majorLabel,
        ChordQuality.minor => l.minorLabel,
        ChordQuality.diminished => l.diminishedLabel,
        ChordQuality.augmented => l.augmentedLabel,
      };

  void _playChord() {
    final midis =
        Triad(Pitch(_root), _quality).pitches.map((p) => p.midiNumber).toList();
    context.read<AudioService>().playArpeggioThenChord(midis);
  }

  void _onAnswer(ChordQuality choice) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = choice == _quality;

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'scales.hear.${_root.name}_${_quality.name}',
            correct,
          );
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
      appBar: GameAppBar(title: l10n.gameMajorMinorEar),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'major_minor_ear',
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
                      prompt: _wide
                          ? l10n.listenChordQualityPrompt
                          : l10n.listenMajorMinorPrompt,
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
                    // 1 row (major/minor) at the base tier; a 2×2 grid at 2★.
                    for (var i = 0; i < _qualities.length; i += 2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            for (final option in _qualities.skip(i).take(2))
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 20,
                                      ),
                                      backgroundColor: _tapped == null
                                          ? null
                                          : option == _quality &&
                                                  _tapped == _quality
                                              ? Colors.green
                                              : option == _tapped
                                                  ? Colors.redAccent
                                                  : null,
                                      textStyle: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    onPressed: () => _onAnswer(option),
                                    child: Text(_labelFor(l10n, option)),
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
    );
  }
}
