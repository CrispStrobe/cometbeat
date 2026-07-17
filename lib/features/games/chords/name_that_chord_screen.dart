// lib/features/games/chords/name_that_chord_screen.dart
//
// "Name That Chord" — read/hear a chord and pick its symbol. The answer is
// graded by crisp_notation's `identifyChord`, so it handles quality AND inversions
// (root position for beginners; diminished/augmented and slash-chord inversions
// like C/E at 2★). The first game built on crisp_notation's chord-identification.
//
// SRI: 'chords.name.<root>_<type>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material also exports `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class NameThatChordScreen extends StatefulWidget {
  const NameThatChordScreen({super.key});

  @override
  State<NameThatChordScreen> createState() => _NameThatChordScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class NameThatChordTester {
  String get answerSymbol;
}

class _NameThatChordScreenState extends State<NameThatChordScreen>
    with QuizRoundMixin
    implements NameThatChordTester {
  static const _roots = [Step.c, Step.d, Step.e, Step.f, Step.g, Step.a];

  final _random = Random();

  late List<Pitch> _pitches;
  late ChordAnalysis _answer;
  late List<String> _options;
  String? _tapped;
  bool? _lastAnswer;
  bool _wide = false;

  @override
  String get answerSymbol => _answer.symbol;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'name_that_chord';

  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    _wide = context.read<ProgressService>().starsFor(gameType) >= 2;
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playChord());
  }

  /// A spelled root-position triad on the given root, in octave 4.
  List<Pitch> _triad(Step root, ChordQuality quality) =>
      Triad(Pitch(root), quality).pitches;

  ChordQuality _randomQuality() {
    final pool = _wide
        ? ChordQuality.values
        : const [ChordQuality.major, ChordQuality.minor];
    return pool[_random.nextInt(pool.length)];
  }

  /// Raise a pitch by one octave, keeping its spelling.
  Pitch _up(Pitch p) => Pitch(p.step, alter: p.alter, octave: p.octave + 1);

  @override
  void prepareRound() {
    final root = _roots[_random.nextInt(_roots.length)];
    final quality = _randomQuality();
    var pitches = _triad(root, quality);

    // At 2★, sometimes invert a major/minor triad so the child meets slash
    // chords — identifyChord names the inversion for us.
    if (_wide &&
        (quality == ChordQuality.major || quality == ChordQuality.minor) &&
        _random.nextBool()) {
      final inv = 1 + _random.nextInt(2); // 1st or 2nd inversion
      for (var i = 0; i < inv; i++) {
        pitches = [...pitches.skip(1), _up(pitches.first)];
      }
    }

    _pitches = pitches;
    _answer = identifyChord(pitches)!;
    _options = _buildOptions(_answer.symbol);
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playChord();
  }

  // Correct symbol + three distinct distractors from other root-position triads.
  List<String> _buildOptions(String correct) {
    final symbols = <String>{correct};
    var guard = 0;
    while (symbols.length < 4 && guard++ < 100) {
      final root = _roots[_random.nextInt(_roots.length)];
      final quality = _randomQuality();
      final sym = chordSymbolFor(_triad(root, quality));
      if (sym != null) symbols.add(sym);
    }
    return symbols.toList()..shuffle(_random);
  }

  void _playChord() => context
      .read<AudioService>()
      .playArpeggioThenChord(_pitches.map((p) => p.midiNumber).toList());

  Score get _score => Score.simple(
        notes: '${_pitches.map(_token).join('+')}:w',
      );

  String _token(Pitch p) {
    final acc = switch (p.alter) { 1 => '#', -1 => 'b', _ => '' };
    return '${p.step.name}$acc${p.octave}';
  }

  void _onAnswer(String choice) {
    if (_lastAnswer == true) return;
    final correct = choice == _answer.symbol;
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'chords.name.${_answer.root.step.name}_${_answer.type.name}',
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
      appBar: GameAppBar(title: l10n.gameNameThatChord),
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
                      prompt: l10n.nameThatChordPrompt,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 12,
                            ),
                            child: StaffView(
                              score: _score,
                              staffSpace: 14,
                              theme: kidsScoreTheme,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: IconButton.filledTonal(
                        iconSize: 44,
                        icon: const Icon(Icons.volume_up),
                        tooltip: l10n.listenAgain,
                        onPressed: _playChord,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 12),
                    AnswerGrid(
                      children: [
                        for (final option in _options)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _tapped == null
                                  ? null
                                  : option == _answer.symbol
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
